//! Main serializer for ECS registry state

const std = @import("std");
const ecs = @import("ecs");
const Config = @import("config.zig").Config;
const SaveMetadata = @import("metadata.zig").SaveMetadata;
const JsonWriter = @import("json_writer.zig").JsonWriter;
const JsonReader = @import("json_reader.zig").JsonReader;
const log = @import("log.zig");
const Logger = log.Logger;
const validation = @import("validation.zig");

/// Type-erased component serializer
const ComponentSerializer = struct {
    name: []const u8,
    is_tag: bool,
    serializeFn: *const fn (*JsonWriter, *ecs.Registry) anyerror!void,
    deserializeFn: *const fn (std.mem.Allocator, std.json.Value, *ecs.Registry, *const EntityMap) anyerror!void,
    hasEntityRefs: bool,
};

/// Map from old entity IDs to new entity IDs
pub const EntityMap = std.AutoHashMap(u32, ecs.Entity);

/// Serializer for ECS registry state
pub fn Serializer(comptime ComponentTypes: []const type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        config: Config,
        logger: Logger,

        pub fn init(allocator: std.mem.Allocator, config: Config) Self {
            return .{
                .allocator = allocator,
                .config = config,
                .logger = Logger.initWithCustomFn(config.log_level, config.log_fn),
            };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        /// Serialize registry to JSON string
        pub fn serialize(self: *Self, registry: *ecs.Registry) ![]u8 {
            self.logger.info("Starting serialization with {d} component types", .{ComponentTypes.len});

            var writer = JsonWriter.init(self.allocator, self.config.pretty_print);
            defer writer.deinit();

            try writer.beginObject();

            // Write metadata
            if (self.config.include_metadata) {
                try writer.writeKey("meta");
                try self.writeMetadata(&writer, registry);
                try writer.writeComma();
            }

            // Write components
            try writer.writeKey("components");
            try writer.beginObject();

            var first = true;
            var total_instances: usize = 0;
            inline for (ComponentTypes) |T| {
                if (!first) try writer.writeComma();
                first = false;

                const name = @typeName(T);
                try writer.writeKey(name);

                if (@sizeOf(T) == 0) {
                    // Tag component - just entity IDs
                    const count = try self.serializeTagComponent(T, &writer, registry);
                    total_instances += count;
                    self.logger.debug("{s}: {d} instances (tag)", .{ name, count });
                } else {
                    // Data component
                    const count = try self.serializeDataComponent(T, &writer, registry);
                    total_instances += count;
                    self.logger.debug("{s}: {d} instances", .{ name, count });
                }
            }

            if (!first) {
                try writer.endObject();
            } else {
                writer.decrementIndent();
                try writer.writeRaw('}');
            }

            try writer.endObject();

            const result = try writer.toOwnedSlice();
            self.logger.info("Serialization complete: {d} component instances, {d} bytes", .{ total_instances, result.len });
            return result;
        }

        fn writeMetadata(self: *Self, writer: *JsonWriter, registry: *ecs.Registry) !void {
            _ = registry;
            try writer.beginObject();

            try writer.writeKey("version");
            try writer.writeInt(self.config.version);
            try writer.writeComma();

            try writer.writeKey("lib_version");
            try writer.writeString("0.1.0");
            try writer.writeComma();

            try writer.writeKey("timestamp");
            try writer.writeInt(std.time.timestamp());

            if (self.config.game_name) |name| {
                try writer.writeComma();
                try writer.writeKey("game_name");
                try writer.writeString(name);
            }

            try writer.endObject();
        }

        fn serializeTagComponent(self: *Self, comptime T: type, writer: *JsonWriter, registry: *ecs.Registry) !usize {
            _ = self;
            try writer.beginArray();

            var view = registry.view(.{T}, .{});
            var first = true;
            var count: usize = 0;
            var iter = view.entityIterator();
            while (iter.next()) |entity| {
                if (!first) try writer.writeComma();
                first = false;
                try writer.writeIndent();
                try writer.writeEntity(entity);
                count += 1;
            }

            if (!first) {
                try writer.endArray();
            } else {
                writer.decrementIndent();
                try writer.writeRaw(']');
            }
            return count;
        }

        fn serializeDataComponent(self: *Self, comptime T: type, writer: *JsonWriter, registry: *ecs.Registry) !usize {
            _ = self;
            try writer.beginArray();

            var view = registry.view(.{T}, .{});
            var first = true;
            var count: usize = 0;
            var iter = view.entityIterator();
            while (iter.next()) |entity| {
                if (!first) try writer.writeComma();
                first = false;

                try writer.writeIndent();
                try writer.beginObject();

                try writer.writeKey("entt");
                try writer.writeEntity(entity);
                try writer.writeComma();

                try writer.writeKey("data");
                const component = registry.get(T, entity);
                try writer.writeValue(component.*);

                try writer.endObject();
                count += 1;
            }

            if (!first) {
                try writer.endArray();
            } else {
                writer.decrementIndent();
                try writer.writeRaw(']');
            }
            return count;
        }

        /// Deserialize JSON string into registry
        pub fn deserialize(self: *Self, registry: *ecs.Registry, json_str: []const u8) !void {
            self.logger.info("Starting deserialization ({d} bytes)", .{json_str.len});

            var reader = try JsonReader.init(self.allocator, json_str);
            defer reader.deinit();

            const root = reader.root();
            if (root != .object) {
                self.logger.@"error"("Invalid save format: root is not an object", .{});
                return error.InvalidSaveFormat;
            }

            // Check version if metadata present
            if (JsonReader.getField(root, "meta")) |meta| {
                try self.validateMetadata(meta);
            }

            // Build entity mapping: old ID -> new Entity
            var entity_map = EntityMap.init(self.allocator);
            defer entity_map.deinit();

            // First pass: create all entities and collect old IDs
            const components = JsonReader.getField(root, "components") orelse {
                self.logger.@"error"("Invalid save format: missing components section", .{});
                return error.InvalidSaveFormat;
            };
            if (components != .object) {
                self.logger.@"error"("Invalid save format: components is not an object", .{});
                return error.InvalidSaveFormat;
            }

            try self.collectEntities(components, registry, &entity_map);
            self.logger.debug("Created {d} entities", .{entity_map.count()});

            // Second pass: deserialize components with entity remapping
            try self.deserializeComponents(components, registry, &entity_map);

            self.logger.info("Deserialization complete: {d} entities loaded", .{entity_map.count()});
        }

        fn validateMetadata(self: *Self, meta: std.json.Value) !void {
            if (meta != .object) return error.InvalidSaveFormat;

            if (JsonReader.getField(meta, "version")) |version_val| {
                if (version_val != .integer) return error.InvalidSaveFormat;
                const version: u32 = @intCast(version_val.integer);

                self.logger.debug("Save version: {d}, current version: {d}", .{ version, self.config.version });

                if (version > self.config.version) {
                    self.logger.@"error"("Save is from newer version ({d} > {d})", .{ version, self.config.version });
                    return error.SaveFromNewerVersion;
                }
                if (version < self.config.min_loadable_version) {
                    self.logger.@"error"("Save is too old ({d} < {d})", .{ version, self.config.min_loadable_version });
                    return error.SaveTooOld;
                }
            }
        }

        fn collectEntities(self: *Self, components: std.json.Value, registry: *ecs.Registry, entity_map: *EntityMap) !void {
            _ = self;

            inline for (ComponentTypes) |T| {
                const name = @typeName(T);
                if (components.object.get(name)) |comp_data| {
                    if (comp_data == .array) {
                        for (comp_data.array.items) |item| {
                            const old_id = try getEntityId(T, item);

                            // Create new entity if not already mapped
                            if (!entity_map.contains(old_id)) {
                                const new_entity = registry.create();
                                try entity_map.put(old_id, new_entity);
                            }
                        }
                    }
                }
            }
        }

        fn getEntityId(comptime T: type, item: std.json.Value) !u32 {
            if (@sizeOf(T) == 0) {
                // Tag component - item is just the entity ID
                if (item != .integer) return error.InvalidSaveFormat;
                return @intCast(item.integer);
            } else {
                // Data component - item is { "entt": id, "data": ... }
                if (item != .object) return error.InvalidSaveFormat;
                const entt = item.object.get("entt") orelse return error.InvalidSaveFormat;
                if (entt != .integer) return error.InvalidSaveFormat;
                return @intCast(entt.integer);
            }
        }

        fn deserializeComponents(self: *Self, components: std.json.Value, registry: *ecs.Registry, entity_map: *const EntityMap) !void {
            inline for (ComponentTypes) |T| {
                const name = @typeName(T);
                if (components.object.get(name)) |comp_data| {
                    if (comp_data == .array) {
                        for (comp_data.array.items) |item| {
                            const old_id = try getEntityId(T, item);
                            const entity = entity_map.get(old_id) orelse return error.InvalidEntityReference;

                            if (@sizeOf(T) == 0) {
                                // Tag component
                                registry.add(entity, T{});
                            } else {
                                // Data component
                                const data = item.object.get("data") orelse return error.InvalidSaveFormat;
                                var component = try JsonReader.readValue(self.allocator, T, data);

                                // Remap entity references
                                remapEntityRefs(T, &component, entity_map);

                                registry.add(entity, component);
                            }
                        }
                    }
                }
            }
        }

        /// Recursively remap entity references in a component
        fn remapEntityRefs(comptime T: type, value: *T, entity_map: *const EntityMap) void {
            const info = @typeInfo(T);

            switch (info) {
                .@"struct" => |s| {
                    inline for (s.fields) |field| {
                        if (field.type == ecs.Entity) {
                            const old_id: u32 = @bitCast(@field(value, field.name));
                            if (entity_map.get(old_id)) |new_entity| {
                                @field(value, field.name) = new_entity;
                            }
                        } else if (field.type == ?ecs.Entity) {
                            if (@field(value, field.name)) |entity| {
                                const old_id: u32 = @bitCast(entity);
                                if (entity_map.get(old_id)) |new_entity| {
                                    @field(value, field.name) = new_entity;
                                }
                            }
                        } else if (@typeInfo(field.type) == .@"struct") {
                            remapEntityRefs(field.type, &@field(value, field.name), entity_map);
                        }
                    }
                },
                .array => |arr| {
                    if (arr.child == ecs.Entity) {
                        for (value) |*item| {
                            const old_id: u32 = @bitCast(item.*);
                            if (entity_map.get(old_id)) |new_entity| {
                                item.* = new_entity;
                            }
                        }
                    } else if (@typeInfo(arr.child) == .@"struct") {
                        for (value) |*item| {
                            remapEntityRefs(arr.child, item, entity_map);
                        }
                    }
                },
                else => {},
            }
        }

        /// Save registry to file
        pub fn save(self: *Self, registry: *ecs.Registry, path: []const u8) !void {
            const json = try self.serialize(registry);
            defer self.allocator.free(json);

            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();

            try file.writeAll(json);
        }

        /// Load registry from file
        pub fn load(self: *Self, registry: *ecs.Registry, path: []const u8) !void {
            const file = try std.fs.cwd().openFile(path, .{});
            defer file.close();

            const json = try file.readToEndAlloc(self.allocator, 1024 * 1024 * 100); // 100MB max
            defer self.allocator.free(json);

            try self.deserialize(registry, json);
        }

        /// Read metadata without loading full save
        pub fn readMetadata(self: *Self, path: []const u8) !SaveMetadata {
            const file = try std.fs.cwd().openFile(path, .{});
            defer file.close();

            // Read enough to get metadata (typically in first few KB)
            var buffer: [8192]u8 = undefined;
            const bytes_read = try file.read(&buffer);

            var reader = try JsonReader.init(self.allocator, buffer[0..bytes_read]);
            defer reader.deinit();

            const root = reader.root();
            const meta = JsonReader.getField(root, "meta") orelse return error.InvalidSaveFormat;

            return try JsonReader.readValue(self.allocator, SaveMetadata, meta);
        }

        /// Validate a save file without loading it
        pub fn validateFile(self: *Self, path: []const u8) !validation.ValidationResult {
            const file = try std.fs.cwd().openFile(path, .{});
            defer file.close();

            const json = try file.readToEndAlloc(self.allocator, 1024 * 1024 * 100);
            defer self.allocator.free(json);

            return validation.validateSave(self.allocator, json, self.config.version);
        }

        /// Dump registry state to a writer for debugging
        pub fn dumpRegistry(self: *Self, registry: *ecs.Registry, writer: anytype) !void {
            try writer.print("Registry Dump\n", .{});
            try writer.print("=============\n", .{});
            try writer.print("Component types: {d}\n\n", .{ComponentTypes.len});

            inline for (ComponentTypes) |T| {
                const name = @typeName(T);
                var view = registry.view(.{T}, .{});
                var count: usize = 0;
                var iter = view.entityIterator();
                while (iter.next()) |_| count += 1;

                try writer.print("{s}: {d} instances\n", .{ name, count });

                if (@sizeOf(T) > 0) {
                    // Reset iterator and print data
                    var iter2 = view.entityIterator();
                    while (iter2.next()) |entity| {
                        const component = registry.get(T, entity);
                        const entity_id: u32 = @bitCast(entity);
                        try writer.print("  Entity {d}: ", .{entity_id});
                        try self.writeComponentDebug(T, component.*, writer);
                        try writer.print("\n", .{});
                    }
                } else {
                    // Tag component - just list entities
                    var iter2 = view.entityIterator();
                    try writer.print("  Entities: ", .{});
                    var first = true;
                    while (iter2.next()) |entity| {
                        if (!first) try writer.print(", ", .{});
                        first = false;
                        const entity_id: u32 = @bitCast(entity);
                        try writer.print("{d}", .{entity_id});
                    }
                    try writer.print("\n", .{});
                }
                try writer.print("\n", .{});
            }
        }

        /// Dump a single entity's components to a writer
        pub fn dumpEntity(self: *Self, registry: *ecs.Registry, entity: ecs.Entity, writer: anytype) !void {
            const entity_id: u32 = @bitCast(entity);
            try writer.print("Entity {d}\n", .{entity_id});
            try writer.print("=========\n", .{});

            inline for (ComponentTypes) |T| {
                if (registry.has(T, entity)) {
                    const name = @typeName(T);
                    try writer.print("{s}: ", .{name});

                    if (@sizeOf(T) > 0) {
                        const component = registry.get(T, entity);
                        try self.writeComponentDebug(T, component.*, writer);
                    } else {
                        try writer.print("(tag)", .{});
                    }
                    try writer.print("\n", .{});
                }
            }
        }

        fn writeComponentDebug(self: *Self, comptime T: type, value: T, writer: anytype) !void {
            _ = self;
            const info = @typeInfo(T);
            switch (info) {
                .@"struct" => |s| {
                    try writer.print("{{ ", .{});
                    inline for (s.fields, 0..) |field, i| {
                        if (i > 0) try writer.print(", ", .{});
                        try writer.print("{s}: ", .{field.name});
                        try writeFieldDebug(field.type, @field(value, field.name), writer);
                    }
                    try writer.print(" }}", .{});
                },
                else => try writer.print("{any}", .{value}),
            }
        }
    };
}

