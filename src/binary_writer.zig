//! Binary serialization writer
//!
//! Writes data in a compact binary format for efficient storage and loading.
//! Format specification:
//! - All integers are little-endian
//! - Strings are length-prefixed (u32 length + bytes)
//! - Arrays are length-prefixed (u32 length + elements)

const std = @import("std");
const ecs = @import("ecs");

/// Magic bytes identifying the format: "LBSR" (LaBelle SeRialization)
pub const MAGIC: [4]u8 = .{ 'L', 'B', 'S', 'R' };

/// Current binary format version
pub const FORMAT_VERSION: u32 = 1;

/// Binary writer with buffered output
pub const BinaryWriter = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8),

    pub fn init(allocator: std.mem.Allocator) BinaryWriter {
        return .{
            .allocator = allocator,
            .buffer = .{},
        };
    }

    pub fn deinit(self: *BinaryWriter) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn toOwnedSlice(self: *BinaryWriter) ![]u8 {
        return self.buffer.toOwnedSlice(self.allocator);
    }

    pub fn getWritten(self: *const BinaryWriter) []const u8 {
        return self.buffer.items;
    }

    /// Write raw bytes
    pub fn writeBytes(self: *BinaryWriter, bytes: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, bytes);
    }

    /// Write a single byte
    pub fn writeByte(self: *BinaryWriter, byte: u8) !void {
        try self.buffer.append(self.allocator, byte);
    }

    /// Write the file header (magic + version)
    pub fn writeHeader(self: *BinaryWriter, save_version: u32) !void {
        try self.writeBytes(&MAGIC);
        try self.writeU32(FORMAT_VERSION);
        try self.writeU32(save_version);
    }

    /// Write a u8
    pub fn writeU8(self: *BinaryWriter, value: u8) !void {
        try self.writeByte(value);
    }

    /// Write an i8
    pub fn writeI8(self: *BinaryWriter, value: i8) !void {
        try self.writeByte(@bitCast(value));
    }

    /// Write a u16 (little-endian)
    pub fn writeU16(self: *BinaryWriter, value: u16) !void {
        const bytes = std.mem.toBytes(std.mem.nativeToLittle(u16, value));
        try self.writeBytes(&bytes);
    }

    /// Write an i16 (little-endian)
    pub fn writeI16(self: *BinaryWriter, value: i16) !void {
        try self.writeU16(@bitCast(value));
    }

    /// Write a u32 (little-endian)
    pub fn writeU32(self: *BinaryWriter, value: u32) !void {
        const bytes = std.mem.toBytes(std.mem.nativeToLittle(u32, value));
        try self.writeBytes(&bytes);
    }

    /// Write an i32 (little-endian)
    pub fn writeI32(self: *BinaryWriter, value: i32) !void {
        try self.writeU32(@bitCast(value));
    }

    /// Write a u64 (little-endian)
    pub fn writeU64(self: *BinaryWriter, value: u64) !void {
        const bytes = std.mem.toBytes(std.mem.nativeToLittle(u64, value));
        try self.writeBytes(&bytes);
    }

    /// Write an i64 (little-endian)
    pub fn writeI64(self: *BinaryWriter, value: i64) !void {
        try self.writeU64(@bitCast(value));
    }

    /// Write an f32 (IEEE 754)
    pub fn writeF32(self: *BinaryWriter, value: f32) !void {
        const bytes = std.mem.toBytes(std.mem.nativeToLittle(u32, @as(u32, @bitCast(value))));
        try self.writeBytes(&bytes);
    }

    /// Write an f64 (IEEE 754)
    pub fn writeF64(self: *BinaryWriter, value: f64) !void {
        const bytes = std.mem.toBytes(std.mem.nativeToLittle(u64, @as(u64, @bitCast(value))));
        try self.writeBytes(&bytes);
    }

    /// Write a bool (1 byte: 0 or 1)
    pub fn writeBool(self: *BinaryWriter, value: bool) !void {
        try self.writeByte(if (value) 1 else 0);
    }

    /// Write a length-prefixed string
    pub fn writeString(self: *BinaryWriter, str: []const u8) !void {
        try self.writeU32(@intCast(str.len));
        try self.writeBytes(str);
    }

    /// Write an entity ID
    pub fn writeEntity(self: *BinaryWriter, entity: ecs.Entity) !void {
        try self.writeU32(@bitCast(entity));
    }

    /// Write any Zig value in binary format
    pub fn writeValue(self: *BinaryWriter, value: anytype) !void {
        const T = @TypeOf(value);
        const info = @typeInfo(T);

        switch (info) {
            .bool => try self.writeBool(value),
            .int => |int_info| {
                // For standard sizes, use optimized paths
                if (int_info.bits == 8) {
                    if (int_info.signedness == .signed) {
                        try self.writeI8(value);
                    } else {
                        try self.writeU8(value);
                    }
                } else if (int_info.bits == 16) {
                    if (int_info.signedness == .signed) {
                        try self.writeI16(value);
                    } else {
                        try self.writeU16(value);
                    }
                } else if (int_info.bits == 32) {
                    if (int_info.signedness == .signed) {
                        try self.writeI32(value);
                    } else {
                        try self.writeU32(value);
                    }
                } else if (int_info.bits == 64) {
                    if (int_info.signedness == .signed) {
                        try self.writeI64(value);
                    } else {
                        try self.writeU64(value);
                    }
                } else if (int_info.bits <= 8) {
                    // Small integers (enums etc) - write as u8
                    try self.writeU8(@intCast(value));
                } else if (int_info.bits <= 16) {
                    try self.writeU16(@intCast(value));
                } else if (int_info.bits <= 32) {
                    try self.writeU32(@intCast(value));
                } else {
                    try self.writeU64(@intCast(value));
                }
            },
            .comptime_int => {
                // Write as i64 for comptime integers
                try self.writeI64(value);
            },
            .float => |float_info| {
                switch (float_info.bits) {
                    32 => try self.writeF32(value),
                    64 => try self.writeF64(value),
                    else => @compileError("Unsupported float bit width: " ++ @typeName(T)),
                }
            },
            .comptime_float => {
                // Write as f64 for comptime floats
                try self.writeF64(value);
            },
            .optional => {
                if (value) |v| {
                    try self.writeBool(true); // has value
                    try self.writeValue(v);
                } else {
                    try self.writeBool(false); // no value
                }
            },
            .@"enum" => |e| {
                if (T == ecs.Entity) {
                    try self.writeEntity(value);
                    return;
                }
                // Write enum as its tag integer value
                const tag_int: e.tag_type = @intFromEnum(value);
                try self.writeValue(tag_int);
            },
            .@"struct" => |s| {
                // Check if this is an Entity (packed struct)
                if (T == ecs.Entity) {
                    try self.writeEntity(value);
                    return;
                }

                // Write each field in order
                inline for (s.fields) |field| {
                    try self.writeValue(@field(value, field.name));
                }
            },
            .array => |arr| {
                // Fixed-size array: write elements directly (no length prefix)
                for (value) |item| {
                    try self.writeValue(item);
                }
                _ = arr;
            },
            .pointer => |ptr| {
                if (ptr.size == .slice) {
                    if (ptr.child == u8) {
                        // String slice - length-prefixed
                        try self.writeString(value);
                    } else {
                        // Other slices - length-prefixed
                        try self.writeU32(@intCast(value.len));
                        for (value) |item| {
                            try self.writeValue(item);
                        }
                    }
                } else {
                    // Single pointer - dereference
                    try self.writeValue(value.*);
                }
            },
            .@"union" => |u| {
                if (u.tag_type) |tag_type| {
                    // Tagged union: write tag index then payload
                    const tag_name = @tagName(value);
                    // Find tag index
                    inline for (u.fields, 0..) |field, idx| {
                        if (std.mem.eql(u8, field.name, tag_name)) {
                            // Write tag index as u16
                            try self.writeU16(@intCast(idx));
                            // Write payload
                            if (field.type != void) {
                                try self.writeValue(@field(value, field.name));
                            }
                            break;
                        }
                    }
                    _ = tag_type;
                } else {
                    @compileError("Untagged unions cannot be serialized");
                }
            },
            .void => {
                // Nothing to write for void
            },
            else => @compileError("Unsupported type for binary serialization: " ++ @typeName(T)),
        }
    }
};
