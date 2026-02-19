# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Lolgato is a native macOS menu bar app (SwiftUI, macOS 14.2+) that controls Elgato lights. It automates light behavior based on camera activity, system sleep/wake, and Night Shift state.

## Build & Development Commands

- **Debug build**: `./scripts/build-debug` (or `just build`)
- **Format code**: `./scripts/format-swift` (or `just format`)
- **Check both in parallel**: `just check`
- **Production build** (archive + DMG + notarize): `./scripts/build`
- **Release** (git tag + GitHub release): `./scripts/release`

Build uses xcodebuild with scheme "Lolgato" and project "Lolgato.xcodeproj". There are no tests.

## Code Formatting

Uses swiftformat with `--disable redundantSelf` (see `.swiftformat`). Install via `brew install swiftformat`.

## Architecture

**Entry point**: `LolgatoApp.swift` — SwiftUI `@main` with `MenuBarExtra` scene.

**AppCoordinator** (`AppCoordinator.swift`) is the central dependency container. It owns:
- `AppState` — observable settings (persisted via `@AppStorage`)
- `ElgatoDeviceManager` — device collection, discovery, and HTTP control
- `CameraMonitor` — available camera list
- Three reactive controllers that subscribe to state changes via Combine

**Reactive automation controllers** (each monitors a trigger and controls lights):
- `LightCameraController` — turns lights on/off when camera becomes active/inactive
- `LightSystemStateController` — turns lights off on sleep, on at wake (via NSWorkspace notifications)
- `NightShiftSyncController` — polls CoreBrightness private framework to sync light color temperature with Night Shift

**Device discovery & control**:
- `ElgatoDiscovery` — Bonjour browser (`NWBrowser`) emitting `AsyncSequence` of discovery events for `_elg._tcp` services
- `ElgatoDevice` — represents one light; communicates via HTTP PUT/GET to `/elgato/lights` REST endpoint
- Devices are persisted as JSON in UserDefaults

**Camera detection**:
- `CameraUsageDetector` — polls AVFoundation to detect active camera usage
- `CameraManager` — enumerates cameras via CoreMediaIO C APIs

## Key Technical Details

- **No App Sandbox**: removed to access CoreBrightness private framework for Night Shift sync
- **Night Shift sync** uses `dlopen()` to load CoreBrightness and `NSClassFromString("CBBlueLightClient")` — fragile across macOS updates
- **Temperature conversion**: Kelvin (2900–7000K) ↔ Elgato internal scale (143–344)
- **Dependencies** (Swift Package Manager): LaunchAtLogin-Modern, SettingsAccess, KeyboardShortcuts
- **Keyboard shortcuts**: defined in `Constants.swift`, managed by AppCoordinator
