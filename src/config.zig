//! Configuration types for the serializer

const log = @import("log.zig");

/// Output format for serialization
pub const Format = enum {
    /// Human-readable JSON format
    json,
    /// Compact binary format (not yet implemented)
    binary,
};

/// Configuration options for the serializer
pub const Config = struct {
    /// Save format version number
    version: u32 = 1,

    /// Minimum version that can be loaded
    min_loadable_version: u32 = 1,

    /// Output format
    format: Format = .json,

    /// Pretty print JSON output (adds indentation and newlines)
    pretty_print: bool = true,

    /// Include metadata in save (timestamp, version info, etc.)
    include_metadata: bool = true,

    /// Validate data integrity on load
    validate_on_load: bool = true,

    /// Game name for save identification
    game_name: ?[]const u8 = null,

    /// Enable string interning for memory efficiency
    string_interning: bool = false,

    /// Log level for serialization operations
    /// Set to .none to disable all logging
    log_level: log.LogLevel = .none,
};
