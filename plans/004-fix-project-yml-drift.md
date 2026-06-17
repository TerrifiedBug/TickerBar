# Plan 004: Resolve project.yml drift — delete the stale XcodeGen spec

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c0c912e..HEAD -- project.yml README.md .github/workflows/release.yml TickerBar.xcodeproj/project.pbxproj`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `c0c912e`, 2026-06-17

## Why this matters

`project.yml` is a stale XcodeGen spec that no longer describes the real app. It names the target, sources, and `PRODUCT_NAME` "StockTicker", uses bundle id `com.stockticker.app`, points `INFOPLIST_FILE`/`CODE_SIGN_ENTITLEMENTS` at a `StockTicker/` directory that does not exist, and declares **no Sparkle package**. The actual project (`TickerBar.xcodeproj/project.pbxproj`) is the hand-maintained source of truth: target/product `TickerBar`, bundle ids `com.tickerbar.app` / `com.tickerbar.tests`, paths under `TickerBar/`, and a linked Sparkle SPM dependency. `xcodegen` is installed locally (`/opt/homebrew/bin/xcodegen`), so anyone running `xcodegen generate` would silently overwrite the working `.xcodeproj` with a broken, Sparkle-less one — breaking auto-update and the release build. Nothing in the repo (README, CI) actually invokes XcodeGen, so the spec has zero value and pure downside. Deleting it removes the footgun and the README will state plainly that `TickerBar.xcodeproj` is hand-maintained.

## Current state

Files involved:

- `project.yml` — stale XcodeGen spec to be deleted. It describes a project that does not exist.
- `TickerBar.xcodeproj/project.pbxproj` — the real, hand-maintained project (source of truth). Do not modify; only read to confirm facts.
- `README.md` — "Build from Source" section to be amended.
- `.github/workflows/release.yml` — release CI; confirmed to NOT invoke xcodegen.
- `.claude/settings.local.json` — contains two `xcodegen` permission allowlist entries; left as-is (see Out of scope).

`project.yml` as it exists today (`project.yml:1-23`):

```yaml
name: StockTicker
options:
  bundleIdPrefix: com.stockticker
  ...
targets:
  StockTicker:
    type: application
    platform: macOS
    sources:
      - StockTicker
    settings:
      base:
        INFOPLIST_FILE: StockTicker/Info.plist
        CODE_SIGN_ENTITLEMENTS: StockTicker/StockTicker.entitlements
        PRODUCT_BUNDLE_IDENTIFIER: com.stockticker.app
        PRODUCT_NAME: StockTicker
```

The real project disagrees on every one of those values (`TickerBar.xcodeproj/project.pbxproj`):

```
:347  PRODUCT_BUNDLE_IDENTIFIER = com.tickerbar.app;
:348  PRODUCT_NAME = TickerBar;
:339  CODE_SIGN_ENTITLEMENTS = TickerBar/TickerBar.entitlements;
:342  INFOPLIST_FILE = TickerBar/Info.plist;
:382  PRODUCT_BUNDLE_IDENTIFIER = com.tickerbar.tests;
:479  repositoryURL = "https://github.com/sparkle-project/Sparkle";
:481  kind = upToNextMajorVersion;
:482  minimumVersion = 2.5.0;
```

`project.yml` declares no `packages:` / Sparkle block at all, so a regenerated project would not link Sparkle.

The `StockTicker/` directory the spec points at does not exist; the real sources live under `TickerBar/` (`TickerBar/TickerBarApp.swift`, `TickerBar/Models/`, `TickerBar/Services/`, `TickerBar/Views/`, `TickerBar/Info.plist`, `TickerBar/TickerBar.entitlements`).

README "Build from Source" section as it exists today (`README.md:41-51`):

```
## Build from Source

Requires Xcode 15+ and macOS 14+.

```bash
git clone https://github.com/TerrifiedBug/TickerBar.git
cd TickerBar
xcodebuild -scheme TickerBar -configuration Release build
```

