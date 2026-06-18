# Plan 011: Keep currentDisplayIndex in sync with the displayed stock

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat c0c912e..HEAD -- TickerBar/Services/StockService.swift TickerBar/Models/StockItem.swift TickerBarTests/StockServiceTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plans/009-*.md (the plan that introduces the deterministic, date-injectable market-hours test infrastructure this test extends). If plan 009 has not landed, see STOP conditions.
- **Category**: bug
- **Planned at**: commit `c0c912e`, 2026-06-17

## Why this matters

When rotation is enabled and the stock currently pointed at by `currentDisplayIndex`
has a closed market, the read-only getter `currentDisplayStock` returns the *first
open* stock — but it does **not** move `currentDisplayIndex`. Meanwhile the rotation
timer drives `advanceDisplay()`, which mutates `currentDisplayIndex` from its stale
value. The two pieces of state therefore disagree for one tick on initial display and
right after the watchlist mutates, producing a bounded one-tick rotation "skip"
(`advanceDisplay()` self-corrects on the next tick). The cost is purely cosmetic, but
the divergence is a correctness smell: a getter and the index it reads from should
never name different stocks. This plan removes the divergence by keeping the getter
pure (no hidden side effects) and moving the "land on an open stock" responsibility
into `advanceDisplay()` plus a new initial-selection helper, so the displayed item and
`currentDisplayIndex` always refer to the same symbol.

## Current state

Files involved:

- `TickerBar/Services/StockService.swift` — `StockService` is `@MainActor @Observable`. Holds the rotation state and display logic (the code to change is at lines 130–171).
- `TickerBar/Models/StockItem.swift` — the `StockItem` struct. Relevant field: `var exchangeTimezoneName: String? = nil` (line 8); `symbol`, `name`, `price`, `previousClose` are non-optional init params (lines 4–7), everything else defaults to `nil`/empty so a test item can be built as `StockItem(symbol:name:price:previousClose:exchangeTimezoneName:)`.
- `TickerBarTests/StockServiceTests.swift` — XCTest, `@MainActor final class StockServiceTests: XCTestCase`. `setUp()` clears persisted UserDefaults keys.

The getter today (`TickerBar/Services/StockService.swift:130-144`):

```swift
var currentDisplayStock: StockItem? {
    guard !stocks.isEmpty else { return nil }
    if rotationEnabled {
        let current = stocks[currentDisplayIndex % stocks.count]
        // If current stock's market is closed, prefer an open one (unless all are closed)
        if !Self.isMarketOpen(timezoneName: current.exchangeTimezoneName) {
            if let openStock = stocks.first(where: { Self.isMarketOpen(timezoneName: $0.exchangeTimezoneName) }) {
                return openStock
            }
        }
        return current
    } else {
        return stocks.first { $0.symbol == pinnedSymbol } ?? stocks.first
    }
}
```

The rotation advance (`TickerBar/Services/StockService.swift:150-171`):

```swift
func advanceDisplay() {
    guard !stocks.isEmpty, rotationEnabled else { return }

    let openStocks = stocks.enumerated().filter {
        Self.isMarketOpen(timezoneName: $0.element.exchangeTimezoneName)
    }

    if openStocks.isEmpty {
        // All markets closed — rotate through everything
        currentDisplayIndex = (currentDisplayIndex + 1) % stocks.count
    } else {
        // Find the next open stock after current index
        let startIndex = currentDisplayIndex
        for offset in 1...stocks.count {
            let candidate = (startIndex + offset) % stocks.count
            if Self.isMarketOpen(timezoneName: stocks[candidate].exchangeTimezoneName) {
                currentDisplayIndex = candidate
                return
            }
        }
    }
}
```

The pure, date-injectable market-hours helper this plan relies on (`TickerBar/Services/StockService.swift:177`):

```swift
nonisolated static func isMarketOpen(timezoneName: String? = nil, at date: Date = Date()) -> Bool {
```

Note the `at date: Date = Date()` parameter — this is what makes the logic unit-testable without wall-clock flakiness (see existing `testIsMarketOpenWeekday` / `testIsMarketClosedWeekend` at `TickerBarTests/StockServiceTests.swift:65-89`, which pin a fixed `date`).

Callers of the symbols being changed (verified — there are no other call sites):

- `TickerBar/Views/MenuBarLabel.swift:8` — reads `service.currentDisplayStock` (read-only; behavior must stay identical).
- `TickerBar/Services/StockService.swift:147` — `menuBarText` reads `currentDisplayStock`.
- `TickerBar/Services/StockService.swift:772` — the rotation timer calls `advanceDisplay()`.
- `currentDisplayIndex` is only mutated inside `advanceDisplay()` and declared at line 10.

