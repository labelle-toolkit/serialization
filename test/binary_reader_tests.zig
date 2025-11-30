//! Tests for BinaryReader
//!
//! Tests cover:
//! - Header reading and validation
//! - Primitive type decoding (integers, floats, bools)
//! - String decoding (length-prefixed)
//! - Error handling for invalid data

const std = @import("std");
const testing = std.testing;
const serialization = @import("serialization");
const BinaryWriter = serialization.BinaryWriter;
const BinaryReader = serialization.BinaryReader;

test "BinaryReader reads header correctly" {
    var writer = BinaryWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeHeader(123);
    const data = try writer.toOwnedSlice();
    defer testing.allocator.free(data);

    var reader = try BinaryReader.init(testing.allocator, data);
    defer reader.deinit();

    try testing.expectEqual(@as(u32, 123), reader.getSaveVersion());
}

test "BinaryReader reads integers correctly" {
    var writer = BinaryWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeHeader(1);
    try writer.writeU8(255);
    try writer.writeI8(-128);
    try writer.writeU16(65535);
    try writer.writeI16(-32768);
    try writer.writeU32(0xDEADBEEF);
    try writer.writeI32(-2147483648);

    const data = try writer.toOwnedSlice();
    defer testing.allocator.free(data);

    var reader = try BinaryReader.init(testing.allocator, data);
    defer reader.deinit();

    try testing.expectEqual(@as(u8, 255), try reader.readU8());
    try testing.expectEqual(@as(i8, -128), try reader.readI8());
    try testing.expectEqual(@as(u16, 65535), try reader.readU16());
    try testing.expectEqual(@as(i16, -32768), try reader.readI16());
    try testing.expectEqual(@as(u32, 0xDEADBEEF), try reader.readU32());
    try testing.expectEqual(@as(i32, -2147483648), try reader.readI32());
}

test "BinaryReader reads 64-bit integers correctly" {
    var writer = BinaryWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeHeader(1);
    try writer.writeU64(0xDEADBEEFCAFEBABE);
    try writer.writeI64(-9223372036854775808);

    const data = try writer.toOwnedSlice();
    defer testing.allocator.free(data);

    var reader = try BinaryReader.init(testing.allocator, data);
    defer reader.deinit();

    try testing.expectEqual(@as(u64, 0xDEADBEEFCAFEBABE), try reader.readU64());
    try testing.expectEqual(@as(i64, -9223372036854775808), try reader.readI64());
}

test "BinaryReader reads floats correctly" {
    var writer = BinaryWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeHeader(1);
    try writer.writeF32(3.14159);
    try writer.writeF64(2.718281828459045);

    const data = try writer.toOwnedSlice();
    defer testing.allocator.free(data);

    var reader = try BinaryReader.init(testing.allocator, data);
    defer reader.deinit();

    try testing.expectApproxEqAbs(@as(f32, 3.14159), try reader.readF32(), 0.00001);
    try testing.expectApproxEqAbs(@as(f64, 2.718281828459045), try reader.readF64(), 0.0000001);
}

test "BinaryReader reads strings correctly" {
    var writer = BinaryWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeHeader(1);
    try writer.writeString("Hello, World!");

    const data = try writer.toOwnedSlice();
    defer testing.allocator.free(data);

    var reader = try BinaryReader.init(testing.allocator, data);
    defer reader.deinit();

    const str = try reader.readString();
    defer testing.allocator.free(str);

    try testing.expectEqualStrings("Hello, World!", str);
}

test "BinaryReader reads empty string" {
    var writer = BinaryWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeHeader(1);
    try writer.writeString("");

    const data = try writer.toOwnedSlice();
    defer testing.allocator.free(data);

    var reader = try BinaryReader.init(testing.allocator, data);
    defer reader.deinit();

    const str = try reader.readString();
    defer testing.allocator.free(str);

    try testing.expectEqual(@as(usize, 0), str.len);
}

test "BinaryReader reads bool correctly" {
    var writer = BinaryWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeHeader(1);
    try writer.writeBool(true);
    try writer.writeBool(false);

    const data = try writer.toOwnedSlice();
    defer testing.allocator.free(data);

    var reader = try BinaryReader.init(testing.allocator, data);
    defer reader.deinit();

    try testing.expectEqual(true, try reader.readBool());
    try testing.expectEqual(false, try reader.readBool());
}

test "BinaryReader rejects invalid magic" {
    const bad_data = "BAAD" ++ [_]u8{0} ** 8;
    const result = BinaryReader.init(testing.allocator, bad_data);
    try testing.expectError(error.InvalidMagic, result);
}

test "BinaryReader rejects invalid bool value" {
    var writer = BinaryWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeHeader(1);
    try writer.writeU8(42); // Invalid bool value

    const data = try writer.toOwnedSlice();
    defer testing.allocator.free(data);

    var reader = try BinaryReader.init(testing.allocator, data);
    defer reader.deinit();

    try testing.expectError(error.InvalidBoolValue, reader.readBool());
}

test "BinaryReader hasMore and remaining work correctly" {
    var writer = BinaryWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeHeader(1);
    try writer.writeU32(42);

    const data = try writer.toOwnedSlice();
    defer testing.allocator.free(data);

    var reader = try BinaryReader.init(testing.allocator, data);
    defer reader.deinit();

    try testing.expect(reader.hasMore());
    try testing.expectEqual(@as(usize, 4), reader.remaining());

    _ = try reader.readU32();

    try testing.expect(!reader.hasMore());
    try testing.expectEqual(@as(usize, 0), reader.remaining());
}
