//! Tests for BinarySerializer
//!
//! Tests cover:
//! - Full serialization/deserialization roundtrip
//! - Size comparison with JSON
//! - Entity ID remapping
//! - Complex nested types
//! - Tag components
//! - Edge cases

const std = @import("std");
const testing = std.testing;
const ecs = @import("ecs");
const serialization = @import("serialization");
const BinarySerializer = serialization.BinarySerializer;

// ============================================================================
// Test Components
// ============================================================================

const Position = struct {
    x: f32,
    y: f32,
};

const Velocity = struct {
    vx: f32,
    vy: f32,
};

const Health = struct {
    current: i32,
    max: i32,
};

const Player = struct {}; // Tag component

const Inventory = struct {
    slots: [8]u32,
    gold: u32,
};

const Stats = struct {
    strength: u8,
    dexterity: u8,
    intelligence: u8,
    level: u16,
    experience: u64,
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

const Action = union(enum) {
    idle: void,
    move: struct { x: f32, y: f32 },
    attack: i32,
};

const ActionComponent = struct {
    current: Action,
};

const OptionalTarget = struct {
    target_id: ?u32,
    priority: ?i8,
};

// ============================================================================
// Roundtrip Serialization Tests
// ============================================================================

test "binary serialization roundtrip - simple components" {
    const allocator = testing.allocator;
    const TestSerializer = BinarySerializer(&[_]type{ Position, Health });

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e1 = registry1.create();
    registry1.add(e1, Position{ .x = 100.5, .y = 200.5 });
    registry1.add(e1, Health{ .current = 80, .max = 100 });

    const e2 = registry1.create();
    registry1.add(e2, Position{ .x = 50.0, .y = 75.0 });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const binary_data = try ser.serialize(&registry1);
    defer allocator.free(binary_data);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, binary_data);

    // Verify entities were loaded
    var pos_view = registry2.view(.{Position}, .{});
    var count: usize = 0;
    var iter = pos_view.entityIterator();
    while (iter.next()) |_| count += 1;
    try testing.expectEqual(@as(usize, 2), count);

    // Verify health component
    var health_view = registry2.view(.{Health}, .{});
    var health_iter = health_view.entityIterator();
    const health_entity = health_iter.next() orelse return error.NoEntity;
    const health = registry2.get(Health, health_entity);
    try testing.expectEqual(@as(i32, 80), health.current);
    try testing.expectEqual(@as(i32, 100), health.max);
}

test "binary serialization roundtrip - tag components" {
    const allocator = testing.allocator;
    const TestSerializer = BinarySerializer(&[_]type{ Position, Player });

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e1 = registry1.create();
    registry1.add(e1, Position{ .x = 0, .y = 0 });
    registry1.add(e1, Player{});

    const e2 = registry1.create();
    registry1.add(e2, Position{ .x = 10, .y = 10 });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const binary_data = try ser.serialize(&registry1);
    defer allocator.free(binary_data);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, binary_data);

    // Verify player tag was loaded
    var player_view = registry2.view(.{Player}, .{});
    var count: usize = 0;
    var iter = player_view.entityIterator();
    while (iter.next()) |_| count += 1;
    try testing.expectEqual(@as(usize, 1), count);
}

test "binary serialization roundtrip - arrays" {
    const allocator = testing.allocator;
    const TestSerializer = BinarySerializer(&[_]type{Inventory});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e = registry1.create();
    registry1.add(e, Inventory{
        .slots = .{ 1, 2, 3, 4, 5, 6, 7, 8 },
        .gold = 1000,
    });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const binary_data = try ser.serialize(&registry1);
    defer allocator.free(binary_data);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, binary_data);

    var view = registry2.view(.{Inventory}, .{});
    var iter = view.entityIterator();
    const loaded_e = iter.next() orelse return error.NoEntity;
    const inv = registry2.get(Inventory, loaded_e);

    try testing.expectEqual(@as(u32, 1), inv.slots[0]);
    try testing.expectEqual(@as(u32, 8), inv.slots[7]);
    try testing.expectEqual(@as(u32, 1000), inv.gold);
}

test "binary serialization roundtrip - optional types" {
    const allocator = testing.allocator;
    const TestSerializer = BinarySerializer(&[_]type{OptionalTarget});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    // Entity with all optionals set
    const e1 = registry1.create();
    registry1.add(e1, OptionalTarget{ .target_id = 42, .priority = -5 });

    // Entity with all optionals null
    const e2 = registry1.create();
    registry1.add(e2, OptionalTarget{ .target_id = null, .priority = null });

    // Entity with mixed optionals
    const e3 = registry1.create();
    registry1.add(e3, OptionalTarget{ .target_id = 100, .priority = null });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const binary_data = try ser.serialize(&registry1);
    defer allocator.free(binary_data);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, binary_data);

    var view = registry2.view(.{OptionalTarget}, .{});
    var found_all_set = false;
    var found_all_null = false;
    var found_mixed = false;
    var iter = view.entityIterator();
    while (iter.next()) |entity| {
        const target = registry2.get(OptionalTarget, entity);
        if (target.target_id != null and target.priority != null) {
            try testing.expectEqual(@as(u32, 42), target.target_id.?);
            try testing.expectEqual(@as(i8, -5), target.priority.?);
            found_all_set = true;
        } else if (target.target_id == null and target.priority == null) {
            found_all_null = true;
        } else if (target.target_id != null and target.priority == null) {
            try testing.expectEqual(@as(u32, 100), target.target_id.?);
            found_mixed = true;
        }
    }
    try testing.expect(found_all_set);
    try testing.expect(found_all_null);
    try testing.expect(found_mixed);
}

