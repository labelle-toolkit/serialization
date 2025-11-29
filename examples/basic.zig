//! Basic example of ECS serialization
//!
//! This example demonstrates:
//! - Defining components for serialization
//! - Creating entities with components
//! - Saving game state to JSON
//! - Loading game state from JSON
//! - Entity reference remapping

const std = @import("std");
const ecs = @import("ecs");
const serialization = @import("serialization");

// Define game components
const Position = struct {
    x: f32,
    y: f32,
};

const Health = struct {
    current: u8,
    max: u8,
};

const Velocity = struct {
    dx: f32,
    dy: f32,
};

const Inventory = struct {
    gold: u32,
    capacity: u8,
};

// Tag components (zero-sized)
const Player = struct {};
const Enemy = struct {};

// Component with entity reference
const FollowTarget = struct {
    target: ecs.Entity,
    follow_distance: f32,
};

// Create serializer for our component types
const GameSerializer = serialization.Serializer(&[_]type{
    Position,
    Health,
    Velocity,
    Inventory,
    Player,
    Enemy,
    FollowTarget,
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ECS Serialization Example ===\n\n", .{});

    // Create registry and populate with game entities
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    // Create player
    const player = registry.create();
    registry.add(player, Position{ .x = 100, .y = 200 });
    registry.add(player, Health{ .current = 85, .max = 100 });
    registry.add(player, Velocity{ .dx = 0, .dy = 0 });
    registry.add(player, Inventory{ .gold = 500, .capacity = 20 });
    registry.add(player, Player{});

    std.debug.print("Created player entity: {d}\n", .{@as(u32, @bitCast(player))});

    // Create enemies
    const enemy1 = registry.create();
    registry.add(enemy1, Position{ .x = 300, .y = 150 });
    registry.add(enemy1, Health{ .current = 50, .max = 50 });
    registry.add(enemy1, Velocity{ .dx = -1, .dy = 0 });
    registry.add(enemy1, Enemy{});

    const enemy2 = registry.create();
    registry.add(enemy2, Position{ .x = 400, .y = 250 });
    registry.add(enemy2, Health{ .current = 30, .max = 50 });
    registry.add(enemy2, Velocity{ .dx = 0, .dy = 1 });
    registry.add(enemy2, Enemy{});
    // This enemy follows the player
    registry.add(enemy2, FollowTarget{ .target = player, .follow_distance = 50.0 });

    std.debug.print("Created enemy entities: {d}, {d}\n", .{ @as(u32, @bitCast(enemy1)), @as(u32, @bitCast(enemy2)) });

    // Initialize serializer
    var ser = GameSerializer.init(allocator, .{
        .version = 1,
        .pretty_print = true,
        .include_metadata = true,
        .game_name = "example_game",
    });
    defer ser.deinit();

    // Serialize to JSON
    const json = try ser.serialize(&registry);
    defer allocator.free(json);

    std.debug.print("\n=== Serialized JSON ===\n{s}\n", .{json});

    // Save to file
    const save_path = "example_save.json";
    {
        const file = try std.fs.cwd().createFile(save_path, .{});
        defer file.close();
        try file.writeAll(json);
    }
    std.debug.print("\nSaved to: {s}\n", .{save_path});

    // Create new registry and load from JSON
    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    std.debug.print("\n=== Loading into new registry ===\n", .{});
    try ser.deserialize(&registry2, json);

    // Verify loaded data
    std.debug.print("\nLoaded entities:\n", .{});

    // Check players
    var player_view = registry2.view(.{ Position, Player }, .{});
    var player_iter = player_view.entityIterator();
    while (player_iter.next()) |e| {
        const pos = registry2.get(Position, e);
        const health = registry2.get(Health, e);
        std.debug.print("  Player at ({d}, {d}) with health {d}/{d}\n", .{
            pos.x,
            pos.y,
            health.current,
            health.max,
        });
    }

    // Check enemies
    var enemy_view = registry2.view(.{ Position, Enemy }, .{});
    var enemy_iter = enemy_view.entityIterator();
    while (enemy_iter.next()) |e| {
        const pos = registry2.get(Position, e);
        const health = registry2.get(Health, e);
        std.debug.print("  Enemy at ({d}, {d}) with health {d}/{d}", .{
            pos.x,
            pos.y,
            health.current,
            health.max,
        });

        // Check if this enemy has a follow target
        if (registry2.tryGet(FollowTarget, e)) |follow| {
            // Verify target entity exists and has Position
            if (registry2.tryGet(Position, follow.target)) |target_pos| {
                std.debug.print(" - Following entity at ({d}, {d})", .{
                    target_pos.x,
                    target_pos.y,
                });
            }
        }
        std.debug.print("\n", .{});
    }

    // Clean up save file
    std.fs.cwd().deleteFile(save_path) catch {};

    std.debug.print("\n=== Example complete ===\n", .{});
}
