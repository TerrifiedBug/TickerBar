# Plan 018: Spike a WidgetKit widget that reuses the existing Yahoo fetch/parse

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c0c912e..HEAD -- TickerBar/Services/StockService.swift TickerBar/Models/StockItem.swift TickerBar/TickerBar.entitlements TickerBar/Info.plist TickerBar/TickerBarApp.swift TickerBar.xcodeproj/project.pbxproj`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: L
- **Risk**: MED
- **Depends on**: composes with `plans/008-*.md` (injected `UserDefaults`) if/when it lands — not a hard prerequisite; see "Current state". Otherwise none.
- **Category**: direction
- **Planned at**: commit `c0c912e`, 2026-06-17
- **Issue**: <omit>

## Why this matters

The product thesis is glanceability — README:15 promises users "see live prices at a glance without opening any app." A WidgetKit widget on the desktop / Notification Center extends that thesis beyond the menu bar at low marginal cost: the networking and parsing are already pure, `nonisolated static` functions (`StockService.fetchQuote`, `StockService.parseQuoteResponse`) and `StockItem` is already `Codable`, so a widget timeline provider can reuse them directly. The expensive unknowns are *integration* unknowns — App Group plumbing under the App Sandbox, whether Yahoo's cookie+crumb auth works from an extension process, and what refresh cadence WidgetKit's budget actually permits against Yahoo's rate limits.

This is a **SPIKE**, not a feature build. The deliverable is a *minimal working widget rendering 1–3 symbols* plus a *written findings section* answering the integration questions, so a future full-build plan can be scoped with real data instead of guesses. Do not chase feature parity with the menu bar (no rotation, no alerts, no holdings, no currency conversion).

## Current state

Files and their roles:

- `TickerBar/Services/StockService.swift` (791 lines) — `@Observable @MainActor` service. Holds the watchlist, persistence, auth, and networking. Contains the pure fetch/parse functions the widget will reuse.
- `TickerBar/Models/StockItem.swift` — the `Codable` quote model the widget will render.
- `TickerBar/TickerBar.entitlements` — App Sandbox entitlements for the main app.
- `TickerBar/Info.plist` — main app Info.plist; `LSUIElement` agent app, Sparkle keys present.
- `TickerBar/TickerBarApp.swift` — `@main` SwiftUI app entry; constructs `StockService`.
- `TickerBar.xcodeproj/project.pbxproj` — **source of truth** for the build. `project.yml` (XcodeGen) is stale/broken — do NOT use or regenerate from it.
- `plans/` — currently empty; you will create `plans/README.md` if it does not exist.

Key excerpts (verified at commit `c0c912e`):

The fetch is `private` today and takes an explicit crumb — this is the one visibility change required (`StockService.swift:395`):

```swift
private nonisolated static func fetchQuote(for symbol: String, crumb: String?) async -> FetchOutcome {
    guard let crumb else { return .failure }
    let urlString = "\(baseURL)/v8/finance/chart/\(symbol)?interval=5m&range=1d&crumb=\(crumb)"
```

`FetchOutcome` is `private` (`StockService.swift:256`) and `baseURL` is `nonisolated private static` (`StockService.swift:97`) — both are referenced by `fetchQuote`, so exposing `fetchQuote` alone is insufficient (see Step 3 / open question O4).

The parser is already public-enough and pure (`StockService.swift:414`):

```swift
nonisolated static func parseQuoteResponse(data: Data) throws -> StockItem {
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    ...
    return StockItem(symbol: symbol, name: name, price: price, previousClose: previousClose, ...)
}
```

The auth flow is an instance method on the `@MainActor` service, NOT `nonisolated` (`StockService.swift:224`), and stores the crumb in private instance state (`StockService.swift:83`). The widget cannot call it as-is:

```swift
private func ensureAuth() async throws {
    if crumb != nil { return }
    let cookieURL = URL(string: "https://fc.yahoo.com")!          // sets cookie (404s)
    let _ = try? await Self.session.data(from: cookieURL)
    let crumbURL = URL(string: "\(Self.baseURL)/v1/test/getcrumb")!  // plaintext crumb
    ...
    self.crumb = crumbString
}
```

The shared `URLSession` uses `HTTPCookieStorage.shared` (`StockService.swift:84-93`) — cookie storage is **per-process**, so the extension is a separate process and will not inherit the app's cookie jar (relevant to open question O1).

Persistence reads `UserDefaults.standard` directly in `init()` (`StockService.swift:100`):

```swift
let defaults = UserDefaults.standard
if let saved = defaults.stringArray(forKey: "watchlist"), !saved.isEmpty {
    self.watchlist = saved
}
```

The watchlist key is the literal string `"watchlist"`; default watchlist is `["AAPL", "GOOGL", "MSFT", "AMZN", "TSLA"]` (`StockService.swift:96`). **Composition note for plan 008**: if plan 008 injects a `UserDefaults` instance into `StockService.init`, the App Group suite created here becomes the natural thing to inject. Until then, this spike reads the App Group suite from the widget side only and leaves the app writing to `.standard` (see Step 4 + open question O3).

`StockItem` is `Codable` and self-contained (`StockItem.swift:3`):

```swift
struct StockItem: Identifiable, Codable, Equatable {
    let symbol: String
    let name: String
    let price: Double
    let previousClose: Double
    ...
    var menuBarText: String { ... }   // reusable label string
}
```

Sandbox + Sparkle entitlements (`TickerBar.entitlements`) — the widget's entitlements must be **a separate file**; do not copy the Sparkle mach-lookup exceptions into it:

```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
<array>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spks</string>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spki</string>
</array>
```

Build facts (from `project.pbxproj`): main app bundle id `com.tickerbar.app`, `MACOSX_DEPLOYMENT_TARGET = 14.0`, `SDKROOT = macosx`, main app `CODE_SIGN_ENTITLEMENTS = TickerBar/TickerBar.entitlements`. There is **no `DEVELOPMENT_TEAM`** set in the project — signing is automatic/empty, which matters for App Group provisioning (see open question O2).

Conventions to honor:
- Pure, testable logic is factored as `nonisolated static` funcs (`parseQuoteResponse`, `mergedStocks`, `isMarketOpen`). Any new pure logic you add follows this pattern.
- Persisted settings use a `didSet` writing to `UserDefaults.standard`.
- Tests are XCTest under `TickerBarTests/`, `@MainActor` where they touch the service. Model after `TickerBarTests/StockItemTests.swift` (pure model/logic) and `TickerBarTests/StockServiceTests.swift` (service-touching).
- No SwiftLint/format config — match neighbouring file style (4-space indent, `// MARK:` sections).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat c0c912e..HEAD -- <in-scope paths>` | empty (no drift) |
| Build (Release) | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` | `** BUILD SUCCEEDED **`, exit 0 |
| Test | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` | `** TEST SUCCEEDED **`, exit 0 |
| List schemes/targets | `xcodebuild -project TickerBar.xcodeproj -list` | lists `TickerBar`, the new widget target |
| Confirm pure funcs callable from a test | (the test build above compiles the test target) | compiles |

Note: `xcodebuild` runs can take minutes; allow generous timeouts. There is no SwiftLint, swift-format, or editorconfig — do not invent a lint step.

## Suggested executor toolkit

- This is a WidgetKit + App Group + App Sandbox integration. Before editing `project.pbxproj` by hand, prefer adding the target through Xcode's project model if a reliable tool is available; pbxproj is fragile to hand-edit. If you must hand-edit, make one logical change per commit and rebuild after each.
- Use `context7` (resolve `WidgetKit` / Apple developer docs) for the current `TimelineProvider`, `IntentTimelineProvider`, and `WidgetCenter.reloadTimelines` APIs and for the documented WidgetKit refresh-budget behavior — do not rely on memory for the cadence numbers, capture the cited figure in the findings.
- The committed `TickerBar.xcodeproj/project.pbxproj` is the source of truth. `project.yml` is stale/broken — ignore it; do not run XcodeGen.

## Scope

**In scope** (the only files/areas you should modify or create):
- `TickerBar/Services/StockService.swift` — minimal visibility bump only (Step 3).
- `TickerBarWidget/` (create) — the new widget extension target source: `TickerBarWidget.swift` (widget + provider + view), `TickerBarWidget.entitlements`, `Info.plist`, `Assets.xcassets` if needed.
- `TickerBarShared/` (create, optional) — a tiny shared file (e.g. `SharedStore.swift`) holding the App Group suite name constant and a function to read the watchlist; added to BOTH the app and widget targets. If creating a shared *target* is too heavy for a spike, instead add the same source file to both targets' membership (note which you chose in findings).
- `TickerBar.xcodeproj/project.pbxproj` — add the widget extension target, its build settings, App Group entitlement wiring, and embed-into-app build phase.
- `TickerBar/TickerBar.entitlements` — add the App Group entitlement (Step 1) so the app and widget share a suite.
- `TickerBarTests/` — one new test file for any new pure logic you add (Step 6).
- `plans/README.md` — status row.
- `FINDINGS` section delivered as the final report (do NOT write a findings .md file — return it in your final message per Step 7).

**Out of scope** (do NOT touch, even though they look related):
- `project.yml` — stale/broken XcodeGen spec; never regenerate the pbxproj from it.
- Rotation, price alerts, holdings, currency conversion, sparklines — explicitly excluded from the spike widget. Render plain symbol + price + change only.
- The V7 quote path (`fetchV7Quotes`, pre/post-market) — out of scope; the widget uses `fetchQuote`/`parseQuoteResponse` only.
- Any change to the app's runtime behavior or the menu bar UI.
- Moving the app's *writes* off `UserDefaults.standard` onto the App Group suite — leave that for plan 008 / a follow-up; this spike only reads from the suite on the widget side and documents the migration (open question O3).
- The Sparkle CI signing key and `release.yml` — do not touch; reference the key by name only if relevant.

## Git workflow

- Branch: `feat/018-direction-widgetkit-spike` (off `master`).
- Per the global Worktree convention, do this in a git worktree, not the main checkout.
- Commit per step or per logical unit. Imperative subjects matching `git log` style (e.g. "Add WidgetKit extension target", "Expose fetchQuote for widget reuse").
- HARD RULES: NO "Co-Authored-By", NO "Generated with Claude Code" or any AI attribution in commits or PR text.
- Do NOT push or open a PR unless the operator instructs it.

## Steps

### Step 1: Add the App Group entitlement to the app

Add an App Group to `TickerBar/TickerBar.entitlements`. Use group id `group.com.tickerbar.app` (matches the existing `com.tickerbar.app` bundle id). Insert alongside the existing keys, keeping the Sparkle mach-lookup exceptions intact:

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.tickerbar.app</string>
</array>
```

If automatic signing rejects the App Group because there is no `DEVELOPMENT_TEAM` (see open question O2), record exactly what failed and proceed with the spike build *unsigned / sign-to-run-locally* — do NOT invent a team id. If the App Group simply cannot be provisioned at all in this environment, that is a STOP condition (see STOP conditions).

**Verify**: `git diff TickerBar/TickerBar.entitlements` shows the `application-groups` key added and the Sparkle exceptions unchanged. Then run the Build command → `** BUILD SUCCEEDED **`.

### Step 2: Add the WidgetKit extension target to the project

Add a macOS Widget Extension target named `TickerBarWidget` to `TickerBar.xcodeproj`:
- Bundle id `com.tickerbar.app.widget`, `MACOSX_DEPLOYMENT_TARGET = 14.0`, `SDKROOT = macosx`.
- `CODE_SIGN_ENTITLEMENTS = TickerBarWidget/TickerBarWidget.entitlements` (created in Step 5).
- Add an "Embed App Extensions" (Embed Foundation/PlugIns) build phase to the `TickerBar` app target so the widget is bundled into the app.
- Create `TickerBarWidget/Info.plist` with `NSExtension` → `NSExtensionPointIdentifier = com.apple.widgetkit-extension`.

Keep the generated stub minimal for now (it will be replaced in Step 5). Make ONE commit for the target addition, then rebuild — pbxproj edits are fragile.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -list` lists a `TickerBarWidget` target. Then Build command → `** BUILD SUCCEEDED **`.

### Step 3: Expose the fetch path for reuse (minimal visibility bump)

The widget's provider needs to fetch and parse. `parseQuoteResponse` is already accessible. Make the minimum changes in `StockService.swift` so the widget can perform a fetch:

1. Change `fetchQuote` from `private nonisolated static` to `nonisolated static` (drop `private`) at `StockService.swift:395`.
2. Because `fetchQuote` returns the `private enum FetchOutcome` (`:256`) and uses the `private static baseURL` (`:97`), either: (a) also drop `private` on `FetchOutcome` and `baseURL`; OR (b) — preferred for a clean spike API — add a new thin `nonisolated static func widgetFetch(symbol:crumb:) async -> StockItem?` wrapper next to `fetchQuote` that returns `StockItem?` (mapping `.success` → the item, everything else → `nil`), so `FetchOutcome` and `baseURL` stay private. Choose (b) unless it proves awkward; record the choice.
3. The widget also needs auth. Add a `nonisolated static func fetchCrumb() async -> String?` that performs the same two-step cookie+crumb flow as `ensureAuth()` (`:224-247`) but as a standalone static returning the crumb (or `nil`). Do NOT delete or rewrite the existing instance `ensureAuth()` — add the static alongside it and note the duplication as deferred cleanup in findings. This keeps the app's runtime behavior unchanged.

Keep the diff to `StockService.swift` as small as possible; no behavior change to the app.

**Verify**: Build command → `** BUILD SUCCEEDED **`. Then `grep -n "static func widgetFetch\|static func fetchCrumb" TickerBar/Services/StockService.swift` → both present (if you chose option (b)); `grep -n "private nonisolated static func fetchQuote" TickerBar/Services/StockService.swift` → no match (the `private` was removed).

### Step 4: Add the shared App Group store accessor

Create `TickerBarShared/SharedStore.swift` (add to BOTH app and widget target membership). It holds the suite name and a read helper:

```swift
import Foundation

enum SharedStore {
    static let appGroupID = "group.com.tickerbar.app"
    static let watchlistKey = "watchlist"   // same key StockService uses

    static var suite: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    /// Watchlist for the widget. Falls back to the default set if the suite is empty.
    static func watchlist() -> [String] {
        suite?.stringArray(forKey: watchlistKey).flatMap { $0.isEmpty ? nil : $0 }
            ?? ["AAPL", "GOOGL", "MSFT"]
    }
}
```

For the spike, the widget reads the suite; the app does not yet write to it (that is plan 008's job — open question O3). So the widget will, in practice, fall back to the default `["AAPL", "GOOGL", "MSFT"]` until the app writes the suite. Document this clearly in findings as the expected next step. Limit the widget to the first 1–3 symbols.

**Verify**: Build command → `** BUILD SUCCEEDED **`. `grep -rn "group.com.tickerbar.app" TickerBarShared TickerBar/TickerBar.entitlements` → matches in both the shared file and the app entitlements.

### Step 5: Implement the minimal widget (provider + view + entitlements)

Create `TickerBarWidget/TickerBarWidget.entitlements` with sandbox + network client + the SAME App Group (and NO Sparkle keys):

```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.application-groups</key>
<array><string>group.com.tickerbar.app</string></array>
```

Create `TickerBarWidget/TickerBarWidget.swift` implementing:
- A `TimelineProvider` whose `getTimeline` calls `StockService.fetchCrumb()` then `StockService.widgetFetch(symbol:crumb:)` (or `fetchQuote` + `parseQuoteResponse`) for the first 1–3 symbols from `SharedStore.watchlist()`, builds a `StockItem`-backed entry, and returns a timeline with a refresh policy `.after(Date().addingTimeInterval(N))` where N is the cadence you justify in Step 7's findings (start conservatively, e.g. 900s / 15 min).
- `placeholder` and `getSnapshot` returning a static sample so the gallery renders without network.
- A SwiftUI view rendering symbol + `displayPrice` (with `currencySymbol`) + signed `changePercent`, supporting `.systemSmall` and `.systemMedium` families. Reuse `StockItem.menuBarText`/computed props where convenient. No rotation, no sparkline, no alerts.

**Verify**: Build command → `** BUILD SUCCEEDED **`. Confirm the widget product is embedded: `find ~/Library/Developer/Xcode/DerivedData -name "TickerBarWidget.appex" -path "*TickerBar*" 2>/dev/null` returns at least one path (or inspect the built `.app` bundle's `Contents/PlugIns/`). If the widget refuses to load in the simulator/gallery, capture the Console error for findings rather than guessing.

### Step 6: Add a unit test for any new pure logic

If you added pure logic in Step 4 (`SharedStore.watchlist()` fallback) or Step 3 (`widgetFetch` mapping), add `TickerBarTests/WidgetSpikeTests.swift` modeled structurally on `TickerBarTests/StockItemTests.swift`. Cover at minimum:
- `SharedStore.watchlist()` returns the default set when the suite is empty/unset.
- (If `widgetFetch` exists) parsing a known-good fixture JSON through `StockService.parseQuoteResponse` yields the expected `StockItem` — reuse any fixture pattern already in `StockServiceTests.swift`; if none exists, inline a small JSON literal.

Do not test live network. If there is genuinely no new pure logic worth a unit (e.g. you only wired existing functions), state that in findings and skip the file — but say so explicitly.

**Verify**: Test command → `** TEST SUCCEEDED **` and the new test names appear in output (e.g. `grep` the xcodebuild log for `WidgetSpikeTests`).

### Step 7: Write the findings report (the primary deliverable)

Produce a findings report **in your final message** (NOT as a committed .md file). It must answer, with concrete observations from Steps 1–6:

1. **App Group entitlement plan** — the suite id chosen, what had to change in both entitlement files, and whether App Group provisioning worked given no `DEVELOPMENT_TEAM` (O2).
2. **Shared-store design** — shared file vs shared target decision and why; the read path; and the concrete migration step for the app to *write* the suite (composes with plan 008's injected `UserDefaults` — name the exact `init` change). (O3)
3. **Auth from the extension** — did `fetchCrumb()` succeed from the widget process? Note that `HTTPCookieStorage.shared` is per-process (`StockService.swift:88`), so the extension fetches its own cookie+crumb; report whether Yahoo served a valid crumb to the extension and any 401/403 seen. (O1)
4. **Refresh cadence recommendation** — the WidgetKit refresh budget you found (cite the source via context7), the cadence N you set, and how it relates to Yahoo's tolerance for the existing app's default 60s polling. Recommend a concrete production cadence. (O5)
5. **Open questions / risks** — enumerated, including the `fetchCrumb`/`ensureAuth` duplication deferred in Step 3, whether `query2` rate-limits the extension's separate cookie session, and gallery/loading issues observed.

**Verify**: Your final message contains a "FINDINGS" section with all five numbered items answered, plus the absolute paths of every file created/modified.

### Step 8: Update the plan index

If `plans/README.md` does not exist, create it using the template structure from the improve skill (table with columns Plan | Title | Priority | Effort | Depends on | Status). Add/update the row for plan 018 to `DONE` (spike) or `BLOCKED` with a one-line reason.

**Verify**: `grep -n "018" plans/README.md` → row present with the correct status.

## Test plan

- New file `TickerBarTests/WidgetSpikeTests.swift` (only if new pure logic exists — see Step 6), modeled on `TickerBarTests/StockItemTests.swift`.
- Cases: `SharedStore.watchlist()` empty-suite fallback; `parseQuoteResponse` happy-path on an inline fixture (reuse the existing test's fixture style).
- Existing tests must still pass unchanged (the `StockService.swift` change is visibility-only).
- Verification: Test command → `** TEST SUCCEEDED **`, including the new test(s); existing `StockServiceTests`/`StockItemTests` still green.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] Build command (`xcodebuild ... -scheme TickerBar -configuration Release build`) prints `** BUILD SUCCEEDED **`, exit 0.
- [ ] Test command (`xcodebuild ... test`) prints `** TEST SUCCEEDED **`, exit 0.
- [ ] `xcodebuild -project TickerBar.xcodeproj -list` lists a `TickerBarWidget` target.
- [ ] `grep -n "com.apple.security.application-groups" TickerBar/TickerBar.entitlements TickerBarWidget/TickerBarWidget.entitlements` matches in both files with the same group id.
- [ ] `grep -n "private nonisolated static func fetchQuote" TickerBar/Services/StockService.swift` returns no match (visibility was bumped).
- [ ] A built `.appex` for the widget exists under DerivedData (Step 5 verify), OR the loading failure is documented in findings with the Console error.
- [ ] Final message contains a FINDINGS section answering all five Step 7 items, with absolute paths of changed files.
- [ ] No files outside the in-scope list are modified (`git status` shows only in-scope paths).
- [ ] `plans/README.md` row for 018 updated.

## STOP conditions

Stop and report back (do not improvise) if:

- The code at the locations in "Current state" does not match the excerpts (drift since `c0c912e`).
- **The App Sandbox + App Group + Sparkle-installer entitlements conflict** — e.g. the app fails to launch, the Sparkle installer XPC (`-spks`/`-spki` mach-lookup) breaks, or App Group provisioning is impossible in this environment without a real `DEVELOPMENT_TEAM`. Report exactly which entitlement combination failed; do NOT remove the Sparkle exceptions or hardcode a team id to force it through.
- A `project.pbxproj` hand-edit corrupts the project (Xcode/`xcodebuild -list` errors). Revert the last pbxproj change and report.
- A step's verification fails twice after a reasonable fix attempt.
- The fix appears to require touching an out-of-scope file (e.g. you find you must move the app's writes onto the App Group suite to make the widget show real data — that is plan 008's territory; document it and stop rather than expanding scope).
- You discover the assumption "Yahoo's crumb auth works from a sandboxed extension process" is false (persistent 401/403 from the widget) — capture the evidence and report; the widget showing only placeholder/sample data is an acceptable spike outcome, but it MUST be documented.

## Maintenance notes

For the human/agent who owns this after the spike lands:

- This is throwaway-grade integration. The `fetchCrumb()` static added in Step 3 duplicates the instance `ensureAuth()` — a follow-up should unify them (likely by making the auth flow a `nonisolated static` and having the service call it), tracked against the StockService god-object refactor.
- The widget will show only the default symbols until the app *writes* the watchlist to the App Group suite. The clean way to do that composes with plan 008: when `StockService.init` takes an injected `UserDefaults`, pass `UserDefaults(suiteName: "group.com.tickerbar.app")` and the existing `didSet` persistence writes flow into the shared suite automatically. Until then the widget is a render-only proof.
- A reviewer should scrutinize: (1) the entitlement diffs — that the Sparkle mach-lookup exceptions are untouched and NOT copied into the widget; (2) the pbxproj target/embed wiring; (3) that no app runtime behavior changed (the only `StockService` change is visibility + an additive static).
- Deferred out of this spike (intentionally): rotation, alerts, holdings, currency conversion, sparklines, V7 pre/post-market, configurable widget intents, and the cadence's interaction with Yahoo rate limits under many installed widgets. Pick these up in the full-build plan informed by this spike's findings.
