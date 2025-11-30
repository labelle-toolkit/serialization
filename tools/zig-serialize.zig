//! zig-serialize CLI tool
//!
//! Command-line tool for working with serialization save files.
//!
//! Usage:
//!   zig-serialize pretty <file>              Pretty-print a save file
//!   zig-serialize stats <file>               Show save file statistics
//!   zig-serialize validate <file>            Validate a save file
//!   zig-serialize diff <file1> <file2>       Compare two save files
//!   zig-serialize extract <file> --entity N  Extract entity data

const std = @import("std");
const serialization = @import("serialization");
const debug = serialization.debug;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "pretty")) {
        try cmdPretty(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "stats")) {
        try cmdStats(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "validate")) {
        try cmdValidate(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "diff")) {
        try cmdDiff(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "extract")) {
        try cmdExtract(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        printUsage();
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        printUsage();
    }
}

fn printUsage() void {
    const usage =
        \\zig-serialize - Save file inspection tool
        \\
        \\Usage:
        \\  zig-serialize <command> [options]
        \\
        \\Commands:
        \\  pretty <file>              Pretty-print a save file
        \\  stats <file>               Show save file statistics
        \\  validate <file>            Validate a save file structure
        \\  diff <file1> <file2>       Compare two save files
        \\  extract <file> --entity N  Extract entity data (JSON)
        \\  help                       Show this help message
        \\
        \\Examples:
        \\  zig-serialize pretty save.json
        \\  zig-serialize stats save.json
        \\  zig-serialize validate save.json
        \\  zig-serialize diff save1.json save2.json
        \\
    ;
    std.debug.print("{s}", .{usage});
}

fn cmdPretty(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Error: pretty requires a file argument\n", .{});
        return;
    }

    const json = try readFile(allocator, args[0]);
    defer allocator.free(json);

    const pretty = try debug.prettyPrint(allocator, json);
    defer allocator.free(pretty);

    std.debug.print("{s}\n", .{pretty});
}

fn cmdStats(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Error: stats requires a file argument\n", .{});
        return;
    }

    const json = try readFile(allocator, args[0]);
    defer allocator.free(json);

    var stats = try debug.getStats(allocator, json);
    defer stats.deinit(allocator);

    // Print stats manually
    std.debug.print("Save File Statistics\n", .{});
    std.debug.print("====================\n", .{});
    if (stats.version) |v| {
        std.debug.print("Version: {d}\n", .{v});
    }
    if (stats.game_name) |name| {
        std.debug.print("Game: {s}\n", .{name});
    }
    std.debug.print("File size: {d} bytes\n", .{stats.file_size});
    std.debug.print("Entities: {d}\n", .{stats.entity_count});
    std.debug.print("Component types: {d}\n", .{stats.component_types});
    std.debug.print("Component instances: {d}\n", .{stats.component_instances});
    std.debug.print("\nComponents:\n", .{});
    for (stats.components) |comp| {
        std.debug.print("  {s}: {d} instances\n", .{ comp.name, comp.instance_count });
    }
}

fn cmdValidate(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Error: validate requires a file argument\n", .{});
        return;
    }

    const json = try readFile(allocator, args[0]);
    defer allocator.free(json);

    const result = try serialization.validateSave(allocator, json, 999); // Accept any version

    switch (result) {
        .valid => std.debug.print("Valid save file\n", .{}),
        .checksum_mismatch => |info| std.debug.print("Checksum mismatch: expected {d}, got {d}\n", .{ info.expected, info.actual }),
        .invalid_structure => |msg| std.debug.print("Invalid structure: {s}\n", .{msg}),
        .version_mismatch => |info| std.debug.print("Version mismatch: save v{d}, max supported v{d}\n", .{ info.save_version, info.max_supported }),
        .missing_metadata => std.debug.print("Missing metadata section\n", .{}),
    }
}

