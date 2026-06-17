# Plan 014: Split the StockService god object into focused collaborators

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c0c912e..HEAD -- TickerBar/Services/StockService.swift TickerBar/Views/SettingsView.swift TickerBar/Views/WatchlistView.swift TickerBar/Views/MenuBarLabel.swift TickerBar/TickerBarApp.swift TickerBarTests/StockServiceTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: L
- **Risk**: MED
- **Depends on**: plans/009-*.md (characterization tests must exist first); do plans/005, plans/006, plans/007, plans/008 before this if they exist (smaller fixes that touch the same file — landing them after this big move causes painful conflicts)
- **Category**: tech-debt
- **Planned at**: commit `c0c912e`, 2026-06-17

## Why this matters

`TickerBar/Services/StockService.swift` is a single 791-line `@MainActor @Observable` class that owns networking, Yahoo cookie+crumb auth, JSON parsing, UserDefaults persistence (13 `didSet` observers), portfolio/FX math, price alerts + notifications, symbol search, two timers, and market-hours logic. Every View and the app entry point touch it, and it is the size outlier (next-largest source file is 549 lines). This is a maintainability problem, not a testability one — some pure logic (`parseQuoteResponse`, `mergedStocks`, `isMarketOpen`) is already extracted as `nonisolated static` and unit-tested. This plan carves three internal seams (a Yahoo client, a settings store, a pure portfolio calculator) so each concern can be read and changed in isolation, **while preserving exact behavior and the existing `service.` / `$service.` access the Views depend on**. Nothing in the public surface that Views use may change.

## Current state

Files involved:

- `TickerBar/Services/StockService.swift` — the god object (791 lines). The class is `@MainActor @Observable final class StockService` (lines 5–7).
- `TickerBar/TickerBarApp.swift` — owns the instance: `@State private var stockService = StockService()` (line 7); passes it to `WatchlistView(service:)` and `MenuBarLabel(service:)`; calls `stockService.startTimers()` (line 21).
- `TickerBar/Views/SettingsView.swift` — `@Bindable var service: StockService` (line 5); binds directly to settings via `$service.refreshInterval`, `$service.rotationEnabled`, `$service.rotationSpeed`, `$service.pinnedSymbol`, `$service.compactMenuBar`, `$service.showPercentChange`, `$service.menuBarFontSize`, `$service.solidPopoverBackground`, `$service.baseCurrency` (lines 19–95).
- `TickerBar/Views/WatchlistView.swift` — `@Bindable var service: StockService` (line 5); uses `StockService.SymbolSearchResult` (line 11) and many `service.` members.
- `TickerBar/Views/MenuBarLabel.swift` — reads display/menu-bar members off `service`.
- `TickerBarTests/StockServiceTests.swift` — XCTest, `@MainActor final class`, exercises `service.watchlist/addSymbol/removeSymbol/advanceDisplay`, `StockService.isMarketOpen`, `StockService.parseQuoteResponse`, `StockService.mergedStocks`, and settings persistence (`menuBarFontSize`, `solidPopoverBackground`).

The three seams to extract (current home in StockService.swift):

- **Yahoo networking + auth + parse** (lines 82–93 `session`, 95–97 constants, 216–252 `ensureAuth`/`invalidateAuth`, 254–525 fetch/parse/V7/FX/`fetchQuote`, 704–737 `searchSymbols`). Already mostly `nonisolated static` or `private`.
- **Settings persistence** — the 13 `didSet` mirrors to `UserDefaults.standard` (lines 16–48 plus `holdings` 61–67 and `priceAlerts` 70–76) and the `init` loads (lines 99–126).
- **Portfolio/FX math** — `normalizedCurrency` (656–661), `rateToBase` (663–668), `totalPortfolioValue/Cost/Gain/GainPercent` (670–690), `baseCurrencySymbol` (692–702).

Exemplar of the codebase pure-logic pattern (follow it for `PortfolioCalculator`):

```swift
// StockService.swift:366
nonisolated static func mergedStocks(watchlist: [String], fresh: [StockItem], previous: [StockItem]) -> [StockItem] {
    watchlist.compactMap { sym in
        fresh.first { $0.symbol == sym } ?? previous.first { $0.symbol == sym }
    }
}
```

Exemplar of the persistence `didSet` pattern (the SettingsStore must reproduce this exact behavior):

```swift
// StockService.swift:19
var refreshInterval: TimeInterval {
    didSet { UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval"); restartRefreshTimer() }
}
```

