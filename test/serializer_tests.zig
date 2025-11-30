//! Comprehensive tests for the serialization library

const std = @import("std");
const ecs = @import("ecs");
const serialization = @import("serialization");
const Serializer = serialization.Serializer;

// Test components
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

const Player = struct {}; // Tag component (zero-sized)
const Enemy = struct {}; // Tag component

const Inventory = struct {
    capacity: u8,
    gold: u32,
};

const FollowTarget = struct {
    target: ecs.Entity,
    distance: f32,
};

const OptionalTarget = struct {
    target: ?ecs.Entity,
    priority: u8,
};

const ItemState = enum {
    dropped,
    carried,
    stored,
};

const Item = struct {
    state: ItemState,
    value: u32,
};

const Container = struct {
    items: [4]u32,
    count: u8,
};

// Basic serialization tests
test "serialize empty registry" {
    const allocator = std.testing.allocator;
    const TestSerializer = Serializer(&[_]type{Position});

    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry);
    defer allocator.free(json);

    // Should produce valid JSON with empty component arrays
    try std.testing.expect(json.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"components\"") != null);
}

test "serialize single entity with data component" {
    const allocator = std.testing.allocator;
    const TestSerializer = Serializer(&[_]type{Position});

    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const entity = registry.create();
    registry.add(entity, Position{ .x = 10.5, .y = 20.5 });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry);
    defer allocator.free(json);

    // Verify JSON contains position data
    try std.testing.expect(std.mem.indexOf(u8, json, "Position") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"x\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"y\"") != null);
}

test "serialize tag component" {
    const allocator = std.testing.allocator;
    const TestSerializer = Serializer(&[_]type{Player});

    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const entity = registry.create();
    registry.add(entity, Player{});

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry);
    defer allocator.free(json);

    // Tag components should serialize as array of entity IDs
    try std.testing.expect(std.mem.indexOf(u8, json, "Player") != null);
}

test "serialize multiple component types" {
    const allocator = std.testing.allocator;
    const TestSerializer = Serializer(&[_]type{ Position, Health, Player });

    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const player = registry.create();
    registry.add(player, Position{ .x = 0, .y = 0 });
    registry.add(player, Health{ .current = 100, .max = 100 });
    registry.add(player, Player{});

    const enemy = registry.create();
    registry.add(enemy, Position{ .x = 50, .y = 50 });
    registry.add(enemy, Health{ .current = 30, .max = 50 });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "Position") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "Health") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "Player") != null);
}

test "serialize enum field" {
    const allocator = std.testing.allocator;
    const TestSerializer = Serializer(&[_]type{Item});

    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const entity = registry.create();
    registry.add(entity, Item{ .state = .carried, .value = 100 });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"carried\"") != null);
}

test "serialize array field" {
    const allocator = std.testing.allocator;
    const TestSerializer = Serializer(&[_]type{Container});

    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const entity = registry.create();
    registry.add(entity, Container{
        .items = .{ 1, 2, 3, 4 },
        .count = 4,
    });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"items\"") != null);
}

// Deserialization tests
test "deserialize single entity" {
    const allocator = std.testing.allocator;
    const TestSerializer = Serializer(&[_]type{Position});

    // Create and serialize
    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const entity = registry1.create();
    registry1.add(entity, Position{ .x = 42.0, .y = 84.0 });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    // Deserialize into new registry
    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    // Verify
    var view = registry2.view(.{Position}, .{});
    var iter = view.entityIterator();
    const loaded_entity = iter.next() orelse return error.NoEntity;
    const pos = registry2.get(Position, loaded_entity);

    try std.testing.expectApproxEqAbs(@as(f32, 42.0), pos.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 84.0), pos.y, 0.001);
}

