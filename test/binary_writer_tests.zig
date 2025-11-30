//! Tests for BinaryWriter
//!
//! Tests cover:
//! - Header writing (magic bytes, version)
//! - Primitive type encoding (integers, floats, bools)
//! - String encoding (length-prefixed)

const std = @import("std");
const testing = std.testing;
const serialization = @import("serialization");
const BinaryWriter = serialization.BinaryWriter;

test "BinaryWriter writes magic and header" {
    var writer = BinaryWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeHeader(42);
    const data = writer.getWritten();

    // Check magic bytes
    try testing.expectEqualSlices(u8, "LBSR", data[0..4]);

    // Check format version (little-endian u32 = 1)
    try testing.expectEqual(@as(u8, 1), data[4]);
    try testing.expectEqual(@as(u8, 0), data[5]);

    // Check save version (little-endian u32 = 42)
    try testing.expectEqual(@as(u8, 42), data[8]);
}

test "BinaryWriter writes integers correctly" {
    var writer = BinaryWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeU8(255);
    try writer.writeI8(-128);
    try writer.writeU16(65535);
    try writer.writeI16(-32768);
    try writer.writeU32(0xDEADBEEF);
    try writer.writeI32(-2147483648);
    try writer.writeU64(0xDEADBEEFCAFEBABE);
    try writer.writeI64(-9223372036854775808);

    const data = try writer.toOwnedSlice();
    defer testing.allocator.free(data);

    // Verify sizes: 1 + 1 + 2 + 2 + 4 + 4 + 8 + 8 = 30 bytes
    try testing.expectEqual(@as(usize, 30), data.len);
}

test "BinaryWriter writes floats correctly" {
    var writer = BinaryWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeF32(3.14159);
    try writer.writeF64(2.718281828459045);

    const data = try writer.toOwnedSlice();
    defer testing.allocator.free(data);

    // 4 + 8 = 12 bytes
    try testing.expectEqual(@as(usize, 12), data.len);
}

test "BinaryWriter writes strings with length prefix" {
    var writer = BinaryWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeString("Hello");

    const data = try writer.toOwnedSlice();
    defer testing.allocator.free(data);

    // 4 bytes length + 5 bytes string = 9 bytes
    try testing.expectEqual(@as(usize, 9), data.len);

    // Length should be 5 (little-endian)
    try testing.expectEqual(@as(u8, 5), data[0]);
    try testing.expectEqual(@as(u8, 0), data[1]);

    // String data
    try testing.expectEqualSlices(u8, "Hello", data[4..9]);
}

test "BinaryWriter writes bool as single byte" {
    var writer = BinaryWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeBool(true);
    try writer.writeBool(false);

    const data = try writer.toOwnedSlice();
    defer testing.allocator.free(data);

    try testing.expectEqual(@as(usize, 2), data.len);
    try testing.expectEqual(@as(u8, 1), data[0]);
    try testing.expectEqual(@as(u8, 0), data[1]);
}

test "BinaryWriter writes empty string" {
    var writer = BinaryWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeString("");

    const data = try writer.toOwnedSlice();
    defer testing.allocator.free(data);

    // 4 bytes length + 0 bytes string = 4 bytes
    try testing.expectEqual(@as(usize, 4), data.len);

    // Length should be 0
    try testing.expectEqual(@as(u8, 0), data[0]);
}

test "BinaryWriter getWritten returns current buffer" {
    var writer = BinaryWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeU32(123);
    const written1 = writer.getWritten();
    try testing.expectEqual(@as(usize, 4), written1.len);

    try writer.writeU32(456);
    const written2 = writer.getWritten();
    try testing.expectEqual(@as(usize, 8), written2.len);
}