test "binary serialization roundtrip - enums" {
    const allocator = testing.allocator;
    const TestSerializer = BinarySerializer(&[_]type{StatusComponent});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e1 = registry1.create();
    registry1.add(e1, StatusComponent{ .state = .idle });

    const e2 = registry1.create();
    registry1.add(e2, StatusComponent{ .state = .attacking });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const binary_data = try ser.serialize(&registry1);
    defer allocator.free(binary_data);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, binary_data);

    var view = registry2.view(.{StatusComponent}, .{});
    var found_idle = false;
    var found_attacking = false;
    var iter = view.entityIterator();
    while (iter.next()) |entity| {
        const status = registry2.get(StatusComponent, entity);
        if (status.state == .idle) found_idle = true;
        if (status.state == .attacking) found_attacking = true;
    }
    try testing.expect(found_idle);
    try testing.expect(found_attacking);
}

test "binary serialization roundtrip - tagged unions" {
    const allocator = testing.allocator;
    const TestSerializer = BinarySerializer(&[_]type{ActionComponent});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e1 = registry1.create();
    registry1.add(e1, ActionComponent{ .current = .idle });

    const e2 = registry1.create();
    registry1.add(e2, ActionComponent{ .current = .{ .move = .{ .x = 10, .y = 20 } } });

    const e3 = registry1.create();
    registry1.add(e3, ActionComponent{ .current = .{ .attack = 50 } });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const binary_data = try ser.serialize(&registry1);
    defer allocator.free(binary_data);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, binary_data);

    var view = registry2.view(.{ActionComponent}, .{});
    var found_idle = false;
    var found_move = false;
    var found_attack = false;
    var iter = view.entityIterator();
    while (iter.next()) |entity| {
        const action = registry2.get(ActionComponent, entity);
        switch (action.current) {
            .idle => found_idle = true,
            .move => |m| {
                try testing.expectApproxEqAbs(@as(f32, 10), m.x, 0.001);
                try testing.expectApproxEqAbs(@as(f32, 20), m.y, 0.001);
                found_move = true;
            },
            .attack => |dmg| {
                try testing.expectEqual(@as(i32, 50), dmg);
                found_attack = true;
            },
        }
    }
    try testing.expect(found_idle);
    try testing.expect(found_move);
    try testing.expect(found_attack);
}

// ============================================================================
// Size Comparison Tests
// ============================================================================

test "binary format is smaller than JSON" {
    const allocator = testing.allocator;
    const JsonSerializer = serialization.Serializer(&[_]type{ Position, Health, Stats });
    const BinSerializer = BinarySerializer(&[_]type{ Position, Health, Stats });

    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    // Create multiple entities with data
    for (0..10) |i| {
        const e = registry.create();
        registry.add(e, Position{ .x = @floatFromInt(i * 10), .y = @floatFromInt(i * 20) });
        registry.add(e, Health{ .current = @intCast(100 - i * 5), .max = 100 });
        registry.add(e, Stats{
            .strength = @intCast(10 + i),
            .dexterity = @intCast(12 + i),
            .intelligence = @intCast(8 + i),
            .level = @intCast(i + 1),
            .experience = @as(u64, i) * 1000,
        });
    }

    var json_ser = JsonSerializer.init(allocator, .{ .pretty_print = false });
    defer json_ser.deinit();
    const json_data = try json_ser.serialize(&registry);
    defer allocator.free(json_data);

    var bin_ser = BinSerializer.init(allocator, .{});
    defer bin_ser.deinit();
    const bin_data = try bin_ser.serialize(&registry);
    defer allocator.free(bin_data);

    // Binary should be significantly smaller
    try testing.expect(bin_data.len < json_data.len);
}

// ============================================================================
// Edge Cases
// ============================================================================

test "binary handles empty registry" {
    const allocator = testing.allocator;
    const TestSerializer = BinarySerializer(&[_]type{Position});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const binary_data = try ser.serialize(&registry1);
    defer allocator.free(binary_data);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, binary_data);

    var view = registry2.view(.{Position}, .{});
    var count: usize = 0;
    var iter = view.entityIterator();
    while (iter.next()) |_| count += 1;
    try testing.expectEqual(@as(usize, 0), count);
}

test "binary handles many entities" {
    const allocator = testing.allocator;
    const TestSerializer = BinarySerializer(&[_]type{Position});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    // Create 1000 entities
    for (0..1000) |i| {
        const e = registry1.create();
        registry1.add(e, Position{
            .x = @floatFromInt(i),
            .y = @floatFromInt(i * 2),
        });
    }

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const binary_data = try ser.serialize(&registry1);
    defer allocator.free(binary_data);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, binary_data);

    var view = registry2.view(.{Position}, .{});
    var count: usize = 0;
    var iter = view.entityIterator();
    while (iter.next()) |_| count += 1;
    try testing.expectEqual(@as(usize, 1000), count);
}

test "binary serialization with metadata" {
    const allocator = testing.allocator;
    const TestSerializer = BinarySerializer(&[_]type{Position});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e = registry1.create();
    registry1.add(e, Position{ .x = 1, .y = 2 });

    var ser = TestSerializer.init(allocator, .{
        .include_metadata = true,
        .game_name = "TestGame",
    });
    defer ser.deinit();

    const binary_data = try ser.serialize(&registry1);
    defer allocator.free(binary_data);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, binary_data);

    var view = registry2.view(.{Position}, .{});
    var iter = view.entityIterator();
    const loaded_e = iter.next() orelse return error.NoEntity;
    const pos = registry2.get(Position, loaded_e);
    try testing.expectApproxEqAbs(@as(f32, 1), pos.x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 2), pos.y, 0.001);
}
