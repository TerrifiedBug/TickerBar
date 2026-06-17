# Plan 002: Add the MIT LICENSE file the README already claims

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c0c912e..HEAD -- README.md LICENSE LICENSE.md COPYING`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: docs
- **Planned at**: commit `c0c912e`, 2026-06-17

## Why this matters

`README.md` declares the project's license as "MIT", but no `LICENSE`, `LICENSE.md`, or `COPYING` file exists anywhere in the repository. Under copyright law, source published without an accompanying license file is **all-rights-reserved by default** — the README text alone does not grant anyone the rights an MIT license conveys. TickerBar is distributed publicly via a Homebrew tap, GitHub releases, and a Sparkle update feed, so downstream users and packagers currently have no legally effective grant to use, copy, modify, or redistribute it. Adding the standard MIT license text closes this gap, makes the README's claim true, and lets GitHub auto-detect and display the license.

## Current state

- `README.md` — top-level project readme. Contains a `## License` section that names MIT but points to no file:

  `README.md:69-71`:
  ```
  ## License

  MIT
  ```

- No license file exists. Confirmed during planning: there is no `LICENSE`, `LICENSE.md`, `LICENSE.txt`, or `COPYING` at the repo root. The executor must create one.

- **Copyright holder / year**: The repository owner's GitHub handle is `TerrifiedBug` (see clone URLs and Homebrew tap in `README.md:27` and `README.md:46`). No real legal name is published in the repo. Per the STOP condition below, use `TerrifiedBug` as the copyright holder and `2026` as the year unless a more authoritative value is explicitly provided to you.

- **Conventions**: This repo has no contributing/license tooling. The MIT text below is the canonical OSI/SPDX MIT template verbatim — do not paraphrase, reflow, or add clauses. GitHub's license detector and SPDX matchers require the text to match the standard template exactly.

## Commands you will need

| Purpose            | Command                                              | Expected on success                          |
|--------------------|-----------------------------------------------------|----------------------------------------------|
| Confirm no license | `ls LICENSE LICENSE.md LICENSE.txt COPYING 2>/dev/null` | no output (no such files)                 |
| View new file      | `cat LICENSE`                                        | MIT text with correct holder/year            |
| First line check   | `head -1 LICENSE`                                    | `MIT License`                                 |
| Copyright check    | `grep -n "Copyright (c) 2026 TerrifiedBug" LICENSE`  | one matching line                            |
| Status check       | `git status --porcelain`                             | only in-scope files listed                    |

(Exact commands for this repo. There is no build/test step required for this docs-only change; the Swift build/test commands are intentionally not part of this plan.)

## Scope

**In scope** (the only files you should create or modify):
- `LICENSE` (create — root of the repo)
- `README.md` (modify — optional link to the LICENSE file, Step 2 only)

**Out of scope** (do NOT touch, even though they look related):
- `appcast.xml`, `.github/workflows/release.yml`, the Homebrew tap repo — license distribution metadata is a separate concern; do not edit them here.
- Any Swift source under `TickerBar/`, tests under `TickerBarTests/`, the Xcode project, or `Info.plist` — adding a license file requires no code changes.
- `LICENSE.md` / `COPYING` — create exactly one file named `LICENSE` (no extension); do not create alternate-named duplicates.

## Git workflow

- Branch: `chore/002-add-license`
- One commit for the whole change. Message subject in imperative style matching `git log` (e.g. `Add MIT LICENSE file`). Example existing subjects: `Fix dropdown empty space after collapsing Settings`, `Update appcast.xml for v1.2.2`.
- Do NOT add `Co-Authored-By`, `Generated with Claude Code`, or any AI attribution anywhere in the commit message.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Create the `LICENSE` file with the standard MIT text

Create a file named exactly `LICENSE` (no extension) at the repository root with the following content, verbatim. Use `TerrifiedBug` as the copyright holder and `2026` as the year (see STOP conditions if you have reason to believe a different holder/year is intended):