Repo conventions that apply here:

- Pure logic is factored as `nonisolated static` funcs (e.g. `parseQuoteResponse`, `mergedStocks`, `isMarketOpen`) so it is unit-testable. Follow that pattern: the new index-selection logic must be a `nonisolated static` function taking explicit inputs (the stocks, the current index, an injectable `Date`), returning the new index — never reading instance state directly.
- Tests are XCTest, `@MainActor` when they touch the service. Build `StockItem` test fixtures with the memberwise init, e.g. `StockItem(symbol: "A", name: "A", price: 1, previousClose: 1, exchangeTimezoneName: "America/New_York")` (see `TickerBarTests/StockServiceTests.swift:53-59`).
- No SwiftLint / swift-format / editorconfig. Match the surrounding brace/indent style (4-space indent).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build (Release) | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` | ends with `** BUILD SUCCEEDED **`, exit 0 |
| Test | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` | ends with `** TEST SUCCEEDED **`, exit 0 |

Run all `xcodebuild` commands from the repo root `/Users/danny/VSCode/workspace/macos-stock-ticker` (the dir containing `TickerBar.xcodeproj`). The committed `TickerBar.xcodeproj/project.pbxproj` is the source of truth; ignore `project.yml` (it is a stale XcodeGen spec — do NOT regenerate the project from it).

## Scope

**In scope** (the only files you should modify):
- `TickerBar/Services/StockService.swift`
- `TickerBarTests/StockServiceTests.swift`

**Out of scope** (do NOT touch, even though they look related):
- `TickerBar/Views/MenuBarLabel.swift` — only reads `currentDisplayStock`; its behavior must remain identical, so no change is needed.
- `TickerBar/Models/StockItem.swift` — read for the init signature only; do not modify.
- `TickerBar/Services/StockService.swift` market-hours helper `isMarketOpen` (lines 177–208) — reuse it; do not change its logic or signature.
- The non-rotation (`else`) branch of `currentDisplayStock` (the `pinnedSymbol` path, lines 141–143) — leave it exactly as-is.
- Any broader refactor of `StockService` (it is a large class; resist the urge to split it — that is a separate effort).

## Git workflow

- Branch: `fix/011-fix-rotation-index-desync` (off `master`).
- Commit per logical unit. Imperative subject matching `git log` style (e.g. "Keep rotation display index in sync with displayed stock"). Recent examples: `Fix dropdown empty space after collapsing Settings`, `Update appcast.xml for v1.2.2`.
- Do NOT add `Co-Authored-By`, "Generated with Claude Code", or any AI attribution anywhere in commits.
- Do NOT push or open a PR unless the operator explicitly instructs it.

## Steps

### Step 1: Add a pure `nonisolated static` index-selection helper

In `TickerBar/Services/StockService.swift`, add a pure helper near the existing display logic (just below `advanceDisplay()`, before the `// MARK: - Market Hours` section). It computes the index of the stock that should be displayed for an *initial* selection / after a non-rotation state change, preferring an open market, returning the current index unchanged when it already points at an open stock or when no stock is open.

Target shape (mirror the `isMarketOpen(at:)` injectable-date convention so it is deterministically testable):

```swift
/// Pure helper: returns the index of the stock that should be displayed,
/// preferring the first open market. Keeps `currentDisplayStock` and
/// `currentDisplayIndex` in agreement. If the stock at `currentIndex` is
/// already open, or no stock is open, `currentIndex` is returned unchanged
/// (clamped into range). Pure — easy to unit test.
nonisolated static func displayIndex(
    for stocks: [StockItem],
    currentIndex: Int,
    at date: Date = Date()
) -> Int {
    guard !stocks.isEmpty else { return 0 }
    let clamped = ((currentIndex % stocks.count) + stocks.count) % stocks.count
    if isMarketOpen(timezoneName: stocks[clamped].exchangeTimezoneName, at: date) {
        return clamped
    }
    if let openIndex = stocks.firstIndex(where: {
        isMarketOpen(timezoneName: $0.exchangeTimezoneName, at: date)
    }) {
        return openIndex
    }
    return clamped
}
```

This intentionally matches the old getter's "first open stock" preference (`stocks.first(where:)` → `firstIndex(where:)`) so display behavior is unchanged.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`, exit 0.

### Step 2: Make the getter pure (read the index, do not diverge from it)

Replace the rotation branch of `currentDisplayStock` (lines 132–140) so it simply returns the stock at the index, with no hidden "prefer open" jump. The "prefer open" responsibility now lives in the index (kept current by Step 3 / Step 4). Leave the `else` (pinned) branch untouched.

