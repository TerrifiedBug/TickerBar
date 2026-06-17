# Plan 001: Add CI that builds and tests on every PR and push

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c0c912e..HEAD -- .github/workflows/ .gitignore TickerBar.xcodeproj/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `c0c912e`, 2026-06-17

## Why this matters

The repo has a full XCTest suite (`TickerBarTests/StockServiceTests.swift`, `TickerBarTests/StockItemTests.swift` — 308 LOC of tests covering `parseQuoteResponse`, `mergedStocks`, `isMarketOpen`, etc.) but **nothing ever runs it**. The only workflow, `.github/workflows/release.yml`, triggers exclusively on `push: tags: ['v*']` and runs only build/codesign/package steps — no `xcodebuild test`. PR #2 merged with zero checks. This plan adds a CI workflow that builds and runs the test suite on every pull request and on pushes to `master`, so regressions are caught before merge. As a prerequisite, it also commits a **shared** Xcode scheme so `xcodebuild -scheme TickerBar` resolves on a clean checkout (today the only scheme lives in gitignored `xcuserdata/`, so CI on a fresh clone could fail to find the scheme). This is the unblocker plan — run it before any other plan that relies on CI feedback.

## Current state

Relevant files and facts, inlined:

- `.github/workflows/release.yml` — the ONLY workflow. Triggers and runner (lines 1–13):
  ```yaml
  name: Release
  on:
    push:
      tags:
        - 'v*'
  permissions:
    contents: write
  jobs:
    build:
      runs-on: macos-latest
  ```
  It floats on `macos-latest` and never selects an Xcode version explicitly. Its build invocation (lines 26–31) is the reference for the build command:
  ```yaml
  xcodebuild -project TickerBar.xcodeproj \
    -scheme TickerBar \
    -configuration Release \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="-"
  ```
  There is **no** `.github/workflows/ci.yml` (confirmed: `ls .github/workflows/` shows only `release.yml`).

- `.gitignore` (full contents — 16 lines):
  ```gitignore
  # Xcode
  build/
  *.xcodeproj/xcuserdata/
  *.xcodeproj/project.xcworkspace/xcuserdata/
  DerivedData/
  *.hmap
  *.ipa
  *.dSYM.zip
  *.dSYM
  # macOS
  .DS_Store
  # Internal docs
  docs/
  ```
  Note line 3 ignores `*.xcodeproj/xcuserdata/` (the user scheme), but does **not** ignore `xcshareddata/` — so a shared scheme at `TickerBar.xcodeproj/xcshareddata/xcschemes/` is NOT gitignored and can be committed as-is. Do not add a broad `*.xcodeproj/*` rule.

- Scheme situation: `TickerBar.xcodeproj/xcshareddata/` does **not exist** (no shared scheme). The only scheme reference is the gitignored `TickerBar.xcodeproj/xcuserdata/danny.xcuserdatad/xcschemes/xcschememanagement.plist`, which lists a `TickerBar.xcscheme_^#shared#^_` entry but the actual `.xcscheme` file is absent from the repo. A clean checkout therefore has no `TickerBar` scheme on disk.

- `TickerBar.xcodeproj/project.pbxproj` — source of truth for the project (the `project.yml` XcodeGen spec is stale/broken; do NOT use or regenerate from it). Verified blueprint identifiers and product names needed to hand-author a scheme:
  - App target `TickerBar`: BlueprintIdentifier `9ACD20D2C97100CD8A5C346E`, BuildableName `TickerBar.app`, BlueprintName `TickerBar`, productType `com.apple.product-type.application` (pbxproj lines 145–164).
  - Test target `TickerBarTests`: BlueprintIdentifier `173B8A840F887241D737ABE4`, BuildableName `TickerBarTests.xctest`, BlueprintName `TickerBarTests`, productType `com.apple.product-type.bundle.unit-test` (pbxproj lines 127–144). It depends on the app target (line 136).
  - Container: `TickerBar.xcodeproj`.
  - `MACOSX_DEPLOYMENT_TARGET = 14.0`, `SWIFT_VERSION = 6.0` (pbxproj lines 306/314).

- Test files that must be exercised by the scheme's Test action (confirmed present): `TickerBarTests/StockServiceTests.swift`, `TickerBarTests/StockItemTests.swift`.

- Single SPM dependency: Sparkle 2.8.1 (resolved in `TickerBar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`). CI must resolve packages; caching `~/Library/Developer/Xcode/DerivedData` and the SPM cache speeds this up.

