//! Save file compression utilities
//!
//! Provides infrastructure for optional compression of save files.
//! Currently supports no-compression mode with header format for future
//! compression algorithm support.

const std = @import("std");

/// Compression algorithm to use
pub const CompressionType = enum(u8) {
    none = 0,
    // Future compression types:
    // deflate = 1,
    // zstd = 2,

    pub fn toString(self: CompressionType) []const u8 {
        return switch (self) {
            .none => "none",
        };
    }
};

/// File header for save files with compression metadata
/// Magic bytes help identify file format and compression status
pub const CompressedHeader = struct {
    /// Magic bytes: "LBSC" for compressed, "LBSR" for raw
    magic: [4]u8,
    /// Compression type used
    compression: CompressionType,
    /// Original uncompressed size (for pre-allocation)
    uncompressed_size: u32,

    pub const MAGIC_COMPRESSED: [4]u8 = .{ 'L', 'B', 'S', 'C' };
    pub const MAGIC_RAW: [4]u8 = .{ 'L', 'B', 'S', 'R' };
    pub const SIZE = 9; // 4 + 1 + 4

    pub fn init(compression: CompressionType, uncompressed_size: u32) CompressedHeader {
        return .{
            .magic = if (compression == .none) MAGIC_RAW else MAGIC_COMPRESSED,
            .compression = compression,
            .uncompressed_size = uncompressed_size,
        };
    }

    pub fn write(self: CompressedHeader, writer: anytype) !void {
        try writer.writeAll(&self.magic);
        try writer.writeByte(@intFromEnum(self.compression));
        try writer.writeInt(u32, self.uncompressed_size, .little);
    }

    pub fn read(reader: anytype) !CompressedHeader {
        var header: CompressedHeader = undefined;
        _ = try reader.readAll(&header.magic);

        // Validate magic
        if (!std.mem.eql(u8, &header.magic, &MAGIC_COMPRESSED) and
            !std.mem.eql(u8, &header.magic, &MAGIC_RAW))
        {
            return error.InvalidMagic;
        }

        const comp_byte = try reader.readByte();
        header.compression = std.meta.intToEnum(CompressionType, comp_byte) catch return error.InvalidCompression;
        header.uncompressed_size = try reader.readInt(u32, .little);
        return header;
    }

    pub fn isCompressed(self: CompressedHeader) bool {
        return std.mem.eql(u8, &self.magic, &MAGIC_COMPRESSED);
    }
};

/// Compression options
pub const CompressionOptions = struct {
    type: CompressionType = .none,
};

/// Compress data using the specified algorithm
pub fn compress(allocator: std.mem.Allocator, data: []const u8, options: CompressionOptions) ![]u8 {
    return switch (options.type) {
        .none => try allocator.dupe(u8, data),
    };
}

/// Decompress data using the specified algorithm
pub fn decompress(allocator: std.mem.Allocator, data: []const u8, compression: CompressionType, uncompressed_size: u32) ![]u8 {
    _ = uncompressed_size;
    return switch (compression) {
        .none => try allocator.dupe(u8, data),
    };
}

/// Compress and write data with header
pub fn compressWithHeader(allocator: std.mem.Allocator, data: []const u8, options: CompressionOptions) ![]u8 {
    const compressed = try compress(allocator, data, options);
    defer allocator.free(compressed);

    const header = CompressedHeader.init(options.type, @intCast(data.len));

    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(allocator);

    header.write(result.writer(allocator)) catch |e| return e;
    try result.appendSlice(allocator, compressed);

    return try result.toOwnedSlice(allocator);
}

/// Read header and decompress data
pub fn decompressWithHeader(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    if (data.len < CompressedHeader.SIZE) {
        return error.DataTooShort;
    }

    var fbs = std.io.fixedBufferStream(data);
    const header = try CompressedHeader.read(fbs.reader());

    const compressed_data = data[CompressedHeader.SIZE..];
    return decompress(allocator, compressed_data, header.compression, header.uncompressed_size);
}

/// Auto-detect if data has a compression header
pub fn hasCompressionHeader(data: []const u8) bool {
    if (data.len < 4) return false;
    return std.mem.eql(u8, data[0..4], &CompressedHeader.MAGIC_COMPRESSED) or
        std.mem.eql(u8, data[0..4], &CompressedHeader.MAGIC_RAW);
}
