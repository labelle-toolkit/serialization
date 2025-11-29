//! Error types for serialization operations

const std = @import("std");

/// Errors that can occur during serialization/deserialization
pub const SerializationError = error{
    /// The save file version is newer than supported
    SaveFromNewerVersion,
    /// The save file version is older than the minimum supported
    SaveTooOld,
    /// The save file is corrupted or invalid
    InvalidSaveFormat,
    /// A required component type was not registered
    UnregisteredComponent,
    /// Entity reference points to non-existent entity
    InvalidEntityReference,
    /// JSON parsing failed
    JsonParseError,
    /// Failed to write to output
    WriteError,
    /// Failed to read from input
    ReadError,
    /// Checksum validation failed
    ChecksumMismatch,
    /// Component type mismatch during deserialization
    TypeMismatch,
    /// Out of memory
    OutOfMemory,
    /// File not found
    FileNotFound,
    /// Access denied
    AccessDenied,
    /// Generic IO error
    IoError,
};

/// Detailed error information for debugging
pub const ErrorInfo = struct {
    error_type: SerializationError,
    message: []const u8,
    context: ?ErrorContext = null,

    pub const ErrorContext = union(enum) {
        component: []const u8,
        entity: u32,
        line: usize,
        field: []const u8,
    };

    pub fn format(
        self: ErrorInfo,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("SerializationError.{s}: {s}", .{
            @errorName(self.error_type),
            self.message,
        });
        if (self.context) |ctx| {
            switch (ctx) {
                .component => |name| try writer.print(" (component: {s})", .{name}),
                .entity => |id| try writer.print(" (entity: {d})", .{id}),
                .line => |ln| try writer.print(" (line: {d})", .{ln}),
                .field => |name| try writer.print(" (field: {s})", .{name}),
            }
        }
    }
};
