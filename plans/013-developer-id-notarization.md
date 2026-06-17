# Plan 013: Sign with Developer ID and notarize the release (decision required)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **THIS PLAN HAS A HARD PREREQUISITE THE EXECUTOR CANNOT SATISFY ALONE.** It
> requires a paid Apple Developer Program membership (~$99/yr), a Developer ID
> Application certificate exported as `.p12`, and several CI secrets that only
> the repository maintainer can provision. **Step 0 is a go/no-go gate. If the
> maintainer has not confirmed the prerequisite and added the secrets, STOP —
> this is a maintainer decision, not a code change.** Do not attempt to create
> an Apple account, generate certificates, or fabricate secret values.
>
> **Drift check (run first)**:
> `git diff --stat c0c912e..HEAD -- .github/workflows/release.yml TickerBar/TickerBar.entitlements TickerBar/Info.plist README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: HIGH
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `c0c912e`, 2026-06-17
- **Issue**: (none)

## Why this matters

The release workflow ships an **ad-hoc-signed, un-notarized** app. It builds
with `CODE_SIGN_IDENTITY="-"` and re-signs with `codesign --force --deep --sign -`
(the `-` identity means "ad-hoc", not a real team identity), and it never
notarizes or staples the bundle before publishing it to the GitHub release.
Consequently macOS Gatekeeper treats every download as untrusted: the README
tells users to right-click-Open or run `xattr -cr` to strip the quarantine flag
(README:37–39). Today the only integrity guarantees are Sparkle's EdDSA update
signature and the Homebrew cask's sha256 — neither is Apple's signing/notarization
chain, so a first-time user has no OS-level assurance the binary is authentic or
unmodified.

After this plan lands, the released `TickerBar.app` is signed with a **Developer
ID Application** certificate (a real team identity), notarized by Apple via
`xcrun notarytool submit --wait`, and stapled with `xcrun stapler staple`, so it
opens on a clean Mac with no Gatekeeper warning and no `xattr` workaround.
Sparkle EdDSA signing is **kept** as defence-in-depth. The deprecated `--deep`
flag is replaced with proper inside-out per-bundle signing of the nested Sparkle
code (XPC services + framework).

## Current state

In-scope files and their roles:

- `.github/workflows/release.yml` — the only CI workflow; runs on `v*` tags
  (lines 3–6). Contains the build, ad-hoc codesign, packaging, Sparkle signing,
  appcast, GitHub release, appcast commit, and Homebrew steps. This is where all
  signing/notarization changes go.
- `TickerBar/Info.plist` — bundle metadata + Sparkle keys. Already carries
  `SUPublicEDKey` and `SUFeedURL`; **not modified** by this plan, quoted only so
  the executor confirms Sparkle config is unrelated to signing.
- `TickerBar/TickerBar.entitlements` — App Sandbox entitlements. Read-only
  reference; sandbox + hardened-runtime interaction noted in Maintenance.
- `README.md` — documents the Gatekeeper workaround that this plan removes.

Exact current excerpts (verify these match before editing):

`.github/workflows/release.yml:25–41` — build, ad-hoc sign, package:

```yaml
      - name: Build Release
        run: |
          xcodebuild -project TickerBar.xcodeproj \
            -scheme TickerBar \
            -configuration Release \
            -derivedDataPath build \
            CODE_SIGN_IDENTITY="-"

      - name: Codesign app
        run: |
          codesign --force --deep --sign - \
            build/Build/Products/Release/TickerBar.app

      - name: Package app
        run: |
          cd build/Build/Products/Release
          zip -r -y TickerBar.zip TickerBar.app
```

`.github/workflows/release.yml:101–105` — release published with no notarization
between packaging and publishing:

```yaml
      - name: Create Release
        uses: softprops/action-gh-release@v2
        with:
          files: build/Build/Products/Release/TickerBar.zip
          body_path: release_notes.md
```

`.github/workflows/release.yml:8–9` — job permissions (unchanged):

```yaml
permissions:
  contents: write
```

`.github/workflows/release.yml:43–62` — the existing Sparkle signing step. It
reads the **already-built** zip at `build/Build/Products/Release/TickerBar.zip`.
**Critical ordering fact:** notarization + stapling must happen on the `.app`
**before** the zip is created, because stapling modifies the bundle. The current
order is Build (25) → ad-hoc sign (33) → zip (38) → Sparkle sign (43). The new
order must be Build → Developer ID sign → notarize → staple → zip → Sparkle sign,
so the Sparkle step keeps reading a zip of the already-stapled app.

`TickerBar/Info.plist:11–12, 27–30` (reference only — do NOT edit):

```xml
	<key>CFBundleIdentifier</key>
	<string>com.tickerbar.app</string>
