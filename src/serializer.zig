//! Main serializer for ECS registry state

const std = @import("std");
const ecs = @import("ecs");
const Config = @import("config.zig").Config;
const SaveMetadata = @import("metadata.zig").SaveMetadata;
const JsonWriter = @import("json_writer.zig").JsonWriter;
const JsonReader = @import("json_reader.zig").JsonReader;

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

        pub fn init(allocator: std.mem.Allocator, config: Config) Self {
            return .{
                .allocator = allocator,
                .config = config,
            };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        /// Serialize registry to JSON string
        pub fn serialize(self: *Self, registry: *ecs.Registry) ![]u8 {
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
            inline for (ComponentTypes) |T| {
                if (!first) try writer.writeComma();
                first = false;

                const name = @typeName(T);
                try writer.writeKey(name);

                if (@sizeOf(T) == 0) {
                    // Tag component - just entity IDs
                    try self.serializeTagComponent(T, &writer, registry);
                } else {
                    // Data component
                    try self.serializeDataComponent(T, &writer, registry);
                }
            }

            if (!first) {
                try writer.endObject();
            } else {
                writer.decrementIndent();
                try writer.writeRaw('}');
            }

            try writer.endObject();

            return writer.toOwnedSlice();
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

        fn serializeTagComponent(self: *Self, comptime T: type, writer: *JsonWriter, registry: *ecs.Registry) !void {
            _ = self;
            try writer.beginArray();

            var view = registry.view(.{T}, .{});
            var first = true;
            var iter = view.entityIterator();
            while (iter.next()) |entity| {
                if (!first) try writer.writeComma();
                first = false;
                try writer.writeIndent();
                try writer.writeEntity(entity);
            }

            if (!first) {
                try writer.endArray();
            } else {
                writer.decrementIndent();
                try writer.writeRaw(']');
            }
        }

        fn serializeDataComponent(self: *Self, comptime T: type, writer: *JsonWriter, registry: *ecs.Registry) !void {
            _ = self;
            try writer.beginArray();

            var view = registry.view(.{T}, .{});
            var first = true;
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
            }

            if (!first) {
                try writer.endArray();
            } else {
                writer.decrementIndent();
                try writer.writeRaw(']');
            }
        }

        /// Deserialize JSON string into registry
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

            // First pass: create all entities and collect old IDs
            const components = JsonReader.getField(root, "components") orelse return error.InvalidSaveFormat;
            if (components != .object) return error.InvalidSaveFormat;

            try self.collectEntities(components, registry, &entity_map);

            // Second pass: deserialize components with entity remapping
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
    };
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

test "SerializerWithTransient excludes transient components" {
    const allocator = std.testing.allocator;

    const Position = struct { x: f32, y: f32 };
    const Velocity = struct { dx: f32, dy: f32 }; // Transient - not saved
    const Health = struct { current: u8, max: u8 };

    // Create serializer that excludes Velocity
    const TestSerializer = SerializerWithTransient(
        &[_]type{ Position, Velocity, Health },
        &[_]type{Velocity},
    );

    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const entity = registry.create();
    registry.add(entity, Position{ .x = 10, .y = 20 });
    registry.add(entity, Velocity{ .dx = 1, .dy = 2 });
    registry.add(entity, Health{ .current = 100, .max = 100 });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry);
    defer allocator.free(json);

    // Verify Velocity is not in the JSON
    try std.testing.expect(std.mem.indexOf(u8, json, "Velocity") == null);
    // But Position and Health are
    try std.testing.expect(std.mem.indexOf(u8, json, "Position") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "Health") != null);
}

