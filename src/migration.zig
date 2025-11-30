//! Version migration system for upgrading old save files
//!
//! This module provides tools for migrating save files between versions
//! when game updates change component structures.

const std = @import("std");

/// Migration function type
pub const MigrationFn = *const fn (*MigrationContext) anyerror!void;

/// Migration step representing a version-to-version migration
pub const MigrationStep = struct {
    from_version: u32,
    to_version: u32,
    migrate: MigrationFn,
};

/// Context for performing migrations on JSON data
pub const MigrationContext = struct {
    allocator: std.mem.Allocator,
    root: std.json.Value,
    log: std.ArrayListUnmanaged([]const u8),
    parsed: std.json.Parsed(std.json.Value),
    /// Track strings we allocate for new keys so we can free them
    allocated_keys: std.ArrayListUnmanaged([]const u8),

    pub fn init(allocator: std.mem.Allocator, json_str: []const u8) !MigrationContext {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            json_str,
            .{ .allocate = .alloc_always },
        );

        return .{
            .allocator = allocator,
            .root = parsed.value,
            .log = .{},
            .parsed = parsed,
            .allocated_keys = .{},
        };
    }

    pub fn deinit(self: *MigrationContext) void {
        for (self.log.items) |msg| {
            self.allocator.free(msg);
        }
        self.log.deinit(self.allocator);
        // Free all keys we allocated for new entries
        for (self.allocated_keys.items) |key| {
            self.allocator.free(key);
        }
        self.allocated_keys.deinit(self.allocator);
        self.parsed.deinit();
    }

    /// Get the current version from metadata
    pub fn getVersion(self: *MigrationContext) ?u32 {
        if (self.root != .object) return null;
        const meta = self.root.object.get("meta") orelse return null;
        if (meta != .object) return null;
        const version = meta.object.get("version") orelse return null;
        if (version != .integer) return null;
        return @intCast(version.integer);
    }

    /// Set the version in metadata
    pub fn setVersion(self: *MigrationContext, version: u32) !void {
        if (self.root != .object) return error.InvalidFormat;
        const meta = self.root.object.getPtr("meta") orelse return error.InvalidFormat;
        if (meta.* != .object) return error.InvalidFormat;
        try meta.object.put("version", .{ .integer = @intCast(version) });
    }

    /// Rename a component type
    pub fn renameComponent(self: *MigrationContext, old_name: []const u8, new_name: []const u8) !void {
        if (self.root != .object) return error.InvalidFormat;
        const components = self.root.object.getPtr("components") orelse return error.InvalidFormat;
        if (components.* != .object) return error.InvalidFormat;

        if (components.object.fetchSwapRemove(old_name)) |entry| {
            const new_key = try self.allocator.dupe(u8, new_name);
            try self.allocated_keys.append(self.allocator, new_key);
            try components.object.put(new_key, entry.value);
            try self.addLog("Renamed component '{s}' to '{s}'", .{ old_name, new_name });
        }
    }

    /// Remove a component type entirely
    pub fn removeComponent(self: *MigrationContext, name: []const u8) !void {
        if (self.root != .object) return error.InvalidFormat;
        const components = self.root.object.getPtr("components") orelse return error.InvalidFormat;
        if (components.* != .object) return error.InvalidFormat;

        if (components.object.swapRemove(name)) {
            try self.addLog("Removed component '{s}'", .{name});
        }
    }

    /// Add a default value for a new field in a component
    pub fn addFieldDefault(self: *MigrationContext, component_name: []const u8, field_name: []const u8, default_value: std.json.Value) !void {
        if (self.root != .object) return error.InvalidFormat;
        const components = self.root.object.getPtr("components") orelse return error.InvalidFormat;
        if (components.* != .object) return error.InvalidFormat;

        const comp_data = components.object.getPtr(component_name) orelse return;
        if (comp_data.* != .array) return;

        for (comp_data.array.items) |*item| {
            if (item.* != .object) continue;
            const data = item.object.getPtr("data") orelse continue;
            if (data.* != .object) continue;

            // Only add if field doesn't exist
            if (!data.object.contains(field_name)) {
                const new_key = try self.allocator.dupe(u8, field_name);
                try self.allocated_keys.append(self.allocator, new_key);
                try data.object.put(new_key, default_value);
            }
        }
        try self.addLog("Added field '{s}' with default to component '{s}'", .{ field_name, component_name });
    }

    /// Rename a field within a component
    pub fn renameField(self: *MigrationContext, component_name: []const u8, old_field: []const u8, new_field: []const u8) !void {
        if (self.root != .object) return error.InvalidFormat;
        const components = self.root.object.getPtr("components") orelse return error.InvalidFormat;
        if (components.* != .object) return error.InvalidFormat;

        const comp_data = components.object.getPtr(component_name) orelse return;
        if (comp_data.* != .array) return;

        for (comp_data.array.items) |*item| {
            if (item.* != .object) continue;
            const data = item.object.getPtr("data") orelse continue;
            if (data.* != .object) continue;

            if (data.object.fetchSwapRemove(old_field)) |entry| {
                const new_key = try self.allocator.dupe(u8, new_field);
                try self.allocated_keys.append(self.allocator, new_key);
                try data.object.put(new_key, entry.value);
            }
        }
        try self.addLog("Renamed field '{s}' to '{s}' in component '{s}'", .{ old_field, new_field, component_name });
    }

    /// Transform a field value using a provided function
    pub fn transformFieldInt(self: *MigrationContext, component_name: []const u8, field_name: []const u8, transform: *const fn (i64) i64) !void {
        if (self.root != .object) return error.InvalidFormat;
        const components = self.root.object.getPtr("components") orelse return error.InvalidFormat;
        if (components.* != .object) return error.InvalidFormat;

        const comp_data = components.object.getPtr(component_name) orelse return;
        if (comp_data.* != .array) return;

        for (comp_data.array.items) |*item| {
            if (item.* != .object) continue;
            const data = item.object.getPtr("data") orelse continue;
            if (data.* != .object) continue;

            if (data.object.getPtr(field_name)) |field_ptr| {
                if (field_ptr.* == .integer) {
                    field_ptr.* = .{ .integer = transform(field_ptr.integer) };
                }
            }
        }
        try self.addLog("Transformed field '{s}' in component '{s}'", .{ field_name, component_name });
    }

    /// Get the components object for advanced manipulation
    pub fn getComponents(self: *MigrationContext) ?*std.json.ObjectMap {
        if (self.root != .object) return null;
        const components = self.root.object.getPtr("components") orelse return null;
        if (components.* != .object) return null;
        return &components.object;
    }

    /// Add a log message
    fn addLog(self: *MigrationContext, comptime fmt: []const u8, args: anytype) !void {
        const msg = try std.fmt.allocPrint(self.allocator, fmt, args);
        try self.log.append(self.allocator, msg);
    }

    /// Get migration log
    pub fn getMigrationLog(self: *MigrationContext) []const []const u8 {
        return self.log.items;
    }

    /// Serialize the migrated data back to JSON
    pub fn toJson(self: *MigrationContext) ![]u8 {
        var out: std.io.Writer.Allocating = .init(self.allocator);
        errdefer out.deinit();

        var write_stream: std.json.Stringify = .{
            .writer = &out.writer,
            .options = .{ .whitespace = .indent_2 },
        };
        try write_stream.write(self.root);
        return out.toOwnedSlice();
    }
};

