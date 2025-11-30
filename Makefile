# Makefile for serialization library
# Provides convenient shortcuts for common operations

.PHONY: all build test usage clean docs help

# Default target
all: build test usage

# Build the library
build:
	zig build

# Run unit tests
test:
	zig build test

# Run all usage examples
usage:
	zig build run-usage

# Run individual usage examples
usage-01:
	zig build run-usage-01-quick-save

usage-02:
	zig build run-usage-02-transient

usage-03:
	zig build run-usage-03-validation

usage-04:
	zig build run-usage-04-migration

usage-05:
	zig build run-usage-05-compression

usage-06:
	zig build run-usage-06-save-slots

usage-07:
	zig build run-usage-07-custom-hooks

usage-08:
	zig build run-usage-08-component-registry

# Run the basic example
example:
	zig build run-example

# Generate documentation
docs:
	zig build docs

# Clean build artifacts
clean:
	rm -rf .zig-cache zig-out

# Format code
fmt:
	zig fmt src/ examples/ usage/

# Check formatting without modifying
fmt-check:
	zig fmt --check src/ examples/ usage/

# Help
help:
	@echo "Available targets:"
	@echo "  all        - Build, test, and run usage examples"
	@echo "  build      - Build the library"
	@echo "  test       - Run unit tests"
	@echo "  usage      - Run all usage examples"
	@echo "  usage-01   - Run quick save example"
	@echo "  usage-02   - Run transient components example"
	@echo "  usage-03   - Run validation example"
	@echo "  usage-04   - Run migration example"
	@echo "  usage-05   - Run compression example"
	@echo "  usage-06   - Run save slots example"
	@echo "  usage-07   - Run custom hooks example"
	@echo "  usage-08   - Run component registry example"
	@echo "  example    - Run basic example"
	@echo "  docs       - Generate documentation"
	@echo "  clean      - Remove build artifacts"
	@echo "  fmt        - Format source code"
	@echo "  fmt-check  - Check code formatting"
	@echo "  help       - Show this help message"
