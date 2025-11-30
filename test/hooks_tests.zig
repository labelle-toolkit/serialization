//! Tests for custom serialization hooks

const std = @import("std");
const serialization = @import("serialization");
const hasCustomSerialize = serialization.hasCustomSerialize;
const hasCustomDeserialize = serialization.hasCustomDeserialize;
const hasCustomSerialization = serialization.hasCustomSerialization;
const serializeValue = serialization.serializeValue;
const deserializeValue = serialization.deserializeValue;

const RegularComponent = struct {
    x: f32,
    y: f32,
};

const CustomComponent = struct {
    data: u32,
    extra: []const u8,

    pub fn serialize(self: @This(), writer: anytype) !void {
        try writer.beginObject();
        try writer.writeKey("data");
        try writer.writeInt(self.data);
        try writer.writeComma();
        try writer.writeKey("extra");
        try writer.writeString(self.extra);
        try writer.endObject();
    }

    pub fn deserialize(allocator: std.mem.Allocator, value: std.json.Value) !@This() {
        _ = allocator;
        if (value != .object) return error.InvalidFormat;

        const data_val = value.object.get("data") orelse return error.InvalidFormat;
        const extra_val = value.object.get("extra") orelse return error.InvalidFormat;

        return .{
            .data = @intCast(data_val.integer),
            .extra = extra_val.string,
        };
    }
};

const PartialCustomComponent = struct {
    value: u32,

    // Only has serialize, not deserialize
    pub fn serialize(self: @This(), writer: anytype) !void {
        try writer.writeInt(self.value);
    }
};

test "hasCustomSerialize detects serialize method" {
    try std.testing.expect(!hasCustomSerialize(RegularComponent));
    try std.testing.expect(hasCustomSerialize(CustomComponent));
    try std.testing.expect(hasCustomSerialize(PartialCustomComponent));
}

test "hasCustomDeserialize detects deserialize method" {
    try std.testing.expect(!hasCustomDeserialize(RegularComponent));
    try std.testing.expect(hasCustomDeserialize(CustomComponent));
    try std.testing.expect(!hasCustomDeserialize(PartialCustomComponent));
}

test "hasCustomSerialization requires both methods" {
    try std.testing.expect(!hasCustomSerialization(RegularComponent));
    try std.testing.expect(hasCustomSerialization(CustomComponent));
    try std.testing.expect(!hasCustomSerialization(PartialCustomComponent));
}

test "deserializeValue uses custom method when available" {
    const allocator = std.testing.allocator;

    // Create a JSON value manually
    var obj = std.json.ObjectMap.init(allocator);
    defer obj.deinit();
    try obj.put("data", .{ .integer = 123 });
    try obj.put("extra", .{ .string = "world" });

    const value = std.json.Value{ .object = obj };

    const result = try deserializeValue(CustomComponent, allocator, value, null);
    try std.testing.expectEqual(@as(u32, 123), result.data);
    try std.testing.expectEqualStrings("world", result.extra);
}