/// Migration registry for managing version migrations
pub fn MigrationRegistry(comptime max_migrations: usize) type {
    return struct {
        const Self = @This();

        migrations: [max_migrations]?MigrationStep = [_]?MigrationStep{null} ** max_migrations,
        count: usize = 0,

        /// Register a migration function
        pub fn register(self: *Self, from: u32, to: u32, migrate_fn: MigrationFn) void {
            if (self.count < max_migrations) {
                self.migrations[self.count] = .{
                    .from_version = from,
                    .to_version = to,
                    .migrate = migrate_fn,
                };
                self.count += 1;
            }
        }

        /// Run all necessary migrations to upgrade from current version to target
        pub fn migrate(self: *const Self, allocator: std.mem.Allocator, json_str: []const u8, target_version: u32) !MigrationResult {
            var ctx = try MigrationContext.init(allocator, json_str);
            errdefer ctx.deinit();

            var current = ctx.getVersion() orelse return error.MissingVersion;

            // Chain migrations until we reach target
            var migrations_run: u32 = 0;
            while (current < target_version) {
                var found = false;
                for (self.migrations[0..self.count]) |maybe_step| {
                    if (maybe_step) |step| {
                        if (step.from_version == current) {
                            try step.migrate(&ctx);
                            try ctx.setVersion(step.to_version);
                            current = step.to_version;
                            migrations_run += 1;
                            found = true;
                            break;
                        }
                    }
                }
                if (!found) {
                    return error.NoMigrationPath;
                }
            }

            const result_json = try ctx.toJson();
            errdefer allocator.free(result_json);

            // Transfer ownership of log entries to result
            const log_slice = try ctx.log.toOwnedSlice(allocator);

            // Clean up context resources (but not the log entries we transferred)
            // Free allocated keys
            for (ctx.allocated_keys.items) |key| {
                allocator.free(key);
            }
            ctx.allocated_keys.deinit(allocator);
            // Free parsed JSON data
            ctx.parsed.deinit();

            return .{
                .json = result_json,
                .migrations_run = migrations_run,
                .log = log_slice,
                .allocator = allocator,
            };
        }
    };
}

/// Result of a migration operation
pub const MigrationResult = struct {
    json: []u8,
    migrations_run: u32,
    log: [][]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *MigrationResult) void {
        self.allocator.free(self.json);
        for (self.log) |msg| {
            self.allocator.free(msg);
        }
        self.allocator.free(self.log);
    }
};