...
	<key>SUPublicEDKey</key>
	<string>XSwbLtdr2wVhhFCaOV/FJuGEtpTngVBU098oOwazgtk=</string>
	<key>SUFeedURL</key>
	<string>https://raw.githubusercontent.com/TerrifiedBug/TickerBar/master/appcast.xml</string>
```

`TickerBar/TickerBar.entitlements:5–13` (reference only — do NOT edit):

```xml
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
    <array>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spks</string>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spki</string>
    </array>
```

`README.md:37–39` — the workaround text this plan removes:

```
3. On first launch, macOS may show a Gatekeeper warning since the app is not notarized:
   - Right-click the app and select **Open**, then click **Open** in the dialog
   - Or run `xattr -cr /Applications/TickerBar.app` in Terminal to remove the quarantine flag
```

Repo conventions that apply:
- YAML steps use the `- name: ...` + `run: |` block style already in the file —
  match it exactly (2-space indent, step names in Title Case).
- Single SPM dependency is Sparkle 2.8.1; its signing tools and nested code
  (XPC services `Updater.app`/`Autoupdate`, `org.sparkle-project.*.xpc`,
  `Sparkle.framework`) live inside `TickerBar.app/Contents/`.
- The workflow runs only on `v*` tags (lines 3–6). It cannot be exercised by a
  normal push; see Test plan for how to validate without cutting a real release.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat c0c912e..HEAD -- .github/workflows/release.yml TickerBar/TickerBar.entitlements TickerBar/Info.plist README.md` | empty output (no drift) |
