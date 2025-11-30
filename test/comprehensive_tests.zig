//! Comprehensive test suite for the serialization library
//!
//! This file covers:
//! - Primitive type serialization (bool, integers, floats)
//! - String and slice serialization
//! - Optional serialization
//! - Enum and tagged union serialization
//! - Nested struct serialization
//! - Edge cases (empty strings, max values, unicode, deeply nested)
//! - Error handling (invalid JSON, type mismatches, corruption)
//! - Large entity counts

const std = @import("std");
const testing = std.testing;
const ecs = @import("ecs");
const serialization = @import("serialization");
const Serializer = serialization.Serializer;

// ============================================================================
// Test Components - Primitives
// ============================================================================

const BoolComponent = struct {
    flag: bool,
    enabled: bool,
};

const IntegerComponent = struct {
    i8_val: i8,
    i16_val: i16,
    i32_val: i32,
    i64_val: i64,
    u8_val: u8,
    u16_val: u16,
    u32_val: u32,
    u64_val: u64,
};

const FloatComponent = struct {
    f32_val: f32,
    f64_val: f64,
};

// ============================================================================
// Test Components - Strings and Arrays
// ============================================================================

const NameComponent = struct {
    name: []const u8,
};

const FixedArrayComponent = struct {
    values: [8]u32,
    flags: [4]bool,
};

const NestedArrayComponent = struct {
    matrix: [3][3]i32,
};

// ============================================================================
// Test Components - Optionals
// ============================================================================

const OptionalPrimitives = struct {
    maybe_int: ?i32,
    maybe_float: ?f32,
    maybe_bool: ?bool,
};

const OptionalNested = struct {
    maybe_pos: ?struct { x: f32, y: f32 },
};

// ============================================================================
// Test Components - Enums
// ============================================================================

const SimpleEnum = enum {
    idle,
    walking,
    running,
    jumping,
};

const EnumComponent = struct {
    state: SimpleEnum,
};

const NumberedEnum = enum(u8) {
    zero = 0,
    one = 1,
    hundred = 100,
    max = 255,
};

const NumberedEnumComponent = struct {
    value: NumberedEnum,
};

// ============================================================================
// Test Components - Tagged Unions
// ============================================================================

const Action = union(enum) {
    idle: void,
    move: struct { x: f32, y: f32 },
    attack: struct { target_id: u32, damage: i32 },
    heal: i32,
};

const ActionComponent = struct {
    current_action: Action,
};

// ============================================================================
// Test Components - Nested Structs
// ============================================================================

const Vector2 = struct {
    x: f32,
    y: f32,
};

const Transform = struct {
    position: Vector2,
    rotation: f32,
    scale: Vector2,
};

const DeepNested = struct {
    level1: struct {
        level2: struct {
            level3: struct {
                value: i32,
            },
        },
    },
};

// ============================================================================
// Test Components - Edge Cases
// ============================================================================

const MaxValuesComponent = struct {
    max_i8: i8,
    min_i8: i8,
    max_u8: u8,
    max_i32: i32,
    min_i32: i32,
    max_u32: u32,
};

const UnicodeComponent = struct {
    text: []const u8,
};

// ============================================================================
// UNIT TESTS - Primitive Types
// ============================================================================

test "serialize and deserialize bool values" {
    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{BoolComponent});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e1 = registry1.create();
    registry1.add(e1, BoolComponent{ .flag = true, .enabled = false });

    const e2 = registry1.create();
    registry1.add(e2, BoolComponent{ .flag = false, .enabled = true });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    var view = registry2.view(.{BoolComponent}, .{});
    var count: usize = 0;
    var iter = view.entityIterator();
    while (iter.next()) |_| count += 1;
    try testing.expectEqual(@as(usize, 2), count);
}