The built app will be in `build/Build/Products/Release/TickerBar.app`.
```

`.github/workflows/release.yml` confirmed to invoke `xcodebuild -project TickerBar.xcodeproj` directly (lines 27, 49) and never `xcodegen` — the committed `.xcodeproj` is what CI builds.

Conventions: this repo has no SwiftLint/swift-format/editorconfig. Commit subjects are imperative and match `git log` style (e.g. "Fix dropdown empty space after collapsing Settings", "Update appcast.xml for v1.2.2"). No AI attribution anywhere.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat c0c912e..HEAD -- project.yml README.md .github/workflows/release.yml TickerBar.xcodeproj/project.pbxproj` | no output (no drift) |
| Delete file | `git rm project.yml` | `rm 'project.yml'`, exit 0 |
| Confirm no refs (source/docs/CI) | `grep -rn "project.yml" --include="*.md" --include="*.yml" --include="*.yaml" --include="*.sh" --include="*.json" .` | only `.claude/settings.local.json` matches (none expected after edit, but that file is unrelated — see below) |
| Confirm file gone | `test ! -e project.yml && echo GONE` | `GONE` |
| Build (Release) | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` | ends with `** BUILD SUCCEEDED **`, exit 0 |
| Working-tree check | `git status --porcelain` | only the three in-scope paths appear |

## Scope

**In scope** (the only files you should modify):
- `project.yml` (delete via `git rm`)
- `README.md` (amend "Build from Source" to name the hand-maintained `.xcodeproj`)
- `plans/README.md` (update this plan's status row, if that index exists)

**Out of scope** (do NOT touch, even though they look related):
- `TickerBar.xcodeproj/project.pbxproj` — the source of truth; this plan does not regenerate or edit it.
- `.github/workflows/release.yml` — already correct (builds the committed `.xcodeproj`); no change needed.
- `.claude/settings.local.json` — contains `Bash(xcodegen --version:*)` / `Bash(xcodegen --help:*)` permission entries (lines 12–13). These are local tool-permission allowlist entries, not references to the deleted file; leave them untouched.
- Creating a LICENSE file, adding CI test automation, or any other finding — separate plans.
- Rewriting `project.yml` to be correct — explicitly NOT this plan (see Maintenance notes).

## Git workflow

- Branch: `chore/004-fix-project-yml-drift`
- One commit is sufficient for this plan; message style imperative, matching `git log` (example subject: `Remove stale project.yml XcodeGen spec`). Body may explain the drift in one or two lines.
- Do NOT add any "Co-Authored-By" line, "Generated with Claude Code", or any AI attribution.
- Do NOT push or open a PR unless the operator explicitly instructed it.

## Steps

### Step 1: Create the branch

From the repo root (`/Users/danny/VSCode/workspace/macos-stock-ticker`):

```bash
git checkout -b chore/004-fix-project-yml-drift
```

**Verify**: `git rev-parse --abbrev-ref HEAD` → `chore/004-fix-project-yml-drift`

### Step 2: Run the drift check before changing anything

```bash
git diff --stat c0c912e..HEAD -- project.yml README.md .github/workflows/release.yml TickerBar.xcodeproj/project.pbxproj
```

**Verify**: no output. If any of these files changed since `c0c912e`, STOP (see STOP conditions) and re-confirm the "Current state" excerpts against the live files before continuing.

### Step 3: Delete `project.yml`

```bash
git rm project.yml
```

**Verify**: `test ! -e project.yml && echo GONE` → `GONE`

### Step 4: Update the README "Build from Source" section

Edit `README.md`. Immediately after the line `Requires Xcode 15+ and macOS 14+.` (currently `README.md:43`), add a sentence stating the project file is hand-maintained. The resulting section should read:

```
## Build from Source

Requires Xcode 15+ and macOS 14+.

`TickerBar.xcodeproj` is hand-maintained and committed to the repository — it is the source of truth for the build. (There is no project generator; do not run XcodeGen against this repo.)

```bash
git clone https://github.com/TerrifiedBug/TickerBar.git
cd TickerBar
xcodebuild -scheme TickerBar -configuration Release build
```