Target shape for the whole getter:

```swift
var currentDisplayStock: StockItem? {
    guard !stocks.isEmpty else { return nil }
    if rotationEnabled {
        return stocks[((currentDisplayIndex % stocks.count) + stocks.count) % stocks.count]
    } else {
        return stocks.first { $0.symbol == pinnedSymbol } ?? stocks.first
    }
}
```

(The double-modulo guards against a negative or out-of-range `currentDisplayIndex`; the original used `currentDisplayIndex % stocks.count`, which is sufficient for non-negative indices — keep the safe form.)

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`, exit 0.

### Step 3: Re-sync the index when the stocks array is rebuilt

`stocks` is reassigned after each fetch (`TickerBar/Services/StockService.swift:355`) and reordered in `moveSymbol` (line 564) and `removeSymbol` (line 555). To guarantee the displayed item lands on an open stock without the getter doing it, snap `currentDisplayIndex` to the open-preferring value after `stocks` is set in `fetchAllQuotes`.

Immediately after the assignment at line 355:

```swift
        let previous = stocks
        stocks = Self.mergedStocks(watchlist: watchlist, fresh: enriched, previous: previous)
```

add, only when rotation is on:

```swift
        if rotationEnabled {
            currentDisplayIndex = Self.displayIndex(for: stocks, currentIndex: currentDisplayIndex)
        }
```

Do NOT add this to `removeSymbol` / `moveSymbol` — `advanceDisplay()` (called by the timer) and the next fetch will reconcile, and Step 4 makes `advanceDisplay()` self-consistent. Keeping the change to one site limits risk.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`, exit 0.

### Step 4: Ensure `advanceDisplay()` agrees with the new helper (no behavior change expected)

`advanceDisplay()` already lands `currentDisplayIndex` on the next open stock (lines 160–169) and rotates through all when none are open (line 159). Confirm it still does after Steps 1–3 — no edit is expected. Re-read lines 150–171 and verify the logic is intact and that `currentDisplayIndex` is the only thing it mutates. If you find yourself wanting to change it, STOP and report.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`, exit 0.

### Step 5: Add the regression test

See the Test plan section for exact cases. Add them to `TickerBarTests/StockServiceTests.swift`.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`, exit 0, and the new test names appear in the output as passing.

## Test plan