test "serialize and deserialize integer types" {
    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{IntegerComponent});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e = registry1.create();
    // Note: JSON uses f64 internally, so we use values within safe integer range
    // (up to 2^53 - 1 for exact representation)
    registry1.add(e, IntegerComponent{
        .i8_val = -128,
        .i16_val = -32768,
        .i32_val = -2147483648,
        .i64_val = -9007199254740991, // -(2^53 - 1), max safe integer
        .u8_val = 255,
        .u16_val = 65535,
        .u32_val = 4294967295,
        .u64_val = 9007199254740991, // 2^53 - 1, max safe integer
    });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    var view = registry2.view(.{IntegerComponent}, .{});
    var iter = view.entityIterator();
    const loaded_e = iter.next() orelse return error.NoEntity;
    const comp = registry2.get(IntegerComponent, loaded_e);

    try testing.expectEqual(@as(i8, -128), comp.i8_val);
    try testing.expectEqual(@as(u8, 255), comp.u8_val);
    try testing.expectEqual(@as(u32, 4294967295), comp.u32_val);
    try testing.expectEqual(@as(i64, -9007199254740991), comp.i64_val);
    try testing.expectEqual(@as(u64, 9007199254740991), comp.u64_val);
}

test "serialize and deserialize float types" {
    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{FloatComponent});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e = registry1.create();
    registry1.add(e, FloatComponent{
        .f32_val = 3.14159,
        .f64_val = 2.718281828459045,
    });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    var view = registry2.view(.{FloatComponent}, .{});
    var iter = view.entityIterator();
    const loaded_e = iter.next() orelse return error.NoEntity;
    const comp = registry2.get(FloatComponent, loaded_e);

    try testing.expectApproxEqAbs(@as(f32, 3.14159), comp.f32_val, 0.0001);
    try testing.expectApproxEqAbs(@as(f64, 2.718281828459045), comp.f64_val, 0.0000001);
}

// ============================================================================
// UNIT TESTS - Arrays
// ============================================================================

test "serialize and deserialize fixed arrays" {
    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{FixedArrayComponent});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e = registry1.create();
    registry1.add(e, FixedArrayComponent{
        .values = .{ 1, 2, 3, 4, 5, 6, 7, 8 },
        .flags = .{ true, false, true, false },
    });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    var view = registry2.view(.{FixedArrayComponent}, .{});
    var iter = view.entityIterator();
    const loaded_e = iter.next() orelse return error.NoEntity;
    const comp = registry2.get(FixedArrayComponent, loaded_e);

    try testing.expectEqual(@as(u32, 1), comp.values[0]);
    try testing.expectEqual(@as(u32, 8), comp.values[7]);
    try testing.expectEqual(true, comp.flags[0]);
    try testing.expectEqual(false, comp.flags[1]);
}

test "serialize and deserialize nested arrays (matrix)" {
    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{NestedArrayComponent});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e = registry1.create();
    registry1.add(e, NestedArrayComponent{
        .matrix = .{
            .{ 1, 2, 3 },
            .{ 4, 5, 6 },
            .{ 7, 8, 9 },
        },
    });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    var view = registry2.view(.{NestedArrayComponent}, .{});
    var iter = view.entityIterator();
    const loaded_e = iter.next() orelse return error.NoEntity;
    const comp = registry2.get(NestedArrayComponent, loaded_e);

    try testing.expectEqual(@as(i32, 1), comp.matrix[0][0]);
    try testing.expectEqual(@as(i32, 5), comp.matrix[1][1]);
    try testing.expectEqual(@as(i32, 9), comp.matrix[2][2]);
}

// ============================================================================
// UNIT TESTS - Optionals
// ============================================================================

test "serialize and deserialize optional primitives - some values" {
    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{OptionalPrimitives});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e = registry1.create();
    registry1.add(e, OptionalPrimitives{
        .maybe_int = 42,
        .maybe_float = 3.14,
        .maybe_bool = true,
    });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    var view = registry2.view(.{OptionalPrimitives}, .{});
    var iter = view.entityIterator();
    const loaded_e = iter.next() orelse return error.NoEntity;
    const comp = registry2.get(OptionalPrimitives, loaded_e);

    try testing.expectEqual(@as(?i32, 42), comp.maybe_int);
    try testing.expect(comp.maybe_float != null);
    try testing.expectEqual(@as(?bool, true), comp.maybe_bool);
}

