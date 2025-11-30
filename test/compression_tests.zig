//! Tests for compression utilities

const std = @import("std");
const serialization = @import("serialization");
const CompressionType = serialization.CompressionType;
const CompressedHeader = serialization.CompressedHeader;
const compress = serialization.compress;
const decompress = serialization.decompress;
const compressWithHeader = serialization.compressWithHeader;
const decompressWithHeader = serialization.decompressWithHeader;
const hasCompressionHeader = serialization.hasCompressionHeader;

test "CompressedHeader write and read" {
    const allocator = std.testing.allocator;

    var buffer: std.ArrayListUnmanaged(u8) = .{};
    defer buffer.deinit(allocator);

    const header = CompressedHeader.init(.none, 1024);
    try header.write(buffer.writer(allocator));

    var fbs = std.io.fixedBufferStream(buffer.items);
    const read_header = try CompressedHeader.read(fbs.reader());

    try std.testing.expectEqualSlices(u8, &CompressedHeader.MAGIC_RAW, &read_header.magic);
    try std.testing.expectEqual(CompressionType.none, read_header.compression);
    try std.testing.expectEqual(@as(u32, 1024), read_header.uncompressed_size);
}

test "no compression roundtrip" {
    const allocator = std.testing.allocator;

    const original = "Hello, World! This is test data.";

    const compressed = try compress(allocator, original, .{ .type = .none });
    defer allocator.free(compressed);

    // No compression means same size
    try std.testing.expectEqual(original.len, compressed.len);

    const decompressed = try decompress(allocator, compressed, .none, @intCast(original.len));
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

test "compression with header roundtrip" {
    const allocator = std.testing.allocator;

    const original = "Test data for compression with header";

    const result = try compressWithHeader(allocator, original, .{ .type = .none });
    defer allocator.free(result);

    try std.testing.expect(hasCompressionHeader(result));
    try std.testing.expectEqual(CompressedHeader.SIZE + original.len, result.len);

    const decompressed = try decompressWithHeader(allocator, result);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

test "hasCompressionHeader detection" {
    try std.testing.expect(hasCompressionHeader(&CompressedHeader.MAGIC_RAW ++ [_]u8{ 0, 0, 0, 0, 0 }));
    try std.testing.expect(hasCompressionHeader(&CompressedHeader.MAGIC_COMPRESSED ++ [_]u8{ 0, 0, 0, 0, 0 }));
    try std.testing.expect(!hasCompressionHeader("{}"));
    try std.testing.expect(!hasCompressionHeader("{\"meta\":"));
}