Add tests to `TickerBarTests/StockServiceTests.swift`, modeling structure on the existing `testCurrentDisplayIndexWraps` (`:50-63`) and the date-pinning style of `testIsMarketOpenWeekday` (`:65-89`). Use deterministic, injected dates so the suite is not wall-clock dependent (this is the dependency on plan 009's date-injectable test approach).

Pick two fixed dates and reuse the existing pattern to build them via `Calendar`/`DateComponents`:
- `weekdayNoonNY` = 2026-02-18 12:00 in `America/New_York` (NYSE open; matches `testIsMarketOpenWeekday`).
- The same instant is a weekend/closed window for nothing here — instead, to get a deterministically *closed* market, use a timezone that is closed at that instant. At 2026-02-18 12:00 New York time it is the evening in Tokyo, so a stock with `exchangeTimezoneName: "Asia/Tokyo"` is closed; `"America/New_York"` is open. Verify this assumption in the test itself with direct `StockService.isMarketOpen(timezoneName:at:)` assertions before relying on it (see case 1).

Tests to add:

1. `testDisplayIndexAssumptionsHold` — sanity-guard the fixtures: assert `StockService.isMarketOpen(timezoneName: "America/New_York", at: weekdayNoonNY)` is `true` and `StockService.isMarketOpen(timezoneName: "Asia/Tokyo", at: weekdayNoonNY)` is `false`. (If this fails, the other cases' premises are wrong — fail fast with a clear message.)

2. `testDisplayIndexLandsOnOpenStockWhenCurrentIsClosed` — `stocks = [Tokyo(closed), NY(open)]`, `currentIndex = 0`. Assert `StockService.displayIndex(for: stocks, currentIndex: 0, at: weekdayNoonNY) == 1`.

3. `testDisplayIndexKeepsCurrentWhenAlreadyOpen` — `stocks = [NY(open), Tokyo(closed)]`, `currentIndex = 0`. Assert result `== 0`.

4. `testDisplayIndexKeepsCurrentWhenAllClosed` — `stocks = [Tokyo(closed), Tokyo(closed)]`, `currentIndex = 1`. Assert result `== 1` (no jump when nothing is open).

5. `testDisplayStockAndIndexAgreeAfterSelection` (the core invariant — the bug this plan fixes): on a real `StockService` instance with `rotationEnabled = true`, set `service.stocks = [Tokyo(closed), NY(open)]` and `service.currentDisplayIndex = 0`, then set `service.currentDisplayIndex = StockService.displayIndex(for: service.stocks, currentIndex: service.currentDisplayIndex, at: weekdayNoonNY)`. Assert `service.currentDisplayStock?.symbol == service.stocks[service.currentDisplayIndex].symbol` AND `service.currentDisplayStock?.symbol == "NY-SYMBOL"`. (Use distinct symbols, e.g. `"TKY"` and `"NYC"`.) Note: `currentDisplayStock` itself uses the default `Date()` for its internal modulo only — it no longer calls `isMarketOpen`, so it is not time-dependent after Step 2; the agreement assertion is therefore deterministic.

6. `testAdvanceDisplayKeepsStockAndIndexAgreeing` — `@MainActor`, real service, `rotationEnabled = true`, `stocks = [Tokyo(closed), NY(open), Tokyo(closed)]`, `currentDisplayIndex = 0`, call `service.advanceDisplay()`, then assert `service.currentDisplayStock?.symbol == service.stocks[service.currentDisplayIndex].symbol`. (`advanceDisplay` uses real `Date()`; the agreement invariant holds regardless of which stock it lands on, so this is not flaky.)

Verification: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`, all existing tests still pass plus the 6 new ones.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` ends with `** BUILD SUCCEEDED **` (exit 0).
- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` ends with `** TEST SUCCEEDED **` (exit 0).
- [ ] The 6 new test methods named in the Test plan exist in `TickerBarTests/StockServiceTests.swift` and pass: `grep -c "func testDisplayIndex\|func testDisplayStockAndIndexAgree\|func testAdvanceDisplayKeepsStockAndIndexAgreeing" TickerBarTests/StockServiceTests.swift` returns `6`.
- [ ] `currentDisplayStock`'s rotation branch no longer calls `isMarketOpen`: `sed -n '130,144p' TickerBar/Services/StockService.swift | grep -c isMarketOpen` returns `0`.
- [ ] A `nonisolated static func displayIndex(` exists: `grep -c "nonisolated static func displayIndex(" TickerBar/Services/StockService.swift` returns `1`.
- [ ] Only the two in-scope files are modified: `git status --porcelain` lists only `TickerBar/Services/StockService.swift` and `TickerBarTests/StockServiceTests.swift` (and, if you create it, `plans/README.md`).
- [ ] `plans/README.md` status row for plan 011 updated (create the file if it does not exist; see the index format in the template).

## STOP conditions

Stop and report back (do not improvise) if:

- The "Current state" excerpts at `TickerBar/Services/StockService.swift:130-171` or the `isMarketOpen(timezoneName:at:)` signature at line 177 do not match the live code (the codebase has drifted since this plan was written).
- Plan 009 has not landed and there is no date-injectable market-hours test infrastructure / `isMarketOpen(at:)` parameter is absent — without an injectable date the new tests would be wall-clock-flaky. Report this rather than writing time-dependent tests.
- `testDisplayIndexAssumptionsHold` (case 1) fails — the `America/New_York` open / `Asia/Tokyo` closed premise for the chosen instant is wrong; pick a different pair and report which.
- Any verification command fails twice after a reasonable fix attempt.
- The fix appears to require editing a file outside the in-scope list (e.g. `MenuBarLabel.swift`).
- Step 4 reveals `advanceDisplay()` needs logic changes to keep index/stock in agreement — report what diverged rather than rewriting it.

## Maintenance notes

For the human/agent who owns this code after the change lands:

- The invariant this plan establishes: **`currentDisplayStock` (rotation branch) and `stocks[currentDisplayIndex]` always name the same symbol.** The getter is now pure (no `isMarketOpen` call). Anything that reassigns `stocks` while `rotationEnabled` must re-run `Self.displayIndex(for:currentIndex:)` — today only `fetchAllQuotes` does (Step 3). If a future change rebuilds `stocks` elsewhere (e.g. a new sort/filter feature) and the displayed item looks "stuck on a closed market", that new site is missing the re-sync call.
- Reviewer should scrutinize: that the getter no longer references `isMarketOpen`; that `displayIndex` preserves the old "first open stock" preference (it uses `firstIndex(where:)`, matching the old `first(where:)`); and that the new tests inject a fixed `Date` rather than relying on the current time.
- Deliberately deferred: re-syncing the index inside `removeSymbol`/`moveSymbol` (the timer + next fetch reconcile, and adding it there widens the blast radius for a cosmetic bug). Revisit only if a user-visible glitch is observed immediately after reordering/removing while rotation is on.
```
