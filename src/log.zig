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
//!
//! // Or use a custom log function
//! const serializer = Serializer(&components).init(allocator, .{
//!     .log_level = .info,
//!     .log_fn = myCustomLogger,
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

/// Custom log function type
/// Users can provide their own logging implementation
pub const LogFn = *const fn (level: LogLevel, message: []const u8) void;

/// Scoped logger for the serialization library
pub const scoped = std.log.scoped(.serialization);

/// Logger that respects the configured log level
pub const Logger = struct {
    level: LogLevel,
    custom_fn: ?LogFn,

    pub fn init(level: LogLevel) Logger {
        return .{ .level = level, .custom_fn = null };
    }

    pub fn initWithCustomFn(level: LogLevel, custom_fn: ?LogFn) Logger {
        return .{ .level = level, .custom_fn = custom_fn };
    }

    /// Log a debug message
    pub fn debug(self: Logger, comptime format: []const u8, args: anytype) void {
        if (self.level.shouldLog(.debug)) {
            if (self.custom_fn) |custom| {
                var buf: [1024]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, format, args) catch return;
                custom(.debug, msg);
            } else {
                scoped.debug(format, args);
            }
        }
    }

    /// Log an info message
    pub fn info(self: Logger, comptime format: []const u8, args: anytype) void {
        if (self.level.shouldLog(.info)) {
            if (self.custom_fn) |custom| {
                var buf: [1024]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, format, args) catch return;
                custom(.info, msg);
            } else {
                scoped.info(format, args);
            }
        }
    }

    /// Log a warning message
    pub fn warn(self: Logger, comptime format: []const u8, args: anytype) void {
        if (self.level.shouldLog(.warn)) {
            if (self.custom_fn) |custom| {
                var buf: [1024]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, format, args) catch return;
                custom(.warn, msg);
            } else {
                scoped.warn(format, args);
            }
        }
    }

    /// Log an error message
    pub fn @"error"(self: Logger, comptime format: []const u8, args: anytype) void {
        if (self.level.shouldLog(.err)) {
            if (self.custom_fn) |custom| {
                var buf: [1024]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, format, args) catch return;
                custom(.err, msg);
            } else {
                scoped.err(format, args);
            }
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
