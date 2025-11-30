//! Usage Example 10: Debug and Inspection Tools
//!
//! This example demonstrates how to use the debug utilities to inspect
//! save files without fully deserializing them. Useful for debugging,
//! tooling, and analyzing save file contents.

const std = @import("std");
const ecs = @import("ecs");
const serialization = @import("serialization");
const debug = serialization.debug;

// Sample components
const Position = struct { x: f32, y: f32 };
const Velocity = struct { vx: f32, vy: f32 };
const Health = struct { current: i32, max: i32 };
const Player = struct {}; // Tag component

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a sample save file
    std.debug.print("=== Debug Tools Example ===\n\n", .{});

    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    // Create some entities
    const player = registry.create();
    registry.add(player, Position{ .x = 100, .y = 200 });
    registry.add(player, Health{ .current = 80, .max = 100 });
    registry.add(player, Player{});

    const enemy1 = registry.create();
    registry.add(enemy1, Position{ .x = 50, .y = 75 });
    registry.add(enemy1, Velocity{ .vx = 1, .vy = 0 });
    registry.add(enemy1, Health{ .current = 30, .max = 50 });

    const enemy2 = registry.create();
    registry.add(enemy2, Position{ .x = 200, .y = 150 });
    registry.add(enemy2, Health{ .current = 50, .max = 50 });

    // Serialize to JSON
    const ComponentTypes = .{ Position, Velocity, Health, Player };
    var serializer = serialization.Serializer(&ComponentTypes).init(allocator, .{
        .game_name = "DebugExample",
        .pretty_print = false, // Compact for this example
    });
    defer serializer.deinit();

    const save1 = try serializer.serialize(&registry);
    defer allocator.free(save1);

    // === 1. Get Statistics ===
    std.debug.print("1. Save File Statistics\n", .{});
    std.debug.print("-----------------------\n", .{});

    var stats = try debug.getStats(allocator, save1);
    defer stats.deinit(allocator);

    // Print stats manually (formatStats requires a writer)
    if (stats.version) |v| {
        std.debug.print("Version: {d}\n", .{v});
    }
    if (stats.game_name) |name| {
        std.debug.print("Game: {s}\n", .{name});
    }
    std.debug.print("File size: {d} bytes\n", .{stats.file_size});
    std.debug.print("Entities: {d}\n", .{stats.entity_count});
    std.debug.print("Component types: {d}\n", .{stats.component_types});
    std.debug.print("Component instances: {d}\n", .{stats.component_instances});
    std.debug.print("\nComponents:\n", .{});
    for (stats.components) |comp| {
        std.debug.print("  {s}: {d} instances\n", .{ comp.name, comp.instance_count });
    }

    // === 2. Pretty Print ===
    std.debug.print("\n2. Pretty-Printed Save\n", .{});
    std.debug.print("----------------------\n", .{});

    const pretty = try debug.prettyPrint(allocator, save1);
    defer allocator.free(pretty);

    // Only show first 500 characters for brevity
    const preview_len = @min(pretty.len, 500);
    std.debug.print("{s}...\n", .{pretty[0..preview_len]});

    // === 3. Diffing Saves ===
    std.debug.print("\n3. Save File Diff\n", .{});
    std.debug.print("-----------------\n", .{});

    // Modify the registry
    registry.remove(Health, enemy2);
    registry.add(enemy2, Velocity{ .vx = -1, .vy = 1 });

    const projectile = registry.create();
    registry.add(projectile, Position{ .x = 100, .y = 200 });
    registry.add(projectile, Velocity{ .vx = 5, .vy = 0 });

    // Create second save
    const save2 = try serializer.serialize(&registry);
    defer allocator.free(save2);

    var diff = try debug.diffSaves(allocator, save1, save2);
    defer diff.deinit();

    // Print diff manually
    if (diff.added_entities.len > 0) {
        std.debug.print("\nAdded entities ({d}):\n", .{diff.added_entities.len});
        for (diff.added_entities) |id| {
            std.debug.print("  + {d}\n", .{id});
        }
    }
    if (diff.removed_entities.len > 0) {
        std.debug.print("\nRemoved entities ({d}):\n", .{diff.removed_entities.len});
        for (diff.removed_entities) |id| {
            std.debug.print("  - {d}\n", .{id});
        }
    }
    if (diff.added_components.len > 0) {
        std.debug.print("\nAdded component types:\n", .{});
        for (diff.added_components) |name| {
            std.debug.print("  + {s}\n", .{name});
        }
    }
    if (diff.removed_components.len > 0) {
        std.debug.print("\nRemoved component types:\n", .{});
        for (diff.removed_components) |name| {
            std.debug.print("  - {s}\n", .{name});
        }
    }

    // === 4. Using with Logging ===
    std.debug.print("\n4. Serializer with Logging\n", .{});
    std.debug.print("--------------------------\n", .{});

    // Create serializer with logging enabled
    var logged_serializer = serialization.Serializer(&ComponentTypes).init(allocator, .{
        .game_name = "LoggedExample",
        .log_level = .info,
    });
    defer logged_serializer.deinit();

    // Operations will now log to std.log
    std.debug.print("Serializing with logging enabled (check stderr)...\n", .{});
    const logged_save = try logged_serializer.serialize(&registry);
    defer allocator.free(logged_save);

    // === 5. Validate Save File ===
    std.debug.print("\n5. Save File Validation\n", .{});
    std.debug.print("-----------------------\n", .{});

    const validation_result = try serialization.validateSave(allocator, save1, 999);
    switch (validation_result) {
        .valid => std.debug.print("Save file is valid!\n", .{}),
        .checksum_mismatch => |info| std.debug.print("Checksum mismatch: expected {d}, got {d}\n", .{ info.expected, info.actual }),
        .invalid_structure => |msg| std.debug.print("Invalid structure: {s}\n", .{msg}),
        .version_mismatch => |info| std.debug.print("Version mismatch: v{d} vs max v{d}\n", .{ info.save_version, info.max_supported }),
        .missing_metadata => std.debug.print("Missing metadata\n", .{}),
    }

    std.debug.print("\n=== Example Complete ===\n", .{});
}
