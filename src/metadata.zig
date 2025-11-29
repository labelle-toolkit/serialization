//! Save file metadata structures

const std = @import("std");

/// Metadata stored in save files
pub const SaveMetadata = struct {
    /// Format version of the save file
    version: u32,

    /// Library version that created this save
    lib_version: []const u8 = "0.1.0",

    /// Unix timestamp when save was created
    timestamp: i64,

    /// Optional game name
    game_name: ?[]const u8 = null,

    /// Optional git hash for debugging
    git_hash: ?[]const u8 = null,

    /// Total entity count in save
    entity_count: u32 = 0,

    /// Number of component types saved
    component_type_count: u32 = 0,

    pub fn now(version: u32) SaveMetadata {
        return .{
            .version = version,
            .timestamp = std.time.timestamp(),
        };
    }
};

/// Game-specific metadata that can be stored alongside saves
pub fn GameMetadata(comptime T: type) type {
    return struct {
        save: SaveMetadata,
        game: T,
    };
}
