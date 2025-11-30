//! Tests for debug and inspection tools

const std = @import("std");
const testing = std.testing;
const serialization = @import("serialization");
const debug = serialization.debug;

const sample_save =
    \\{
    \\  "meta": {
    \\    "version": 1,
    \\    "game_name": "TestGame",
    \\    "timestamp": 1700000000
    \\  },
    \\  "components": {
    \\    "Position": [
    \\      {"entt": 1, "data": {"x": 10, "y": 20}},
    \\      {"entt": 2, "data": {"x": 30, "y": 40}}
    \\    ],
    \\    "Health": [
    \\      {"entt": 1, "data": {"current": 100, "max": 100}}
    \\    ],
    \\    "Player": [1]
    \\  }
    \\}
;

const sample_save2 =
    \\{
    \\  "meta": {
    \\    "version": 1,
    \\    "game_name": "TestGame"
    \\  },
    \\  "components": {
    \\    "Position": [
    \\      {"entt": 1, "data": {"x": 100, "y": 200}},
    \\      {"entt": 3, "data": {"x": 50, "y": 60}}
    \\    ],
    \\    "Velocity": [
    \\      {"entt": 3, "data": {"vx": 1, "vy": 2}}
    \\    ],
    \\    "Player": [1]
    \\  }
    \\}
;

test "getStats returns correct entity count" {
    const stats = try debug.getStats(testing.allocator, sample_save);
    defer @constCast(&stats).deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 2), stats.entity_count); // entities 1 and 2
}

test "getStats returns correct component type count" {
    const stats = try debug.getStats(testing.allocator, sample_save);
    defer @constCast(&stats).deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 3), stats.component_types); // Position, Health, Player
}

test "getStats returns correct component instance count" {
    const stats = try debug.getStats(testing.allocator, sample_save);
    defer @constCast(&stats).deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 4), stats.component_instances); // 2 Position + 1 Health + 1 Player
}

test "getStats parses metadata" {
    const stats = try debug.getStats(testing.allocator, sample_save);
    defer @constCast(&stats).deinit(testing.allocator);

    try testing.expectEqual(@as(?u32, 1), stats.version);
    try testing.expectEqualStrings("TestGame", stats.game_name.?);
    try testing.expectEqual(@as(?i64, 1700000000), stats.timestamp);
}

test "getStats reports file size" {
    const stats = try debug.getStats(testing.allocator, sample_save);
    defer @constCast(&stats).deinit(testing.allocator);

    try testing.expectEqual(sample_save.len, stats.file_size);
}

test "getStats reports per-component breakdown" {
    const stats = try debug.getStats(testing.allocator, sample_save);
    defer @constCast(&stats).deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 3), stats.components.len);

    // Find each component type and verify counts
    var found_position = false;
    var found_health = false;
    var found_player = false;

    for (stats.components) |comp| {
        if (std.mem.eql(u8, comp.name, "Position")) {
            try testing.expectEqual(@as(usize, 2), comp.instance_count);
            found_position = true;
        } else if (std.mem.eql(u8, comp.name, "Health")) {
            try testing.expectEqual(@as(usize, 1), comp.instance_count);
            found_health = true;
        } else if (std.mem.eql(u8, comp.name, "Player")) {
            try testing.expectEqual(@as(usize, 1), comp.instance_count);
            found_player = true;
        }
    }

    try testing.expect(found_position);
    try testing.expect(found_health);
    try testing.expect(found_player);
}

test "prettyPrint produces valid JSON" {
    const pretty = try debug.prettyPrint(testing.allocator, sample_save);
    defer testing.allocator.free(pretty);

    // Should be able to parse the pretty-printed output
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, pretty, .{});
    defer parsed.deinit();

    // Verify it's an object with expected keys
    try testing.expect(parsed.value == .object);
    try testing.expect(parsed.value.object.contains("meta"));
    try testing.expect(parsed.value.object.contains("components"));
}

test "prettyPrint adds indentation" {
    const compact =
        \\{"meta":{"version":1},"components":{}}
    ;

    const pretty = try debug.prettyPrint(testing.allocator, compact);
    defer testing.allocator.free(pretty);

    // Pretty print should be longer due to whitespace
    try testing.expect(pretty.len > compact.len);

    // Should contain newlines
    try testing.expect(std.mem.indexOf(u8, pretty, "\n") != null);
}

