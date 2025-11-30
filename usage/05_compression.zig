//! Compression Example
//!
//! Demonstrates the compression header infrastructure for save files.
//! Currently supports no-compression mode with extensible header format.

const std = @import("std");
const ecs = @import("ecs");
const serialization = @import("serialization");

const Position = struct { x: f32, y: f32 };
const Health = struct { current: u8, max: u8 };

const GameSerializer = serialization.Serializer(&[_]type{ Position, Health });

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Compression Infrastructure Example ===\n\n", .{});

    // Create game state
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    for (0..5) |i| {
        const entity = registry.create();
        registry.add(entity, Position{ .x = @floatFromInt(i * 100), .y = @floatFromInt(i * 50) });
        registry.add(entity, Health{ .current = 80, .max = 100 });
    }

    // Serialize to JSON
    var ser = GameSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry);
    defer allocator.free(json);

    std.debug.print("Original JSON size: {d} bytes\n\n", .{json.len});

    // Wrap with compression header (no actual compression yet)
    const with_header = try serialization.compressWithHeader(allocator, json, .{ .type = .none });
    defer allocator.free(with_header);

    std.debug.print("With header size: {d} bytes (header adds {d} bytes)\n", .{
        with_header.len,
        serialization.CompressedHeader.SIZE,
    });

    // Auto-detect header
    std.debug.print("\nAuto-detection:\n", .{});
    if (serialization.hasCompressionHeader(with_header)) {
        std.debug.print("  - with_header: Has compression header (detected)\n", .{});
    }
    if (!serialization.hasCompressionHeader(json)) {
        std.debug.print("  - raw json: No compression header (raw JSON)\n", .{});
    }

    // Read back the header
    var fbs = std.io.fixedBufferStream(with_header);
    const header = try serialization.CompressedHeader.read(fbs.reader());

    std.debug.print("\nHeader info:\n", .{});
    std.debug.print("  - Magic: {s}\n", .{&header.magic});
    std.debug.print("  - Compression: {s}\n", .{header.compression.toString()});
    std.debug.print("  - Original size: {d} bytes\n", .{header.uncompressed_size});

    // Decompress (extract from header)
    const decompressed = try serialization.decompressWithHeader(allocator, with_header);
    defer allocator.free(decompressed);

    std.debug.print("\nRoundtrip verification: ", .{});
    if (std.mem.eql(u8, json, decompressed)) {
        std.debug.print("OK\n", .{});
    } else {
        std.debug.print("FAILED\n", .{});
    }
}