| YAML lint (if available) | `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml'))"` | exit 0, no output |
| Workflow visible to GitHub | `gh workflow list` | `Release` appears in the list |
| List repo secrets | `gh secret list` | shows the required secret names (see Step 0) |
| Confirm no stray edits | `git status --porcelain` | only in-scope files listed |
| Local build sanity (optional, macOS only) | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` | `** BUILD SUCCEEDED **` |

## Suggested executor toolkit

- Apple notarization reference (read before editing the workflow):
  `xcrun notarytool --help` and `xcrun stapler --help` on the runner; Apple docs
  "Customizing the notarization workflow" and "Signing a daemon with a restricted
  entitlement".
- `codesign --display --verbose=4 <bundle>` and `spctl -a -vvv -t install <app>`
  to inspect signing/Gatekeeper status during the dry run.

## Scope

**In scope** (the only files you should modify):
- `.github/workflows/release.yml`
- `README.md` (remove the Gatekeeper workaround once notarization is in place)
- `plans/README.md` (status row update at the end)

**Out of scope** (do NOT touch, even though they look related):
- `TickerBar/Info.plist` — no signing config belongs here; CFBundleIdentifier and
  Sparkle keys are already correct. Touching it risks breaking the appcast feed.
- `TickerBar/TickerBar.entitlements` — sandbox/hardened-runtime entitlements are
  already valid for a notarized sandboxed app. Adding/removing entitlements is a
  separate decision with its own review.
- `TickerBar.xcodeproj/project.pbxproj` — do NOT change the project's signing
  settings; signing is driven from the workflow via `codesign` to keep the
  certificate out of the committed project. (`project.yml` is stale/broken —
  ignore it entirely.)
- The Sparkle EdDSA signing step (lines 43–62) — keep it as defence-in-depth;
  only its **position** in the file may move (after stapling), not its logic.
- Any change that disables App Sandbox.

## Git workflow

- Branch: `ci/013-developer-id-notarization`
- Commit per logical unit; imperative subjects matching `git log` style
  (e.g. "Add", "Fix", "Replace"). Example existing subject:
  `Fix dropdown empty space after collapsing Settings`.
- NO "Co-Authored-By", NO "Generated with Claude Code", no AI attribution
  anywhere in commits or PR text.
- Do NOT push or open a PR unless the operator explicitly instructs it.

## Steps

### Step 0: GO/NO-GO gate — confirm the Apple prerequisite and CI secrets exist

This step is a decision checkpoint, not a code change. The maintainer must have
provisioned, **before** any workflow edit:

1. A paid **Apple Developer Program** membership (~$99/yr).
2. A **Developer ID Application** certificate, exported (including its private
   key) as a `.p12` file, then base64-encoded.
3. The following repository secrets added via the GitHub UI or
   `gh secret set <NAME>` (REFERENCE BY NAME ONLY — never read, print, or embed
   the values):
   - `MACOS_CERTIFICATE` — base64 of the Developer ID Application `.p12`.
   - `MACOS_CERTIFICATE_PASSWORD` — password protecting the `.p12`.
   - `KEYCHAIN_PASSWORD` — an arbitrary password used to create a temporary
     keychain on the runner.
   - `APPLE_TEAM_ID` — the 10-character Apple Team ID (the signing identity
     suffix, e.g. shown as `Developer ID Application: Name (TEAMID)`).
   - For notarization, **either** an App Store Connect API key set:
     `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID`, `NOTARY_API_KEY_P8` (base64 of
     the `.p8`), **or** an Apple ID set: `NOTARY_APPLE_ID`,
     `NOTARY_PASSWORD` (an app-specific password), `NOTARY_TEAM_ID`. This plan
     uses the **App Store Connect API key** variant (more robust in CI); if the
     maintainer provisioned the Apple-ID variant instead, that is a STOP — report
     it so the plan can be adjusted.
   - (Existing, unchanged) `SPARKLE_PRIVATE_KEY`, `HOMEBREW_TAP_TOKEN`.

**Verify**: `gh secret list` lists `MACOS_CERTIFICATE`,
`MACOS_CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD`, `APPLE_TEAM_ID`,
`NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID`, `NOTARY_API_KEY_P8`,
`SPARKLE_PRIVATE_KEY`.
→ If **any** of those names is missing, **STOP** and report exactly which are
missing. Do not proceed to Step 1. Do not invent values.

### Step 1: Import the signing certificate into a temporary keychain

Insert a new step **after** the "Set version from tag" step and **before**
"Build Release" (currently line 25). It decodes the `.p12`, creates a throwaway
keychain, imports the cert, and exposes the signing identity name to later steps.
Match the existing YAML style.

Target shape:

```yaml
      - name: Import Developer ID certificate
        env:
          MACOS_CERTIFICATE: ${{ secrets.MACOS_CERTIFICATE }}
          MACOS_CERTIFICATE_PASSWORD: ${{ secrets.MACOS_CERTIFICATE_PASSWORD }}
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          CERT_PATH="$RUNNER_TEMP/certificate.p12"
          KEYCHAIN_PATH="$RUNNER_TEMP/app-signing.keychain-db"
          echo -n "$MACOS_CERTIFICATE" | base64 --decode -o "$CERT_PATH"
          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security import "$CERT_PATH" -P "$MACOS_CERTIFICATE_PASSWORD" \
            -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
          security set-key-partition-list -S apple-tool:,apple: \
            -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
          security list-keychain -d user -s "$KEYCHAIN_PATH" login.keychain-db
          SIGN_ID=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
            | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')
          echo "SIGN_IDENTITY=$SIGN_ID" >> "$GITHUB_ENV"
          echo "KEYCHAIN_PATH=$KEYCHAIN_PATH" >> "$GITHUB_ENV"
```

**Verify**: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"`
→ exit 0 (YAML still parses).

### Step 2: Build with the real signing identity instead of ad-hoc

Replace `CODE_SIGN_IDENTITY="-"` in the "Build Release" step (line 31) so
xcodebuild signs with the Developer ID identity and enables the hardened runtime
(required for notarization). Keep `CODE_SIGN_STYLE=Manual` so xcodebuild does not
try Automatic provisioning.

Replace the build `run:` block (lines 26–31) with:

```yaml
        run: |
          xcodebuild -project TickerBar.xcodeproj \
            -scheme TickerBar \
            -configuration Release \
            -derivedDataPath build \
            CODE_SIGN_STYLE=Manual \
            CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
            DEVELOPMENT_TEAM="${{ secrets.APPLE_TEAM_ID }}" \
            OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime"
```

**Verify**: `grep -c 'CODE_SIGN_IDENTITY="-"' .github/workflows/release.yml`
→ `0` (the ad-hoc identity is gone from the build step).

### Step 3: Replace `--deep` ad-hoc re-sign with inside-out Developer ID signing

Replace the "Codesign app" step (lines 33–36). `--deep` is deprecated and signs
nested code with the **same** flags as the outer bundle, which is wrong for
Sparkle's XPC services. Sign nested code first (frameworks, XPC services), then
the outer app, all with hardened runtime + secure timestamp. xcodebuild in Step 2
already signs most of this; this step is the authoritative re-sign that guarantees
the hardened runtime and timestamp on every nested Mach-O.