fn writeFieldDebug(comptime T: type, value: T, writer: anytype) !void {
    const info = @typeInfo(T);
    switch (info) {
        .int, .comptime_int => try writer.print("{d}", .{value}),
        .float, .comptime_float => try writer.print("{d:.2}", .{value}),
        .bool => try writer.print("{}", .{value}),
        .@"enum" => try writer.print(".{s}", .{@tagName(value)}),
        .optional => {
            if (value) |v| {
                try writeFieldDebug(@TypeOf(v), v, writer);
            } else {
                try writer.print("null", .{});
            }
        },
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                try writer.print("\"{s}\"", .{value});
            } else {
                try writer.print("{any}", .{value});
            }
        },
        .array => try writer.print("{any}", .{value}),
        else => try writer.print("{any}", .{value}),
    }
}

/// Create a serializer for the given component types
pub fn serializer(comptime ComponentTypes: []const type) type {
    return Serializer(ComponentTypes);
}

/// Serializer with transient component support
/// Transient components are excluded from serialization but can still exist in the registry
pub fn SerializerWithTransient(comptime ComponentTypes: []const type, comptime TransientTypes: []const type) type {
    // Filter out transient types from component types
    const filtered = comptime blk: {
        var count: usize = 0;
        for (ComponentTypes) |T| {
            var is_transient = false;
            for (TransientTypes) |Tr| {
                if (T == Tr) {
                    is_transient = true;
                    break;
                }
            }
            if (!is_transient) count += 1;
        }

        var result: [count]type = undefined;
        var idx: usize = 0;
        for (ComponentTypes) |T| {
            var is_transient = false;
            for (TransientTypes) |Tr| {
                if (T == Tr) {
                    is_transient = true;
                    break;
                }
            }
            if (!is_transient) {
                result[idx] = T;
                idx += 1;
            }
        }
        break :blk result;
    };

    return Serializer(&filtered);
}

