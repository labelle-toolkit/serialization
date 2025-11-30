//! ECS Serialization Library for Zig
//!
//! A library for serializing and deserializing zig-ecs registry state.
//! Supports JSON format with entity ID remapping and versioning.

const std = @import("std");
const ecs = @import("ecs");

pub const Serializer = @import("serializer.zig").Serializer;
pub const SerializerWithTransient = @import("serializer.zig").SerializerWithTransient;
pub const isTransient = @import("serializer.zig").isTransient;
pub const SelectiveSerializer = @import("serializer.zig").SelectiveSerializer;
pub const SelectiveDeserializer = @import("serializer.zig").SelectiveDeserializer;
pub const SelectiveOptions = @import("serializer.zig").SelectiveOptions;
pub const Config = @import("config.zig").Config;
pub const Format = @import("config.zig").Format;
pub const SaveMetadata = @import("metadata.zig").SaveMetadata;
pub const SerializationError = @import("errors.zig").SerializationError;
pub const ValidationResult = @import("validation.zig").ValidationResult;
pub const validateSave = @import("validation.zig").validateSave;
pub const crc32 = @import("validation.zig").crc32;
pub const addChecksum = @import("validation.zig").addChecksum;
pub const MigrationContext = @import("migration.zig").MigrationContext;
pub const MigrationRegistry = @import("migration.zig").MigrationRegistry;
pub const MigrationResult = @import("migration.zig").MigrationResult;
pub const MigrationFn = @import("migration.zig").MigrationFn;
pub const CompressionType = @import("compression.zig").CompressionType;
pub const CompressionOptions = @import("compression.zig").CompressionOptions;
pub const CompressedHeader = @import("compression.zig").CompressedHeader;
pub const compress = @import("compression.zig").compress;
pub const decompress = @import("compression.zig").decompress;
pub const compressWithHeader = @import("compression.zig").compressWithHeader;
pub const decompressWithHeader = @import("compression.zig").decompressWithHeader;
pub const hasCompressionHeader = @import("compression.zig").hasCompressionHeader;

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
    _ = @import("validation.zig");
    _ = @import("migration.zig");
    _ = @import("compression.zig");
    _ = @import("tests/serializer_tests.zig");
}
