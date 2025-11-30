//! Version Migration Example
//!
//! Demonstrates using MigrationRegistry to upgrade old save files
//! when game updates change component structures.

const std = @import("std");
const serialization = @import("serialization");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Version Migration Example ===\n\n", .{});

    // Set up migration registry
    var registry = serialization.MigrationRegistry(10){};

    // Register v1 -> v2: Rename "HP" component to "Health"
    registry.register(1, 2, struct {
        fn migrate(ctx: *serialization.MigrationContext) !void {
            try ctx.renameComponent("HP", "Health");
        }
    }.migrate);

    // Register v2 -> v3: Add "max" field to Health component
    registry.register(2, 3, struct {
        fn migrate(ctx: *serialization.MigrationContext) !void {
            try ctx.addFieldDefault("Health", "max", .{ .integer = 100 });
        }
    }.migrate);

    // Register v3 -> v4: Rename position fields from posX/posY to x/y
    registry.register(3, 4, struct {
        fn migrate(ctx: *serialization.MigrationContext) !void {
            try ctx.renameField("Position", "posX", "x");
            try ctx.renameField("Position", "posY", "y");
        }
    }.migrate);

    // Old save file from v1
    const old_save =
        \\{
        \\  "meta": { "version": 1 },
        \\  "components": {
        \\    "HP": [{ "entt": 1, "data": { "current": 80 } }],
        \\    "Position": [{ "entt": 1, "data": { "posX": 100, "posY": 200 } }]
        \\  }
        \\}
    ;

    std.debug.print("Original save (v1):\n{s}\n\n", .{old_save});

    // Migrate from v1 to v4 (chains: v1->v2->v3->v4)
    var result = try registry.migrate(allocator, old_save, 4);
    defer result.deinit();

    std.debug.print("Migrated save (v4):\n{s}\n\n", .{result.json});
    std.debug.print("Migrations applied: {d}\n", .{result.migrations_run});

    std.debug.print("\nMigration log:\n", .{});
    for (result.log) |entry| {
        std.debug.print("  - {s}\n", .{entry});
    }
}
