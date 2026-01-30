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

# Build release archive with notarization
archive:
    ./scripts/archive

# Build notarized DMG for distribution
build-dmg:
    ./scripts/build

# Clean build, package DMG, and release
release:
    ./scripts/build-and-release

# Build and install to /Applications (release)
install:
    ./scripts/build-install

# Build and install dev version to /Applications
install-dev:
    ./scripts/build-install --dev