fn cmdDiff(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        std.debug.print("Error: diff requires two file arguments\n", .{});
        return;
    }

    const json1 = try readFile(allocator, args[0]);
    defer allocator.free(json1);

    const json2 = try readFile(allocator, args[1]);
    defer allocator.free(json2);

    var diff_result = try debug.diffSaves(allocator, json1, json2);
    defer diff_result.deinit();

    // Print diff manually
    std.debug.print("Save File Diff\n", .{});
    std.debug.print("==============\n", .{});

    if (diff_result.added_entities.len > 0) {
        std.debug.print("\nAdded entities ({d}):\n", .{diff_result.added_entities.len});
        for (diff_result.added_entities) |id| {
            std.debug.print("  + {d}\n", .{id});
        }
    }

    if (diff_result.removed_entities.len > 0) {
        std.debug.print("\nRemoved entities ({d}):\n", .{diff_result.removed_entities.len});
        for (diff_result.removed_entities) |id| {
            std.debug.print("  - {d}\n", .{id});
        }
    }

    if (diff_result.added_components.len > 0) {
        std.debug.print("\nAdded component types:\n", .{});
        for (diff_result.added_components) |name| {
            std.debug.print("  + {s}\n", .{name});
        }
    }

    if (diff_result.removed_components.len > 0) {
        std.debug.print("\nRemoved component types:\n", .{});
        for (diff_result.removed_components) |name| {
            std.debug.print("  - {s}\n", .{name});
        }
    }

    if (diff_result.added_entities.len == 0 and diff_result.removed_entities.len == 0 and
        diff_result.added_components.len == 0 and diff_result.removed_components.len == 0)
    {
        std.debug.print("\nNo differences found.\n", .{});
    }
}

fn cmdExtract(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Error: extract requires a file argument\n", .{});
        return;
    }

    var entity_id: ?u32 = null;
    var file_path: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--entity") or std.mem.eql(u8, args[i], "-e")) {
            if (i + 1 < args.len) {
                entity_id = std.fmt.parseInt(u32, args[i + 1], 10) catch {
                    std.debug.print("Error: invalid entity ID\n", .{});
                    return;
                };
                i += 1;
            }
        } else if (file_path == null) {
            file_path = args[i];
        }
    }

    if (file_path == null) {
        std.debug.print("Error: no file specified\n", .{});
        return;
    }

    if (entity_id == null) {
        std.debug.print("Error: --entity <id> required\n", .{});
        return;
    }

    const json = try readFile(allocator, file_path.?);
    defer allocator.free(json);

    // Parse and find entity
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) {
        std.debug.print("Error: invalid save format\n", .{});
        return;
    }

    const components = root.object.get("components") orelse {
        std.debug.print("Error: no components section\n", .{});
        return;
    };

    std.debug.print("Entity {d}:\n", .{entity_id.?});

    // Search for entity in all component types
    var comp_iter = components.object.iterator();
    while (comp_iter.next()) |entry| {
        const comp_name = entry.key_ptr.*;
        const comp_data = entry.value_ptr.*;

        if (comp_data != .array) continue;

        for (comp_data.array.items) |item| {
            const eid = getEntityId(item) catch continue;
            if (eid == entity_id.?) {
                std.debug.print("  {s}: ", .{comp_name});
                if (item == .integer) {
                    std.debug.print("(tag)\n", .{});
                } else if (item == .object) {
                    if (item.object.get("data")) |data| {
                        var out: std.io.Writer.Allocating = .init(allocator);
                        defer out.deinit();
                        var write_stream: std.json.Stringify = .{
                            .writer = &out.writer,
                            .options = .{ .whitespace = .indent_2 },
                        };
                        try write_stream.write(data);
                        const result = try out.toOwnedSlice();
                        defer allocator.free(result);
                        std.debug.print("{s}\n", .{result});
                    }
                }
            }
        }
    }
}

fn getEntityId(item: std.json.Value) !u32 {
    if (item == .integer) {
        return @intCast(item.integer);
    }
    if (item == .object) {
        const entt = item.object.get("entt") orelse return error.InvalidFormat;
        if (entt == .integer) {
            return @intCast(entt.integer);
        }
    }
    return error.InvalidFormat;
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.debug.print("Error opening file '{s}': {}\n", .{ path, err });
        return err;
    };
    defer file.close();

    return file.readToEndAlloc(allocator, 100 * 1024 * 1024) catch |err| {
        std.debug.print("Error reading file: {}\n", .{err});
        return err;
    };
}
