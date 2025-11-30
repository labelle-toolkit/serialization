//! Usage Example 11: Binary Serialization Format
//!
//! This example demonstrates how to use the binary serialization format
//! as an alternative to JSON for smaller file sizes and faster load times.

const std = @import("std");
const ecs = @import("ecs");
const serialization = @import("serialization");
const BinarySerializer = serialization.BinarySerializer;
const Serializer = serialization.Serializer; // JSON serializer for comparison

// Sample components
const Position = struct { x: f32, y: f32 };
const Velocity = struct { vx: f32, vy: f32 };
const Health = struct { current: i32, max: i32 };
const Player = struct {}; // Tag component

const Inventory = struct {
    slots: [8]u32,
    gold: u32,
};

const Status = enum {
    idle,
    walking,
    running,
    attacking,
};

const StatusComponent = struct {
    state: Status,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Binary Format Example ===\n\n", .{});

    // === 1. Basic Binary Serialization ===
    std.debug.print("1. Basic Binary Serialization\n", .{});
    std.debug.print("-----------------------------\n", .{});

    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    // Create some entities with various component types
    const player = registry.create();
    registry.add(player, Position{ .x = 100.5, .y = 200.5 });
    registry.add(player, Velocity{ .vx = 1.5, .vy = -0.5 });
    registry.add(player, Health{ .current = 80, .max = 100 });
    registry.add(player, Player{});
    registry.add(player, Inventory{
        .slots = .{ 1, 5, 0, 0, 3, 0, 0, 2 },
        .gold = 1500,
    });
    registry.add(player, StatusComponent{ .state = .idle });

    const enemy1 = registry.create();
    registry.add(enemy1, Position{ .x = 50.0, .y = 75.0 });
    registry.add(enemy1, Velocity{ .vx = -1.0, .vy = 0.0 });
    registry.add(enemy1, Health{ .current = 30, .max = 50 });
    registry.add(enemy1, StatusComponent{ .state = .attacking });

    const enemy2 = registry.create();
    registry.add(enemy2, Position{ .x = 200.0, .y = 150.0 });
    registry.add(enemy2, Health{ .current = 50, .max = 50 });
    registry.add(enemy2, StatusComponent{ .state = .walking });

    // Serialize to binary
    const ComponentTypes = .{ Position, Velocity, Health, Player, Inventory, StatusComponent };
    var bin_serializer = BinarySerializer(&ComponentTypes).init(allocator, .{
        .game_name = "BinaryExample",
    });
    defer bin_serializer.deinit();

    const binary_data = try bin_serializer.serialize(&registry);
    defer allocator.free(binary_data);

    std.debug.print("Serialized {d} entities to {d} bytes of binary data\n", .{ 3, binary_data.len });

    // Show first few bytes (header)
    std.debug.print("Header bytes: ", .{});
    for (binary_data[0..@min(16, binary_data.len)]) |byte| {
        if (byte >= 32 and byte < 127) {
            std.debug.print("{c}", .{byte});
        } else {
            std.debug.print("\\x{x:0>2}", .{byte});
        }
    }
    std.debug.print("...\n\n", .{});

    // === 2. Size Comparison with JSON ===
    std.debug.print("2. Size Comparison with JSON\n", .{});
    std.debug.print("----------------------------\n", .{});

    var json_serializer = Serializer(&ComponentTypes).init(allocator, .{
        .game_name = "BinaryExample",
        .pretty_print = false, // Compact JSON for fair comparison
    });
    defer json_serializer.deinit();

    const json_data = try json_serializer.serialize(&registry);
    defer allocator.free(json_data);

    const ratio = @as(f64, @floatFromInt(binary_data.len)) / @as(f64, @floatFromInt(json_data.len)) * 100.0;
    std.debug.print("JSON size:   {d} bytes\n", .{json_data.len});
    std.debug.print("Binary size: {d} bytes\n", .{binary_data.len});
    std.debug.print("Binary is {d:.1}% of JSON size ({d:.1}% smaller)\n\n", .{ ratio, 100.0 - ratio });

    // === 3. Deserialize Binary Data ===
    std.debug.print("3. Deserialize Binary Data\n", .{});
    std.debug.print("--------------------------\n", .{});

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try bin_serializer.deserialize(&registry2, binary_data);

    // Verify the data
    var pos_view = registry2.view(.{Position}, .{});
    var pos_count: usize = 0;
    var pos_iter = pos_view.entityIterator();
    while (pos_iter.next()) |_| pos_count += 1;
    std.debug.print("Loaded {d} entities with Position\n", .{pos_count});

    var player_view = registry2.view(.{Player}, .{});
    var player_count: usize = 0;
    var player_iter = player_view.entityIterator();
    while (player_iter.next()) |_| player_count += 1;
    std.debug.print("Loaded {d} Player tags\n", .{player_count});

    // Check inventory data
    var inv_view = registry2.view(.{Inventory}, .{});
    var inv_iter = inv_view.entityIterator();
    if (inv_iter.next()) |entity| {
        const inv = registry2.get(Inventory, entity);
        std.debug.print("Player gold: {d}\n", .{inv.gold});
    }

    // Check status enums
    var status_view = registry2.view(.{StatusComponent}, .{});
    std.debug.print("Status values: ", .{});
    var status_iter = status_view.entityIterator();
    var first = true;
    while (status_iter.next()) |entity| {
        if (!first) std.debug.print(", ", .{});
        first = false;
        const status = registry2.get(StatusComponent, entity);
        std.debug.print("{s}", .{@tagName(status.state)});
    }
    std.debug.print("\n\n", .{});

    // === 4. Save and Load from File ===
    std.debug.print("4. Save and Load from File\n", .{});
    std.debug.print("--------------------------\n", .{});

    // Save to binary file
    const bin_path = "/tmp/game_save.bin";
    try bin_serializer.save(&registry, bin_path);
    std.debug.print("Saved to {s}\n", .{bin_path});

    // Load from binary file
    var registry3 = ecs.Registry.init(allocator);
    defer registry3.deinit();

    try bin_serializer.load(&registry3, bin_path);

    var loaded_view = registry3.view(.{Position}, .{});
    var loaded_count: usize = 0;
    var loaded_iter = loaded_view.entityIterator();
    while (loaded_iter.next()) |_| loaded_count += 1;
    std.debug.print("Loaded {d} entities from file\n\n", .{loaded_count});

    // === 5. When to Use Binary vs JSON ===
    std.debug.print("5. When to Use Binary vs JSON\n", .{});
    std.debug.print("-----------------------------\n", .{});
    std.debug.print("Use BINARY format when:\n", .{});
    std.debug.print("  - File size matters (mobile, network transfer)\n", .{});
    std.debug.print("  - Load time is critical (fast game startup)\n", .{});
    std.debug.print("  - Exact numeric precision is required\n", .{});
    std.debug.print("  - Save files don't need to be human-readable\n\n", .{});
    std.debug.print("Use JSON format when:\n", .{});
    std.debug.print("  - Human readability matters (debugging, modding)\n", .{});
    std.debug.print("  - Interoperability with other tools needed\n", .{});
    std.debug.print("  - Save files need to be manually edited\n", .{});
    std.debug.print("  - Version migration requires inspecting data\n\n", .{});

    std.debug.print("=== Example Complete ===\n", .{});
}
