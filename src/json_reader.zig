//! JSON deserialization reader

const std = @import("std");
const ecs = @import("ecs");

/// JSON reader for deserialization
pub const JsonReader = struct {
    allocator: std.mem.Allocator,
    parsed: std.json.Parsed(std.json.Value),

    pub fn init(allocator: std.mem.Allocator, json_str: []const u8) !JsonReader {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            json_str,
            .{},
        );
        return .{
            .allocator = allocator,
            .parsed = parsed,
        };
    }

    pub fn deinit(self: *JsonReader) void {
        self.parsed.deinit();
    }

    pub fn root(self: *const JsonReader) std.json.Value {
        return self.parsed.value;
    }

    /// Get a field from an object
    pub fn getField(value: std.json.Value, key: []const u8) ?std.json.Value {
        if (value != .object) return null;
        return value.object.get(key);
    }

    /// Read a value of type T from JSON
    pub fn readValue(allocator: std.mem.Allocator, comptime T: type, value: std.json.Value) !T {
        const info = @typeInfo(T);

        switch (info) {
            .bool => {
                if (value != .bool) return error.TypeMismatch;
                return value.bool;
            },
            .int => {
                if (value == .integer) {
                    return @intCast(value.integer);
                } else if (value == .float) {
                    return @intFromFloat(value.float);
                }
                return error.TypeMismatch;
            },
            .float => {
                if (value == .float) {
                    return @floatCast(value.float);
                } else if (value == .integer) {
                    return @floatFromInt(value.integer);
                }
                return error.TypeMismatch;
            },
            .optional => |opt| {
                if (value == .null) return null;
                return try readValue(allocator, opt.child, value);
            },
            .@"enum" => |e| {
                if (T == ecs.Entity) {
                    if (value != .integer) return error.TypeMismatch;
                    return @enumFromInt(@as(u32, @intCast(value.integer)));
                }
                if (value != .string) return error.TypeMismatch;
                inline for (e.fields) |field| {
                    if (std.mem.eql(u8, field.name, value.string)) {
                        return @enumFromInt(field.value);
                    }
                }
                return error.InvalidEnumValue;
            },
            .array => |arr| {
                if (value != .array) return error.TypeMismatch;
                if (value.array.items.len != arr.len) return error.ArrayLengthMismatch;
                var result: T = undefined;
                for (value.array.items, 0..) |item, i| {
                    result[i] = try readValue(allocator, arr.child, item);
                }
                return result;
            },
            .pointer => |ptr| {
                if (ptr.size == .slice) {
                    if (ptr.child == u8) {
                        // String slice
                        if (value != .string) return error.TypeMismatch;
                        return try allocator.dupe(u8, value.string);
                    } else {
                        // Other slices
                        if (value != .array) return error.TypeMismatch;
                        const items = try allocator.alloc(ptr.child, value.array.items.len);
                        errdefer allocator.free(items);
                        for (value.array.items, 0..) |item, i| {
                            items[i] = try readValue(allocator, ptr.child, item);
                        }
                        return items;
                    }
                }
                @compileError("Non-slice pointers not supported");
            },
            .@"struct" => |s| {
                // Special case: Entity is a packed struct serialized as integer
                if (T == ecs.Entity) {
                    if (value != .integer) return error.TypeMismatch;
                    return @bitCast(@as(u32, @intCast(value.integer)));
                }

                if (value != .object) return error.TypeMismatch;
                var result: T = undefined;
                inline for (s.fields) |field| {
                    if (value.object.get(field.name)) |field_value| {
                        @field(result, field.name) = try readValue(allocator, field.type, field_value);
                    } else if (field.defaultValue()) |default| {
                        @field(result, field.name) = default;
                    } else {
                        return error.MissingField;
                    }
                }
                return result;
            },
            .@"union" => |u| {
                if (u.tag_type) |_| {
                    if (value != .object) return error.TypeMismatch;
                    const tag_value = value.object.get("tag") orelse return error.MissingField;
                    if (tag_value != .string) return error.TypeMismatch;
                    const tag_name = tag_value.string;

                    inline for (u.fields) |field| {
                        if (std.mem.eql(u8, field.name, tag_name)) {
                            if (field.type == void) {
                                return @unionInit(T, field.name, {});
                            } else {
                                const payload_value = value.object.get("value") orelse return error.MissingField;
                                const payload = try readValue(allocator, field.type, payload_value);
                                return @unionInit(T, field.name, payload);
                            }
                        }
                    }
                    return error.InvalidUnionTag;
                }
                @compileError("Untagged unions cannot be deserialized");
            },
            .void => return {},
            else => @compileError("Unsupported type for JSON deserialization: " ++ @typeName(T)),
        }
    }

    /// Read Entity ID, returning the raw u32 value for remapping
    pub fn readEntityRaw(value: std.json.Value) !u32 {
        if (value != .integer) return error.TypeMismatch;
        return @intCast(value.integer);
    }
};

const TypeMismatch = error.TypeMismatch;
const InvalidEnumValue = error.InvalidEnumValue;
const ArrayLengthMismatch = error.ArrayLengthMismatch;
const MissingField = error.MissingField;
const InvalidUnionTag = error.InvalidUnionTag;