test "diffSaves detects added entities" {
    var diff = try debug.diffSaves(testing.allocator, sample_save, sample_save2);
    defer diff.deinit();

    // Entity 3 is in save2 but not save1
    try testing.expectEqual(@as(usize, 1), diff.added_entities.len);
    try testing.expectEqual(@as(u32, 3), diff.added_entities[0]);
}

test "diffSaves detects removed entities" {
    var diff = try debug.diffSaves(testing.allocator, sample_save, sample_save2);
    defer diff.deinit();

    // Entity 2 is in save1 but not save2
    try testing.expectEqual(@as(usize, 1), diff.removed_entities.len);
    try testing.expectEqual(@as(u32, 2), diff.removed_entities[0]);
}

test "diffSaves detects added component types" {
    var diff = try debug.diffSaves(testing.allocator, sample_save, sample_save2);
    defer diff.deinit();

    // Velocity is in save2 but not save1
    try testing.expectEqual(@as(usize, 1), diff.added_components.len);
    try testing.expectEqualStrings("Velocity", diff.added_components[0]);
}

test "diffSaves detects removed component types" {
    var diff = try debug.diffSaves(testing.allocator, sample_save, sample_save2);
    defer diff.deinit();

    // Health is in save1 but not save2
    try testing.expectEqual(@as(usize, 1), diff.removed_components.len);
    try testing.expectEqualStrings("Health", diff.removed_components[0]);
}

test "diffSaves with identical saves shows no differences" {
    var diff = try debug.diffSaves(testing.allocator, sample_save, sample_save);
    defer diff.deinit();

    try testing.expectEqual(@as(usize, 0), diff.added_entities.len);
    try testing.expectEqual(@as(usize, 0), diff.removed_entities.len);
    try testing.expectEqual(@as(usize, 0), diff.added_components.len);
    try testing.expectEqual(@as(usize, 0), diff.removed_components.len);
}

test "formatStats produces readable output" {
    const stats = try debug.getStats(testing.allocator, sample_save);
    defer @constCast(&stats).deinit(testing.allocator);

    var output: std.ArrayListUnmanaged(u8) = .{};
    defer output.deinit(testing.allocator);

    try debug.formatStats(stats, output.writer(testing.allocator));

    const result = output.items;

    // Should contain key information
    try testing.expect(std.mem.indexOf(u8, result, "Version: 1") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Game: TestGame") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Entities: 2") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Component types: 3") != null);
}

test "formatDiff produces readable output" {
    var diff = try debug.diffSaves(testing.allocator, sample_save, sample_save2);
    defer diff.deinit();

    var output: std.ArrayListUnmanaged(u8) = .{};
    defer output.deinit(testing.allocator);

    try debug.formatDiff(diff, output.writer(testing.allocator));

    const result = output.items;

    // Should contain diff markers
    try testing.expect(std.mem.indexOf(u8, result, "+ 3") != null); // Added entity 3
    try testing.expect(std.mem.indexOf(u8, result, "- 2") != null); // Removed entity 2
    try testing.expect(std.mem.indexOf(u8, result, "+ Velocity") != null); // Added component type
    try testing.expect(std.mem.indexOf(u8, result, "- Health") != null); // Removed component type
}

test "getStats handles missing metadata gracefully" {
    const minimal_save =
        \\{"components": {"Tag": [1, 2, 3]}}
    ;

    const stats = try debug.getStats(testing.allocator, minimal_save);
    defer @constCast(&stats).deinit(testing.allocator);

    try testing.expectEqual(@as(?u32, null), stats.version);
    try testing.expectEqual(@as(?[]const u8, null), stats.game_name);
    try testing.expectEqual(@as(?i64, null), stats.timestamp);
    try testing.expectEqual(@as(usize, 3), stats.entity_count);
}

test "getStats returns error for invalid JSON" {
    const invalid = "not valid json";
    const result = debug.getStats(testing.allocator, invalid);
    try testing.expectError(error.SyntaxError, result);
}

test "getStats returns error for non-object root" {
    const array_root = "[1, 2, 3]";
    const result = debug.getStats(testing.allocator, array_root);
    try testing.expectError(error.InvalidSaveFormat, result);
}

test "getStats returns error for missing components section" {
    const no_components =
        \\{"meta": {"version": 1}}
    ;
    const result = debug.getStats(testing.allocator, no_components);
    try testing.expectError(error.InvalidSaveFormat, result);
}
