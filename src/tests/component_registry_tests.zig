//! Tests for ComponentRegistry

const std = @import("std");
const ComponentRegistry = @import("../component_registry.zig").ComponentRegistry;

// Test types
const TestPosition = struct { x: f32, y: f32 };
const TestHealth = struct { current: u8, max: u8 };
const TestPlayer = struct {}; // Tag
const TestDebug = struct { info: []const u8 };

test "fromTuple creates type list" {
    const types = ComponentRegistry.fromTuple(.{ TestPosition, TestHealth, TestPlayer });
    try std.testing.expectEqual(@as(usize, 3), types.len);
    try std.testing.expect(types[0] == TestPosition);
    try std.testing.expect(types[1] == TestHealth);
    try std.testing.expect(types[2] == TestPlayer);
}

test "exclude removes types from list" {
    const all = &[_]type{ TestPosition, TestHealth, TestPlayer, TestDebug };
    const filtered = comptime ComponentRegistry.exclude(all, .{TestDebug});

    try std.testing.expectEqual(@as(usize, 3), filtered.len);
    try std.testing.expect(comptime ComponentRegistry.contains(filtered, TestPosition));
    try std.testing.expect(comptime ComponentRegistry.contains(filtered, TestHealth));
    try std.testing.expect(comptime ComponentRegistry.contains(filtered, TestPlayer));
    try std.testing.expect(comptime !ComponentRegistry.contains(filtered, TestDebug));
}

test "merge combines type lists" {
    const list1 = &[_]type{ TestPosition, TestHealth };
    const list2 = &[_]type{ TestPlayer, TestDebug };
    const merged = ComponentRegistry.merge(.{ list1, list2 });

    try std.testing.expectEqual(@as(usize, 4), merged.len);
}

test "contains checks for type presence" {
    const types = &[_]type{ TestPosition, TestHealth };
    try std.testing.expect(ComponentRegistry.contains(types, TestPosition));
    try std.testing.expect(ComponentRegistry.contains(types, TestHealth));
    try std.testing.expect(!ComponentRegistry.contains(types, TestPlayer));
}

test "count returns list length" {
    const types = &[_]type{ TestPosition, TestHealth, TestPlayer };
    try std.testing.expectEqual(@as(usize, 3), ComponentRegistry.count(types));
}

// Test module for fromModule
const TestComponentModule = struct {
    pub const Position = struct { x: f32, y: f32 };
    pub const Health = struct { hp: u32 };
    pub const Tag = struct {};

    // These should be ignored
    pub const some_value: u32 = 42;
    pub fn someFunction() void {}
};

test "fromModule extracts struct types" {
    const types = ComponentRegistry.fromModule(TestComponentModule);
    try std.testing.expectEqual(@as(usize, 3), types.len);
}

test "validateSerializable passes for valid types" {
    // These types should pass validation
    const valid_types = &[_]type{ TestPosition, TestHealth, TestPlayer };

    // This should compile without error - validates at comptime
    comptime ComponentRegistry.validateSerializable(valid_types);

    // If we get here, validation passed
    try std.testing.expect(true);
}

test "validateSerializable handles nested structs" {
    const NestedComponent = struct {
        inner: struct {
            value: u32,
        },
        name: []const u8,
    };

    const types = &[_]type{NestedComponent};
    comptime ComponentRegistry.validateSerializable(types);
    try std.testing.expect(true);
}
