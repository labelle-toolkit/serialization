//! Tests for save slot management

const std = @import("std");
const serialization = @import("serialization");
const SaveSlotManager = serialization.SaveSlotManager;

test "SaveSlotManager path generation" {
    const allocator = std.testing.allocator;

    const Manager = SaveSlotManager(.{
        .save_dir = "test_saves",
        .max_slots = 5,
    });

    var manager = Manager.init(allocator);
    defer manager.deinit();

    const path0 = try manager.getSlotPath(0);
    defer allocator.free(path0);
    try std.testing.expectEqualStrings("test_saves/slot_00.json", path0);

    const path9 = try manager.getSlotPath(9);
    defer allocator.free(path9);
    try std.testing.expectEqualStrings("test_saves/slot_09.json", path9);

    const auto_path = try manager.getAutoSavePath(0);
    defer allocator.free(auto_path);
    try std.testing.expectEqualStrings("test_saves/auto_00.json", auto_path);
}

test "SaveSlotManager auto-save rotation" {
    const allocator = std.testing.allocator;

    const Manager = SaveSlotManager(.{
        .save_dir = "saves",
        .auto_save_slots = 3,
    });

    var manager = Manager.init(allocator);
    defer manager.deinit();

    // First auto-save goes to slot 0
    const path0 = try manager.getNextAutoSavePath();
    defer allocator.free(path0);
    try std.testing.expectEqualStrings("saves/auto_00.json", path0);

    // Second goes to slot 1
    const path1 = try manager.getNextAutoSavePath();
    defer allocator.free(path1);
    try std.testing.expectEqualStrings("saves/auto_01.json", path1);

    // Third goes to slot 2
    const path2 = try manager.getNextAutoSavePath();
    defer allocator.free(path2);
    try std.testing.expectEqualStrings("saves/auto_02.json", path2);

    // Fourth wraps back to slot 0
    const path3 = try manager.getNextAutoSavePath();
    defer allocator.free(path3);
    try std.testing.expectEqualStrings("saves/auto_00.json", path3);
}
