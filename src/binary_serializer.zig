//! Binary serializer for ECS registry state
//!
//! Provides compact binary serialization as an alternative to JSON.
//! Benefits:
//! - 50-80% smaller than JSON
//! - Faster parsing (no string parsing)
//! - No floating point precision loss

const std = @import("std");
const ecs = @import("ecs");
const Config = @import("config.zig").Config;
const BinaryWriter = @import("binary_writer.zig").BinaryWriter;
const BinaryReader = @import("binary_reader.zig").BinaryReader;
const log = @import("log.zig");
const Logger = log.Logger;

/// Map from old entity IDs to new entity IDs
pub const EntityMap = std.AutoHashMap(u32, ecs.Entity);

/// Binary serializer for ECS registry state
pub fn BinarySerializer(comptime ComponentTypes: []const type) type {
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

        /// Serialize registry to binary data
        pub fn serialize(self: *Self, registry: *ecs.Registry) ![]u8 {
            self.logger.info("Starting binary serialization with {d} component types", .{ComponentTypes.len});

            var writer = BinaryWriter.init(self.allocator);
            defer writer.deinit();

            // Write header
            try writer.writeHeader(self.config.version);

            // Write metadata if enabled
            if (self.config.include_metadata) {
                try self.writeMetadata(&writer);
            }

            // Count entities first
            var entity_count: u32 = 0;
            var entity_set = std.AutoHashMap(u32, void).init(self.allocator);
            defer entity_set.deinit();

            inline for (ComponentTypes) |T| {
                var view = registry.view(.{T}, .{});
                var iter = view.entityIterator();
                while (iter.next()) |entity| {
                    const id: u32 = @bitCast(entity);
                    if (!entity_set.contains(id)) {
                        try entity_set.put(id, {});
                        entity_count += 1;
                    }
                }
            }

            // Write entity count
            try writer.writeU32(entity_count);

            // Write component type count
            try writer.writeU32(@intCast(ComponentTypes.len));

            // Write each component type
            var total_instances: usize = 0;
            inline for (ComponentTypes) |T| {
                const name = @typeName(T);

                // Write component name
                try writer.writeString(name);

                if (@sizeOf(T) == 0) {
                    // Tag component
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

            const result = try writer.toOwnedSlice();
            self.logger.info("Binary serialization complete: {d} component instances, {d} bytes", .{ total_instances, result.len });
            return result;
        }

        fn writeMetadata(self: *Self, writer: *BinaryWriter) !void {
            // Write timestamp
            try writer.writeI64(std.time.timestamp());

            // Write game name (empty string if none)
            if (self.config.game_name) |name| {
                try writer.writeString(name);
            } else {
                try writer.writeString("");
            }
        }

        fn serializeTagComponent(self: *Self, comptime T: type, writer: *BinaryWriter, registry: *ecs.Registry) !usize {
            _ = self;

            // Count instances first
            var count: u32 = 0;
            var view = registry.view(.{T}, .{});
            var iter = view.entityIterator();
            while (iter.next()) |_| count += 1;

            // Write instance count
            try writer.writeU32(count);

            // Write entity IDs
            var iter2 = view.entityIterator();
            while (iter2.next()) |entity| {
                try writer.writeEntity(entity);
            }

            return count;
        }

        fn serializeDataComponent(self: *Self, comptime T: type, writer: *BinaryWriter, registry: *ecs.Registry) !usize {
            _ = self;

            // Count instances first
            var count: u32 = 0;
            var view = registry.view(.{T}, .{});
            var iter = view.entityIterator();
            while (iter.next()) |_| count += 1;

            // Write instance count
            try writer.writeU32(count);

            // Write entity ID + component data for each
            var iter2 = view.entityIterator();
            while (iter2.next()) |entity| {
                try writer.writeEntity(entity);
                const component = registry.get(T, entity);
                try writer.writeValue(component.*);
            }

            return count;
        }

        /// Deserialize binary data into registry
        pub fn deserialize(self: *Self, registry: *ecs.Registry, data: []const u8) !void {
            self.logger.info("Starting binary deserialization ({d} bytes)", .{data.len});

            var reader = try BinaryReader.init(self.allocator, data);
            defer reader.deinit();

            // Check version
            const save_version = reader.getSaveVersion();
            self.logger.debug("Save version: {d}, current version: {d}", .{ save_version, self.config.version });

            if (save_version > self.config.version) {
                self.logger.@"error"("Save is from newer version ({d} > {d})", .{ save_version, self.config.version });
                return error.SaveFromNewerVersion;
            }
            if (save_version < self.config.min_loadable_version) {
                self.logger.@"error"("Save is too old ({d} < {d})", .{ save_version, self.config.min_loadable_version });
                return error.SaveTooOld;
            }

            // Read metadata if present
            if (self.config.include_metadata) {
                _ = try reader.readI64(); // timestamp
                const game_name = try reader.readString();
                defer self.allocator.free(game_name);
                self.logger.debug("Game name: {s}", .{game_name});
            }

            // Read entity count (for info)
            const entity_count = try reader.readU32();
            self.logger.debug("Entity count: {d}", .{entity_count});

            // Read component type count
            const comp_type_count = try reader.readU32();
            self.logger.debug("Component type count: {d}", .{comp_type_count});

            // Build entity mapping: old ID -> new Entity
            var entity_map = EntityMap.init(self.allocator);
            defer entity_map.deinit();

            // First pass: collect all entity IDs and create new entities
            const start_pos = reader.pos;
            try self.collectEntities(&reader, &entity_map, registry, comp_type_count);
            self.logger.debug("Created {d} entities", .{entity_map.count()});

            // Reset position for second pass
            reader.pos = start_pos;

            // Second pass: deserialize components
            try self.deserializeComponents(&reader, &entity_map, registry, comp_type_count);

            self.logger.info("Binary deserialization complete: {d} entities loaded", .{entity_map.count()});
        }

        fn collectEntities(self: *Self, reader: *BinaryReader, entity_map: *EntityMap, registry: *ecs.Registry, comp_type_count: u32) !void {
            for (0..comp_type_count) |_| {
                // Read component name
                const name = try reader.readString();
                defer self.allocator.free(name);

                // Read instance count
                const instance_count = try reader.readU32();

                // Check if this is a known component type
                var found = false;
                inline for (ComponentTypes) |T| {
                    if (std.mem.eql(u8, @typeName(T), name)) {
                        found = true;
                        // Read entity IDs
                        for (0..instance_count) |_| {
                            const old_id = try reader.readEntityRaw();
                            if (!entity_map.contains(old_id)) {
                                const new_entity = registry.create();
                                try entity_map.put(old_id, new_entity);
                            }

                            // Skip component data if not a tag
                            if (@sizeOf(T) > 0) {
                                _ = try reader.readValue(T);
                            }
                        }
                        break;
                    }
                }

                // Skip unknown component types
                if (!found) {
                    // We can't skip properly without knowing the size, so this is an error
                    // In a more robust implementation, we'd store size info in the format
                    return error.UnknownComponentType;
                }
            }
        }

        fn deserializeComponents(self: *Self, reader: *BinaryReader, entity_map: *const EntityMap, registry: *ecs.Registry, comp_type_count: u32) !void {
            for (0..comp_type_count) |_| {
                // Read component name
                const name = try reader.readString();
                defer self.allocator.free(name);

                // Read instance count
                const instance_count = try reader.readU32();

                // Find matching component type
                inline for (ComponentTypes) |T| {
                    if (std.mem.eql(u8, @typeName(T), name)) {
                        for (0..instance_count) |_| {
                            const old_id = try reader.readEntityRaw();
                            const entity = entity_map.get(old_id) orelse return error.InvalidEntityReference;

                            if (@sizeOf(T) == 0) {
                                // Tag component
                                registry.add(entity, T{});
                            } else {
                                // Data component
                                var component = try reader.readValue(T);

                                // Remap entity references
                                remapEntityRefs(T, &component, entity_map);

                                registry.add(entity, component);
                            }
                        }
                        break;
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

        /// Save registry to file in binary format
        pub fn save(self: *Self, registry: *ecs.Registry, path: []const u8) !void {
            const data = try self.serialize(registry);
            defer self.allocator.free(data);

            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();

            try file.writeAll(data);
        }

        /// Load registry from binary file
        pub fn load(self: *Self, registry: *ecs.Registry, path: []const u8) !void {
            const file = try std.fs.cwd().openFile(path, .{});
            defer file.close();

            const data = try file.readToEndAlloc(self.allocator, 1024 * 1024 * 100); // 100MB max
            defer self.allocator.free(data);

            try self.deserialize(registry, data);
        }
    };
}
