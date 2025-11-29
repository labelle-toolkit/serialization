//! ECS Serialization Library for Zig
//!
//! A library for serializing and deserializing zig-ecs registry state.
//! Supports JSON format with entity ID remapping and versioning.

const std = @import("std");
const ecs = @import("ecs");

pub const Serializer = @import("serializer.zig").Serializer;
pub const Config = @import("config.zig").Config;
pub const Format = @import("config.zig").Format;
pub const SaveMetadata = @import("metadata.zig").SaveMetadata;
pub const SerializationError = @import("errors.zig").SerializationError;

// Re-export commonly used types
pub const Registry = ecs.Registry;
pub const Entity = ecs.Entity;

/// Library version
pub const version = std.SemanticVersion{
    .major = 0,
    .minor = 1,
    .patch = 0,
};

test {
    std.testing.refAllDecls(@This());
    _ = @import("serializer.zig");
    _ = @import("config.zig");
    _ = @import("metadata.zig");
    _ = @import("errors.zig");
    _ = @import("json_writer.zig");
    _ = @import("json_reader.zig");
    _ = @import("tests/serializer_tests.zig");
}