test "deserialize preserves all components" {
    const allocator = std.testing.allocator;
    const TestSerializer = Serializer(&[_]type{ Position, Health, Player });

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const player = registry1.create();
    registry1.add(player, Position{ .x = 10, .y = 20 });
    registry1.add(player, Health{ .current = 80, .max = 100 });
    registry1.add(player, Player{});

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    // Count entities with Player tag
    var view = registry2.view(.{Player}, .{});
    var count: usize = 0;
    var iter = view.entityIterator();
    while (iter.next()) |e| {
        count += 1;
        // This entity should also have Position and Health
        try std.testing.expect(registry2.has(Position, e));
        try std.testing.expect(registry2.has(Health, e));
    }
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "deserialize enum field" {
    const allocator = std.testing.allocator;
    const TestSerializer = Serializer(&[_]type{Item});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const entity = registry1.create();
    registry1.add(entity, Item{ .state = .stored, .value = 500 });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    var view = registry2.view(.{Item}, .{});
    var iter = view.entityIterator();
    const loaded_entity = iter.next() orelse return error.NoEntity;
    const item = registry2.get(Item, loaded_entity);

    try std.testing.expectEqual(ItemState.stored, item.state);
    try std.testing.expectEqual(@as(u32, 500), item.value);
}

// Entity reference remapping tests
test "remap entity references" {
    const allocator = std.testing.allocator;
    const TestSerializer = Serializer(&[_]type{ Position, FollowTarget });

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const leader = registry1.create();
    registry1.add(leader, Position{ .x = 0, .y = 0 });

    const follower = registry1.create();
    registry1.add(follower, Position{ .x = 10, .y = 10 });
    registry1.add(follower, FollowTarget{ .target = leader, .distance = 5.0 });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    // Find the follower and verify target reference is valid
    var view = registry2.view(.{FollowTarget}, .{});
    var iter = view.entityIterator();
    const loaded_follower = iter.next() orelse return error.NoEntity;
    const follow = registry2.get(FollowTarget, loaded_follower);

    // The target should be a valid entity in the new registry
    try std.testing.expect(registry2.has(Position, follow.target));
}

test "remap optional entity reference" {
    const allocator = std.testing.allocator;
    const TestSerializer = Serializer(&[_]type{ Position, OptionalTarget });

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const target = registry1.create();
    registry1.add(target, Position{ .x = 0, .y = 0 });

    const entity_with_target = registry1.create();
    registry1.add(entity_with_target, OptionalTarget{ .target = target, .priority = 1 });

    const entity_without_target = registry1.create();
    registry1.add(entity_without_target, OptionalTarget{ .target = null, .priority = 2 });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    // Verify both entities loaded correctly
    var view = registry2.view(.{OptionalTarget}, .{});
    var count: usize = 0;
    var iter = view.entityIterator();
    while (iter.next()) |e| {
        count += 1;
        const opt = registry2.get(OptionalTarget, e);
        if (opt.priority == 1) {
            // Should have a valid target
            try std.testing.expect(opt.target != null);
            try std.testing.expect(registry2.has(Position, opt.target.?));
        } else {
            // Should have null target
            try std.testing.expectEqual(@as(?ecs.Entity, null), opt.target);
        }
    }
    try std.testing.expectEqual(@as(usize, 2), count);
}

// Version tests
test "version check rejects newer saves" {
    const allocator = std.testing.allocator;
    const TestSerializer = Serializer(&[_]type{Position});

    var ser = TestSerializer.init(allocator, .{
        .version = 1,
    });
    defer ser.deinit();

    // JSON with version 99
    const future_json =
        \\{
        \\  "meta": { "version": 99 },
        \\  "components": {}
        \\}
    ;

    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const result = ser.deserialize(&registry, future_json);
    try std.testing.expectError(error.SaveFromNewerVersion, result);
}

test "version check rejects old saves" {
    const allocator = std.testing.allocator;
    const TestSerializer = Serializer(&[_]type{Position});

    var ser = TestSerializer.init(allocator, .{
        .version = 5,
        .min_loadable_version = 3,
    });
    defer ser.deinit();

    // JSON with version 1 (too old)
    const old_json =
        \\{
        \\  "meta": { "version": 1 },
        \\  "components": {}
        \\}
    ;

    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const result = ser.deserialize(&registry, old_json);
    try std.testing.expectError(error.SaveTooOld, result);
}

// Metadata tests
test "includes metadata when configured" {
    const allocator = std.testing.allocator;
    const TestSerializer = Serializer(&[_]type{Position});

    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    var ser = TestSerializer.init(allocator, .{
        .include_metadata = true,
        .game_name = "test_game",
    });
    defer ser.deinit();

    const json = try ser.serialize(&registry);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"meta\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"version\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"test_game\"") != null);
}

// Pretty print tests
test "pretty print adds formatting" {
    const allocator = std.testing.allocator;
    const TestSerializer = Serializer(&[_]type{Position});

    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const entity = registry.create();
    registry.add(entity, Position{ .x = 1, .y = 2 });

    var ser_pretty = TestSerializer.init(allocator, .{ .pretty_print = true });
    defer ser_pretty.deinit();

    var ser_compact = TestSerializer.init(allocator, .{ .pretty_print = false });
    defer ser_compact.deinit();

    const json_pretty = try ser_pretty.serialize(&registry);
    defer allocator.free(json_pretty);

    const json_compact = try ser_compact.serialize(&registry);
    defer allocator.free(json_compact);

    // Pretty should have newlines, compact should not
    try std.testing.expect(std.mem.indexOf(u8, json_pretty, "\n") != null);
    try std.testing.expectEqual(@as(?usize, null), std.mem.indexOf(u8, json_compact, "\n"));
}

// Multiple entities test
test "serialize and deserialize many entities" {
    const allocator = std.testing.allocator;
    const TestSerializer = Serializer(&[_]type{ Position, Health });

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    // Create 100 entities
    const entity_count = 100;
    for (0..entity_count) |i| {
        const e = registry1.create();
        registry1.add(e, Position{
            .x = @floatFromInt(i),
            .y = @floatFromInt(i * 2),
        });
        if (i % 2 == 0) {
            registry1.add(e, Health{ .current = @intCast(i), .max = 100 });
        }
    }

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    // Verify entity counts
    var pos_view = registry2.view(.{Position}, .{});
    var pos_count: usize = 0;
    var pos_iter = pos_view.entityIterator();
    while (pos_iter.next()) |_| pos_count += 1;

    var health_view = registry2.view(.{Health}, .{});
    var health_count: usize = 0;
    var health_iter = health_view.entityIterator();
    while (health_iter.next()) |_| health_count += 1;

    try std.testing.expectEqual(@as(usize, entity_count), pos_count);
    try std.testing.expectEqual(@as(usize, entity_count / 2), health_count);
}

