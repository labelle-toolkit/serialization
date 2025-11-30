//! Save file validation and integrity checking

const std = @import("std");

/// Serialize a JSON value to a string using Zig 0.15 API
fn jsonValueToString(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: std.io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    var write_stream: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{},
    };
    try write_stream.write(value);
    return out.toOwnedSlice();
}

/// Serialize a JSON value to a string with pretty printing
fn jsonValueToStringPretty(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: std.io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    var write_stream: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .indent_2 },
    };
    try write_stream.write(value);
    return out.toOwnedSlice();
}

/// Validation result
pub const ValidationResult = union(enum) {
    valid,
    checksum_mismatch: struct {
        expected: u32,
        actual: u32,
    },
    invalid_structure: []const u8,
    version_mismatch: struct {
        save_version: u32,
        max_supported: u32,
    },
    missing_metadata,
};

/// Calculate CRC32 checksum of data
pub fn crc32(data: []const u8) u32 {
    return std.hash.Crc32.hash(data);
}

/// Validate a save file without fully loading it
pub fn validateSave(allocator: std.mem.Allocator, json_str: []const u8, max_version: u32) !ValidationResult {
    // Parse JSON
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_str,
        .{},
    ) catch {
        return .{ .invalid_structure = "Failed to parse JSON" };
    };
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) {
        return .{ .invalid_structure = "Root must be an object" };
    }

    // Check for metadata
    const meta = root.object.get("meta") orelse {
        return .missing_metadata;
    };

    if (meta != .object) {
        return .{ .invalid_structure = "Metadata must be an object" };
    }

    // Check version
    if (meta.object.get("version")) |version_val| {
        if (version_val != .integer) {
            return .{ .invalid_structure = "Version must be an integer" };
        }
        const version: u32 = @intCast(version_val.integer);
        if (version > max_version) {
            return .{ .version_mismatch = .{
                .save_version = version,
                .max_supported = max_version,
            } };
        }
    }

    // Check for checksum if present
    if (meta.object.get("checksum")) |checksum_val| {
        if (checksum_val != .integer) {
            return .{ .invalid_structure = "Checksum must be an integer" };
        }
        const expected: u32 = @intCast(checksum_val.integer);

        // Calculate checksum of components section
        if (root.object.get("components")) |components| {
            const buffer = jsonValueToString(allocator, components) catch {
                return .{ .invalid_structure = "Failed to stringify components" };
            };
            defer allocator.free(buffer);

            const actual = crc32(buffer);
            if (actual != expected) {
                return .{ .checksum_mismatch = .{
                    .expected = expected,
                    .actual = actual,
                } };
            }
        }
    }

    // Check components structure
    if (root.object.get("components")) |components| {
        if (components != .object) {
            return .{ .invalid_structure = "Components must be an object" };
        }
    } else {
        return .{ .invalid_structure = "Missing components section" };
    }

    return .valid;
}

/// Add checksum to serialized JSON
pub fn addChecksum(allocator: std.mem.Allocator, json_str: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_str,
        .{},
    );
    defer parsed.deinit();

    var root = parsed.value;
    if (root != .object) return error.InvalidFormat;

    // Calculate checksum of components
    const components = root.object.get("components") orelse return error.InvalidFormat;

    const buffer = try jsonValueToString(allocator, components);
    defer allocator.free(buffer);

    const checksum = crc32(buffer);

    // Add checksum to metadata
    if (root.object.getPtr("meta")) |meta_ptr| {
        if (meta_ptr.* == .object) {
            try meta_ptr.object.put("checksum", .{ .integer = @intCast(checksum) });
        }
    }

    // Re-stringify with checksum
    return jsonValueToStringPretty(allocator, root);
}
