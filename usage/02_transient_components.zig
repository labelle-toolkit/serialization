//! Transient Components Example
//!
//! Demonstrates using SerializerWithTransient to exclude runtime-only
//! components from serialization (like velocity, animations, UI state).

const std = @import("std");
const ecs = @import("ecs");
const serialization = @import("serialization");

// Persistent components - saved to disk
const Position = struct { x: f32, y: f32 };
const Health = struct { current: u8, max: u8 };
const CharacterName = struct { name: [32]u8, len: u8 };

// Transient components - NOT saved (runtime only)
const Velocity = struct { dx: f32, dy: f32 };
const AnimationState = struct { frame: u16, timer: f32 };
const RenderCache = struct { sprite_id: u32, dirty: bool };

// All components the game uses
const AllComponents = &[_]type{
    Position,
    Health,
    CharacterName,
    Velocity,
    AnimationState,
    RenderCache,
};

// Components that should NOT be saved
const TransientComponents = &[_]type{
    Velocity,
    AnimationState,
    RenderCache,
};

// Serializer that excludes transient components
const GameSerializer = serialization.SerializerWithTransient(AllComponents, TransientComponents);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Transient Components Example ===\n\n", .{});

    // Create game state with both persistent and transient data
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const player = registry.create();

    // Persistent state
    registry.add(player, Position{ .x = 100, .y = 200 });
    registry.add(player, Health{ .current = 80, .max = 100 });
    var name = CharacterName{ .name = undefined, .len = 0 };
    const player_name = "Hero";
    @memcpy(name.name[0..player_name.len], player_name);
    name.len = player_name.len;
    registry.add(player, name);

    // Transient state (will be excluded from save)
    registry.add(player, Velocity{ .dx = 5.0, .dy = -2.0 });
    registry.add(player, AnimationState{ .frame = 12, .timer = 0.35 });
    registry.add(player, RenderCache{ .sprite_id = 42, .dirty = true });

    std.debug.print("Entity has {d} components total\n", .{6});
    std.debug.print("  - Persistent: Position, Health, CharacterName\n", .{});
    std.debug.print("  - Transient: Velocity, AnimationState, RenderCache\n\n", .{});

    // Serialize - transient components are automatically excluded
    var ser = GameSerializer.init(allocator, .{ .pretty_print = true });
    defer ser.deinit();

    const json = try ser.serialize(&registry);
    defer allocator.free(json);

    std.debug.print("Saved JSON (transient data excluded):\n{s}\n", .{json});

    // Notice: Velocity, AnimationState, RenderCache are NOT in the output
    std.debug.print("\nTransient data is NOT in the save file.\n", .{});
    std.debug.print("On load, you would reinitialize these components with defaults.\n", .{});
}