Conventions that apply:

- Swift 6 strict concurrency. `StockService` is `@MainActor`; pure/networking helpers are `nonisolated static`. New networking code must stay `nonisolated` (no MainActor capture); pure calculator code must be `nonisolated`.
- New persisted logic that is pure must be extracted as `nonisolated static` so it stays unit-testable (this is what makes the existing tests possible).
- No SwiftLint/swift-format. Match surrounding brace/indent style (4-space, K&R braces).
- `plans/008` (if present) injects `UserDefaults` instead of hard-coding `UserDefaults.standard`. If `init(defaults:)` already exists when you start, the `SettingsStore` you build must accept that same injected `UserDefaults` rather than referencing `.standard` directly. If 008 has NOT landed, keep `UserDefaults.standard` as-is — do not introduce injection yourself (out of scope).

**Hard constraint — do not break View bindings**: `SettingsView` uses `$service.refreshInterval` etc. For `$service.<x>` to keep compiling, `<x>` must remain a directly-assignable stored-style property **on `StockService`** that `@Observable` tracks. Therefore the settings properties may NOT be relocated onto a separate `SettingsStore` object and accessed as `$service.settings.refreshInterval` (that changes every View call site = out of scope). The `SettingsStore` seam is the **persistence mechanism only**: StockService keeps the public properties; their `didSet`/`init` bodies delegate load/save to `SettingsStore`. See Step 3 for the exact shape.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build (Release) | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` | ends `** BUILD SUCCEEDED **`, exit 0 |
| Test | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` | ends `** TEST SUCCEEDED **`, exit 0 |
| Line count | `wc -l TickerBar/Services/StockService.swift` | a number (used in Done criteria) |
| Changed files | `git status --porcelain` | only in-scope files listed |

Run all commands from the repo root `/Users/danny/VSCode/workspace/macos-stock-ticker`. The committed `TickerBar.xcodeproj/project.pbxproj` is the source of truth — `project.yml` (XcodeGen) is stale; do NOT regenerate the project from it.

**New-file gotcha**: new `.swift` files must be added to the `TickerBar` target's "Compile Sources" build phase in `TickerBar.xcodeproj/project.pbxproj`, or they will not compile into the app. After creating a file, confirm the build actually compiles it (a build failure referencing the new type's symbols = it was not added to the target). If editing `project.pbxproj` by hand is error-prone, prefer adding the new types as additional declarations appended inside an existing already-compiled file first, then split into their own files only once green — but the end state for this plan is separate files (see Scope). If you cannot reliably add a file to the target, that is a STOP condition.

## Scope

**In scope** (the only files you should modify or create):