- Conventions: there is no SwiftLint/swift-format/editorconfig and no CI other than `release.yml`. Match the existing YAML style of `release.yml` (2-space indent, `actions/checkout@v4`).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build (local sanity) | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` | ends with `** BUILD SUCCEEDED **`, exit 0 |
| Test (local sanity) | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` | ends with `** TEST SUCCEEDED **`, exit 0 |
| List schemes | `xcodebuild -project TickerBar.xcodeproj -list` | `Schemes:` block includes `TickerBar` |
| YAML lint (if available) | `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))"` | exit 0, no output |
| Git status | `git status --porcelain` | only in-scope paths listed |

Note: these `xcodebuild` commands require macOS + Xcode. If this executor environment is not macOS or has no Xcode, you can still author the files, but you cannot run the build/test verifications locally — see STOP conditions.

## Scope

**In scope** (the only files you should create/modify):
- `.github/workflows/ci.yml` (create)
- `TickerBar.xcodeproj/xcshareddata/xcschemes/TickerBar.xcscheme` (create — the shared scheme)
- `.gitignore` (modify ONLY if it is found to exclude `xcshareddata` — see Step 1; per Current state it does not, so likely no change)
- `plans/README.md` (update status row; create if absent)

**Out of scope** (do NOT touch):
- `.github/workflows/release.yml` — the release pipeline. Do not change its triggers, runner, or steps in this plan; a separate plan may later pin its runner/Xcode. Touching it here risks breaking releases.
- `project.yml` — stale/broken XcodeGen spec. Do NOT use it to regenerate the project or scheme. The committed `project.pbxproj` is the source of truth.
- `TickerBar.xcodeproj/project.pbxproj` — do NOT edit; the targets already exist. You only add a scheme file alongside it.
- Any source under `TickerBar/` or test under `TickerBarTests/` — no code changes in this plan.

## Git workflow

- Branch: `ci/001-add-ci-build-test`
- Commit per logical unit (one for the scheme, one for the workflow is fine, or a single commit). Imperative subject matching `git log` style (e.g. existing commits: "Fix dropdown empty space...", "Update appcast.xml..."). Example for this work: `Add CI workflow and shared Xcode scheme`.
- Do NOT add any "Co-Authored-By" line, "Generated with Claude Code", or any AI attribution anywhere in commits or PR.
- Do NOT push or open a PR unless the operator explicitly instructs it.

## Steps

### Step 1: Create the branch and confirm `.gitignore` does not exclude the shared scheme

Create the worktree/branch off the planned base:
```bash
git fetch origin
git worktree add ../macos-stock-ticker-worktrees/001-add-ci-build-test -b ci/001-add-ci-build-test origin/master
```
(If worktrees are not in use here, a plain `git checkout -b ci/001-add-ci-build-test` is acceptable.)

Confirm `.gitignore` will not block the new shared scheme. Run:
```bash
grep -nE 'xcshareddata' .gitignore || echo "NO xcshareddata rule — good"
```
Expected: prints `NO xcshareddata rule — good`. If a rule matching `xcshareddata` IS present, remove only that line (it must not exclude `xcshareddata`), then re-run the grep.

**Verify**: `git check-ignore -v TickerBar.xcodeproj/xcshareddata/xcschemes/TickerBar.xcscheme; echo "exit=$?"` → prints `exit=1` (path is NOT ignored). If it prints `exit=0`, a gitignore rule still matches — fix `.gitignore` before continuing.

### Step 2: Create the shared Xcode scheme

Preferred (GUI available): open the project in Xcode, Product → Scheme → Manage Schemes, tick **Shared** for the `TickerBar` scheme, ensure its **Test** action lists the `TickerBarTests` target. Then verify the file landed at `TickerBar.xcodeproj/xcshareddata/xcschemes/TickerBar.xcscheme`.

