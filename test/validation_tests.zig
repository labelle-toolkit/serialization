//! Tests for save file validation

const std = @import("std");
const serialization = @import("serialization");
const validateSave = serialization.validateSave;
const crc32 = serialization.crc32;

test "crc32 produces consistent results" {
    const data = "Hello, World!";
    const hash1 = crc32(data);
    const hash2 = crc32(data);
    try std.testing.expectEqual(hash1, hash2);
}

test "validateSave detects valid save" {
    const allocator = std.testing.allocator;

    const valid_json =
        \\{
        \\  "meta": { "version": 1 },
        \\  "components": {}
        \\}
    ;

    const result = try validateSave(allocator, valid_json, 1);
    try std.testing.expect(result == .valid);
}

test "validateSave detects version mismatch" {
    const allocator = std.testing.allocator;

    const future_json =
        \\{
        \\  "meta": { "version": 99 },
        \\  "components": {}
        \\}
    ;

    const result = try validateSave(allocator, future_json, 1);
    try std.testing.expect(result == .version_mismatch);
}

test "validateSave detects invalid JSON" {
    const allocator = std.testing.allocator;

    const result = try validateSave(allocator, "not valid json", 1);
    try std.testing.expect(result == .invalid_structure);
}

test "validateSave detects missing metadata" {
    const allocator = std.testing.allocator;

    const no_meta =
        \\{
        \\  "components": {}
        \\}
    ;

    const result = try validateSave(allocator, no_meta, 1);
    try std.testing.expect(result == .missing_metadata);
}
