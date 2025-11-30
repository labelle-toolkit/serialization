//! Save slot management for game saves
//!
//! Provides high-level API for managing multiple save slots,
//! similar to traditional game save systems.

const std = @import("std");

/// Save slot information
pub const SlotInfo = struct {
    /// Slot index (0-based)
    index: u32,
    /// File path
    path: []const u8,
    /// Whether this slot has save data
    exists: bool,
    /// File size in bytes (0 if doesn't exist)
    size: u64,
    /// Last modified timestamp (0 if doesn't exist)
    modified: i128,
};

/// Save slot manager configuration
pub const SaveSlotConfig = struct {
    /// Directory for save files
    save_dir: []const u8 = "saves",
    /// Maximum number of slots
    max_slots: u32 = 10,
    /// Number of auto-save slots (rotating)
    auto_save_slots: u32 = 3,
    /// File extension for save files
    extension: []const u8 = ".json",
    /// Prefix for regular saves
    slot_prefix: []const u8 = "slot_",
    /// Prefix for auto-saves
    auto_prefix: []const u8 = "auto_",
};

/// Manager for save slots
pub fn SaveSlotManager(comptime config: SaveSlotConfig) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        current_auto_slot: u32 = 0,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        /// Get the file path for a save slot
        pub fn getSlotPath(self: *Self, slot: u32) ![]u8 {
            return std.fmt.allocPrint(
                self.allocator,
                "{s}/{s}{d:0>2}{s}",
                .{ config.save_dir, config.slot_prefix, slot, config.extension },
            );
        }

        /// Get the file path for an auto-save slot
        pub fn getAutoSavePath(self: *Self, slot: u32) ![]u8 {
            return std.fmt.allocPrint(
                self.allocator,
                "{s}/{s}{d:0>2}{s}",
                .{ config.save_dir, config.auto_prefix, slot, config.extension },
            );
        }

        /// Get the path for the next auto-save (rotating)
        pub fn getNextAutoSavePath(self: *Self) ![]u8 {
            const path = try self.getAutoSavePath(self.current_auto_slot);
            self.current_auto_slot = (self.current_auto_slot + 1) % config.auto_save_slots;
            return path;
        }

        /// List all save slots with their status
        pub fn listSlots(self: *Self) ![config.max_slots]SlotInfo {
            var slots: [config.max_slots]SlotInfo = undefined;

            for (0..config.max_slots) |i| {
                const path = try self.getSlotPath(@intCast(i));
                defer self.allocator.free(path);

                slots[i] = .{
                    .index = @intCast(i),
                    .path = "",
                    .exists = false,
                    .size = 0,
                    .modified = 0,
                };

                // Check if file exists
                const file = std.fs.cwd().openFile(path, .{}) catch continue;
                defer file.close();

                const stat = file.stat() catch continue;
                slots[i].exists = true;
                slots[i].size = stat.size;
                slots[i].modified = stat.mtime;
            }

            return slots;
        }

        /// Find the next available (empty) slot
        pub fn findNextAvailableSlot(self: *Self) !?u32 {
            for (0..config.max_slots) |i| {
                const path = try self.getSlotPath(@intCast(i));
                defer self.allocator.free(path);

                std.fs.cwd().access(path, .{}) catch {
                    return @intCast(i);
                };
            }
            return null;
        }

        /// Check if a slot exists
        pub fn slotExists(self: *Self, slot: u32) !bool {
            const path = try self.getSlotPath(slot);
            defer self.allocator.free(path);

            std.fs.cwd().access(path, .{}) catch return false;
            return true;
        }

        /// Delete a save slot
        pub fn deleteSlot(self: *Self, slot: u32) !void {
            const path = try self.getSlotPath(slot);
            defer self.allocator.free(path);

            try std.fs.cwd().deleteFile(path);
        }

        /// Copy a save slot to another slot
        pub fn copySlot(self: *Self, from: u32, to: u32) !void {
            const from_path = try self.getSlotPath(from);
            defer self.allocator.free(from_path);

            const to_path = try self.getSlotPath(to);
            defer self.allocator.free(to_path);

            try std.fs.cwd().copyFile(from_path, std.fs.cwd(), to_path, .{});
        }

        /// Ensure save directory exists
        pub fn ensureSaveDir(self: *Self) !void {
            _ = self;
            std.fs.cwd().makeDir(config.save_dir) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };
        }

        /// Get configuration
        pub fn getConfig() SaveSlotConfig {
            return config;
        }
    };
}