Target shape:

```yaml
      - name: Codesign app (Developer ID, hardened runtime)
        run: |
          APP="build/Build/Products/Release/TickerBar.app"
          # Sign nested code inside-out: deepest first, app bundle last.
          find "$APP/Contents" \
            \( -name "*.xpc" -o -name "*.app" -o -name "*.framework" \
               -o -name "*.dylib" \) -print0 \
            | sort -rz \
            | while IFS= read -r -d '' ITEM; do
                codesign --force --timestamp --options runtime \
                  --sign "$SIGN_IDENTITY" "$ITEM"
              done
          codesign --force --timestamp --options runtime \
            --entitlements TickerBar/TickerBar.entitlements \
            --sign "$SIGN_IDENTITY" "$APP"
          codesign --verify --deep --strict --verbose=2 "$APP"
```

**Verify**: `grep -c -- '--deep --sign -' .github/workflows/release.yml`
→ `0` (the deprecated ad-hoc deep-sign is gone).

### Step 4: Notarize and staple BEFORE packaging

Insert a new "Notarize and staple" step **after** the codesign step and **before**
the "Package app" step (current line 38). It zips a temporary copy for submission
(notarytool needs an archive), submits with `--wait`, then staples the original
`.app`. Stapling the bundle before the real zip is created is mandatory.

Target shape:

```yaml
      - name: Notarize and staple
        env:
          NOTARY_API_KEY_ID: ${{ secrets.NOTARY_API_KEY_ID }}
          NOTARY_API_ISSUER_ID: ${{ secrets.NOTARY_API_ISSUER_ID }}
          NOTARY_API_KEY_P8: ${{ secrets.NOTARY_API_KEY_P8 }}
        run: |
          APP="build/Build/Products/Release/TickerBar.app"
          KEY_PATH="$RUNNER_TEMP/AuthKey.p8"
          echo -n "$NOTARY_API_KEY_P8" | base64 --decode -o "$KEY_PATH"
          SUBMIT_ZIP="$RUNNER_TEMP/notarize.zip"
          ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
          xcrun notarytool submit "$SUBMIT_ZIP" \
            --key "$KEY_PATH" \
            --key-id "$NOTARY_API_KEY_ID" \
            --issuer "$NOTARY_API_ISSUER_ID" \
            --wait
          xcrun stapler staple "$APP"
          xcrun stapler validate "$APP"
```

Note: use `ditto -c -k --keepParent` (not `zip`) for the submission archive so
the bundle structure survives. The publishable zip is still produced by the
existing "Package app" step using `zip -r -y`.

**Verify**: `grep -c 'notarytool submit' .github/workflows/release.yml` → `1`
and `grep -c 'stapler staple' .github/workflows/release.yml` → `1`.

### Step 5: Confirm step ordering is build → sign → notarize → staple → zip → Sparkle

The "Package app" step (now after notarize/staple) must still produce
`build/Build/Products/Release/TickerBar.zip` from the stapled app, and the
existing "Sign update with Sparkle" step (lines 43–62) must remain **after**
packaging so it signs the stapled zip. Do not change Sparkle logic; only verify
position.

**Verify**: `grep -n -E 'name: (Build Release|Codesign app|Notarize and staple|Package app|Sign update with Sparkle)' .github/workflows/release.yml`
→ the five step names appear in exactly that source order (ascending line
numbers: Build Release < Codesign app < Notarize and staple < Package app < Sign
update with Sparkle).

### Step 6: Remove the Gatekeeper workaround from the README

Now that the released app is notarized + stapled, delete the workaround at
`README.md:37–39`. Replace the three lines with a single line confirming the app
is signed and notarized, e.g.:

```
3. The app is signed with an Apple Developer ID and notarized, so it opens normally — no right-click or `xattr` workaround needed.
```

**Verify**: `grep -c 'xattr -cr' README.md` → `0`.

### Step 7: Validate the workflow file end to end

**Verify**:
- `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"` → exit 0.
- `gh workflow list` → `Release` listed (file is still a valid workflow).
- `git status --porcelain` → only `.github/workflows/release.yml`, `README.md`
  (and later `plans/README.md`) appear.

## Test plan

This workflow only runs on `v*` tags and cannot be exercised by a normal push,
so validation is structural plus a controlled dry run:

