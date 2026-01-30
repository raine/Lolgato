# Swift project checks

# Run both format and build in parallel
[parallel]
check: format build

# Format Swift files
format:
    ./scripts/format-swift

# Build Mac app
build:
    ./scripts/build-debug

# Run app with auto-restart on rebuild
dev *args:
    ./scripts/run-dev {{args}}