test "Serializer roundtrip" {
    const allocator = std.testing.allocator;

    const Position = struct { x: f32, y: f32 };
    const Health = struct { current: u8, max: u8 };
    const Player = struct {}; // Tag

    const TestSerializer = Serializer(&[_]type{ Position, Health, Player });

    // Create and populate registry
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const player = registry.create();
    registry.add(player, Position{ .x = 100, .y = 200 });
    registry.add(player, Health{ .current = 80, .max = 100 });
    registry.add(player, Player{});

    const enemy = registry.create();
    registry.add(enemy, Position{ .x = 50, .y = 75 });
    registry.add(enemy, Health{ .current = 50, .max = 50 });

    // Serialize
    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry);
    defer allocator.free(json);

    // Deserialize into new registry
    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    // Verify data
    var view = registry2.view(.{Position}, .{});
    var count: usize = 0;
    var iter = view.entityIterator();
    while (iter.next()) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
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

test "SelectiveSerializer saves only selected components" {
    const allocator = std.testing.allocator;

    const Position = struct { x: f32, y: f32 };
    const Health = struct { current: u8, max: u8 };
    const Inventory = struct { slots: u8 };

    // Full component list
    const AllComponents = &[_]type{ Position, Health, Inventory };
    // Quick save profile
    const QuickSaveComponents = &[_]type{ Position, Health };

    // Create registry with all component types
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const player = registry.create();
    registry.add(player, Position{ .x = 100, .y = 200 });
    registry.add(player, Health{ .current = 80, .max = 100 });
    registry.add(player, Inventory{ .slots = 20 });

    // Use selective serializer (only Position and Health)
    const QuickSerializer = SelectiveSerializer(AllComponents, QuickSaveComponents);
    var ser = QuickSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry);
    defer allocator.free(json);

    // Verify Inventory is not in the output
    try std.testing.expect(std.mem.indexOf(u8, json, "Inventory") == null);
    // But Position and Health are
    try std.testing.expect(std.mem.indexOf(u8, json, "Position") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "Health") != null);
}

test "SelectiveDeserializer loads only selected components" {
    const allocator = std.testing.allocator;

    const Position = struct { x: f32, y: f32 };
    const Health = struct { current: u8, max: u8 };
    const Inventory = struct { slots: u8 };

    // Create a full save
    const FullSerializer = Serializer(&[_]type{ Position, Health, Inventory });
    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const player = registry1.create();
    registry1.add(player, Position{ .x = 100, .y = 200 });
    registry1.add(player, Health{ .current = 80, .max = 100 });
    registry1.add(player, Inventory{ .slots = 20 });

    var full_ser = FullSerializer.init(allocator, .{});
    defer full_ser.deinit();

    const full_json = try full_ser.serialize(&registry1);
    defer allocator.free(full_json);

    // Load only Position from the full save
    const PositionOnlyLoader = SelectiveDeserializer(&[_]type{Position});
    var loader = PositionOnlyLoader.initWithOptions(allocator, .{}, .{ .skip_missing = true });
    defer loader.deinit();

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try loader.deserialize(&registry2, full_json);

    // Verify only Position was loaded
    var pos_view = registry2.view(.{Position}, .{});
    var pos_count: usize = 0;
    var pos_iter = pos_view.entityIterator();
    while (pos_iter.next()) |_| {
        pos_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), pos_count);
}

test "SelectiveDeserializer errors on missing component without skip_missing" {
    const allocator = std.testing.allocator;

    const Position = struct { x: f32, y: f32 };
    const Health = struct { current: u8, max: u8 };

    // Create a save with only Position
    const PositionSerializer = Serializer(&[_]type{Position});
    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const player = registry1.create();
    registry1.add(player, Position{ .x = 100, .y = 200 });

    var ser = PositionSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    // Try to load both Position and Health (Health is missing)
    const BothLoader = SelectiveDeserializer(&[_]type{ Position, Health });
    var loader = BothLoader.init(allocator, .{}); // skip_missing = false by default
    defer loader.deinit();

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    // Should error because Health is not in the save
    try std.testing.expectError(error.ComponentNotInSave, loader.deserialize(&registry2, json));
}