Fallback (no GUI — hand-author the file). Create `TickerBar.xcodeproj/xcshareddata/xcschemes/TickerBar.xcscheme` with exactly this content (blueprint identifiers verified against `project.pbxproj`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "9ACD20D2C97100CD8A5C346E"
               BuildableName = "TickerBar.app"
               BlueprintName = "TickerBar"
               ReferencedContainer = "container:TickerBar.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "173B8A840F887241D737ABE4"
               BuildableName = "TickerBarTests.xctest"
               BlueprintName = "TickerBarTests"
               ReferencedContainer = "container:TickerBar.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "9ACD20D2C97100CD8A5C346E"
            BuildableName = "TickerBar.app"
            BlueprintName = "TickerBar"
            ReferencedContainer = "container:TickerBar.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "9ACD20D2C97100CD8A5C346E"
            BuildableName = "TickerBar.app"
            BlueprintName = "TickerBar"
            ReferencedContainer = "container:TickerBar.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

**Verify**: `xcodebuild -project TickerBar.xcodeproj -list` → the `Schemes:` block includes `TickerBar`. Then `git check-ignore TickerBar.xcodeproj/xcshareddata/xcschemes/TickerBar.xcscheme; echo "exit=$?"` → `exit=1` (committable). If `xcodebuild` is unavailable in this environment, skip the `-list` check and rely on the workflow run instead (see STOP conditions).

### Step 3: Confirm the test action resolves and the suite runs locally

If macOS + Xcode are available, run the test command the CI will use:
```bash
xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test
```

**Verify**: output ends with `** TEST SUCCEEDED **` and includes test cases from `StockServiceTests` and `StockItemTests`. If the Test action cannot be resolved (error like "scheme ... is not currently configured for the test action" or no testables), this is a STOP condition — see STOP conditions.

### Step 4: Create the CI workflow

Create `.github/workflows/ci.yml` with this content (pins runner to `macos-15`, selects Xcode explicitly via `maxim-lobanov/setup-xcode@v1`, caches SPM/DerivedData, runs build then test). Match the 2-space YAML style of `release.yml`:

```yaml
name: CI

on:
  pull_request:
  push:
    branches:
      - master

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '16.2'

      - name: Cache SwiftPM
        uses: actions/cache@v4
        with:
          path: |
            ~/Library/Developer/Xcode/DerivedData/**/SourcePackages
            ~/Library/Caches/org.swift.swiftpm
          key: ${{ runner.os }}-spm-${{ hashFiles('TickerBar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved') }}
          restore-keys: |
            ${{ runner.os }}-spm-

      - name: Resolve packages
        run: |
          xcodebuild -project TickerBar.xcodeproj \
            -scheme TickerBar \
            -resolvePackageDependencies

      - name: Build
        run: |
          xcodebuild -project TickerBar.xcodeproj \
            -scheme TickerBar \
            -configuration Release \
            -destination 'platform=macOS' \
            CODE_SIGN_IDENTITY="-" \
            build

      - name: Test
        run: |
          xcodebuild -project TickerBar.xcodeproj \
            -scheme TickerBar \
            -destination 'platform=macOS' \
            CODE_SIGN_IDENTITY="-" \
            test
```

Notes for the executor:
- `macos-15` and Xcode `16.2` are pinned for reproducibility (release.yml floats on `macos-latest` — do not change release.yml here). `16.2` is a stable Xcode that ships Swift 6 toolchain on the `macos-15` image. If the workflow run fails at "Select Xcode" because `16.2` is unavailable on the image, that is a STOP condition (report so the version can be adjusted) — do not silently switch to `macos-latest` or remove the pin.
- `CODE_SIGN_IDENTITY="-"` mirrors release.yml so signing does not block CI.

**Verify**: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); print('ok')"` → prints `ok` (valid YAML). If `python3`/`pyyaml` is unavailable, run `cat .github/workflows/ci.yml` and visually confirm it matches the block above.

### Step 5: Update the plans index

If `plans/README.md` does not exist, create it using the index format from the template with a single row for this plan. If it exists, set this plan's row Status to `DONE`.

Minimal `plans/README.md` if creating new:
```markdown
# Implementation Plans

## Execution order & status

| Plan | Title | Priority | Effort | Depends on | Status |
|------|-------|----------|--------|------------|--------|
| 001  | Add CI that builds and tests on every PR and push | P1 | S | — | DONE |
```

**Verify**: `grep -n '001' plans/README.md` → shows the row with `DONE`.

### Step 6: Final status check

**Verify**: `git status --porcelain` → lists ONLY in-scope paths: `.github/workflows/ci.yml`, `TickerBar.xcodeproj/xcshareddata/xcschemes/TickerBar.xcscheme`, `plans/README.md` (and `.gitignore` only if Step 1 required an edit). No source files, no `release.yml`, no `project.pbxproj`.

## Test plan

This plan adds no Swift code, so there are no new XCTest cases to write. The "test" being added is the CI automation that runs the **existing** suite (`TickerBarTests/StockServiceTests.swift`, `TickerBarTests/StockItemTests.swift`).