```
MIT License

Copyright (c) 2026 TerrifiedBug

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

**Verify**: `head -1 LICENSE` → `MIT License` AND `grep -c "Copyright (c) 2026 TerrifiedBug" LICENSE` → `1`

### Step 2: (Optional) Link the LICENSE from the README

This step is optional polish; do it only if it can be done without altering the meaning of the existing section. In `README.md`, replace the bare `MIT` line in the `## License` section so it links to the new file. Change:

```
## License

MIT
```

to:

```
## License

This project is licensed under the [MIT License](LICENSE).
```

Do not change any other line in `README.md`.

**Verify**: `grep -n "MIT License](LICENSE)" README.md` → one matching line (line ~71). If you skipped this optional step, instead confirm the section is unchanged: `grep -nA2 "## License" README.md` → still shows `MIT`.

### Step 3: Confirm scope is clean

**Verify**: `git status --porcelain` → lists only `LICENSE` (new file) and, if Step 2 was done, `README.md` (modified). No other paths.

## Test plan

This is a documentation/legal-file change with no executable behavior, so there are no unit tests to add. Verification is by file-content inspection:

- `head -1 LICENSE` is exactly `MIT License`.
- The copyright line reads `Copyright (c) 2026 TerrifiedBug`.
- The body matches the canonical MIT template verbatim (three paragraphs after the copyright line: the permission grant, the inclusion clause, the all-caps warranty disclaimer).
- `git status` shows no out-of-scope files modified.

Verification command bundle: `head -1 LICENSE && grep -c "Copyright (c) 2026 TerrifiedBug" LICENSE && git status --porcelain` → `MIT License`, then `1`, then only the in-scope files.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `LICENSE` exists at the repo root: `test -f LICENSE && echo OK` → `OK`
- [ ] `head -1 LICENSE` → `MIT License`
- [ ] `grep -c "Copyright (c) 2026 TerrifiedBug" LICENSE` → `1` (or the explicitly-confirmed alternative holder/year)
- [ ] The warranty disclaimer is present: `grep -c "THE SOFTWARE IS PROVIDED \"AS IS\"" LICENSE` → `1`
- [ ] No files outside the in-scope list are modified: `git status --porcelain` lists only `LICENSE` and optionally `README.md`
- [ ] `plans/README.md` status row for plan 002 updated (if a `plans/README.md` index exists in the repo)

## STOP conditions

Stop and report back (do not improvise) if:

- The drift check shows `README.md` no longer matches the `## License` / `MIT` excerpt in "Current state" (the readme changed since this plan was written), OR a `LICENSE`/`LICENSE.md`/`COPYING` file already exists — in either case the situation has changed and the right action may differ.
- You have positive reason to believe the intended copyright holder is a real legal name or organization other than `TerrifiedBug`, or the intended year is not `2026`. Do NOT guess a legal name. Create the file with `TerrifiedBug` + `2026`, then report this for human review rather than inventing a value.
- README declares a license other than MIT when you re-read it (the "MIT" claim has changed) — the license text you add must match what the project actually intends.
- A verification command fails twice after a reasonable fix attempt.

## Maintenance notes

For the human/agent who owns this code after the change lands:

- A reviewer should confirm (a) the copyright holder/year are acceptable — `TerrifiedBug` + `2026` were used as the default because no legal name is published in the repo; substitute a real name/org if the owner prefers, and (b) the MIT text is the unmodified canonical template (GitHub's license detector and SPDX scanners depend on an exact match).
- After this merges, GitHub should display "MIT License" in the repo sidebar; the Homebrew formula and any release metadata can optionally reference `MIT` as the SPDX identifier — that is deliberately deferred and out of scope here.
- If the project ever relicenses or adds third-party code with its own license terms (note: it bundles Sparkle 2.8.1, which is itself MIT-licensed — compatible), revisit this file and consider adding a `THIRD-PARTY-LICENSES` / NOTICE file for Sparkle's attribution.