1. **Static validation** (always): YAML parses (Step 1/7 verify), the ad-hoc
   patterns are gone (`grep` checks in Steps 2 and 3 return 0), and notarize +
   staple appear exactly once each (Step 4).
2. **Controlled dry run on a throwaway tag** (maintainer-run, after merge): push
   a pre-release tag such as `v0.0.0-notarize-test` to trigger the workflow on a
   branch/fork the maintainer controls, then confirm in the Actions log:
   - The "Import Developer ID certificate" step finds a
     `Developer ID Application` identity (non-empty `SIGN_IDENTITY`).
   - The "Notarize and staple" step prints `status: Accepted` from notarytool and
     `The validate action worked!` from `stapler validate`.
   - Download the produced `TickerBar.zip`, unzip on a clean Mac, and run
     `spctl -a -vvv -t install TickerBar.app` → `accepted` and
     `source=Notarized Developer ID`.
   Then delete the throwaway tag/release. **Do not** add this dry-run tag to the
   appcast.
3. No app source code or unit tests change, so the existing XCTest suite
   (`TickerBarTests/`) is unaffected and is not part of this plan's gating.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `grep -c 'CODE_SIGN_IDENTITY="-"' .github/workflows/release.yml` → `0`
- [ ] `grep -c -- '--deep --sign -' .github/workflows/release.yml` → `0`
- [ ] `grep -c 'Developer ID Application' .github/workflows/release.yml` → `>= 1`
- [ ] `grep -c 'notarytool submit' .github/workflows/release.yml` → `1`
- [ ] `grep -c 'stapler staple' .github/workflows/release.yml` → `1`
- [ ] `grep -c 'Sign update with Sparkle' .github/workflows/release.yml` → `1` (Sparkle EdDSA retained)
- [ ] `grep -c 'xattr -cr' README.md` → `0`
- [ ] `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"` exits 0
- [ ] Step ordering verify in Step 5 passes (build < codesign < notarize < package < sparkle)
- [ ] `git status --porcelain` shows only in-scope files modified
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- **Step 0 secrets are missing** — any of the required secret names is absent from
  `gh secret list`. This is the primary gate: signing/notarization is impossible
  and is a maintainer decision. Report exactly which secrets are missing.
- The maintainer provisioned the **Apple ID / app-specific password** notarization
  variant instead of the App Store Connect API key variant assumed by Step 4.
- The code at the locations in "Current state" doesn't match the excerpts (the
  workflow has drifted since this plan was written).
- The dry-run notarization returns `status: Invalid` — fetch the log with
  `xcrun notarytool log <submission-id> ...`; this usually means a nested binary
  lacks the hardened runtime or a secure timestamp. Do not weaken signing to make
  it pass; report the log.
- Fixing this appears to require editing `TickerBar.xcodeproj/project.pbxproj`,
  `Info.plist`, or `TickerBar.entitlements` (all out of scope).
- A step's verification fails twice after a reasonable fix attempt.

## Maintenance notes

For whoever owns the release pipeline after this lands:

- **Certificate expiry**: Developer ID Application certs are valid ~5 years. When
  it expires, re-export the new `.p12`, re-base64 it, and update the
  `MACOS_CERTIFICATE` / `MACOS_CERTIFICATE_PASSWORD` secrets. Notarization fails
  hard on an expired cert.
- **Apple ID app-specific password rotation**: if the maintainer later switches
  from the App Store Connect API key to the Apple ID variant, the notarize step
  (Step 4) must be rewritten to use `--apple-id/--password/--team-id`.
- **Sparkle + hardened runtime + sandbox**: the app keeps App Sandbox
  (`TickerBar.entitlements`) and now runs under the hardened runtime. Sparkle's
  XPC services (`*-spks`, `*-spki` mach-lookup exceptions in the entitlements)
  must each be Developer-ID-signed by the inside-out loop in Step 3. If a future
  Sparkle upgrade adds or renames nested XPC services, re-verify the `find`
  pattern in Step 3 still catches them (`codesign --verify --deep --strict` will
  fail the build if one is unsigned).
- **Reviewer focus**: confirm no secret values are echoed in workflow logs (the
  `security`/`base64` commands above never `echo` decoded secrets), confirm the
  notarize step runs strictly before packaging, and confirm the Sparkle EdDSA
  step still signs the final stapled zip.
- **Deferred out of this plan**: switching the build to produce a notarized `.dmg`
  instead of a `.zip`, and adding a `notarytool log` artifact upload on failure —
  both are nice-to-haves left for a follow-up.
```
