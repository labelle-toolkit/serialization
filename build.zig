const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get zig-ecs dependency
    const ecs_dep = b.dependency("entt", .{
        .target = target,
        .optimize = optimize,
    });
    const ecs = ecs_dep.module("zig-ecs");

    // Main library module
    const lib_mod = b.addModule("serialization", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ecs", .module = ecs },
        },
    });

    // Static library artifact
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "serialization",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });
    b.installArtifact(lib);

    // Tests
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // Example: basic save/load
    const example_basic = b.addExecutable(.{
        .name = "example-basic",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/basic.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "serialization", .module = lib_mod },
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });
    b.installArtifact(example_basic);

    const run_example_basic = b.addRunArtifact(example_basic);
    const example_step = b.step("run-example", "Run the basic example");
    example_step.dependOn(&run_example_basic.step);

    // Usage examples
    const usage_examples = [_]struct { name: []const u8, file: []const u8 }{
        .{ .name = "usage-01-quick-save", .file = "usage/01_quick_save.zig" },
        .{ .name = "usage-02-transient", .file = "usage/02_transient_components.zig" },
        .{ .name = "usage-03-validation", .file = "usage/03_validation.zig" },
        .{ .name = "usage-04-migration", .file = "usage/04_migration.zig" },
        .{ .name = "usage-05-compression", .file = "usage/05_compression.zig" },
    };

    const usage_step = b.step("run-usage", "Run all usage examples");

    inline for (usage_examples) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.file),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "serialization", .module = lib_mod },
                    .{ .name = "ecs", .module = ecs },
                },
            }),
        });
        b.installArtifact(exe);

        const run_exe = b.addRunArtifact(exe);
        usage_step.dependOn(&run_exe.step);

        // Individual run step
        const run_step = b.step("run-" ++ example.name, "Run " ++ example.name);
        run_step.dependOn(&run_exe.step);
    }

    // Docs
    const docs = b.addLibrary(.{
        .linkage = .static,
        .name = "serialization-docs",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&install_docs.step);
}
