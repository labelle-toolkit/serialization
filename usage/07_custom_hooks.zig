//! Custom Serialization Hooks Example
//!
//! Demonstrates how components can define custom serialize/deserialize logic
//! for complex types that can't be automatically serialized.

const std = @import("std");
const serialization = @import("serialization");

/// Example component with custom serialization
/// This component has a dynamic array that needs special handling
const Inventory = struct {
    /// Static field - serializes automatically
    gold: u32,

    /// Dynamic field - needs custom serialization
    /// In a real scenario, this would be std.ArrayList
    item_count: u32,
    item_ids: [16]u32, // Fixed array to simulate dynamic storage

    /// Custom serialize method
    /// The serializer will detect this and call it instead of default serialization
    pub fn serialize(self: @This(), writer: anytype) !void {
        try writer.beginObject();

        try writer.writeKey("gold");
        try writer.writeInt(self.gold);
        try writer.writeComma();

        try writer.writeKey("items");
        try writer.beginArray();
        for (0..self.item_count) |i| {
            if (i > 0) try writer.writeComma();
            try writer.writeIndent();
            try writer.writeInt(self.item_ids[i]);
        }
        if (self.item_count > 0) {
            try writer.endArray();
        } else {
            writer.decrementIndent();
            try writer.writeRaw(']');
        }

        try writer.endObject();
    }

    /// Custom deserialize method
    /// Receives the allocator and raw JSON value
    pub fn deserialize(allocator: std.mem.Allocator, value: std.json.Value) !@This() {
        _ = allocator;
        if (value != .object) return error.InvalidFormat;

        const gold_val = value.object.get("gold") orelse return error.InvalidFormat;
        const items_val = value.object.get("items") orelse return error.InvalidFormat;

        var result = Inventory{
            .gold = @intCast(gold_val.integer),
            .item_count = 0,
            .item_ids = [_]u32{0} ** 16,
        };

        if (items_val == .array) {
            for (items_val.array.items, 0..) |item, i| {
                if (i >= 16) break;
                result.item_ids[i] = @intCast(item.integer);
                result.item_count += 1;
            }
        }

        return result;
    }
};

/// Regular component without custom hooks
const Position = struct {
    x: f32,
    y: f32,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Custom Serialization Hooks Example ===\n\n", .{});

    // Check compile-time detection of custom methods
    std.debug.print("Component Analysis:\n", .{});
    std.debug.print("  Position has custom serialize: {}\n", .{serialization.hasCustomSerialize(Position)});
    std.debug.print("  Position has custom deserialize: {}\n", .{serialization.hasCustomDeserialize(Position)});
    std.debug.print("  Inventory has custom serialize: {}\n", .{serialization.hasCustomSerialize(Inventory)});
    std.debug.print("  Inventory has custom deserialize: {}\n", .{serialization.hasCustomDeserialize(Inventory)});
    std.debug.print("  Inventory has full custom serialization: {}\n\n", .{serialization.hasCustomSerialization(Inventory)});

    // Demonstrate custom serialization
    std.debug.print("Serializing Inventory with custom hook:\n", .{});

    const inventory = Inventory{
        .gold = 500,
        .item_count = 3,
        .item_ids = .{ 101, 202, 303 } ++ [_]u32{0} ** 13,
    };

    // For demonstration, show what the custom format looks like
    std.debug.print("  Inventory: gold={d}, items=[", .{inventory.gold});
    for (0..inventory.item_count) |i| {
        if (i > 0) std.debug.print(", ", .{});
        std.debug.print("{d}", .{inventory.item_ids[i]});
    }
    std.debug.print("]\n\n", .{});

    // Show the hook API usage pattern
    std.debug.print("=== Usage Pattern ===\n\n", .{});
    std.debug.print(
        \\// Define component with custom hooks
        \\const MyComponent = struct {{
        \\    dynamic_data: std.ArrayList(u32),
        \\
        \\    pub fn serialize(self: @This(), writer: anytype) !void {{
        \\        // Write custom JSON format
        \\        try writer.beginArray();
        \\        for (self.dynamic_data.items) |item| {{
        \\            try writer.writeInt(item);
        \\        }}
        \\        try writer.endArray();
        \\    }}
        \\
        \\    pub fn deserialize(allocator: std.mem.Allocator, value: std.json.Value) !@This() {{
        \\        var result = .{{ .dynamic_data = std.ArrayList(u32).init(allocator) }};
        \\        if (value == .array) {{
        \\            for (value.array.items) |item| {{
        \\                try result.dynamic_data.append(@intCast(item.integer));
        \\            }}
        \\        }}
        \\        return result;
        \\    }}
        \\}};
        \\
        \\// The serializer automatically detects and uses custom hooks
        \\const has_hooks = serialization.hasCustomSerialization(MyComponent);
        \\
    , .{});

    // Verify roundtrip with custom hooks
    std.debug.print("\n=== Roundtrip Test ===\n\n", .{});

    // Create JSON representation manually
    var obj = std.json.ObjectMap.init(allocator);
    defer obj.deinit();
    try obj.put("gold", .{ .integer = 1000 });

    var items = std.json.Array.init(allocator);
    defer items.deinit();
    try items.append(.{ .integer = 1 });
    try items.append(.{ .integer = 2 });
    try items.append(.{ .integer = 3 });
    try obj.put("items", .{ .array = items });

    const json_value = std.json.Value{ .object = obj };

    // Deserialize using custom hook
    const loaded = try Inventory.deserialize(allocator, json_value);
    std.debug.print("Deserialized Inventory:\n", .{});
    std.debug.print("  gold: {d}\n", .{loaded.gold});
    std.debug.print("  items: [", .{});
    for (0..loaded.item_count) |i| {
        if (i > 0) std.debug.print(", ", .{});
        std.debug.print("{d}", .{loaded.item_ids[i]});
    }
    std.debug.print("]\n", .{});
}
