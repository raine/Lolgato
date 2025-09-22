# Swift project checks

# Run both format and build in parallel
[parallel]
check: format build

# Format Swift files
format:
    ./scripts/format-swift

# Build the project
build:
    ./scripts/build-debug