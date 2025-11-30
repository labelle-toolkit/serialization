//! Tests for logging utilities

const std = @import("std");
const serialization = @import("serialization");
const LogLevel = serialization.LogLevel;
const Logger = serialization.Logger;

test "LogLevel.shouldLog respects level hierarchy" {
    // Debug level should log everything
    try std.testing.expect(LogLevel.debug.shouldLog(.debug));
    try std.testing.expect(LogLevel.debug.shouldLog(.info));
    try std.testing.expect(LogLevel.debug.shouldLog(.warn));
    try std.testing.expect(LogLevel.debug.shouldLog(.err));

    // Info level should not log debug
    try std.testing.expect(!LogLevel.info.shouldLog(.debug));
    try std.testing.expect(LogLevel.info.shouldLog(.info));
    try std.testing.expect(LogLevel.info.shouldLog(.warn));
    try std.testing.expect(LogLevel.info.shouldLog(.err));

    // Warn level should only log warn and err
    try std.testing.expect(!LogLevel.warn.shouldLog(.debug));
    try std.testing.expect(!LogLevel.warn.shouldLog(.info));
    try std.testing.expect(LogLevel.warn.shouldLog(.warn));
    try std.testing.expect(LogLevel.warn.shouldLog(.err));

    // Error level should only log err
    try std.testing.expect(!LogLevel.err.shouldLog(.debug));
    try std.testing.expect(!LogLevel.err.shouldLog(.info));
    try std.testing.expect(!LogLevel.err.shouldLog(.warn));
    try std.testing.expect(LogLevel.err.shouldLog(.err));

    // None should log nothing
    try std.testing.expect(!LogLevel.none.shouldLog(.debug));
    try std.testing.expect(!LogLevel.none.shouldLog(.info));
    try std.testing.expect(!LogLevel.none.shouldLog(.warn));
    try std.testing.expect(!LogLevel.none.shouldLog(.err));
}

test "LogLevel.toStdLevel conversion" {
    try std.testing.expectEqual(@as(?std.log.Level, .debug), LogLevel.debug.toStdLevel());
    try std.testing.expectEqual(@as(?std.log.Level, .info), LogLevel.info.toStdLevel());
    try std.testing.expectEqual(@as(?std.log.Level, .warn), LogLevel.warn.toStdLevel());
    try std.testing.expectEqual(@as(?std.log.Level, .err), LogLevel.err.toStdLevel());
    try std.testing.expectEqual(@as(?std.log.Level, null), LogLevel.none.toStdLevel());
}

test "Logger can be initialized" {
    const logger = Logger.init(.info);
    _ = logger;
}

test "Config default log_level is none" {
    const config = serialization.Config{};
    try std.testing.expectEqual(LogLevel.none, config.log_level);
}

test "Serializer accepts log_level config" {
    const allocator = std.testing.allocator;

    const Position = struct { x: f32, y: f32 };
    const TestSerializer = serialization.Serializer(&[_]type{Position});

    // Test with logging disabled (default)
    var ser1 = TestSerializer.init(allocator, .{});
    defer ser1.deinit();

    // Test with logging enabled
    var ser2 = TestSerializer.init(allocator, .{ .log_level = .debug });
    defer ser2.deinit();

    // Test with only errors
    var ser3 = TestSerializer.init(allocator, .{ .log_level = .err });
    defer ser3.deinit();
}