test "serialize and deserialize optional primitives - null values" {
    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{OptionalPrimitives});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e = registry1.create();
    registry1.add(e, OptionalPrimitives{
        .maybe_int = null,
        .maybe_float = null,
        .maybe_bool = null,
    });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    var view = registry2.view(.{OptionalPrimitives}, .{});
    var iter = view.entityIterator();
    const loaded_e = iter.next() orelse return error.NoEntity;
    const comp = registry2.get(OptionalPrimitives, loaded_e);

    try testing.expectEqual(@as(?i32, null), comp.maybe_int);
    try testing.expectEqual(@as(?f32, null), comp.maybe_float);
    try testing.expectEqual(@as(?bool, null), comp.maybe_bool);
}

// ============================================================================
// UNIT TESTS - Enums
// ============================================================================

test "serialize and deserialize simple enum" {
    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{EnumComponent});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e1 = registry1.create();
    registry1.add(e1, EnumComponent{ .state = .idle });

    const e2 = registry1.create();
    registry1.add(e2, EnumComponent{ .state = .running });

    const e3 = registry1.create();
    registry1.add(e3, EnumComponent{ .state = .jumping });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    // Verify enum names in JSON
    try testing.expect(std.mem.indexOf(u8, json, "\"idle\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"running\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"jumping\"") != null);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    var view = registry2.view(.{EnumComponent}, .{});
    var count: usize = 0;
    var iter = view.entityIterator();
    while (iter.next()) |_| count += 1;
    try testing.expectEqual(@as(usize, 3), count);
}

test "serialize and deserialize numbered enum" {
    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{NumberedEnumComponent});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e = registry1.create();
    registry1.add(e, NumberedEnumComponent{ .value = .max });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    var view = registry2.view(.{NumberedEnumComponent}, .{});
    var iter = view.entityIterator();
    const loaded_e = iter.next() orelse return error.NoEntity;
    const comp = registry2.get(NumberedEnumComponent, loaded_e);

    try testing.expectEqual(NumberedEnum.max, comp.value);
}

// ============================================================================
// UNIT TESTS - Tagged Unions
// ============================================================================

test "serialize and deserialize tagged union - void variant" {
    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{ActionComponent});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e = registry1.create();
    registry1.add(e, ActionComponent{ .current_action = .idle });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    var view = registry2.view(.{ActionComponent}, .{});
    var iter = view.entityIterator();
    const loaded_e = iter.next() orelse return error.NoEntity;
    const comp = registry2.get(ActionComponent, loaded_e);

    try testing.expectEqual(Action.idle, comp.current_action);
}

test "serialize and deserialize tagged union - struct variant" {
    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{ActionComponent});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e = registry1.create();
    registry1.add(e, ActionComponent{
        .current_action = .{ .move = .{ .x = 10.5, .y = 20.5 } },
    });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    var view = registry2.view(.{ActionComponent}, .{});
    var iter = view.entityIterator();
    const loaded_e = iter.next() orelse return error.NoEntity;
    const comp = registry2.get(ActionComponent, loaded_e);

    switch (comp.current_action) {
        .move => |m| {
            try testing.expectApproxEqAbs(@as(f32, 10.5), m.x, 0.001);
            try testing.expectApproxEqAbs(@as(f32, 20.5), m.y, 0.001);
        },
        else => return error.WrongVariant,
    }
}

test "serialize and deserialize tagged union - primitive variant" {
    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{ActionComponent});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e = registry1.create();
    registry1.add(e, ActionComponent{ .current_action = .{ .heal = 50 } });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    var view = registry2.view(.{ActionComponent}, .{});
    var iter = view.entityIterator();
    const loaded_e = iter.next() orelse return error.NoEntity;
    const comp = registry2.get(ActionComponent, loaded_e);

    switch (comp.current_action) {
        .heal => |amount| try testing.expectEqual(@as(i32, 50), amount),
        else => return error.WrongVariant,
    }
}

