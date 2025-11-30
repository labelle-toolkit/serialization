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

    // Tests - library tests
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });

    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_tests.step);

    // Tests - serializer tests
    const serializer_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/serializer_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "serialization", .module = lib_mod },
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });

    const run_serializer_tests = b.addRunArtifact(serializer_tests);
    test_step.dependOn(&run_serializer_tests.step);

    // Tests - component registry tests
    const registry_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/component_registry_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "serialization", .module = lib_mod },
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });

    const run_registry_tests = b.addRunArtifact(registry_tests);
    test_step.dependOn(&run_registry_tests.step);

    // Tests - compression tests
    const compression_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compression_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "serialization", .module = lib_mod },
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(compression_tests).step);

    // Tests - json tests
    const json_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/json_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "serialization", .module = lib_mod },
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(json_tests).step);

    // Tests - validation tests
    const validation_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/validation_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "serialization", .module = lib_mod },
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(validation_tests).step);

    // Tests - save slots tests
    const save_slots_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/save_slots_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "serialization", .module = lib_mod },
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(save_slots_tests).step);

    // Tests - hooks tests
    const hooks_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/hooks_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "serialization", .module = lib_mod },
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(hooks_tests).step);

    // Tests - migration tests
    const migration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/migration_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "serialization", .module = lib_mod },
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(migration_tests).step);

    // Tests - log tests
    const log_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/log_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "serialization", .module = lib_mod },
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(log_tests).step);

    // Tests - debug tests
    const debug_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/debug_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "serialization", .module = lib_mod },
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(debug_tests).step);

    // Tests - comprehensive tests (Issue #21)
    const comprehensive_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/comprehensive_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "serialization", .module = lib_mod },
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(comprehensive_tests).step);

    // Tests - binary writer tests (Issue #5)
    const binary_writer_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/binary_writer_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "serialization", .module = lib_mod },
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(binary_writer_tests).step);

    // Tests - binary reader tests (Issue #5)
    const binary_reader_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/binary_reader_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "serialization", .module = lib_mod },
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(binary_reader_tests).step);

    // Tests - binary serializer tests (Issue #5)
    const binary_serializer_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/binary_serializer_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "serialization", .module = lib_mod },
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(binary_serializer_tests).step);

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
        .{ .name = "usage-06-save-slots", .file = "usage/06_save_slots.zig" },
        .{ .name = "usage-07-custom-hooks", .file = "usage/07_custom_hooks.zig" },
        .{ .name = "usage-08-component-registry", .file = "usage/08_component_registry.zig" },
        .{ .name = "usage-09-logging", .file = "usage/09_logging.zig" },
        .{ .name = "usage-10-debug-tools", .file = "usage/10_debug_tools.zig" },
        .{ .name = "usage-11-binary-format", .file = "usage/11_binary_format.zig" },
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

    // CLI tool: zig-serialize
    const cli_tool = b.addExecutable(.{
        .name = "zig-serialize",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zig-serialize.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "serialization", .module = lib_mod },
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });
    b.installArtifact(cli_tool);

    const run_cli = b.addRunArtifact(cli_tool);
    run_cli.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cli.addArgs(args);
    }

    const cli_step = b.step("cli", "Run the zig-serialize CLI tool");
    cli_step.dependOn(&run_cli.step);

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
