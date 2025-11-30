//! Quick Save Example
//!
//! Demonstrates using SelectiveSerializer to create fast "quick save" functionality
//! that only saves essential player state (position, health) for rapid save/load.

const std = @import("std");
const ecs = @import("ecs");
const serialization = @import("serialization");

// All game components
const Position = struct { x: f32, y: f32 };
const Health = struct { current: u8, max: u8 };
const Inventory = struct { items: [10]u32, count: u8 };
const QuestProgress = struct { quest_id: u32, stage: u8 };
const PlayerStats = struct { level: u8, experience: u32 };

// Define what gets saved in a quick save vs full save
const AllComponents = &[_]type{ Position, Health, Inventory, QuestProgress, PlayerStats };
const QuickSaveComponents = &[_]type{ Position, Health };

// Quick save serializer - only saves position and health
const QuickSaveSerializer = serialization.SelectiveSerializer(AllComponents, QuickSaveComponents);

// Full save serializer - saves everything
const FullSaveSerializer = serialization.Serializer(AllComponents);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create game state
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const player = registry.create();
    registry.add(player, Position{ .x = 150, .y = 300 });
    registry.add(player, Health{ .current = 75, .max = 100 });
    registry.add(player, Inventory{ .items = [_]u32{ 1, 2, 3, 0, 0, 0, 0, 0, 0, 0 }, .count = 3 });
    registry.add(player, QuestProgress{ .quest_id = 42, .stage = 3 });
    registry.add(player, PlayerStats{ .level = 15, .experience = 12500 });

    std.debug.print("=== Quick Save vs Full Save Example ===\n\n", .{});

    // Quick save - fast, minimal data
    var quick_ser = QuickSaveSerializer.init(allocator, .{ .pretty_print = true });
    defer quick_ser.deinit();

    const quick_json = try quick_ser.serialize(&registry);
    defer allocator.free(quick_json);

    std.debug.print("Quick Save ({d} bytes):\n{s}\n\n", .{ quick_json.len, quick_json });

    // Full save - complete game state
    var full_ser = FullSaveSerializer.init(allocator, .{ .pretty_print = true });
    defer full_ser.deinit();

    const full_json = try full_ser.serialize(&registry);
    defer allocator.free(full_json);

    std.debug.print("Full Save ({d} bytes):\n{s}\n", .{ full_json.len, full_json });

    // Quick save is smaller and faster to write/read
    std.debug.print("\nQuick save is {d}% smaller than full save\n", .{
        100 - (quick_json.len * 100 / full_json.len),
    });
}
