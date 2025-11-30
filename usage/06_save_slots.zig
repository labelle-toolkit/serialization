//! Save Slots Example
//!
//! Demonstrates using SaveSlotManager for managing multiple save files
//! like traditional game save systems.

const std = @import("std");
const serialization = @import("serialization");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Save Slot Management Example ===\n\n", .{});

    // Create a save slot manager with custom configuration
    const Manager = serialization.SaveSlotManager(.{
        .save_dir = "game_saves",
        .max_slots = 5,
        .auto_save_slots = 3,
        .extension = ".sav",
        .slot_prefix = "save_",
        .auto_prefix = "autosave_",
    });

    var manager = Manager.init(allocator);
    defer manager.deinit();

    // Show configuration
    const config = Manager.getConfig();
    std.debug.print("Save Configuration:\n", .{});
    std.debug.print("  Directory: {s}\n", .{config.save_dir});
    std.debug.print("  Max slots: {d}\n", .{config.max_slots});
    std.debug.print("  Auto-save slots: {d}\n", .{config.auto_save_slots});
    std.debug.print("  Extension: {s}\n\n", .{config.extension});

    // Generate slot paths
    std.debug.print("Slot Paths:\n", .{});
    for (0..3) |i| {
        const path = try manager.getSlotPath(@intCast(i));
        defer allocator.free(path);
        std.debug.print("  Slot {d}: {s}\n", .{ i, path });
    }

    // Generate auto-save paths (rotating)
    std.debug.print("\nAuto-save Paths (rotating):\n", .{});
    for (0..5) |i| {
        const path = try manager.getNextAutoSavePath();
        defer allocator.free(path);
        std.debug.print("  Auto-save {d}: {s}\n", .{ i, path });
    }

    // In a real game, you would use the manager like this:
    std.debug.print("\n=== Usage Pattern ===\n\n", .{});
    std.debug.print(
        \\// Ensure save directory exists
        \\try manager.ensureSaveDir();
        \\
        \\// Save to a specific slot
        \\const path = try manager.getSlotPath(0);
        \\defer allocator.free(path);
        \\const json = try serializer.serialize(&registry);
        \\try std.fs.cwd().writeFile(path, json);
        \\
        \\// Auto-save (uses rotating slots)
        \\const auto_path = try manager.getNextAutoSavePath();
        \\defer allocator.free(auto_path);
        \\try std.fs.cwd().writeFile(auto_path, json);
        \\
        \\// Find next available slot
        \\if (try manager.findNextAvailableSlot()) |slot| {{
        \\    std.debug.print("Next available: slot {{d}}\n", .{{slot}});
        \\}}
        \\
        \\// Delete a save
        \\try manager.deleteSlot(0);
        \\
        \\// Copy a save to another slot
        \\try manager.copySlot(1, 2);
        \\
    , .{});
}
