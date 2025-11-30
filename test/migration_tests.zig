//! Tests for version migration system

const std = @import("std");
const serialization = @import("serialization");
const MigrationContext = serialization.MigrationContext;
const MigrationRegistry = serialization.MigrationRegistry;

test "MigrationContext rename component" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "meta": { "version": 1 },
        \\  "components": {
        \\    "HP": [{ "entt": 1, "data": { "value": 100 } }]
        \\  }
        \\}
    ;

    var ctx = try MigrationContext.init(allocator, json);
    defer ctx.deinit();

    try ctx.renameComponent("HP", "Health");

    const components = ctx.getComponents().?;
    try std.testing.expect(components.get("Health") != null);
    try std.testing.expect(components.get("HP") == null);
}

test "MigrationContext add field default" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "meta": { "version": 1 },
        \\  "components": {
        \\    "Health": [{ "entt": 1, "data": { "current": 80 } }]
        \\  }
        \\}
    ;

    var ctx = try MigrationContext.init(allocator, json);
    defer ctx.deinit();

    try ctx.addFieldDefault("Health", "max", .{ .integer = 100 });

    const result = try ctx.toJson();
    defer allocator.free(result);

    // Verify the max field was added
    try std.testing.expect(std.mem.indexOf(u8, result, "\"max\"") != null);
}

test "MigrationContext rename field" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "meta": { "version": 1 },
        \\  "components": {
        \\    "Position": [{ "entt": 1, "data": { "posX": 10, "posY": 20 } }]
        \\  }
        \\}
    ;

    var ctx = try MigrationContext.init(allocator, json);
    defer ctx.deinit();

    try ctx.renameField("Position", "posX", "x");
    try ctx.renameField("Position", "posY", "y");

    const result = try ctx.toJson();
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"x\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"y\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"posX\"") == null);
}

test "MigrationRegistry chains migrations" {
    const allocator = std.testing.allocator;

    var registry = MigrationRegistry(10){};

    // Register v1 -> v2: rename HP to Health
    registry.register(1, 2, struct {
        fn migrate(ctx: *MigrationContext) !void {
            try ctx.renameComponent("HP", "Health");
        }
    }.migrate);

    // Register v2 -> v3: add max field
    registry.register(2, 3, struct {
        fn migrate(ctx: *MigrationContext) !void {
            try ctx.addFieldDefault("Health", "max", .{ .integer = 100 });
        }
    }.migrate);

    const json =
        \\{
        \\  "meta": { "version": 1 },
        \\  "components": {
        \\    "HP": [{ "entt": 1, "data": { "current": 80 } }]
        \\  }
        \\}
    ;

    var result = try registry.migrate(allocator, json, 3);
    defer result.deinit();

    try std.testing.expectEqual(@as(u32, 2), result.migrations_run);
    try std.testing.expect(std.mem.indexOf(u8, result.json, "\"Health\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.json, "\"max\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.json, "\"version\": 3") != null);
}

test "MigrationContext remove component" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "meta": { "version": 1 },
        \\  "components": {
        \\    "Position": [{ "entt": 1, "data": { "x": 10 } }],
        \\    "DebugInfo": [{ "entt": 1, "data": { "info": "test" } }]
        \\  }
        \\}
    ;

    var ctx = try MigrationContext.init(allocator, json);
    defer ctx.deinit();

    try ctx.removeComponent("DebugInfo");

    const components = ctx.getComponents().?;
    try std.testing.expect(components.get("Position") != null);
    try std.testing.expect(components.get("DebugInfo") == null);
}
