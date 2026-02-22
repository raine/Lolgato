# KeyboardShortcuts Remote SPM Reference Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the local `XCLocalSwiftPackageReference` for `KeyboardShortcuts` with a remote `XCRemoteSwiftPackageReference`, so the project builds from a clean clone with no manual setup.

**Architecture:** The Xcode project file (`project.pbxproj`) stores package references directly. We swap the local path reference for a remote GitHub URL reference (same pattern as `LaunchAtLogin-Modern` and `SettingsAccess`), then let `xcodebuild -resolvePackageDependencies` regenerate `Package.resolved` with the correct pin.

**Tech Stack:** Swift Package Manager, Xcode project file (pbxproj), xcodebuild CLI

---

### Task 1: Switch KeyboardShortcuts from local to remote in project.pbxproj

**Files:**
- Modify: `Lolgato.xcodeproj/project.pbxproj`

The pbxproj is a plain text file. We need three edits:

**Step 1: Replace the XCLocalSwiftPackageReference section**

Find and replace the entire local reference block. The current block is:

```
/* Begin XCLocalSwiftPackageReference section */
		F7EC5EF72CA173E7000EFB2C /* XCLocalSwiftPackageReference "../../git/KeyboardShortcuts" */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = ../../git/KeyboardShortcuts;
		};
/* End XCLocalSwiftPackageReference section */
```

Replace it with a remote reference block (reusing the same UUID so no other references need updating):

```
/* Begin XCRemoteSwiftPackageReference section */
		F70476072CA46DBA0084A2A2 /* XCRemoteSwiftPackageReference "SettingsAccess" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/orchetect/SettingsAccess";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 2.0.0;
			};
		};
		F7EC5EF72CA173E7000EFB2C /* XCRemoteSwiftPackageReference "KeyboardShortcuts" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/sindresorhus/KeyboardShortcuts";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 1.0.0;
			};
		};
		F7F6F5B52CA1746E00D0CF5F /* XCRemoteSwiftPackageReference "LaunchAtLogin-Modern" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/sindresorhus/LaunchAtLogin-Modern";
			requirement = {
				branch = main;
				kind = branch;
			};
		};
/* End XCRemoteSwiftPackageReference section */
```

Note: the existing `/* Begin XCRemoteSwiftPackageReference section */` block (containing `SettingsAccess` and `LaunchAtLogin-Modern`) must be merged into this new combined block — do not leave two separate `XCRemoteSwiftPackageReference` sections.

**Step 2: Update the packageReferences comment**

Find the `packageReferences` array entry for KeyboardShortcuts:

```
F7EC5EF72CA173E7000EFB2C /* XCLocalSwiftPackageReference "../../git/KeyboardShortcuts" */,
```

Replace the comment so it reads:

```
F7EC5EF72CA173E7000EFB2C /* XCRemoteSwiftPackageReference "KeyboardShortcuts" */,
```

**Step 3: Update the XCSwiftPackageProductDependency comment**

Find:

```
		F7F6F5B32CA1744900D0CF5F /* KeyboardShortcuts */ = {
			isa = XCSwiftPackageProductDependency;
			package = F7EC5EF72CA173E7000EFB2C /* XCLocalSwiftPackageReference "../../git/KeyboardShortcuts" */;
			productName = KeyboardShortcuts;
		};
```

Replace the `package` line comment:

```
		F7F6F5B32CA1744900D0CF5F /* KeyboardShortcuts */ = {
			isa = XCSwiftPackageProductDependency;
			package = F7EC5EF72CA173E7000EFB2C /* XCRemoteSwiftPackageReference "KeyboardShortcuts" */;
			productName = KeyboardShortcuts;
		};
```

**Step 4: Verify the file has no remaining local reference**

```bash
grep -c "XCLocalSwiftPackageReference" Lolgato.xcodeproj/project.pbxproj
```

Expected output: `0`

---

### Task 2: Regenerate Package.resolved

**Files:**
- Modify: `Lolgato.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (auto-generated)

**Step 1: Resolve packages via xcodebuild**

```bash
xcodebuild -project Lolgato.xcodeproj -resolvePackageDependencies 2>&1 | tail -10
```

Expected: resolves `KeyboardShortcuts` from GitHub and prints something like:
```
Resolved source packages:
  KeyboardShortcuts: https://github.com/sindresorhus/KeyboardShortcuts @ 1.10.0
  ...
```

**Step 2: Verify Package.resolved now includes KeyboardShortcuts**

```bash
grep -A5 "KeyboardShortcuts" Lolgato.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

Expected: a pinned entry with `kind: remoteSourceControl` and a version.

---

### Task 3: Build and verify

**Step 1: Build with code signing disabled (for local testing)**

```bash
xcodebuild -project Lolgato.xcodeproj -scheme Lolgato -configuration Debug \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 4: Commit

**Step 1: Stage and commit**

```bash
git add Lolgato.xcodeproj/project.pbxproj \
        Lolgato.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "switch KeyboardShortcuts from local path to remote SPM reference"
```
