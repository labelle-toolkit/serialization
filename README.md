# serialization

A Zig library for serializing and deserializing ECS (Entity Component System) game state. Designed to work with [zig-ecs](https://github.com/Avokadoen/zig-ecs) and the [labelle](https://github.com/labelle-toolkit/labelle) graphics library.

## Features

- **Full ECS State Persistence**: Save and load complete game state including all entities and components
- **Entity ID Remapping**: Automatically handles entity reference updates when loading saves
- **Multiple Formats**: Support for JSON (human-readable) and binary (compact) formats
- **Versioning**: Built-in save format versioning for backward compatibility
- **Selective Serialization**: Mark components as transient to exclude from saves
- **Incremental Saves**: Support for delta saves to reduce save file size
- **Compression**: Optional compression for save files

## Installation

Add `serialization` to your `build.zig.zon`:

```zig
.dependencies = .{
    .serialization = .{
        .url = "https://github.com/labelle-toolkit/serialization/archive/refs/heads/main.tar.gz",
        .hash = "...",
    },
},
```

Then in your `build.zig`:

```zig
const serialization = b.dependency("serialization", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("serialization", serialization.module("serialization"));
```

## Quick Start

```zig
const std = @import("std");
const ecs = @import("zig-ecs");
const serialization = @import("serialization");

// Define your components
const Position = struct { x: f32, y: f32 };
const Health = struct { current: u8, max: u8 };
const Velocity = struct { dx: f32, dy: f32 };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create registry and add entities
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const player = registry.create();
    registry.add(player, Position{ .x = 100, .y = 200 });
    registry.add(player, Health{ .current = 80, .max = 100 });

    // Create serializer with component registration
    var serializer = serialization.Serializer.init(allocator, .{
        .version = 1,
        .format = .json,
    });
    defer serializer.deinit();

    // Register components to serialize
    try serializer.registerComponent(Position);
    try serializer.registerComponent(Health);
    // Don't register Velocity - it won't be saved (transient)

    // Save game state
    try serializer.save(&registry, "saves/game.json");

    // Load game state
    var new_registry = ecs.Registry.init(allocator);
    defer new_registry.deinit();

    try serializer.load(&new_registry, "saves/game.json");
}
```

## Advanced Usage

### Entity Reference Handling

Components that reference other entities are automatically remapped:

```zig
const FollowTarget = struct {
    target: ecs.Entity,
    distance: f32,
};

const Parent = struct {
    entity: ecs.Entity,
};

// Register with entity field hints
try serializer.registerComponent(FollowTarget);
try serializer.registerComponent(Parent);

// Entity references are automatically detected and remapped on load
```

### Custom Serialization

For complex types, implement custom serialize/deserialize:

```zig
const ComplexComponent = struct {
    data: std.ArrayList(u8),

    pub fn serialize(self: @This(), writer: anytype) !void {
        try writer.writeInt(u32, @intCast(self.data.items.len));
        try writer.writeAll(self.data.items);
    }

    pub fn deserialize(allocator: std.mem.Allocator, reader: anytype) !@This() {
        const len = try reader.readInt(u32);
        var data = std.ArrayList(u8).init(allocator);
        try data.resize(len);
        _ = try reader.readAll(data.items);
        return .{ .data = data };
    }
};
```

### Versioned Migrations

Handle save format changes between versions:

```zig
try serializer.registerMigration(1, 2, struct {
    fn migrate(data: *SaveData) !void {
        // Migrate from v1 to v2 format
        // e.g., rename component, add default values
    }
}.migrate);
```

### Save Metadata

Include game-specific metadata in saves:

```zig
const metadata = SaveMetadata{
    .save_name = "Slot 1",
    .play_time_seconds = 3600,
    .timestamp = std.time.timestamp(),
    .screenshot_path = "saves/slot1_thumb.png",
};

try serializer.saveWithMetadata(&registry, "saves/slot1.json", metadata);
```

## Supported Component Types

- Primitives: `bool`, `u8`-`u64`, `i8`-`i64`, `f16`-`f128`
- Arrays and slices
- Optionals
- Structs (nested)
- Enums
- Tagged unions
- Entity references (automatically remapped)
- Pointers (serialized as optional values)

## Configuration

```zig
const config = serialization.Config{
    .version = 1,
    .format = .json,           // .json or .binary
    .pretty_print = true,      // JSON formatting
    .compression = .none,      // .none, .zlib, .zstd
    .include_metadata = true,  // Save timestamp, version, etc.
};
```

## Use Cases

This library is designed for games like [flying-platform](https://github.com/apotema/flying_platform) that need to persist:

- **Character State**: Position, health, needs (hunger, thirst, tiredness), current tasks
- **World State**: Room layouts, workstation configurations, item placements
- **Progress**: Production progress, task queues, time of day
- **Inventory**: Items, storage contents, delivery tasks
- **Relationships**: Entity references (who carries what, who works where)

## Related Projects

- [labelle](https://github.com/labelle-toolkit/labelle) - 2D graphics library for Zig games
- [zig-ecs](https://github.com/Avokadoen/zig-ecs) - Entity Component System for Zig
- [flying-platform](https://github.com/apotema/flying_platform) - Example game using this library

## License

MIT License - see [LICENSE](LICENSE) for details.