/// Check if a component type has transient marker
pub fn isTransient(comptime T: type) bool {
    return @hasDecl(T, "serialization_transient") and T.serialization_transient;
}

/// Options for selective serialization
pub const SelectiveOptions = struct {
    /// Skip missing components during load (don't error if component not in save)
    skip_missing: bool = false,
};

/// Create a serializer that only handles a subset of component types.
/// This is useful for different save scenarios:
/// - Quick-save: Only save player position and health
/// - Full save: Save everything
/// - Checkpoint: Save progress markers only
///
/// Example:
/// ```zig
/// const AllComponents = &[_]type{ Position, Health, Inventory, QuestProgress };
/// const QuickSaveComponents = &[_]type{ Position, Health };
///
/// // Full serializer
/// const FullSerializer = Serializer(AllComponents);
///
/// // Quick save serializer (subset of components)
/// const QuickSerializer = SelectiveSerializer(AllComponents, QuickSaveComponents);
/// ```
pub fn SelectiveSerializer(comptime AllComponents: []const type, comptime SelectedComponents: []const type) type {
    // At compile time, verify all selected components are in AllComponents
    comptime {
        for (SelectedComponents) |Selected| {
            var found = false;
            for (AllComponents) |All| {
                if (Selected == All) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                @compileError("SelectiveSerializer: Selected component type '" ++ @typeName(Selected) ++ "' is not in AllComponents");
            }
        }
    }

    return Serializer(SelectedComponents);
}