The built app will be in `build/Build/Products/Release/TickerBar.app`.
```

Do not change any other part of the README.

**Verify**: `grep -n "hand-maintained" README.md` → one match in the Build from Source section.

### Step 5: Confirm no real references to the deleted file remain

```bash
grep -rn "project.yml" --include="*.md" --include="*.yml" --include="*.yaml" --include="*.sh" --include="*.json" .
```

**Verify**: returns nothing. (Before this plan, the only matches were `.claude/settings.local.json:12-13`, which are `xcodegen --version`/`--help` permission entries that do NOT contain the string `project.yml` — so this grep should already return zero hits. If it returns any match, inspect it: a genuine reference to the deleted spec is a STOP condition; anything else, report it.)

### Step 6: Confirm the build still works from the committed `.xcodeproj`

```bash
xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build
```

**Verify**: output ends with `** BUILD SUCCEEDED **`, exit 0.

### Step 7: Commit

```bash
git add README.md
git commit -m "Remove stale project.yml XcodeGen spec"
```

(`project.yml` is already staged from `git rm` in Step 3.)

**Verify**: `git show --stat HEAD` shows exactly two paths changed: `project.yml` (deleted) and `README.md` (modified). The commit message has no AI attribution and no "Co-Authored-By" line.

## Test plan

No new code tests — this plan deletes a build-spec file and edits docs. The functional verification is the Release build:

- `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`. This proves the committed `.xcodeproj` (which links Sparkle) still builds without the deleted spec.
- Optionally run the existing test suite to confirm nothing regressed: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → all tests pass (`TickerBarTests/StockServiceTests.swift`, `TickerBarTests/StockItemTests.swift`). This is not strictly required since no source changed, but is a cheap safety net.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `test ! -e project.yml && echo GONE` prints `GONE`
- [ ] `grep -rn "project.yml" --include="*.md" --include="*.yml" --include="*.yaml" --include="*.sh" --include="*.json" .` returns no matches
- [ ] `grep -n "hand-maintained" README.md` returns one match
- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` ends with `** BUILD SUCCEEDED **` (exit 0)
- [ ] `git show --stat HEAD` shows only `project.yml` (deleted) and `README.md` (modified)
- [ ] `git status --porcelain` shows no unexpected modified files (only the committed changes, working tree otherwise clean)
- [ ] Commit message contains no "Co-Authored-By" and no AI-attribution text
- [ ] `plans/README.md` status row updated (if that index exists)

## STOP conditions

Stop and report back (do not improvise) if:

- The drift check in Step 2 shows any in-scope file changed since `c0c912e`, and the live content no longer matches the "Current state" excerpts.
- `git rm project.yml` fails because the file is already gone or already untracked — report; the spec may have been removed by another change.
- The grep in Step 5 finds a genuine reference to `project.yml` in a build script, README, or CI workflow (i.e. something actually depends on the spec) — deleting it could break that consumer; stop and report what references it.
- The Release build in Step 6 fails. (A clean working tree with only `project.yml` deleted should not affect the build, since CI and `xcodebuild` use `TickerBar.xcodeproj` directly. A failure means something else is wrong — report the error, do not attempt to "fix" by restoring the spec.)
- You find yourself needing to edit `TickerBar.xcodeproj/project.pbxproj` or any out-of-scope file to make a step pass.

## Maintenance notes

For the human/agent who owns this after the change lands:

- **Reviewer focus**: confirm the deletion does not break any local helper script or onboarding doc the reviewer knows about but that wasn't in the repo grep. Confirm the README wording correctly tells contributors not to run XcodeGen.
- **The `.claude/settings.local.json` xcodegen permission entries** (lines 12–13) are now vestigial. They are harmless local permission allowlist entries, not part of this plan's scope; a future cleanup may remove them, but they do not reference the deleted file and are not a build dependency.
- **Alternative, deferred — do NOT do unless the maintainer explicitly asks**: if the team later wants XcodeGen back as the project generator, do not resurrect this stale spec. Rewrite it from scratch to match `TickerBar.xcodeproj/project.pbxproj`:
  - target/sources/`PRODUCT_NAME` = `TickerBar`; tests target `TickerBarTests`
  - bundle ids `com.tickerbar.app` (app) and `com.tickerbar.tests` (tests)
  - `INFOPLIST_FILE: TickerBar/Info.plist`, `CODE_SIGN_ENTITLEMENTS: TickerBar/TickerBar.entitlements`, sources rooted at `TickerBar/`
  - add the Sparkle SPM package: `packages:` entry named `Sparkle`, url `https://github.com/sparkle-project/Sparkle`, `upToNextMajorVersion` from `2.5.0` (matching `project.pbxproj:479-482`), and link it to the `TickerBar` target
  - carry over the `SUFeedURL` and `SUPublicEDKey` Info.plist keys (present in `TickerBar/Info.plist:27,29`)
  - then run `xcodegen generate` in a throwaway branch and diff the result against the committed `project.pbxproj` before adopting it. Only switch the build over once the generated project links Sparkle and builds + signs identically.
