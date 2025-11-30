//! Binary deserialization reader
//!
//! Reads data from the compact binary format.
//! Format specification:
//! - All integers are little-endian
//! - Strings are length-prefixed (u32 length + bytes)
//! - Arrays are length-prefixed (u32 length + elements)

const std = @import("std");
const ecs = @import("ecs");
const binary_writer = @import("binary_writer.zig");

pub const BinaryReadError = error{
    InvalidMagic,
    UnsupportedFormatVersion,
    UnexpectedEndOfData,
    InvalidBoolValue,
    InvalidEnumValue,
    InvalidUnionTag,
    StringTooLong,
    ArrayTooLong,
};

/// Binary reader for deserialization
pub const BinaryReader = struct {
    allocator: std.mem.Allocator,
    data: []const u8,
    pos: usize,
    save_version: u32,

    pub fn init(allocator: std.mem.Allocator, data: []const u8) !BinaryReader {
        var reader = BinaryReader{
            .allocator = allocator,
            .data = data,
            .pos = 0,
            .save_version = 0,
        };

        // Read and validate header
        try reader.readHeader();

        return reader;
    }

    pub fn deinit(self: *BinaryReader) void {
        _ = self;
        // Nothing to clean up - we don't own the data
    }

    /// Get the save version from the file header
    pub fn getSaveVersion(self: *const BinaryReader) u32 {
        return self.save_version;
    }

    /// Check if there's more data to read
    pub fn hasMore(self: *const BinaryReader) bool {
        return self.pos < self.data.len;
    }

    /// Get remaining bytes
    pub fn remaining(self: *const BinaryReader) usize {
        return self.data.len - self.pos;
    }

    fn readHeader(self: *BinaryReader) !void {
        // Read magic
        const magic = try self.readBytesFixed(4);
        if (!std.mem.eql(u8, &magic, &binary_writer.MAGIC)) {
            return BinaryReadError.InvalidMagic;
        }

        // Read format version
        const format_version = try self.readU32();
        if (format_version > binary_writer.FORMAT_VERSION) {
            return BinaryReadError.UnsupportedFormatVersion;
        }

        // Read save version
        self.save_version = try self.readU32();
    }

    /// Read a fixed number of bytes
    fn readBytesFixed(self: *BinaryReader, comptime len: usize) ![len]u8 {
        if (self.pos + len > self.data.len) {
            return BinaryReadError.UnexpectedEndOfData;
        }
        const bytes = self.data[self.pos..][0..len];
        self.pos += len;
        return bytes.*;
    }

    /// Read a slice of bytes (caller specifies length)
    fn readBytesSlice(self: *BinaryReader, len: usize) ![]const u8 {
        if (self.pos + len > self.data.len) {
            return BinaryReadError.UnexpectedEndOfData;
        }
        const bytes = self.data[self.pos .. self.pos + len];
        self.pos += len;
        return bytes;
    }

    /// Read a single byte
    pub fn readByte(self: *BinaryReader) !u8 {
        if (self.pos >= self.data.len) {
            return BinaryReadError.UnexpectedEndOfData;
        }
        const byte = self.data[self.pos];
        self.pos += 1;
        return byte;
    }

    /// Read a u8
    pub fn readU8(self: *BinaryReader) !u8 {
        return self.readByte();
    }

    /// Read an i8
    pub fn readI8(self: *BinaryReader) !i8 {
        return @bitCast(try self.readByte());
    }

    /// Read a u16 (little-endian)
    pub fn readU16(self: *BinaryReader) !u16 {
        const bytes = try self.readBytesFixed(2);
        return std.mem.littleToNative(u16, std.mem.bytesToValue(u16, &bytes));
    }

    /// Read an i16 (little-endian)
    pub fn readI16(self: *BinaryReader) !i16 {
        return @bitCast(try self.readU16());
    }

    /// Read a u32 (little-endian)
    pub fn readU32(self: *BinaryReader) !u32 {
        const bytes = try self.readBytesFixed(4);
        return std.mem.littleToNative(u32, std.mem.bytesToValue(u32, &bytes));
    }

    /// Read an i32 (little-endian)
    pub fn readI32(self: *BinaryReader) !i32 {
        return @bitCast(try self.readU32());
    }

    /// Read a u64 (little-endian)
    pub fn readU64(self: *BinaryReader) !u64 {
        const bytes = try self.readBytesFixed(8);
        return std.mem.littleToNative(u64, std.mem.bytesToValue(u64, &bytes));
    }

    /// Read an i64 (little-endian)
    pub fn readI64(self: *BinaryReader) !i64 {
        return @bitCast(try self.readU64());
    }

    /// Read an f32 (IEEE 754)
    pub fn readF32(self: *BinaryReader) !f32 {
        const bytes = try self.readBytesFixed(4);
        const bits = std.mem.littleToNative(u32, std.mem.bytesToValue(u32, &bytes));
        return @bitCast(bits);
    }

    /// Read an f64 (IEEE 754)
    pub fn readF64(self: *BinaryReader) !f64 {
        const bytes = try self.readBytesFixed(8);
        const bits = std.mem.littleToNative(u64, std.mem.bytesToValue(u64, &bytes));
        return @bitCast(bits);
    }

    /// Read a bool (1 byte: 0 or 1)
    pub fn readBool(self: *BinaryReader) !bool {
        const byte = try self.readByte();
        return switch (byte) {
            0 => false,
            1 => true,
            else => BinaryReadError.InvalidBoolValue,
        };
    }

    /// Read a length-prefixed string (allocates memory)
    pub fn readString(self: *BinaryReader) ![]u8 {
        const len = try self.readU32();
        if (len > 10 * 1024 * 1024) { // 10MB max string length
            return BinaryReadError.StringTooLong;
        }
        const bytes = try self.readBytesSlice(len);
        return try self.allocator.dupe(u8, bytes);
    }

    /// Read an entity ID
    pub fn readEntity(self: *BinaryReader) !ecs.Entity {
        return @bitCast(try self.readU32());
    }

    /// Read an entity ID as raw u32 (for remapping)
    pub fn readEntityRaw(self: *BinaryReader) !u32 {
        return try self.readU32();
    }

    /// Read any Zig value from binary format
    pub fn readValue(self: *BinaryReader, comptime T: type) !T {
        const info = @typeInfo(T);

        switch (info) {
            .bool => return try self.readBool(),
            .int => |int_info| {
                // For standard sizes, use optimized paths
                if (int_info.bits == 8) {
                    return if (int_info.signedness == .signed)
                        @as(T, try self.readI8())
                    else
                        @as(T, try self.readU8());
                } else if (int_info.bits == 16) {
                    return if (int_info.signedness == .signed)
                        @as(T, try self.readI16())
                    else
                        @as(T, try self.readU16());
                } else if (int_info.bits == 32) {
                    return if (int_info.signedness == .signed)
                        @as(T, try self.readI32())
                    else
                        @as(T, try self.readU32());
                } else if (int_info.bits == 64) {
                    return if (int_info.signedness == .signed)
                        @as(T, try self.readI64())
                    else
                        @as(T, try self.readU64());
                } else if (int_info.bits <= 8) {
                    // Small integers (enums etc) - read as u8
                    return @intCast(try self.readU8());
                } else if (int_info.bits <= 16) {
                    return @intCast(try self.readU16());
                } else if (int_info.bits <= 32) {
                    return @intCast(try self.readU32());
                } else {
                    return @intCast(try self.readU64());
                }
            },
            .float => |float_info| {
                return switch (float_info.bits) {
                    32 => try self.readF32(),
                    64 => try self.readF64(),
                    else => @compileError("Unsupported float bit width: " ++ @typeName(T)),
                };
            },
            .optional => |opt| {
                const has_value = try self.readBool();
                if (has_value) {
                    return try self.readValue(opt.child);
                } else {
                    return null;
                }
            },
            .@"enum" => |e| {
                if (T == ecs.Entity) {
                    return try self.readEntity();
                }
                // Read enum as its tag integer value
                const tag_int = try self.readValue(e.tag_type);
                return @enumFromInt(tag_int);
            },
            .@"struct" => |s| {
                // Check if this is an Entity (packed struct)
                if (T == ecs.Entity) {
                    return try self.readEntity();
                }

                // Read each field in order
                var result: T = undefined;
                inline for (s.fields) |field| {
                    @field(result, field.name) = try self.readValue(field.type);
                }
                return result;
            },
            .array => |arr| {
                // Fixed-size array: read elements directly (no length prefix)
                var result: T = undefined;
                for (&result) |*item| {
                    item.* = try self.readValue(arr.child);
                }
                return result;
            },
            .pointer => |ptr| {
                if (ptr.size == .slice) {
                    if (ptr.child == u8) {
                        // String slice - length-prefixed
                        return try self.readString();
                    } else {
                        // Other slices - length-prefixed
                        const len = try self.readU32();
                        if (len > 10 * 1024 * 1024) { // 10M max elements
                            return BinaryReadError.ArrayTooLong;
                        }
                        const items = try self.allocator.alloc(ptr.child, len);
                        errdefer self.allocator.free(items);
                        for (items) |*item| {
                            item.* = try self.readValue(ptr.child);
                        }
                        return items;
                    }
                }
                @compileError("Non-slice pointers not supported");
            },
            .@"union" => |u| {
                if (u.tag_type) |_| {
                    // Tagged union: read tag index then payload
                    const tag_idx = try self.readU16();

                    inline for (u.fields, 0..) |field, idx| {
                        if (tag_idx == idx) {
                            if (field.type == void) {
                                return @unionInit(T, field.name, {});
                            } else {
                                const payload = try self.readValue(field.type);
                                return @unionInit(T, field.name, payload);
                            }
                        }
                    }
                    return BinaryReadError.InvalidUnionTag;
                }
                @compileError("Untagged unions cannot be deserialized");
            },
            .void => return {},
            else => @compileError("Unsupported type for binary deserialization: " ++ @typeName(T)),
        }
    }
};