// ============================================================================
// UNIT TESTS - Nested Structs
// ============================================================================

test "serialize and deserialize nested struct" {
    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{Transform});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e = registry1.create();
    registry1.add(e, Transform{
        .position = .{ .x = 100, .y = 200 },
        .rotation = 1.57,
        .scale = .{ .x = 2.0, .y = 2.0 },
    });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    var view = registry2.view(.{Transform}, .{});
    var iter = view.entityIterator();
    const loaded_e = iter.next() orelse return error.NoEntity;
    const comp = registry2.get(Transform, loaded_e);

    try testing.expectApproxEqAbs(@as(f32, 100), comp.position.x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 200), comp.position.y, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 1.57), comp.rotation, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 2.0), comp.scale.x, 0.001);
}

test "serialize and deserialize deeply nested struct" {
    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{DeepNested});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e = registry1.create();
    registry1.add(e, DeepNested{
        .level1 = .{
            .level2 = .{
                .level3 = .{
                    .value = 42,
                },
            },
        },
    });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    var view = registry2.view(.{DeepNested}, .{});
    var iter = view.entityIterator();
    const loaded_e = iter.next() orelse return error.NoEntity;
    const comp = registry2.get(DeepNested, loaded_e);

    try testing.expectEqual(@as(i32, 42), comp.level1.level2.level3.value);
}

// ============================================================================
// EDGE CASE TESTS
// ============================================================================

test "serialize and deserialize max/min integer values" {
    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{MaxValuesComponent});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e = registry1.create();
    registry1.add(e, MaxValuesComponent{
        .max_i8 = 127,
        .min_i8 = -128,
        .max_u8 = 255,
        .max_i32 = 2147483647,
        .min_i32 = -2147483648,
        .max_u32 = 4294967295,
    });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    var view = registry2.view(.{MaxValuesComponent}, .{});
    var iter = view.entityIterator();
    const loaded_e = iter.next() orelse return error.NoEntity;
    const comp = registry2.get(MaxValuesComponent, loaded_e);

    try testing.expectEqual(@as(i8, 127), comp.max_i8);
    try testing.expectEqual(@as(i8, -128), comp.min_i8);
    try testing.expectEqual(@as(u8, 255), comp.max_u8);
    try testing.expectEqual(@as(i32, 2147483647), comp.max_i32);
    try testing.expectEqual(@as(i32, -2147483648), comp.min_i32);
    try testing.expectEqual(@as(u32, 4294967295), comp.max_u32);
}

test "serialize and deserialize unicode strings" {
    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{UnicodeComponent});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e = registry1.create();
    registry1.add(e, UnicodeComponent{ .text = "Hello 世界 🎮 émoji" });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    var view = registry2.view(.{UnicodeComponent}, .{});
    var iter = view.entityIterator();
    const loaded_e = iter.next() orelse return error.NoEntity;
    const comp = registry2.get(UnicodeComponent, loaded_e);

    try testing.expectEqualStrings("Hello 世界 🎮 émoji", comp.text);

    // Free allocated string memory (deserialized strings are heap-allocated)
    allocator.free(comp.text);
}

test "serialize and deserialize empty string" {
    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{UnicodeComponent});

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e = registry1.create();
    registry1.add(e, UnicodeComponent{ .text = "" });

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    var view = registry2.view(.{UnicodeComponent}, .{});
    var iter = view.entityIterator();
    const loaded_e = iter.next() orelse return error.NoEntity;
    const comp = registry2.get(UnicodeComponent, loaded_e);

    try testing.expectEqualStrings("", comp.text);

    // Free allocated string memory (deserialized strings are heap-allocated)
    allocator.free(comp.text);
}