Verification of the automation:
- Local (if macOS/Xcode present): `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`, with cases from both test files appearing in output.
- CI: once the branch is pushed (only when the operator instructs a push), the `CI / build-test` check on the PR completes green, and its log shows the Test step running `StockServiceTests` and `StockItemTests`.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `.github/workflows/ci.yml` exists and is valid YAML (`python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` exits 0)
- [ ] `ci.yml` triggers on `pull_request` and `push` to `master`, and contains a step invoking `xcodebuild ... test` with `-destination 'platform=macOS'` (`grep -q "test" .github/workflows/ci.yml` and `grep -q "platform=macOS" .github/workflows/ci.yml`)
- [ ] `ci.yml` pins the runner (`grep -q "runs-on: macos-15" .github/workflows/ci.yml`) and selects Xcode explicitly (`grep -q "setup-xcode" .github/workflows/ci.yml`)
- [ ] Shared scheme exists at `TickerBar.xcodeproj/xcshareddata/xcschemes/TickerBar.xcscheme` and is committable (`git check-ignore TickerBar.xcodeproj/xcshareddata/xcschemes/TickerBar.xcscheme` exits 1)
- [ ] `xcodebuild -project TickerBar.xcodeproj -list` lists `TickerBar` under Schemes (skip only if no Xcode available — then verified via CI run)
- [ ] `release.yml` is unchanged (`git diff c0c912e..HEAD -- .github/workflows/release.yml` is empty)
- [ ] `project.pbxproj` is unchanged (`git diff c0c912e..HEAD -- TickerBar.xcodeproj/project.pbxproj` is empty)
- [ ] `git status --porcelain` shows only in-scope paths
- [ ] `plans/README.md` row for plan 001 is `DONE`

## STOP conditions

Stop and report back (do not improvise) if:

- The drift check shows any in-scope file changed since `c0c912e` and the live code no longer matches the "Current state" excerpts (e.g. `release.yml` triggers/runner differ, or a shared scheme already exists, or the pbxproj blueprint identifiers `9ACD20D2C97100CD8A5C346E` / `173B8A840F887241D737ABE4` no longer match).
- The hand-authored scheme's Test action cannot be resolved — `xcodebuild ... test` reports the scheme is not configured for testing, or `xcodebuild -list` does not show `TickerBar`. (Likely a blueprint-identifier mismatch; report the actual identifiers from `project.pbxproj`.)
- This executor environment is not macOS or has no Xcode, so the local build/test verifications in Steps 2–3 cannot run. Author the files, then STOP and report that local verification was skipped and CI must confirm green before merge.
- The `build` or `test` step requires touching `project.pbxproj`, `release.yml`, `project.yml`, or any source file to pass — that is out of scope.
- A verification command fails twice after a reasonable fix attempt.

## Maintenance notes

For whoever owns CI after this lands:

- The shared scheme's `BlueprintIdentifier` values are tied to `project.pbxproj`. If targets are recreated/renamed (or the project is ever regenerated from the broken `project.yml`), those IDs change and `TickerBar.xcscheme` must be regenerated, or CI's scheme resolution breaks. Note: the stale `project.yml` is known-broken — do not regenerate from it without fixing it first.
- Xcode is pinned to `16.2` on `macos-15`. When GitHub deprecates the `macos-15` image or that Xcode version, bump both the `runs-on` and `setup-xcode` `xcode-version` together, and confirm Swift 6 strict-concurrency still builds.
- `release.yml` still floats on `macos-latest` and does not run tests — a deliberately out-of-scope follow-up. Consider a later plan to pin release.yml's runner/Xcode to match CI and add a test gate before packaging.
- A reviewer should scrutinize: (1) that `ci.yml` triggers actually fire on PRs (check the PR shows a `CI / build-test` check), (2) that the cache key is keyed on `Package.resolved` so Sparkle resolution is cached but invalidated on dependency bumps, (3) that no AI attribution appears in the commit/PR.

Files referenced (all absolute):
- `/Users/danny/VSCode/workspace/macos-stock-ticker/.github/workflows/ci.yml` (to create)
- `/Users/danny/VSCode/workspace/macos-stock-ticker/TickerBar.xcodeproj/xcshareddata/xcschemes/TickerBar.xcscheme` (to create)
- `/Users/danny/VSCode/workspace/macos-stock-ticker/.github/workflows/release.yml` (reference only, out of scope)
- `/Users/danny/VSCode/workspace/macos-stock-ticker/.gitignore`
- `/Users/danny/VSCode/workspace/macos-stock-ticker/TickerBar.xcodeproj/project.pbxproj` (reference only, out of scope)
- `/Users/danny/VSCode/workspace/macos-stock-ticker/plans/README.md` (to create/update)
