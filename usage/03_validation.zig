//! Save Validation Example
//!
//! Demonstrates validating save files before loading to detect:
//! - Corrupted save files
//! - Save files from newer game versions
//! - Missing required data

const std = @import("std");
const ecs = @import("ecs");
const serialization = @import("serialization");

const Position = struct { x: f32, y: f32 };
const Health = struct { current: u8, max: u8 };

const GameSerializer = serialization.Serializer(&[_]type{ Position, Health });

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Save Validation Example ===\n\n", .{});

    // Current game version
    const current_version: u32 = 2;

    // Test various save file scenarios
    const test_cases = [_]struct { name: []const u8, json: []const u8 }{
        .{
            .name = "Valid save (v2)",
            .json =
            \\{
            \\  "meta": { "version": 2 },
            \\  "components": { "Position": [], "Health": [] }
            \\}
            ,
        },
        .{
            .name = "Future version (v99)",
            .json =
            \\{
            \\  "meta": { "version": 99 },
            \\  "components": {}
            \\}
            ,
        },
        .{
            .name = "Missing metadata",
            .json =
            \\{
            \\  "components": {}
            \\}
            ,
        },
        .{
            .name = "Invalid JSON",
            .json = "{ not valid json }",
        },
        .{
            .name = "Missing components section",
            .json =
            \\{
            \\  "meta": { "version": 1 }
            \\}
            ,
        },
    };

    for (test_cases) |tc| {
        std.debug.print("Testing: {s}\n", .{tc.name});

        const result = try serialization.validateSave(allocator, tc.json, current_version);

        switch (result) {
            .valid => std.debug.print("  Result: VALID\n\n", .{}),
            .version_mismatch => |v| std.debug.print(
                "  Result: VERSION MISMATCH (save: v{d}, max supported: v{d})\n\n",
                .{ v.save_version, v.max_supported },
            ),
            .missing_metadata => std.debug.print("  Result: MISSING METADATA\n\n", .{}),
            .invalid_structure => |msg| std.debug.print("  Result: INVALID ({s})\n\n", .{msg}),
            .checksum_mismatch => |c| std.debug.print(
                "  Result: CHECKSUM MISMATCH (expected: {x}, actual: {x})\n\n",
                .{ c.expected, c.actual },
            ),
        }
    }

    // Example of safe loading pattern
    std.debug.print("=== Safe Load Pattern ===\n\n", .{});

    const save_json =
        \\{
        \\  "meta": { "version": 2 },
        \\  "components": {
        \\    "Position": [{ "entt": 1, "data": { "x": 100, "y": 200 } }],
        \\    "Health": [{ "entt": 1, "data": { "current": 75, "max": 100 } }]
        \\  }
        \\}
    ;

    // Always validate before loading
    const validation = try serialization.validateSave(allocator, save_json, current_version);

    if (validation == .valid) {
        std.debug.print("Save file validated successfully. Loading...\n", .{});

        var registry = ecs.Registry.init(allocator);
        defer registry.deinit();

        var ser = GameSerializer.init(allocator, .{ .version = current_version });
        defer ser.deinit();

        try ser.deserialize(&registry, save_json);
        std.debug.print("Load complete!\n", .{});
    } else {
        std.debug.print("Save file validation failed. Cannot load.\n", .{});
    }
}