const NoEntity = error.NoEntity;

// Additional imports for transient/selective tests
const SerializerWithTransient = serialization.SerializerWithTransient;
const SelectiveSerializer = serialization.SelectiveSerializer;
const SelectiveDeserializer = serialization.SelectiveDeserializer;

// Additional test component for slots
const InventorySlots = struct {
    slots: u8,
};

test "SerializerWithTransient excludes transient components" {
    const allocator = std.testing.allocator;

    // Create serializer that excludes Velocity
    const TestSerializer = SerializerWithTransient(
        &[_]type{ Position, Velocity, Health },
        &[_]type{Velocity},
    );

    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const entity = registry.create();
    registry.add(entity, Position{ .x = 10, .y = 20 });
    registry.add(entity, Velocity{ .dx = 1, .dy = 2 });
    registry.add(entity, Health{ .current = 100, .max = 100 });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry);
    defer allocator.free(json);

    // Verify Velocity is not in the JSON
    try std.testing.expect(std.mem.indexOf(u8, json, "Velocity") == null);
    // But Position and Health are
    try std.testing.expect(std.mem.indexOf(u8, json, "Position") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "Health") != null);
}

test "Serializer roundtrip" {
    const allocator = std.testing.allocator;

    const TestSerializer = Serializer(&[_]type{ Position, Health, Player });

    // Create and populate registry
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const player = registry.create();
    registry.add(player, Position{ .x = 100, .y = 200 });
    registry.add(player, Health{ .current = 80, .max = 100 });
    registry.add(player, Player{});

    const enemy = registry.create();
    registry.add(enemy, Position{ .x = 50, .y = 75 });
    registry.add(enemy, Health{ .current = 50, .max = 50 });

    // Serialize
    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry);
    defer allocator.free(json);

    // Deserialize into new registry
    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    // Verify data
    var view = registry2.view(.{Position}, .{});
    var count: usize = 0;
    var iter = view.entityIterator();
    while (iter.next()) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "SelectiveSerializer saves only selected components" {
    const allocator = std.testing.allocator;

    // Full component list
    const AllComponents = &[_]type{ Position, Health, InventorySlots };
    // Quick save profile
    const QuickSaveComponents = &[_]type{ Position, Health };

    // Create registry with all component types
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const player = registry.create();
    registry.add(player, Position{ .x = 100, .y = 200 });
    registry.add(player, Health{ .current = 80, .max = 100 });
    registry.add(player, InventorySlots{ .slots = 20 });

    // Use selective serializer (only Position and Health)
    const QuickSerializer = SelectiveSerializer(AllComponents, QuickSaveComponents);
    var ser = QuickSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry);
    defer allocator.free(json);

    // Verify InventorySlots is not in the output
    try std.testing.expect(std.mem.indexOf(u8, json, "InventorySlots") == null);
    // But Position and Health are
    try std.testing.expect(std.mem.indexOf(u8, json, "Position") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "Health") != null);
}

test "SelectiveDeserializer loads only selected components" {
    const allocator = std.testing.allocator;

    // Create a full save
    const FullSerializer = Serializer(&[_]type{ Position, Health, InventorySlots });
    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const player = registry1.create();
    registry1.add(player, Position{ .x = 100, .y = 200 });
    registry1.add(player, Health{ .current = 80, .max = 100 });
    registry1.add(player, InventorySlots{ .slots = 20 });

    var full_ser = FullSerializer.init(allocator, .{});
    defer full_ser.deinit();

    const full_json = try full_ser.serialize(&registry1);
    defer allocator.free(full_json);

    // Load only Position from the full save
    const PositionOnlyLoader = SelectiveDeserializer(&[_]type{Position});
    var loader = PositionOnlyLoader.initWithOptions(allocator, .{}, .{ .skip_missing = true });
    defer loader.deinit();

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try loader.deserialize(&registry2, full_json);

    // Verify only Position was loaded
    var pos_view = registry2.view(.{Position}, .{});
    var pos_count: usize = 0;
    var pos_iter = pos_view.entityIterator();
    while (pos_iter.next()) |_| {
        pos_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), pos_count);
}

test "SelectiveDeserializer errors on missing component without skip_missing" {
    const allocator = std.testing.allocator;

    // Create a save with only Position
    const PositionSerializer = Serializer(&[_]type{Position});
    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const player = registry1.create();
    registry1.add(player, Position{ .x = 100, .y = 200 });

    var ser = PositionSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    // Try to load both Position and Health (Health is missing)
    const BothLoader = SelectiveDeserializer(&[_]type{ Position, Health });
    var loader = BothLoader.init(allocator, .{}); // skip_missing = false by default
    defer loader.deinit();

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    // Should error because Health is not in the save
    try std.testing.expectError(error.ComponentNotInSave, loader.deserialize(&registry2, json));
}
