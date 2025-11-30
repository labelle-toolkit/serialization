# Implementation Plan: Debug and Inspection Tools (Issue #24)

## Overview
Implement all remaining sub-issues in a single PR for debug and inspection tools.

## Issues to Implement

### 1. #42 - Validate save without loading
**Status**: Already partially implemented in `validation.zig`
**Work needed**:
- Add `validateFile(path)` convenience function to Serializer
- Export in lib.zig (already exported as `validateSave`)

### 2. #37 - Pretty-print save files
**Work needed**:
- Add `prettyPrint(json_str) -> []u8` function in `validation.zig` or new `debug.zig`
- Uses existing `jsonValueToStringPretty` internally

### 3. #40 - Save file statistics
**Work needed**:
- Create `SaveStats` struct with entity_count, component_types, component_instances, file_size, version
- Add `getStats(json_str) -> SaveStats` function
- Parse metadata and count components without full deserialization

### 4. #39 - Dump registry state to console
**Work needed**:
- Add `dumpRegistry(registry, writer)` to Serializer
- Add `dumpEntity(registry, entity, writer)` to Serializer
- Format: entity ID, component types, component values

### 5. #38 - Diff two save files
**Work needed**:
- Create `RegistryDiff` struct with added_entities, removed_entities, modified_entities
- Add `diffSaves(json1, json2) -> RegistryDiff` function
- Compare entity IDs and component data

### 6. #43 - Custom log function via config
**Work needed**:
- Add `log_fn` optional callback to Config
- Modify Logger to call custom function if provided
- Fallback to std.log otherwise

### 7. #44 - Compile-time option to strip logging
**Work needed**:
- Add build option `strip_logging`
- Conditionally use NoOpLogger when enabled
- Update build.zig to expose option

### 8. #41 - CLI tool (zig-serialize)
**Work needed**:
- Create `tools/zig-serialize.zig` with main function
- Implement subcommands: pretty, diff, validate, stats, extract
- Add to build.zig as separate executable

## Implementation Order

1. **src/debug.zig** (new file) - Core debug utilities
   - `SaveStats` struct
   - `getStats()` function
   - `prettyPrint()` function
   - `diffSaves()` function
   - `RegistryDiff` struct

2. **src/serializer.zig** - Add methods to Serializer
   - `dumpRegistry()`
   - `dumpEntity()`
   - `validateFile()`

3. **src/log.zig** - Custom log function support
   - Add callback type
   - Modify Logger to use callback

4. **src/config.zig** - Add log_fn option

5. **build.zig** - Add strip_logging option + CLI tool

6. **tools/zig-serialize.zig** (new file) - CLI tool

7. **test/debug_tests.zig** (new file) - Tests for new functionality

8. **usage/10_debug_tools.zig** (new file) - Usage example

9. **lib.zig** - Export new types

## Files to Create
- `src/debug.zig`
- `tools/zig-serialize.zig`
- `test/debug_tests.zig`
- `usage/10_debug_tools.zig`

## Files to Modify
- `src/lib.zig` - exports
- `src/config.zig` - log_fn option
- `src/log.zig` - custom callback support
- `src/serializer.zig` - dump methods
- `build.zig` - strip_logging option, CLI tool