- `TickerBar/Services/StockService.swift` (modify — becomes a thin coordinator)
- `TickerBar/Services/YahooFinanceClient.swift` (create)
- `TickerBar/Services/SettingsStore.swift` (create)
- `TickerBar/Services/PortfolioCalculator.swift` (create)
- `TickerBar.xcodeproj/project.pbxproj` (modify — only to register the 3 new files in the TickerBar target's Compile Sources phase, and the test file if a new test file is added)
- `TickerBarTests/PortfolioCalculatorTests.swift` (create — see Test plan)
- `TickerBarTests/StockServiceTests.swift` (modify only if a relocated symbol forces a reference update; prefer leaving untouched)

**Out of scope** (do NOT touch, even though they look related):

- `TickerBar/Views/SettingsView.swift`, `WatchlistView.swift`, `MenuBarLabel.swift` — the entire point is that View call sites (`service.x`, `$service.x`, `StockService.SymbolSearchResult`) stay byte-for-byte unchanged. If your refactor requires editing any View, STOP.
- `TickerBar/TickerBarApp.swift` — `StockService()` and `startTimers()` must keep working unchanged.
- Public method/property names and signatures that Views reference (full list under "Current state"). Renaming any of them is out of scope.
- `project.yml` — stale XcodeGen spec; do not edit or run it.
- `UserDefaults` injection (that is plan 008's job).
- Any behavior change to auth retry, market-hours math, alert arming, or merge logic. This is a pure move.

## Git workflow

- Branch: `refactor/014-split-stockservice` (create off `master`).
- Commit per step (one logical seam per commit). Imperative subjects matching `git log` style, e.g. `Extract YahooFinanceClient from StockService`, `Move portfolio math into PortfolioCalculator`.
- HARD RULES: NO `Co-Authored-By`, NO "Generated with Claude Code" or any AI attribution anywhere in commits or PR.
- Do NOT push or open a PR unless the operator explicitly tells you to.

## Steps

Each step keeps the build and tests green. Build + test after every step.

### Step 1: Branch and baseline-green

Create the branch and confirm a clean baseline before touching anything.

```
git checkout master && git checkout -b refactor/014-split-stockservice
```

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`. If the baseline is not green, STOP (you cannot distinguish your regressions from pre-existing failures).

### Step 2: Extract `PortfolioCalculator` (lowest-risk, pure, nonisolated)

This is the safest seam because it is pure math with no actor isolation or I/O.

1. Create `TickerBar/Services/PortfolioCalculator.swift` with a `nonisolated enum PortfolioCalculator` (use an enum as a namespace — no instances). Move the bodies of `normalizedCurrency`, `rateToBase`, `totalPortfolioValue`, `totalPortfolioCost`, `totalPortfolioGain`, `totalPortfolioGainPercent`, and `baseCurrencySymbol` into `nonisolated static func`s that take their inputs as parameters (they currently read `self.stocks`, `self.holdings`, `self.exchangeRates`, `self.baseCurrency`). Target shape:

```swift
enum PortfolioCalculator {
    static func normalizedCurrency(for stock: StockItem) -> String { /* moved */ }
    static func rateToBase(for stock: StockItem, baseCurrency: String, exchangeRates: [String: Double]) -> Double { /* moved */ }
    static func totalValue(stocks: [StockItem], holdings: [String: StockService.Holding], baseCurrency: String, exchangeRates: [String: Double]) -> Double { /* moved */ }
    static func totalCost(stocks: [StockItem], holdings: [String: StockService.Holding], baseCurrency: String, exchangeRates: [String: Double]) -> Double { /* moved */ }
    static func gain(value: Double, cost: Double) -> Double { value - cost }
    static func gainPercent(value: Double, cost: Double) -> Double { cost > 0 ? ((value - cost) / cost) * 100 : 0 }
    static func currencySymbol(for baseCurrency: String) -> String { /* moved switch */ }
}
```

2. In `StockService.swift`, keep the SAME public computed properties (`totalPortfolioValue`, `totalPortfolioCost`, `totalPortfolioGain`, `totalPortfolioGainPercent`, `baseCurrencySymbol`) so View call sites are untouched, but make their bodies delegate, e.g.:

```swift
var totalPortfolioValue: Double {
    PortfolioCalculator.totalValue(stocks: stocks, holdings: holdings, baseCurrency: baseCurrency, exchangeRates: exchangeRates)
}
var baseCurrencySymbol: String { PortfolioCalculator.currencySymbol(for: baseCurrency) }
```

The private `normalizedCurrency(for:)` / `rateToBase(for:)` instance methods may be deleted from StockService once `fetchAllQuotes`'s currency-normalization block (lines 327–334) and any remaining callers route through `PortfolioCalculator`. Keep the inline normalization in `fetchAllQuotes` behavior-identical (you may call `PortfolioCalculator.normalizedCurrency(for:)` there).

3. Register `PortfolioCalculator.swift` in the TickerBar target (project.pbxproj Compile Sources).

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **` AND `xcodebuild ... test` → `** TEST SUCCEEDED **`. The relocated math is now covered by Step 2's new tests (write them now — see Test plan).

### Step 3: Extract `SettingsStore` (persistence mechanism only)

Goal: remove the 13 repeated `UserDefaults.standard.set(..., forKey:)` literals and the `init` load block from StockService, WITHOUT relocating the public settings properties (the `$service.x` bindings require them to stay on StockService).

1. Create `TickerBar/Services/SettingsStore.swift` containing a `struct SettingsStore` (or `final class`) that wraps a `UserDefaults` (default `.standard`; if plan 008 already injected one, accept it via init) and exposes typed load/save helpers, e.g. `func saveRefreshInterval(_ v: TimeInterval)`, `func loadRefreshInterval() -> TimeInterval` (returning the existing defaults: 60, true, 5, etc.), and the Codable load/save for `holdings` and `priceAlerts`. Centralize the UserDefaults keys as string constants here.

2. In StockService, keep every public settings property exactly as declared, but change `didSet` bodies to delegate:

```swift
var refreshInterval: TimeInterval {
    didSet { settings.saveRefreshInterval(refreshInterval); restartRefreshTimer() }
}
```

and replace the `init` body's load lines with `settings.loadRefreshInterval()` etc. Add a `private let settings = SettingsStore()` stored property. **Side effects that currently live in `didSet` (`restartRefreshTimer()`, `restartRotationTimer()`) stay in StockService's `didSet`** — SettingsStore only does persistence.

3. Preserve exact load semantics: the current `init` uses `defaults.double(forKey:).nonZero ?? 60`, `defaults.object(forKey:) as? Bool ?? true`, `defaults.bool(forKey:)`, etc. (lines 99–126). The `nonZero` extension (lines 787–791) and these fallbacks must produce identical values — move/keep them so behavior is bit-identical. The persistence tests (`testMenuBarFontSizePersists`, `testSolidPopoverBackgroundPersists`, `testMenuBarFontSizeDefaultsToTen`, `testSolidPopoverBackgroundDefaultsToFalse`) MUST still pass unchanged — they assert directly against `UserDefaults.standard` keys, so SettingsStore must use the same key strings (`"menuBarFontSize"`, `"solidPopoverBackground"`, etc.).

4. Register `SettingsStore.swift` in the target.

**Verify**: `xcodebuild ... test` → `** TEST SUCCEEDED **` with the existing persistence tests still passing (they prove key strings and defaults are preserved). If any persistence test fails, you changed a key or a default — revert and fix before continuing.

### Step 4: Extract `YahooFinanceClient` (networking + auth + parse + search)

1. Create `TickerBar/Services/YahooFinanceClient.swift`. Move into it: the `session` (lines 84–93), `baseURL` (97), `ensureAuth`/`invalidateAuth`/`crumb` (83, 216–252), `FetchOutcome` (256–260), `fetchQuotes`/`fetchQuote` (375–412), `parseQuoteResponse` (414–447), `V7QuoteData` + `fetchV7Quotes` (451–493), `fetchExchangeRates` (498–525), and `searchSymbols` (713–737). Preserve `nonisolated static` on the pure/static fetch+parse helpers; auth state (`crumb`) needs an isolation home — make `YahooFinanceClient` an `actor` or keep it `@MainActor`, whichever compiles cleanly under Swift 6 with the existing `withTaskGroup`/`nonisolated static` call shape. Do not change the auth retry flow.

2. **CRITICAL — keep `parseQuoteResponse` callable as `StockService.parseQuoteResponse(...)` and `mergedStocks`/`isMarketOpen` as `StockService.x(...)`** because `StockServiceTests` calls them via `StockService.` (lines 75, 120, 143, 156, 175 etc.). Two options: (a) leave `parseQuoteResponse`, `mergedStocks`, `isMarketOpen` ON `StockService` and only move the networking/auth that the tests do NOT reference; or (b) move `parseQuoteResponse` to `YahooFinanceClient` and add a `nonisolated static func parseQuoteResponse` thin forwarder on StockService. Prefer (a): keep the already-tested pure statics where the tests expect them; move only auth + the HTTP fetch wrappers. This minimizes test churn — `StockServiceTests.swift` should need ZERO edits.

3. `StockService` keeps a `private let yahoo = YahooFinanceClient()` and its public `fetchAllQuotes`, `validateSymbol`, `searchSymbols`, `addSymbol`, etc. delegate the network calls to `yahoo`. `fetchAllQuotes`'s orchestration (assigning `stocks`, `errorMessage`, `lastUpdated`, calling `checkPriceAlerts()`) stays on StockService (it mutates `@MainActor @Observable` state). Only the raw HTTP/auth moves.

4. Register `YahooFinanceClient.swift` in the target.

**Verify**: `xcodebuild ... test` → `** TEST SUCCEEDED **`, and `git diff --stat HEAD -- TickerBarTests/StockServiceTests.swift` shows no changes (zero test churn confirms the public surface held). If `StockServiceTests.swift` had to change, that signals an API ripple — re-evaluate against the STOP conditions.

### Step 5: Final tidy and size check

Confirm StockService is now a thin coordinator: published `@Observable` state, settings properties (delegating persistence), display/rotation/market-hours wiring, timers, alert orchestration, and delegation to the three collaborators. Remove now-dead private helpers and unused imports.

**Verify**: `wc -l TickerBar/Services/StockService.swift` → a value materially below 791 (target: under ~450). AND `git status --porcelain` → only in-scope files. AND full `xcodebuild ... test` → `** TEST SUCCEEDED **`.

## Test plan

- New file `TickerBarTests/PortfolioCalculatorTests.swift` (model structurally after `TickerBarTests/StockServiceTests.swift`; this one need NOT be `@MainActor` since `PortfolioCalculator` is `nonisolated`). Cover:
  - `totalValue` happy path: one holding, same currency (rate 1.0) → `price * shares`.
  - `totalValue` with FX: a `GBP` stock, `baseCurrency = "USD"`, `exchangeRates = ["GBP": 1.27]` → value scaled by 1.27.
  - `normalizedCurrency`: `"GBp"` → `"GBP"`, `"GBX"` → `"GBP"`, `"ILA"` → `"ILS"`, `"usd"` → `"USD"`, `nil` → `"USD"`.
  - `gain` / `gainPercent`: cost 0 → percent is 0 (no divide-by-zero); cost 100, value 110 → gain 10, percent 10.
  - `currencySymbol`: `"GBP"`→`£`, `"JPY"`→`¥`, `"USD"`/unknown→`$`.
  - `totalCost`: holdings present vs symbol with no holding (skipped).
  - Register the new test file in the `TickerBarTests` target (project.pbxproj).
- Existing `TickerBarTests/StockServiceTests.swift` must pass UNCHANGED — it is the characterization safety net for this refactor. Treat any required edit to it as a signal (see STOP conditions).
- Verification: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`, including the new `PortfolioCalculatorTests` cases.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **` (exit 0)
- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **` (exit 0)
- [ ] Files exist: `ls TickerBar/Services/YahooFinanceClient.swift TickerBar/Services/SettingsStore.swift TickerBar/Services/PortfolioCalculator.swift TickerBarTests/PortfolioCalculatorTests.swift` → all four print, exit 0
- [ ] `wc -l TickerBar/Services/StockService.swift` → under 500
- [ ] `git diff c0c912e..HEAD -- TickerBar/Views/ TickerBar/TickerBarApp.swift` → empty (no View or app-entry changes)
- [ ] `git diff c0c912e..HEAD -- TickerBarTests/StockServiceTests.swift` → empty (characterization tests untouched)
- [ ] `git status --porcelain` → lists only in-scope files
- [ ] `plans/README.md` status row for 014 updated (unless a reviewer owns the index)

## STOP conditions

Stop and report back (do not improvise) if:

- The code at the locations in "Current state" doesn't match the excerpts (the file drifted since `c0c912e`).
- Extracting a seam forces a change to any View (`SettingsView.swift`, `WatchlistView.swift`, `MenuBarLabel.swift`) or to `TickerBarApp.swift` — this means the refactor is rippling into the public API the Views depend on, which is explicitly out of scope.
- `StockServiceTests.swift` requires edits to keep compiling/passing (the public test surface moved — re-evaluate the seam boundary instead).
- A Swift 6 strict-concurrency / actor-isolation error appears that cannot be resolved without changing a public signature or sprinkling `@MainActor`/`nonisolated` onto View-facing members.
- You cannot reliably add a new `.swift` file to the TickerBar (or TickerBarTests) target in `project.pbxproj`.
- Any step's verification fails twice after a reasonable fix attempt.
- Plan 009 (characterization tests) is not present/green — its tests are the safety net this refactor relies on.

## Maintenance notes

For the human/agent who owns this after it lands:

- The settings properties intentionally stay ON `StockService` (not relocated to `SettingsStore`) solely to preserve `$service.<x>` SwiftUI bindings in `SettingsView`. If a future change moves Views to access settings via a nested object, those binding call sites must be migrated in the same change.
- `SettingsStore` is persistence-only; timer side-effects (`restartRefreshTimer`, `restartRotationTimer`) deliberately remain in `StockService`'s `didSet`. Don't move them into the store.
- If plan 008 (inject `UserDefaults`) lands after this, wire its injected defaults through `SettingsStore`'s init rather than re-introducing `UserDefaults.standard`.
- Reviewer should scrutinize: (1) the diff is a pure move — diff the moved function bodies against the originals; (2) zero changes to Views/app/`StockServiceTests.swift`; (3) auth retry flow in `fetchAllQuotes` is behavior-identical; (4) UserDefaults key strings are unchanged.
- Deferred out of scope: converting `UpdateChecker` (ObservableObject) similarly, and any `UserDefaults` injection — both are separate plans.
