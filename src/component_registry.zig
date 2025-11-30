//! Component Registry Utilities
//!
//! Provides compile-time utilities for building component type lists,
//! making it easier to register components for serialization.
//!
//! ## Usage
//!
//! ```zig
//! // Option 1: Use a tuple of component types
//! const MySerializer = serialization.Serializer(
//!     serialization.ComponentRegistry.fromTuple(.{
//!         Position, Health, Inventory,
//!         Player, NPC,  // Tags
//!     })
//! );
//!
//! // Option 2: Extract from a module (all public structs)
//! const Components = @import("components.zig");
//! const MySerializer = serialization.Serializer(
//!     serialization.ComponentRegistry.fromModule(Components)
//! );
//!
//! // Option 3: Exclude specific types
//! const MySerializer = serialization.Serializer(
//!     serialization.ComponentRegistry.exclude(
//!         AllComponents,
//!         .{ DebugComponent, TransientState },
//!     )
//! );
//! ```

const std = @import("std");

/// Utility for building component type lists at compile time
pub const ComponentRegistry = struct {
    /// Convert a tuple of types into a slice of types suitable for Serializer
    ///
    /// Example:
    /// ```zig
    /// const types = ComponentRegistry.fromTuple(.{ Position, Health, Player });
    /// const MySerializer = Serializer(types);
    /// ```
    pub fn fromTuple(comptime tuple: anytype) []const type {
        const info = @typeInfo(@TypeOf(tuple));
        if (info != .@"struct" or !info.@"struct".is_tuple) {
            @compileError("Expected a tuple of types");
        }

        const fields = info.@"struct".fields;

        comptime {
            for (fields) |field| {
                const FieldType = field.type;
                if (@typeInfo(FieldType) != .type) {
                    @compileError("Tuple must contain types, found: " ++ @typeName(FieldType));
                }
            }
        }

        const types = comptime blk: {
            var result: [fields.len]type = undefined;
            for (fields, 0..) |field, i| {
                result[i] = @field(tuple, field.name);
            }
            break :blk result;
        };

        return &types;
    }

    /// Extract all public struct types from a module
    ///
    /// This is useful when you have a components.zig file with all your components:
    /// ```zig
    /// // components.zig
    /// pub const Position = struct { x: f32, y: f32 };
    /// pub const Health = struct { current: u8, max: u8 };
    /// pub const Player = struct {};  // Tag
    ///
    /// // main.zig
    /// const Components = @import("components.zig");
    /// const types = ComponentRegistry.fromModule(Components);
    /// ```
    pub fn fromModule(comptime Module: type) []const type {
        const decls = @typeInfo(Module).@"struct".decls;

        // First pass: count valid types
        comptime var type_count: usize = 0;
        inline for (decls) |decl| {
            if (@hasDecl(Module, decl.name)) {
                const DeclType = @TypeOf(@field(Module, decl.name));
                if (DeclType == type) {
                    const ActualType = @field(Module, decl.name);
                    if (isSerializableType(ActualType)) {
                        type_count += 1;
                    }
                }
            }
        }

        // Second pass: collect types
        var types: [type_count]type = undefined;
        comptime var idx: usize = 0;
        inline for (decls) |decl| {
            if (@hasDecl(Module, decl.name)) {
                const DeclType = @TypeOf(@field(Module, decl.name));
                if (DeclType == type) {
                    const ActualType = @field(Module, decl.name);
                    if (isSerializableType(ActualType)) {
                        types[idx] = ActualType;
                        idx += 1;
                    }
                }
            }
        }

        return &types;
    }

    /// Exclude specific types from a component list
    ///
    /// Example:
    /// ```zig
    /// const AllComponents = &[_]type{ Position, Health, DebugInfo, Velocity };
    /// const SaveableComponents = ComponentRegistry.exclude(
    ///     AllComponents,
    ///     .{ DebugInfo, Velocity },  // Transient, don't save
    /// );
    /// ```
    pub fn exclude(
        comptime all_types: []const type,
        comptime excluded: anytype,
    ) []const type {
        const excluded_types = fromTuple(excluded);

        // Count non-excluded types
        comptime var result_count: usize = 0;
        inline for (all_types) |T| {
            var is_excluded = false;
            inline for (excluded_types) |E| {
                if (T == E) {
                    is_excluded = true;
                    break;
                }
            }
            if (!is_excluded) result_count += 1;
        }

        // Collect non-excluded types
        var result: [result_count]type = undefined;
        comptime var idx: usize = 0;
        inline for (all_types) |T| {
            var is_excluded = false;
            inline for (excluded_types) |E| {
                if (T == E) {
                    is_excluded = true;
                    break;
                }
            }
            if (!is_excluded) {
                result[idx] = T;
                idx += 1;
            }
        }

        return &result;
    }

    /// Merge multiple component lists into one
    ///
    /// Example:
    /// ```zig
    /// const CoreComponents = &[_]type{ Position, Health };
    /// const GameComponents = &[_]type{ Inventory, Quest };
    /// const AllComponents = ComponentRegistry.merge(.{
    ///     CoreComponents,
    ///     GameComponents,
    /// });
    /// ```
    pub fn merge(comptime lists: anytype) []const type {
        const info = @typeInfo(@TypeOf(lists));
        if (info != .@"struct" or !info.@"struct".is_tuple) {
            @compileError("Expected a tuple of type slices");
        }

        // Count total types
        comptime var total: usize = 0;
        inline for (info.@"struct".fields) |field| {
            const list = @field(lists, field.name);
            total += list.len;
        }

        // Collect all types
        var result: [total]type = undefined;
        comptime var idx: usize = 0;
        inline for (info.@"struct".fields) |field| {
            const list = @field(lists, field.name);
            inline for (list) |T| {
                result[idx] = T;
                idx += 1;
            }
        }

        return &result;
    }

    /// Check if a type is serializable (struct type)
    fn isSerializableType(comptime T: type) bool {
        const info = @typeInfo(T);
        return info == .@"struct";
    }

    /// Validate that all types in a list are serializable
    /// Returns a compile error with details if any type is not serializable
    pub fn validateSerializable(comptime types: []const type) void {
        inline for (types) |T| {
            const info = @typeInfo(T);
            if (info != .@"struct") {
                @compileError("Type '" ++ @typeName(T) ++ "' is not a struct and cannot be serialized");
            }

            // Check for problematic field types
            inline for (info.@"struct".fields) |field| {
                validateFieldType(T, field.name, field.type);
            }
        }
    }

    fn validateFieldType(comptime Parent: type, comptime field_name: []const u8, comptime T: type) void {
        const info = @typeInfo(T);
        switch (info) {
            .pointer => |ptr| {
                // Slices of u8 (strings) are OK
                if (ptr.size == .slice and ptr.child == u8) {
                    return;
                }
                // Other slices are OK too (will serialize as arrays)
                if (ptr.size == .slice) {
                    return;
                }
                // Single pointers are problematic
                @compileError("Field '" ++ field_name ++ "' in '" ++ @typeName(Parent) ++
                    "' is a pointer type which cannot be directly serialized. " ++
                    "Consider using custom serialization hooks.");
            },
            .@"fn" => {
                @compileError("Field '" ++ field_name ++ "' in '" ++ @typeName(Parent) ++
                    "' is a function pointer which cannot be serialized.");
            },
            .@"struct" => {
                // Recursively validate nested structs
                inline for (info.@"struct".fields) |nested_field| {
                    validateFieldType(T, nested_field.name, nested_field.type);
                }
            },
            .optional => |opt| {
                validateFieldType(Parent, field_name, opt.child);
            },
            .array => |arr| {
                validateFieldType(Parent, field_name, arr.child);
            },
            else => {},
        }
    }

    /// Get the count of types in a list
    pub fn count(comptime types: []const type) usize {
        return types.len;
    }

    /// Check if a type is in the list
    pub fn contains(comptime types: []const type, comptime T: type) bool {
        inline for (types) |ListT| {
            if (ListT == T) return true;
        }
        return false;
    }
};
