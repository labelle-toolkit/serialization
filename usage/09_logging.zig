//! Usage Example 09: Configurable Logging
//!
//! This example demonstrates how to configure logging in the serialization library.
//! Logging helps debug serialization issues and understand what's happening during
//! save/load operations.

const std = @import("std");
const serialization = @import("serialization");

// Example components
const Position = struct {
    x: f32,
    y: f32,
};

const Health = struct {
    current: u8,
    max: u8,
};

const Player = struct {}; // Tag component

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ecs = @import("ecs");

    // Create a registry with some entities
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    // Create some test entities
    const player = registry.create();
    registry.add(player, Position{ .x = 100, .y = 200 });
    registry.add(player, Health{ .current = 80, .max = 100 });
    registry.add(player, Player{});

    const enemy1 = registry.create();
    registry.add(enemy1, Position{ .x = 50, .y = 75 });
    registry.add(enemy1, Health{ .current = 30, .max = 50 });

    const enemy2 = registry.create();
    registry.add(enemy2, Position{ .x = 150, .y = 225 });
    registry.add(enemy2, Health{ .current = 50, .max = 50 });

    // =========================================================================
    // Example 1: Logging disabled (default)
    // =========================================================================
    std.debug.print("\n=== Example 1: Logging disabled (default) ===\n", .{});

    const Serializer = serialization.Serializer(&[_]type{ Position, Health, Player });

    var ser_quiet = Serializer.init(allocator, .{
        // log_level defaults to .none
    });
    defer ser_quiet.deinit();

    const json1 = try ser_quiet.serialize(&registry);
    defer allocator.free(json1);
    std.debug.print("Serialized (no log output above)\n", .{});

    // =========================================================================
    // Example 2: Info level logging
    // =========================================================================
    std.debug.print("\n=== Example 2: Info level logging ===\n", .{});

    var ser_info = Serializer.init(allocator, .{
        .log_level = .info,
    });
    defer ser_info.deinit();

    const json2 = try ser_info.serialize(&registry);
    defer allocator.free(json2);

    // =========================================================================
    // Example 3: Debug level logging (verbose)
    // =========================================================================
    std.debug.print("\n=== Example 3: Debug level logging ===\n", .{});

    var ser_debug = Serializer.init(allocator, .{
        .log_level = .debug,
    });
    defer ser_debug.deinit();

    const json3 = try ser_debug.serialize(&registry);
    defer allocator.free(json3);

    // Now deserialize with debug logging
    std.debug.print("\n--- Deserializing with debug logging ---\n", .{});
    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser_debug.deserialize(&registry2, json3);

    // =========================================================================
    // Example 4: Only log errors
    // =========================================================================
    std.debug.print("\n=== Example 4: Error-only logging ===\n", .{});

    var ser_errors = Serializer.init(allocator, .{
        .log_level = .err,
    });
    defer ser_errors.deinit();

    // This will work silently (no errors)
    const json4 = try ser_errors.serialize(&registry);
    defer allocator.free(json4);
    std.debug.print("Serialized successfully (no errors to log)\n", .{});

    // Try to deserialize invalid JSON to see error logging
    var registry3 = ecs.Registry.init(allocator);
    defer registry3.deinit();

    ser_errors.deserialize(&registry3, "invalid json") catch |err| {
        std.debug.print("Caught expected error: {}\n", .{err});
    };

    // =========================================================================
    // Log levels summary
    // =========================================================================
    std.debug.print(
        \\
        \\=== Log Levels Summary ===
        \\.debug  - Verbose: component counts, entity IDs, version info
        \\.info   - Normal: start/complete messages, byte counts
        \\.warn   - Warnings only (e.g., deprecated features)
        \\.err    - Errors only (e.g., invalid format, version mismatch)
        \\.none   - Silent (default)
        \\
    , .{});
}
