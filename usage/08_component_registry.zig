//! Component Registry Example
//!
//! Demonstrates using ComponentRegistry for easier component registration
//! instead of manually listing all component types.

const std = @import("std");
const serialization = @import("serialization");

// Example component module - in a real project this would be components.zig
const Components = struct {
    pub const Position = struct { x: f32, y: f32 };
    pub const Health = struct { current: u8, max: u8 };
    pub const Inventory = struct { slots: [10]u8, count: u8 };
    pub const Player = struct {}; // Tag component
    pub const NPC = struct {}; // Tag component

    // Non-component declarations (will be ignored by fromModule)
    pub const MAX_ENTITIES: u32 = 1000;
    pub fn helper() void {}
};

// Transient components that shouldn't be saved
const TransientComponents = struct {
    pub const Velocity = struct { dx: f32, dy: f32 };
    pub const AnimationState = struct { frame: u8, time: f32 };
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Component Registry Example ===\n\n", .{});

    // Method 1: fromTuple - explicit list of types
    std.debug.print("Method 1: fromTuple\n", .{});
    const tuple_types = serialization.ComponentRegistry.fromTuple(.{
        Components.Position,
        Components.Health,
        Components.Player,
    });
    std.debug.print("  Types count: {d}\n", .{tuple_types.len});

    // Method 2: fromModule - extract all structs from a module
    std.debug.print("\nMethod 2: fromModule\n", .{});
    const module_types = serialization.ComponentRegistry.fromModule(Components);
    std.debug.print("  Types from Components module: {d}\n", .{module_types.len});
    std.debug.print("  (ignores non-struct declarations like MAX_ENTITIES and helper)\n", .{});

    // Method 3: exclude - filter out types
    std.debug.print("\nMethod 3: exclude\n", .{});
    const all_types = &[_]type{
        Components.Position,
        Components.Health,
        Components.Inventory,
        TransientComponents.Velocity,
        TransientComponents.AnimationState,
    };
    const saveable = comptime serialization.ComponentRegistry.exclude(all_types, .{
        TransientComponents.Velocity,
        TransientComponents.AnimationState,
    });
    std.debug.print("  All types: {d}\n", .{all_types.len});
    std.debug.print("  After excluding transients: {d}\n", .{saveable.len});

    // Method 4: merge - combine multiple lists
    std.debug.print("\nMethod 4: merge\n", .{});
    const core_types = &[_]type{ Components.Position, Components.Health };
    const tag_types = &[_]type{ Components.Player, Components.NPC };
    const merged = serialization.ComponentRegistry.merge(.{ core_types, tag_types });
    std.debug.print("  Core types: {d}\n", .{core_types.len});
    std.debug.print("  Tag types: {d}\n", .{tag_types.len});
    std.debug.print("  Merged: {d}\n", .{merged.len});

    // Method 5: contains - check if type is in list
    std.debug.print("\nMethod 5: contains\n", .{});
    const has_position = comptime serialization.ComponentRegistry.contains(core_types, Components.Position);
    const has_inventory = comptime serialization.ComponentRegistry.contains(core_types, Components.Inventory);
    std.debug.print("  core_types contains Position: {}\n", .{has_position});
    std.debug.print("  core_types contains Inventory: {}\n", .{has_inventory});

    // Using with Serializer
    std.debug.print("\n=== Using with Serializer ===\n\n", .{});

    // Create serializer with types from ComponentRegistry
    const GameSerializer = serialization.Serializer(
        serialization.ComponentRegistry.fromTuple(.{
            Components.Position,
            Components.Health,
            Components.Player,
        }),
    );

    var registry = serialization.Registry.init(allocator);
    defer registry.deinit();

    // Create a player entity
    const player = registry.create();
    registry.add(player, Components.Position{ .x = 100, .y = 200 });
    registry.add(player, Components.Health{ .current = 80, .max = 100 });
    registry.add(player, Components.Player{});

    var ser = GameSerializer.init(allocator, .{ .pretty_print = true });
    defer ser.deinit();

    const json = try ser.serialize(&registry);
    defer allocator.free(json);

    std.debug.print("Serialized with ComponentRegistry-defined types:\n{s}\n", .{json});
}
