//! Logging utilities for the serialization library
//!
//! Provides configurable logging that can be enabled/disabled and filtered by level.
//! Uses std.log under the hood with a scoped logger for the serialization library.
//!
//! ## Usage
//!
//! ```zig
//! const serializer = Serializer(&components).init(allocator, .{
//!     .log_level = .info,  // Enable info and above
//! });
//!
//! // Or disable logging entirely
//! const serializer = Serializer(&components).init(allocator, .{
//!     .log_level = .none,
//! });
//! ```

const std = @import("std");

/// Log levels for the serialization library
pub const LogLevel = enum {
    /// Detailed debugging information
    debug,
    /// General information about operations
    info,
    /// Warning conditions
    warn,
    /// Error conditions
    err,
    /// Disable all logging
    none,

    /// Convert to std.log.Level (returns null for .none)
    pub fn toStdLevel(self: LogLevel) ?std.log.Level {
        return switch (self) {
            .debug => .debug,
            .info => .info,
            .warn => .warn,
            .err => .err,
            .none => null,
        };
    }

    /// Check if a message at the given level should be logged
    pub fn shouldLog(self: LogLevel, message_level: LogLevel) bool {
        if (self == .none) return false;
        return @intFromEnum(message_level) >= @intFromEnum(self);
    }
};

/// Scoped logger for the serialization library
pub const scoped = std.log.scoped(.serialization);

/// Logger that respects the configured log level
pub const Logger = struct {
    level: LogLevel,

    pub fn init(level: LogLevel) Logger {
        return .{ .level = level };
    }

    /// Log a debug message
    pub fn debug(self: Logger, comptime format: []const u8, args: anytype) void {
        if (self.level.shouldLog(.debug)) {
            scoped.debug(format, args);
        }
    }

    /// Log an info message
    pub fn info(self: Logger, comptime format: []const u8, args: anytype) void {
        if (self.level.shouldLog(.info)) {
            scoped.info(format, args);
        }
    }

    /// Log a warning message
    pub fn warn(self: Logger, comptime format: []const u8, args: anytype) void {
        if (self.level.shouldLog(.warn)) {
            scoped.warn(format, args);
        }
    }

    /// Log an error message
    pub fn @"error"(self: Logger, comptime format: []const u8, args: anytype) void {
        if (self.level.shouldLog(.err)) {
            scoped.err(format, args);
        }
    }
};

/// No-op logger for when logging is disabled at compile time
pub const NoOpLogger = struct {
    pub fn debug(_: NoOpLogger, comptime _: []const u8, _: anytype) void {}
    pub fn info(_: NoOpLogger, comptime _: []const u8, _: anytype) void {}
    pub fn warn(_: NoOpLogger, comptime _: []const u8, _: anytype) void {}
    pub fn @"error"(_: NoOpLogger, comptime _: []const u8, _: anytype) void {}
};