/// Create a selective deserializer that only loads specific components from a save.
/// Unlike SelectiveSerializer, this can load partial data from a full save.
/// Components not in SelectedComponents will be ignored during load.
///
/// Example:
/// ```zig
/// // Load only Position from a full save file
/// const PositionOnlyLoader = SelectiveDeserializer(&[_]type{ Position });
/// var loader = PositionOnlyLoader.init(allocator, .{});
/// try loader.deserialize(&registry, full_save_json);
/// ```
pub fn SelectiveDeserializer(comptime SelectedComponents: []const type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        config: Config,
        options: SelectiveOptions,

        pub fn init(allocator: std.mem.Allocator, config: Config) Self {
            return .{
                .allocator = allocator,
                .config = config,
                .options = .{},
            };
        }

        pub fn initWithOptions(allocator: std.mem.Allocator, config: Config, options: SelectiveOptions) Self {
            return .{
                .allocator = allocator,
                .config = config,
                .options = options,
            };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        /// Deserialize JSON string into registry, loading only SelectedComponents
        pub fn deserialize(self: *Self, registry: *ecs.Registry, json_str: []const u8) !void {
            var reader = try JsonReader.init(self.allocator, json_str);
            defer reader.deinit();

            const root = reader.root();
            if (root != .object) return error.InvalidSaveFormat;

            // Check version if metadata present
            if (JsonReader.getField(root, "meta")) |meta| {
                try self.validateMetadata(meta);
            }

            // Build entity mapping: old ID -> new Entity
            var entity_map = EntityMap.init(self.allocator);
            defer entity_map.deinit();

            const components = JsonReader.getField(root, "components") orelse return error.InvalidSaveFormat;
            if (components != .object) return error.InvalidSaveFormat;

            // First pass: create entities for selected components
            try self.collectEntities(components, registry, &entity_map);

            // Second pass: deserialize only selected components
            try self.deserializeComponents(components, registry, &entity_map);
        }

        fn validateMetadata(self: *Self, meta: std.json.Value) !void {
            if (meta != .object) return error.InvalidSaveFormat;

            if (JsonReader.getField(meta, "version")) |version_val| {
                if (version_val != .integer) return error.InvalidSaveFormat;
                const version: u32 = @intCast(version_val.integer);

                if (version > self.config.version) {
                    return error.SaveFromNewerVersion;
                }
                if (version < self.config.min_loadable_version) {
                    return error.SaveTooOld;
                }
            }
        }

        fn collectEntities(self: *Self, components: std.json.Value, registry: *ecs.Registry, entity_map: *EntityMap) !void {
            inline for (SelectedComponents) |T| {
                const name = @typeName(T);
                if (components.object.get(name)) |comp_data| {
                    if (comp_data == .array) {
                        for (comp_data.array.items) |item| {
                            const old_id = try getEntityIdSelective(T, item);

                            if (!entity_map.contains(old_id)) {
                                const new_entity = registry.create();
                                try entity_map.put(old_id, new_entity);
                            }
                        }
                    }
                } else if (!self.options.skip_missing) {
                    return error.ComponentNotInSave;
                }
            }
        }

        fn getEntityIdSelective(comptime T: type, item: std.json.Value) !u32 {
            if (@sizeOf(T) == 0) {
                if (item != .integer) return error.InvalidSaveFormat;
                return @intCast(item.integer);
            } else {
                if (item != .object) return error.InvalidSaveFormat;
                const entt = item.object.get("entt") orelse return error.InvalidSaveFormat;
                if (entt != .integer) return error.InvalidSaveFormat;
                return @intCast(entt.integer);
            }
        }

        fn deserializeComponents(self: *Self, components: std.json.Value, registry: *ecs.Registry, entity_map: *const EntityMap) !void {
            inline for (SelectedComponents) |T| {
                const name = @typeName(T);
                if (components.object.get(name)) |comp_data| {
                    if (comp_data == .array) {
                        for (comp_data.array.items) |item| {
                            const old_id = try getEntityIdSelective(T, item);
                            const entity = entity_map.get(old_id) orelse return error.InvalidEntityReference;

                            if (@sizeOf(T) == 0) {
                                registry.add(entity, T{});
                            } else {
                                const data = item.object.get("data") orelse return error.InvalidSaveFormat;
                                var component = try JsonReader.readValue(self.allocator, T, data);
                                remapEntityRefsSelective(T, &component, entity_map);
                                registry.add(entity, component);
                            }
                        }
                    }
                }
                // If component not found and skip_missing is true, we just skip it
            }
        }

        /// Recursively remap entity references in a component
        fn remapEntityRefsSelective(comptime T: type, value: *T, entity_map: *const EntityMap) void {
            const info = @typeInfo(T);

            switch (info) {
                .@"struct" => |s| {
                    inline for (s.fields) |field| {
                        if (field.type == ecs.Entity) {
                            const old_id: u32 = @bitCast(@field(value, field.name));
                            if (entity_map.get(old_id)) |new_entity| {
                                @field(value, field.name) = new_entity;
                            }
                        } else if (field.type == ?ecs.Entity) {
                            if (@field(value, field.name)) |entity| {
                                const old_id: u32 = @bitCast(entity);
                                if (entity_map.get(old_id)) |new_entity| {
                                    @field(value, field.name) = new_entity;
                                }
                            }
                        } else if (@typeInfo(field.type) == .@"struct") {
                            remapEntityRefsSelective(field.type, &@field(value, field.name), entity_map);
                        }
                    }
                },
                .array => |arr| {
                    if (arr.child == ecs.Entity) {
                        for (value) |*item| {
                            const old_id: u32 = @bitCast(item.*);
                            if (entity_map.get(old_id)) |new_entity| {
                                item.* = new_entity;
                            }
                        }
                    } else if (@typeInfo(arr.child) == .@"struct") {
                        for (value) |*item| {
                            remapEntityRefsSelective(arr.child, item, entity_map);
                        }
                    }
                },
                else => {},
            }
        }

        /// Load registry from file
        pub fn load(self: *Self, registry: *ecs.Registry, path: []const u8) !void {
            const file = try std.fs.cwd().openFile(path, .{});
            defer file.close();

            const json = try file.readToEndAlloc(self.allocator, 1024 * 1024 * 100);
            defer self.allocator.free(json);

            try self.deserialize(registry, json);
        }
    };
}
