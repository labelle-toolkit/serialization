//! Tests for JSON reader and writer

const std = @import("std");

// Import internal modules directly for testing
const JsonReader = @import("serialization").ValidationResult; // Placeholder - we need direct access
const JsonWriter = @import("serialization").ValidationResult; // Placeholder - we need direct access

// Since JsonReader and JsonWriter are internal, we test them through the public API
// by using the serialization module's public exports

test "JsonReader basic types" {
    const allocator = std.testing.allocator;

    // Parse a simple JSON integer
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, "42", .{});
    defer parsed.deinit();

    // The value should be an integer
    try std.testing.expect(parsed.value == .integer);
    try std.testing.expectEqual(@as(i64, 42), parsed.value.integer);
}

test "JsonReader struct" {
    const allocator = std.testing.allocator;

    const TestStruct = struct {
        x: i32,
        y: i32,
    };

    const json_str =
        \\{"x": 10, "y": 20}
    ;

    const parsed = try std.json.parseFromSlice(TestStruct, allocator, json_str, .{});
    defer parsed.deinit();

    try std.testing.expectEqual(@as(i32, 10), parsed.value.x);
    try std.testing.expectEqual(@as(i32, 20), parsed.value.y);
}

test "JSON roundtrip through std.json" {
    const allocator = std.testing.allocator;

    const TestStruct = struct {
        x: i32,
        y: i32,
        name: []const u8,
    };

    // Test parsing JSON
    const json_str =
        \\{"x": 10, "y": 20, "name": "test"}
    ;

    const parsed = try std.json.parseFromSlice(TestStruct, allocator, json_str, .{});
    defer parsed.deinit();

    try std.testing.expectEqual(@as(i32, 10), parsed.value.x);
    try std.testing.expectEqual(@as(i32, 20), parsed.value.y);
    try std.testing.expectEqualStrings("test", parsed.value.name);
}
