//! JSON serialization writer

const std = @import("std");
const ecs = @import("ecs");

/// JSON writer with pretty printing support
pub const JsonWriter = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8),
    pretty: bool,
    indent_level: usize = 0,

    const indent_str = "  ";

    pub fn init(allocator: std.mem.Allocator, pretty: bool) JsonWriter {
        return .{
            .allocator = allocator,
            .buffer = .{},
            .pretty = pretty,
        };
    }

    pub fn deinit(self: *JsonWriter) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn toOwnedSlice(self: *JsonWriter) ![]u8 {
        return self.buffer.toOwnedSlice(self.allocator);
    }

    pub fn getWritten(self: *const JsonWriter) []const u8 {
        return self.buffer.items;
    }

    pub fn writeIndent(self: *JsonWriter) !void {
        if (self.pretty) {
            for (0..self.indent_level) |_| {
                try self.buffer.appendSlice(self.allocator, indent_str);
            }
        }
    }

    fn writeNewline(self: *JsonWriter) !void {
        if (self.pretty) {
            try self.buffer.append(self.allocator, '\n');
        }
    }

    fn writeSpace(self: *JsonWriter) !void {
        if (self.pretty) {
            try self.buffer.append(self.allocator, ' ');
        }
    }

    pub fn beginObject(self: *JsonWriter) !void {
        try self.buffer.append(self.allocator, '{');
        try self.writeNewline();
        self.indent_level += 1;
    }

    pub fn endObject(self: *JsonWriter) !void {
        self.indent_level -= 1;
        try self.writeNewline();
        try self.writeIndent();
        try self.buffer.append(self.allocator, '}');
    }

    pub fn beginArray(self: *JsonWriter) !void {
        try self.buffer.append(self.allocator, '[');
        try self.writeNewline();
        self.indent_level += 1;
    }

    pub fn endArray(self: *JsonWriter) !void {
        self.indent_level -= 1;
        try self.writeNewline();
        try self.writeIndent();
        try self.buffer.append(self.allocator, ']');
    }

    pub fn writeKey(self: *JsonWriter, key: []const u8) !void {
        try self.writeIndent();
        try self.writeString(key);
        try self.buffer.append(self.allocator, ':');
        try self.writeSpace();
    }

    pub fn writeComma(self: *JsonWriter) !void {
        try self.buffer.append(self.allocator, ',');
        try self.writeNewline();
    }

    pub fn writeString(self: *JsonWriter, str: []const u8) !void {
        try self.buffer.append(self.allocator, '"');
        for (str) |c| {
            switch (c) {
                '"' => try self.buffer.appendSlice(self.allocator, "\\\""),
                '\\' => try self.buffer.appendSlice(self.allocator, "\\\\"),
                '\n' => try self.buffer.appendSlice(self.allocator, "\\n"),
                '\r' => try self.buffer.appendSlice(self.allocator, "\\r"),
                '\t' => try self.buffer.appendSlice(self.allocator, "\\t"),
                else => {
                    if (c < 0x20) {
                        var buf: [6]u8 = undefined;
                        const written = std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c}) catch unreachable;
                        try self.buffer.appendSlice(self.allocator, written);
                    } else {
                        try self.buffer.append(self.allocator, c);
                    }
                },
            }
        }
        try self.buffer.append(self.allocator, '"');
    }

    pub fn writeInt(self: *JsonWriter, value: anytype) !void {
        var buf: [32]u8 = undefined;
        const written = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
        try self.buffer.appendSlice(self.allocator, written);
    }

    pub fn writeFloat(self: *JsonWriter, value: anytype) !void {
        var buf: [64]u8 = undefined;
        const written = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
        try self.buffer.appendSlice(self.allocator, written);
    }

    pub fn writeBool(self: *JsonWriter, value: bool) !void {
        try self.buffer.appendSlice(self.allocator, if (value) "true" else "false");
    }

    pub fn writeNull(self: *JsonWriter) !void {
        try self.buffer.appendSlice(self.allocator, "null");
    }

    pub fn writeRaw(self: *JsonWriter, char: u8) !void {
        try self.buffer.append(self.allocator, char);
    }

    pub fn decrementIndent(self: *JsonWriter) void {
        self.indent_level -= 1;
    }

    pub fn writeEntity(self: *JsonWriter, entity: ecs.Entity) !void {
        try self.writeInt(@as(u32, @bitCast(entity)));
    }

    /// Write any Zig value as JSON
    pub fn writeValue(self: *JsonWriter, value: anytype) !void {
        const T = @TypeOf(value);
        const info = @typeInfo(T);

        switch (info) {
            .bool => try self.writeBool(value),
            .int, .comptime_int => try self.writeInt(value),
            .float, .comptime_float => try self.writeFloat(value),
            .optional => {
                if (value) |v| {
                    try self.writeValue(v);
                } else {
                    try self.writeNull();
                }
            },
            .@"enum" => {
                try self.writeString(@tagName(value));
            },
            .@"struct" => |s| {
                // Check if this is an Entity (packed struct)
                if (T == ecs.Entity) {
                    try self.writeEntity(value);
                    return;
                }

                try self.beginObject();
                var first = true;
                inline for (s.fields) |field| {
                    if (!first) try self.writeComma();
                    first = false;
                    try self.writeKey(field.name);
                    try self.writeValue(@field(value, field.name));
                }
                if (!first) {
                    try self.endObject();
                } else {
                    self.indent_level -= 1;
                    try self.buffer.append(self.allocator, '}');
                }
            },
            .array => |arr| {
                try self.beginArray();
                for (value, 0..) |item, i| {
                    if (i > 0) try self.writeComma();
                    try self.writeIndent();
                    try self.writeValue(item);
                }
                if (arr.len > 0) {
                    try self.endArray();
                } else {
                    self.indent_level -= 1;
                    try self.buffer.append(self.allocator, ']');
                }
            },
            .pointer => |ptr| {
                if (ptr.size == .slice) {
                    if (ptr.child == u8) {
                        // String slice
                        try self.writeString(value);
                    } else {
                        // Other slices
                        try self.beginArray();
                        for (value, 0..) |item, i| {
                            if (i > 0) try self.writeComma();
                            try self.writeIndent();
                            try self.writeValue(item);
                        }
                        if (value.len > 0) {
                            try self.endArray();
                        } else {
                            self.indent_level -= 1;
                            try self.buffer.append(self.allocator, ']');
                        }
                    }
                } else {
                    // Single pointer - dereference
                    try self.writeValue(value.*);
                }
            },
            .@"union" => |u| {
                if (u.tag_type) |_| {
                    // Tagged union
                    try self.beginObject();
                    const tag_name = @tagName(value);
                    try self.writeKey("tag");
                    try self.writeString(tag_name);
                    try self.writeComma();
                    try self.writeKey("value");
                    inline for (u.fields) |field| {
                        if (std.mem.eql(u8, field.name, tag_name)) {
                            if (field.type == void) {
                                try self.writeNull();
                            } else {
                                try self.writeValue(@field(value, field.name));
                            }
                            break;
                        }
                    }
                    try self.endObject();
                } else {
                    @compileError("Untagged unions cannot be serialized");
                }
            },
            .void => try self.writeNull(),
            else => @compileError("Unsupported type for JSON serialization: " ++ @typeName(T)),
        }
    }
};
