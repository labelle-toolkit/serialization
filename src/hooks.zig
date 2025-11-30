//! Custom serialization hooks
//!
//! Allows components to define custom serialize/deserialize logic
//! for complex types that can't be automatically serialized.
//!
//! Components can opt into custom serialization by defining:
//! - `pub fn serialize(self: @This(), writer: anytype) !void`
//! - `pub fn deserialize(allocator: std.mem.Allocator, value: std.json.Value) !@This()`
//!
//! Example:
//! ```zig
//! const Inventory = struct {
//!     items: std.ArrayList(Item),
//!     gold: u32,
//!
//!     pub fn serialize(self: @This(), writer: anytype) !void {
//!         try writer.beginObject();
//!         try writer.writeKey("gold");
//!         try writer.writeInt(self.gold);
//!         try writer.writeComma();
//!         try writer.writeKey("items");
//!         try writer.beginArray();
//!         for (self.items.items, 0..) |item, i| {
//!             if (i > 0) try writer.writeComma();
//!             try writer.writeIndent();
//!             try writer.writeValue(item);
//!         }
//!         try writer.endArray();
//!         try writer.endObject();
//!     }
//!
//!     pub fn deserialize(allocator: std.mem.Allocator, value: std.json.Value) !@This() {
//!         const gold = JsonReader.getField(value, "gold") orelse return error.InvalidFormat;
//!         const items_val = JsonReader.getField(value, "items") orelse return error.InvalidFormat;
//!
//!         var items = std.ArrayList(Item).init(allocator);
//!         if (items_val == .array) {
//!             for (items_val.array.items) |item| {
//!                 try items.append(try JsonReader.readValue(allocator, Item, item));
//!             }
//!         }
//!
//!         return .{ .items = items, .gold = @intCast(gold.integer) };
//!     }
//! };
//! ```

const std = @import("std");

/// Check if a type has a custom serialize method
pub fn hasCustomSerialize(comptime T: type) bool {
    if (!@hasDecl(T, "serialize")) return false;

    const SerializeFn = @TypeOf(@field(T, "serialize"));
    const fn_info = @typeInfo(SerializeFn);

    if (fn_info != .@"fn") return false;

    const params = fn_info.@"fn".params;
    // Should have 2 params: self and writer
    if (params.len != 2) return false;

    // First param should be the type itself (or pointer to it)
    const first_param = params[0].type orelse return false;
    if (first_param != T and first_param != *const T and first_param != *T) return false;

    return true;
}

/// Check if a type has a custom deserialize method
pub fn hasCustomDeserialize(comptime T: type) bool {
    if (!@hasDecl(T, "deserialize")) return false;

    const DeserializeFn = @TypeOf(@field(T, "deserialize"));
    const fn_info = @typeInfo(DeserializeFn);

    if (fn_info != .@"fn") return false;

    const params = fn_info.@"fn".params;
    // Should have 2 params: allocator and json value
    if (params.len != 2) return false;

    // First param should be allocator
    const first_param = params[0].type orelse return false;
    if (first_param != std.mem.Allocator) return false;

    // Second param should be std.json.Value
    const second_param = params[1].type orelse return false;
    if (second_param != std.json.Value) return false;

    return true;
}

/// Check if a type has both custom serialize and deserialize
pub fn hasCustomSerialization(comptime T: type) bool {
    return hasCustomSerialize(T) and hasCustomDeserialize(T);
}

/// Marker trait for types that opt out of automatic serialization
/// Add `pub const serialization_custom = true;` to your type to indicate
/// it must use custom serialization (will error if hooks not defined)
pub fn requiresCustomSerialization(comptime T: type) bool {
    return @hasDecl(T, "serialization_custom") and T.serialization_custom;
}

/// Serialize a value using custom hooks if available, otherwise use default
pub fn serializeValue(comptime T: type, value: T, writer: anytype) !void {
    if (comptime hasCustomSerialize(T)) {
        try value.serialize(writer);
    } else if (comptime requiresCustomSerialization(T)) {
        @compileError("Type '" ++ @typeName(T) ++ "' requires custom serialization but no serialize method defined");
    } else {
        try writer.writeValue(value);
    }
}

/// Deserialize a value using custom hooks if available, otherwise use default
pub fn deserializeValue(comptime T: type, allocator: std.mem.Allocator, value: std.json.Value, reader: anytype) !T {
    _ = reader;
    if (comptime hasCustomDeserialize(T)) {
        return T.deserialize(allocator, value);
    } else if (comptime requiresCustomSerialization(T)) {
        @compileError("Type '" ++ @typeName(T) ++ "' requires custom serialization but no deserialize method defined");
    } else {
        const JsonReader = @import("json_reader.zig").JsonReader;
        return JsonReader.readValue(allocator, T, value);
    }
}

// Tests

const TestItem = struct {
    id: u32,
    name: []const u8,
};

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

test "serializeValue uses custom method when available" {
    const allocator = std.testing.allocator;
    const JsonWriter = @import("json_writer.zig").JsonWriter;

    var writer = JsonWriter.init(allocator, false);
    defer writer.deinit();

    const custom = CustomComponent{ .data = 42, .extra = "hello" };
    try serializeValue(CustomComponent, custom, &writer);

    const result = writer.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "\"data\":42") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"extra\":\"hello\"") != null);
}

test "serializeValue uses default for regular types" {
    const allocator = std.testing.allocator;
    const JsonWriter = @import("json_writer.zig").JsonWriter;

    var writer = JsonWriter.init(allocator, false);
    defer writer.deinit();

    const regular = RegularComponent{ .x = 1.5, .y = 2.5 };
    try serializeValue(RegularComponent, regular, &writer);

    const result = writer.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "\"x\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"y\":") != null);
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
