# Design: Switch KeyboardShortcuts to Remote SPM Reference

Date: 2026-02-22

## Problem

`KeyboardShortcuts` is currently referenced as a local Swift Package Manager dependency
(`XCLocalSwiftPackageReference`) pointing to `../../git/KeyboardShortcuts`. This requires
every contributor to manually clone the package to `~/git/KeyboardShortcuts` before the
project will build. The other two dependencies (`LaunchAtLogin-Modern`, `SettingsAccess`)
are already managed as remote SPM references and need no manual setup.

## Solution

Replace the `XCLocalSwiftPackageReference` with a `XCRemoteSwiftPackageReference` in
`Lolgato.xcodeproj/project.pbxproj`, pointing to
`https://github.com/sindresorhus/KeyboardShortcuts`. Use `upToNextMajorVersion` from
`1.0.0`, consistent with how `SettingsAccess` is pinned.

Update `Package.resolved` to include a pinned entry for `KeyboardShortcuts` at `v1.10.0`
(revision `70caa8dea43e2d273cd5ab78885d7eff01df550c`).

## Changes

- `Lolgato.xcodeproj/project.pbxproj`: remove `XCLocalSwiftPackageReference` block,
  add `XCRemoteSwiftPackageReference` block, update the `XCSwiftPackageProductDependency`
  to reference the new remote package, update the `packageReferences` array.
- `Lolgato.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`: add
  `KeyboardShortcuts` pin entry.

## Outcome

The project builds from a clean clone with no manual setup steps. The local
`~/git/KeyboardShortcuts` checkout is no longer required.