test "serialize and deserialize registry with only tags" {
    const Tag1 = struct {};
    const Tag2 = struct {};
    const Tag3 = struct {};

    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{ Tag1, Tag2, Tag3 });

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const e1 = registry1.create();
    registry1.add(e1, Tag1{});
    registry1.add(e1, Tag2{});

    const e2 = registry1.create();
    registry1.add(e2, Tag2{});
    registry1.add(e2, Tag3{});

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    // Verify tag counts
    var tag1_view = registry2.view(.{Tag1}, .{});
    var tag1_count: usize = 0;
    var tag1_iter = tag1_view.entityIterator();
    while (tag1_iter.next()) |_| tag1_count += 1;

    var tag2_view = registry2.view(.{Tag2}, .{});
    var tag2_count: usize = 0;
    var tag2_iter = tag2_view.entityIterator();
    while (tag2_iter.next()) |_| tag2_count += 1;

    try testing.expectEqual(@as(usize, 1), tag1_count);
    try testing.expectEqual(@as(usize, 2), tag2_count);
}

// ============================================================================
// INTEGRATION TESTS - Large Entity Counts
// ============================================================================

test "serialize and deserialize 1000+ entities" {
    const Position = struct { x: f32, y: f32 };
    const Velocity = struct { dx: f32, dy: f32 };

    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{ Position, Velocity });

    var registry1 = ecs.Registry.init(allocator);
    defer registry1.deinit();

    const entity_count = 1000;
    for (0..entity_count) |i| {
        const e = registry1.create();
        registry1.add(e, Position{
            .x = @floatFromInt(i),
            .y = @floatFromInt(i * 2),
        });
        if (i % 3 == 0) {
            registry1.add(e, Velocity{
                .dx = @floatFromInt(i % 10),
                .dy = @floatFromInt(i % 5),
            });
        }
    }

    var ser = TestSerializer.init(allocator, .{ .pretty_print = false });
    defer ser.deinit();

    const json = try ser.serialize(&registry1);
    defer allocator.free(json);

    var registry2 = ecs.Registry.init(allocator);
    defer registry2.deinit();

    try ser.deserialize(&registry2, json);

    // Verify counts
    var pos_view = registry2.view(.{Position}, .{});
    var pos_count: usize = 0;
    var pos_iter = pos_view.entityIterator();
    while (pos_iter.next()) |_| pos_count += 1;

    var vel_view = registry2.view(.{Velocity}, .{});
    var vel_count: usize = 0;
    var vel_iter = vel_view.entityIterator();
    while (vel_iter.next()) |_| vel_count += 1;

    try testing.expectEqual(@as(usize, entity_count), pos_count);
    try testing.expectEqual(@as(usize, 334), vel_count); // 1000/3 + 1
}

// ============================================================================
// ERROR HANDLING TESTS
// ============================================================================

test "deserialize rejects invalid JSON" {
    const Position = struct { x: f32, y: f32 };

    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{Position});

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const invalid_json = "{ not valid json }}}";
    const result = ser.deserialize(&registry, invalid_json);
    try testing.expectError(error.SyntaxError, result);
}

test "deserialize rejects non-object root" {
    const Position = struct { x: f32, y: f32 };

    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{Position});

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const array_json = "[1, 2, 3]";
    const result = ser.deserialize(&registry, array_json);
    try testing.expectError(error.InvalidSaveFormat, result);
}

test "deserialize rejects missing components section" {
    const Position = struct { x: f32, y: f32 };

    const allocator = testing.allocator;
    const TestSerializer = Serializer(&[_]type{Position});

    var ser = TestSerializer.init(allocator, .{});
    defer ser.deinit();

    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    const no_components =
        \\{"meta": {"version": 1}}
    ;
    const result = ser.deserialize(&registry, no_components);
    try testing.expectError(error.InvalidSaveFormat, result);
}

const NoEntity = error.NoEntity;
const WrongVariant = error.WrongVariant;
