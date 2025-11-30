//! Debug and inspection tools for save files
//!
//! Provides utilities for debugging serialization without requiring
//! full deserialization or access to component types.

const std = @import("std");

/// Statistics about a save file
pub const SaveStats = struct {
    /// Number of unique entities in the save
    entity_count: usize,
    /// Number of component types
    component_types: usize,
    /// Total number of component instances
    component_instances: usize,
    /// Size of the JSON in bytes
    file_size: usize,
    /// Save format version (if present)
    version: ?u32,
    /// Game name (if present, owned copy)
    game_name: ?[]const u8,
    /// Timestamp (if present)
    timestamp: ?i64,

    /// Component breakdown by type (names are owned copies)
    components: []const ComponentStats,

    /// Allocator used for owned strings
    allocator: std.mem.Allocator,

    pub fn deinit(self: *SaveStats) void {
        if (self.game_name) |name| {
            self.allocator.free(name);
        }
        for (self.components) |comp| {
            self.allocator.free(comp.name);
        }
        self.allocator.free(self.components);
    }
};

/// Statistics for a single component type
pub const ComponentStats = struct {
    name: []const u8,
    instance_count: usize,
};

/// Result of diffing two save files
pub const RegistryDiff = struct {
    /// Entity IDs that exist in save2 but not save1
    added_entities: []const u32,
    /// Entity IDs that exist in save1 but not save2
    removed_entities: []const u32,
    /// Entity IDs that exist in both but have different component data
    /// Note: Currently unimplemented and always empty
    modified_entities: []const u32,
    /// Component types added in save2
    added_components: []const []const u8,
    /// Component types removed from save1
    removed_components: []const []const u8,

    allocator: std.mem.Allocator,

    pub fn deinit(self: *RegistryDiff) void {
        self.allocator.free(self.added_entities);
        self.allocator.free(self.removed_entities);
        self.allocator.free(self.modified_entities);
        for (self.added_components) |name| {
            self.allocator.free(name);
        }
        self.allocator.free(self.added_components);
        for (self.removed_components) |name| {
            self.allocator.free(name);
        }
        self.allocator.free(self.removed_components);
    }
};

/// Get statistics about a save file without fully loading it
pub fn getStats(allocator: std.mem.Allocator, json_str: []const u8) !SaveStats {
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_str,
        .{},
    );
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.InvalidSaveFormat;

    var stats = SaveStats{
        .entity_count = 0,
        .component_types = 0,
        .component_instances = 0,
        .file_size = json_str.len,
        .version = null,
        .game_name = null,
        .timestamp = null,
        .components = &[_]ComponentStats{},
        .allocator = allocator,
    };

    // Parse metadata
    if (root.object.get("meta")) |meta| {
        if (meta == .object) {
            if (meta.object.get("version")) |v| {
                if (v == .integer) stats.version = @intCast(v.integer);
            }
            if (meta.object.get("game_name")) |v| {
                if (v == .string) stats.game_name = try allocator.dupe(u8, v.string);
            }
            if (meta.object.get("timestamp")) |v| {
                if (v == .integer) stats.timestamp = v.integer;
            }
        }
    }
    errdefer if (stats.game_name) |name| allocator.free(name);

    // Parse components
    const components = root.object.get("components") orelse return error.InvalidSaveFormat;
    if (components != .object) return error.InvalidSaveFormat;

    // Collect unique entity IDs and component stats
    var entity_set = std.AutoHashMap(u32, void).init(allocator);
    defer entity_set.deinit();

    var component_stats: std.ArrayListUnmanaged(ComponentStats) = .{};
    errdefer {
        for (component_stats.items) |comp| {
            allocator.free(comp.name);
        }
        component_stats.deinit(allocator);
    }

    var comp_iter = components.object.iterator();
    while (comp_iter.next()) |entry| {
        const comp_name = entry.key_ptr.*;
        const comp_data = entry.value_ptr.*;

        if (comp_data != .array) continue;

        const instance_count = comp_data.array.items.len;
        stats.component_instances += instance_count;

        const duped_name = try allocator.dupe(u8, comp_name);
        errdefer allocator.free(duped_name);

        try component_stats.append(allocator, .{
            .name = duped_name,
            .instance_count = instance_count,
        });

        // Collect entity IDs
        for (comp_data.array.items) |item| {
            const entity_id = getEntityIdFromItem(item) catch continue;
            try entity_set.put(entity_id, {});
        }
    }

    stats.entity_count = entity_set.count();
    stats.component_types = component_stats.items.len;
    stats.components = try component_stats.toOwnedSlice(allocator);

    return stats;
}

