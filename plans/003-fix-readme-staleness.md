# Plan 003: Fix stale README: removed market-hours toggle and wrong build-output path

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c0c912e..HEAD -- README.md CHANGELOG.md .github/workflows/release.yml TickerBar/Views/SettingsView.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: docs
- **Planned at**: commit `c0c912e`, 2026-06-17

## Why this matters

`README.md` is the first thing a user or contributor reads, and two of its
statements are factually wrong for the shipped app. (1) It lists "Only refresh
during market hours" as a Settings toggle, but that toggle was removed in v1.1.1
("handled automatically" — see `CHANGELOG.md:55-56`) and does not exist in
`SettingsView.swift`. A user looking for it will be confused. (2) The "Build from
Source" instructions give a command whose stated output path does not exist: the
README's `xcodebuild ... build` invocation never writes to
`build/Build/Products/Release/TickerBar.app` because that relative path only
materializes when `-derivedDataPath build` is passed (as the CI does in
`release.yml:30`). A contributor following the README verbatim will build
successfully but find nothing at the documented location. Fixing both makes the
README match shipped behavior; this is a documentation-only change with no code
or test impact.

## Current state

The only file being modified is `README.md`. The other three files are read-only
evidence that the README is wrong — do not modify them.

- `README.md` — project README; contains both inaccuracies (Build section ~lines
  41-51, Settings list ~lines 53-63).
- `CHANGELOG.md` — read-only evidence the toggle was removed.
- `.github/workflows/release.yml` — read-only evidence of the correct build flags.
- `TickerBar/Views/SettingsView.swift` — read-only evidence the toggle UI is absent.

### Inaccuracy 1: non-existent "market hours" Settings toggle

`README.md:53-63` (the Settings list):

```
## Settings

Click the TickerBar menu bar item to open the watchlist, then click **Settings** to configure:

- Refresh interval (30s to 15 min)
- Stock rotation toggle and speed (3s to 1 min)
- Compact / normal menu bar display
- Show/hide percentage change
- Only refresh during market hours
- Launch at login
- Automatic update checking
```

Line 61 is the offending bullet: `- Only refresh during market hours`

Evidence it is wrong:

- `CHANGELOG.md:55-56` (v1.1.1 "Removed" section):
  ```
  ### Removed
  - "Only refresh during market hours" toggle — handled automatically
  ```
- `TickerBar/Views/SettingsView.swift` (the entire `body`, lines 13-145) contains
  toggles for "Rotate stocks in menu bar" (line 30), "Compact menu bar" (line 66),
  "Show % change in menu bar" (line 69), "Solid dropdown background" (line 89),
  "Launch at login" (line 105), and "Automatically check for updates" (line 133).
  There is **no** toggle bound to a market-hours setting anywhere in the file.

Decision: **remove the bullet** (line 61). This matches the shipped "handled
automatically" behavior and is the simplest fix. (Alternative, NOT chosen:
re-expose a SwiftUI `Toggle` in `SettingsView.swift` bound to
`service.marketHoursOnly`. Rejected because it expands a docs fix into a code +
test change and reverses a deliberate product decision recorded in the changelog.
If a maintainer later wants the toggle back, that is a separate `feat` plan.)

### Inaccuracy 2: build command missing `-derivedDataPath build`

`README.md:41-51` (the Build from Source section):

```
## Build from Source

Requires Xcode 15+ and macOS 14+.

\`\`\`bash
git clone https://github.com/TerrifiedBug/TickerBar.git
cd TickerBar
xcodebuild -scheme TickerBar -configuration Release build
\`\`\`

The built app will be in `build/Build/Products/Release/TickerBar.app`.
```

Line 48 is the offending command:
`xcodebuild -scheme TickerBar -configuration Release build`

Line 51 claims the output is at `build/Build/Products/Release/TickerBar.app`. That
path is **only** produced when `-derivedDataPath build` is supplied. Evidence —
`.github/workflows/release.yml:25-31` (the CI's working invocation), which is the
source of truth for how this repo builds and which produces exactly that path:

```yaml
      - name: Build Release
        run: |
          xcodebuild -project TickerBar.xcodeproj \
            -scheme TickerBar \
            -configuration Release \
            -derivedDataPath build \
            CODE_SIGN_IDENTITY="-"
```

Fix: add `-derivedDataPath build` to the README command so the stated output path
is real. (The CI also passes `-project TickerBar.xcodeproj` and
`CODE_SIGN_IDENTITY="-"`; `-project` is unnecessary when run from the repo root
with a single `.xcodeproj` present, and `CODE_SIGN_IDENTITY="-"` is a CI signing
concern, not needed for a local source build. Adding only `-derivedDataPath build`
is the minimal change that makes line 51 true and is what this plan does.)

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat c0c912e..HEAD -- README.md CHANGELOG.md .github/workflows/release.yml TickerBar/Views/SettingsView.swift` | empty output (no in-scope drift) |
| Confirm toggle bullet present before edit | `grep -n "Only refresh during market hours" README.md` | one match on line 61 |
| Confirm toggle bullet gone after edit | `grep -c "Only refresh during market hours" README.md` | `0` |
| Confirm build flag absent before edit | `grep -n "derivedDataPath" README.md` | no output (exit 1) |
| Confirm build flag present after edit | `grep -n "derivedDataPath build" README.md` | one match in the bash code block |
| Confirm only README changed | `git status --porcelain` | only ` M README.md` |

No build or test commands are required: this is a docs-only change to `README.md`,
which is not compiled or tested. (For reference, the app's build command is
`xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build`
and tests are `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test`, but neither is needed here.)

## Scope

**In scope** (the only file you should modify):
- `README.md`

**Out of scope** (do NOT touch, even though they look related):
- `TickerBar/Views/SettingsView.swift` — do NOT re-add a market-hours toggle; the
  decision is to remove the stale README bullet, not restore the feature.
- `CHANGELOG.md` — read-only evidence; no changelog entry is needed for a README
  accuracy fix (it documents app behavior, not docs typos).
- `.github/workflows/release.yml` — read-only evidence of correct build flags; the
  CI already works.
- Any other documentation under `docs/` or elsewhere — not part of this finding.

## Git workflow

- Branch: `docs/003-fix-readme-staleness` (created off `master` at the planned-at
  commit or later).
- Single commit for both edits. Message style: imperative subject matching
  `git log` (e.g. recent commits "Fix dropdown empty space after collapsing
  Settings", "Update appcast.xml for v1.2.2"). Suggested message:
  `Fix stale README: remove dropped market-hours toggle, correct build path`
- Do NOT add "Co-Authored-By", "Generated with Claude Code", or any AI attribution
  to the commit message or anywhere.
- Do NOT push or open a PR unless the operator explicitly instructs it.

## Steps

### Step 1: Create the working branch

From the repo root (`/Users/danny/VSCode/workspace/macos-stock-ticker`):

```bash
git checkout -b docs/003-fix-readme-staleness
```

**Verify**: `git rev-parse --abbrev-ref HEAD` → `docs/003-fix-readme-staleness`

### Step 2: Remove the stale "market hours" Settings bullet

In `README.md`, delete the entire line 61:

```
- Only refresh during market hours
```

Leave the surrounding bullets (lines 57-60 and 62-63) intact. After the edit the
Settings list should read, in order: Refresh interval; Stock rotation toggle and
speed; Compact / normal menu bar display; Show/hide percentage change; Launch at
login; Automatic update checking.

**Verify**: `grep -c "Only refresh during market hours" README.md` → `0`

### Step 3: Add `-derivedDataPath build` to the build command

In `README.md`, change line 48 from:

```
xcodebuild -scheme TickerBar -configuration Release build
```

to:

```
xcodebuild -scheme TickerBar -configuration Release -derivedDataPath build build
```

(The trailing `build` is the xcodebuild *action* and must remain last; the new
`-derivedDataPath build` flag goes before it. Do not change line 51's stated
output path — it is now correct.)

**Verify**: `grep -n "derivedDataPath build" README.md` → exactly one match inside
the bash code block (around line 48).

### Step 4: Confirm no other file changed

**Verify**: `git status --porcelain` → output is exactly ` M README.md` (only
README.md modified, nothing staged outside scope).

### Step 5: Commit

```bash
git add README.md
git commit -m "Fix stale README: remove dropped market-hours toggle, correct build path"
```

**Verify**: `git log -1 --pretty=%s` → `Fix stale README: remove dropped market-hours toggle, correct build path`
and `git log -1 --pretty=%b` contains no "Co-Authored-By" / "Generated with"
lines (expected: empty body).

## Test plan

No automated tests apply — `README.md` is documentation, not compiled or covered
by the XCTest suite under `TickerBarTests/`. Verification is the `grep`/`git`
checks in the Done criteria below.

Manual sanity check (optional, recommended): open `README.md` and read the
"Build from Source" and "Settings" sections to confirm they read naturally after
the edits (no dangling list item, no broken code fence).

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `grep -c "Only refresh during market hours" README.md` returns `0`
- [ ] `grep -n "derivedDataPath build" README.md` returns exactly one match
- [ ] `grep -c "build/Build/Products/Release/TickerBar.app" README.md` still returns `1` (the output-path line is preserved and now correct)
- [ ] `git status --porcelain` shows only ` M README.md` (no out-of-scope files modified)
- [ ] `git log -1 --pretty=%B` contains no "Co-Authored-By" and no "Generated with Claude Code" / AI attribution
- [ ] `plans/README.md` status row for plan 003 updated to DONE

## STOP conditions

Stop and report back (do not improvise) if:

- The drift check (`git diff --stat c0c912e..HEAD -- README.md ...`) shows
  `README.md` already changed AND the line 61 bullet or line 48 command no longer
  matches the "Current state" excerpts — the README may have been fixed already
  or restructured.
- The "Only refresh during market hours" bullet is NOT found in `README.md`
  (`grep` returns 0 matches before Step 2) — the fix may already be applied;
  report rather than guessing.
- `SettingsView.swift` is found to contain a market-hours toggle after all (search
  the file for any `Toggle` whose label mentions "market" or any binding named
  like `marketHoursOnly`) — the premise that the feature was removed would be
  false, which changes the correct fix (you would re-add the bullet, not remove
  it). Report this; do not proceed.
- Any step's verification fails twice after a reasonable fix attempt.

## Maintenance notes

For the human/agent who owns this after the change lands:

- If a maintainer later decides to restore a user-facing market-hours toggle, that
  is a separate `feat` plan touching `SettingsView.swift` (add a `Toggle` bound to
  `service.marketHoursOnly`, following the existing `Toggle` pattern at
  `SettingsView.swift:30/66/69/89`) and would re-add the README bullet removed here.
- If the build instructions are ever revisited, consider aligning the README
  command fully with CI (`.github/workflows/release.yml:25-31`), which also passes
  `-project TickerBar.xcodeproj` and `CODE_SIGN_IDENTITY="-"`. This plan
  deliberately added only `-derivedDataPath build` as the minimal fix that makes
  the stated output path correct.
- Reviewer should scrutinize: that the Settings bullet list still reads cleanly
  (no orphaned blank line) and that the xcodebuild action word `build` remains the
  final token on the command line (flags before actions).