fn getEntityIdFromItem(item: std.json.Value) !u32 {
    // Tag component - item is just the entity ID
    if (item == .integer) {
        return @intCast(item.integer);
    }
    // Data component - item is { "entt": id, "data": ... }
    if (item == .object) {
        const entt = item.object.get("entt") orelse return error.InvalidFormat;
        if (entt == .integer) {
            return @intCast(entt.integer);
        }
    }
    return error.InvalidFormat;
}

/// Pretty-print a JSON save file
pub fn prettyPrint(allocator: std.mem.Allocator, json_str: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_str,
        .{},
    );
    defer parsed.deinit();

    return jsonValueToStringPretty(allocator, parsed.value);
}

fn jsonValueToStringPretty(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: std.io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    var write_stream: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .indent_2 },
    };
    try write_stream.write(value);
    return out.toOwnedSlice();
}

/// Diff two save files and return the differences
pub fn diffSaves(allocator: std.mem.Allocator, json1: []const u8, json2: []const u8) !RegistryDiff {
    const parsed1 = try std.json.parseFromSlice(std.json.Value, allocator, json1, .{});
    defer parsed1.deinit();

    const parsed2 = try std.json.parseFromSlice(std.json.Value, allocator, json2, .{});
    defer parsed2.deinit();

    const root1 = parsed1.value;
    const root2 = parsed2.value;

    if (root1 != .object or root2 != .object) return error.InvalidSaveFormat;

    const components1 = root1.object.get("components") orelse return error.InvalidSaveFormat;
    const components2 = root2.object.get("components") orelse return error.InvalidSaveFormat;

    if (components1 != .object or components2 != .object) return error.InvalidSaveFormat;

    // Collect entities from both saves
    var entities1 = std.AutoHashMap(u32, void).init(allocator);
    defer entities1.deinit();
    var entities2 = std.AutoHashMap(u32, void).init(allocator);
    defer entities2.deinit();

    // Component types
    var comp_types1 = std.StringHashMap(void).init(allocator);
    defer comp_types1.deinit();
    var comp_types2 = std.StringHashMap(void).init(allocator);
    defer comp_types2.deinit();

    // Collect from save1
    var iter1 = components1.object.iterator();
    while (iter1.next()) |entry| {
        try comp_types1.put(entry.key_ptr.*, {});
        if (entry.value_ptr.* == .array) {
            for (entry.value_ptr.array.items) |item| {
                const entity_id = getEntityIdFromItem(item) catch continue;
                try entities1.put(entity_id, {});
            }
        }
    }

    // Collect from save2
    var iter2 = components2.object.iterator();
    while (iter2.next()) |entry| {
        try comp_types2.put(entry.key_ptr.*, {});
        if (entry.value_ptr.* == .array) {
            for (entry.value_ptr.array.items) |item| {
                const entity_id = getEntityIdFromItem(item) catch continue;
                try entities2.put(entity_id, {});
            }
        }
    }

    // Find added entities (in save2 but not save1)
    var added: std.ArrayListUnmanaged(u32) = .{};
    errdefer added.deinit(allocator);
    var iter_e2 = entities2.keyIterator();
    while (iter_e2.next()) |key| {
        if (!entities1.contains(key.*)) {
            try added.append(allocator, key.*);
        }
    }

    // Find removed entities (in save1 but not save2)
    var removed: std.ArrayListUnmanaged(u32) = .{};
    errdefer removed.deinit(allocator);
    var iter_e1 = entities1.keyIterator();
    while (iter_e1.next()) |key| {
        if (!entities2.contains(key.*)) {
            try removed.append(allocator, key.*);
        }
    }

    // Find added component types
    var added_comps: std.ArrayListUnmanaged([]const u8) = .{};
    errdefer {
        for (added_comps.items) |item| allocator.free(item);
        added_comps.deinit(allocator);
    }
    var iter_c2 = comp_types2.keyIterator();
    while (iter_c2.next()) |key| {
        if (!comp_types1.contains(key.*)) {
            const duped = try allocator.dupe(u8, key.*);
            try added_comps.append(allocator, duped);
        }
    }

    // Find removed component types
    var removed_comps: std.ArrayListUnmanaged([]const u8) = .{};
    errdefer {
        for (removed_comps.items) |item| allocator.free(item);
        removed_comps.deinit(allocator);
    }
    var iter_c1 = comp_types1.keyIterator();
    while (iter_c1.next()) |key| {
        if (!comp_types2.contains(key.*)) {
            const duped = try allocator.dupe(u8, key.*);
            try removed_comps.append(allocator, duped);
        }
    }

    return RegistryDiff{
        .added_entities = try added.toOwnedSlice(allocator),
        .removed_entities = try removed.toOwnedSlice(allocator),
        .modified_entities = &[_]u32{}, // TODO: implement component data comparison
        .added_components = try added_comps.toOwnedSlice(allocator),
        .removed_components = try removed_comps.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

/// Format save stats for display
pub fn formatStats(stats: SaveStats, writer: anytype) !void {
    try writer.print("Save File Statistics\n", .{});
    try writer.print("====================\n", .{});
    if (stats.version) |v| {
        try writer.print("Version: {d}\n", .{v});
    }
    if (stats.game_name) |name| {
        try writer.print("Game: {s}\n", .{name});
    }
    try writer.print("File size: {d} bytes\n", .{stats.file_size});
    try writer.print("Entities: {d}\n", .{stats.entity_count});
    try writer.print("Component types: {d}\n", .{stats.component_types});
    try writer.print("Component instances: {d}\n", .{stats.component_instances});
    try writer.print("\nComponents:\n", .{});
    for (stats.components) |comp| {
        try writer.print("  {s}: {d} instances\n", .{ comp.name, comp.instance_count });
    }
}

/// Format diff for display
pub fn formatDiff(diff: RegistryDiff, writer: anytype) !void {
    try writer.print("Save File Diff\n", .{});
    try writer.print("==============\n", .{});

    if (diff.added_entities.len > 0) {
        try writer.print("\nAdded entities ({d}):\n", .{diff.added_entities.len});
        for (diff.added_entities) |id| {
            try writer.print("  + {d}\n", .{id});
        }
    }

    if (diff.removed_entities.len > 0) {
        try writer.print("\nRemoved entities ({d}):\n", .{diff.removed_entities.len});
        for (diff.removed_entities) |id| {
            try writer.print("  - {d}\n", .{id});
        }
    }

    if (diff.added_components.len > 0) {
        try writer.print("\nAdded component types:\n", .{});
        for (diff.added_components) |name| {
            try writer.print("  + {s}\n", .{name});
        }
    }

    if (diff.removed_components.len > 0) {
        try writer.print("\nRemoved component types:\n", .{});
        for (diff.removed_components) |name| {
            try writer.print("  - {s}\n", .{name});
        }
    }

    if (diff.added_entities.len == 0 and diff.removed_entities.len == 0 and
        diff.added_components.len == 0 and diff.removed_components.len == 0)
    {
        try writer.print("\nNo differences found.\n", .{});
    }
}
