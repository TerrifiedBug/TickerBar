# Plan 010: Improve market-hours accuracy (Asian lunch breaks; prefer Yahoo marketState)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c0c912e..HEAD -- TickerBar/Services/StockService.swift TickerBar/Models/StockItem.swift TickerBar/Views/WatchlistView.swift TickerBarTests/StockServiceTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/009-*.md (its isMarketOpen boundary tests must already be merged; this plan extends them)
- **Category**: bug
- **Planned at**: commit `c0c912e`, 2026-06-17

## Why this matters

`isMarketOpen` is a weekday + local-hour heuristic, self-labeled "Approximate" (`StockService.swift:191`). It treats Asian exchanges as continuously open through their lunch sessions: the Tokyo Stock Exchange closes 11:30–12:30 and HKEX/Shanghai close 12:00–13:00, yet the heuristic reports them open the whole day. This verdict drives both the UI ("Markets Closed" banner, rotation skipping closed stocks) and polling (timer refresh is skipped when `marketHoursOnly && !anyMarketOpen` at `StockService.swift:265`), so it causes wrong status display and wasted/missing fetches.

Two improvements land here. **Tier 1** encodes the per-exchange lunch break as a second closed interval so the clock heuristic returns `false` during lunch. **Tier 2** prefers the real source of truth: the v7 fetch already returns `marketState` (PRE/REGULAR/POST/CLOSED) and stores it on `StockItem` (`StockService.swift:318`, `StockItem.swift:17`), but it is currently used only for a tooltip line (`WatchlistView.swift:450`). Where a fresh `marketState` exists for a stock, we use it for that stock's open/closed decision and fall back to the clock heuristic only when `marketState` is nil (e.g. before the first fetch). Exchange holidays and half-days stay out of scope (a maintained calendar is a separate effort).

## Current state

Files this plan touches:

- `TickerBar/Services/StockService.swift` — owns the market-hours logic and all its callers.
- `TickerBar/Models/StockItem.swift` — holds the `marketState` field.
- `TickerBar/Views/WatchlistView.swift` — consumes market-open status for the "Markets Closed" banner and per-row dimming.
- `TickerBarTests/StockServiceTests.swift` — XCTest target; existing market-hours tests.

The heuristic today (`StockService.swift:177-208`):

```swift
nonisolated static func isMarketOpen(timezoneName: String? = nil, at date: Date = Date()) -> Bool {
    let tzID = timezoneName ?? "America/New_York"
    var calendar = Calendar(identifier: .gregorian)
    guard let tz = TimeZone(identifier: tzID) else { return true }
    calendar.timeZone = tz

    let weekday = calendar.component(.weekday, from: date)
    // 1 = Sunday, 7 = Saturday
    guard weekday >= 2 && weekday <= 6 else { return false }

    let hour = calendar.component(.hour, from: date)
    let minute = calendar.component(.minute, from: date)
    let minuteOfDay = hour * 60 + minute

    // Approximate market hours for major exchanges (local time)
    // US (NYSE/NASDAQ): 9:30-16:00, UK (LSE): 8:00-16:30,
    // Europe: 9:00-17:30, Asia varies but ~9:00-15:00
    let (marketOpen, marketClose): (Int, Int) = switch tzID {
    case let tz where tz.starts(with: "Europe/London"):
        (8 * 60, 16 * 60 + 30)       // LSE: 8:00-16:30
    case let tz where tz.starts(with: "Europe/"):
        (9 * 60, 17 * 60 + 30)       // EU: 9:00-17:30
    case let tz where tz.starts(with: "Asia/Tokyo"):
        (9 * 60, 15 * 60)            // TSE: 9:00-15:00
    case let tz where tz.starts(with: "Asia/Hong_Kong"), let tz where tz.starts(with: "Asia/Shanghai"):
        (9 * 60 + 30, 16 * 60)       // HKEX/SSE: 9:30-16:00
    default:
        (9 * 60 + 30, 16 * 60)       // US default: 9:30-16:00
    }

    return minuteOfDay >= marketOpen && minuteOfDay < marketClose
}
```

`anyMarketOpen` and the callers that consume the verdict (`StockService.swift:130-171, 210-214, 265`):

```swift
var anyMarketOpen: Bool {
    if stocks.isEmpty { return Self.isMarketOpen() }
    return stocks.contains { Self.isMarketOpen(timezoneName: $0.exchangeTimezoneName) }
}
```
Other callers using only the clock heuristic on a stock: `currentDisplayStock` (`:135-136`), `advanceDisplay` (`:154, :165`), and `WatchlistView.swift:473`.

`StockItem.marketState` (`StockItem.swift:17`):
```swift
var marketState: String? = nil  // PRE, REGULAR, POST, CLOSED
```

`marketState` is populated during v7 enrichment (`StockService.swift:318`):
```swift
enriched[i].marketState = extra.marketState
```
and parsed from the v7 JSON at `StockService.swift:484` (`marketState: quote["marketState"] as? String`). Its only current consumer is the tooltip line (`WatchlistView.swift:450-452`):
```swift
if let state = stock.marketState {
    lines.append("Market: \(state)")
}
```

The "Markets Closed" banner consumes `anyMarketOpen` (`WatchlistView.swift:49`):
```swift
if service.marketHoursOnly && !service.anyMarketOpen {
```

Conventions to honor:
- Pure, testable logic is a `nonisolated static func` (e.g. `isMarketOpen(timezoneName:at:)`). Add new pure logic the same way so it is unit-testable without the `@MainActor` service.
- The `switch` uses Swift's expression-`switch` with `case let tz where tz.starts(with:)` matching. Match that style for any new branch.
- Existing market-hours tests construct a `Date` via `DateComponents` in a named timezone, then assert `StockService.isMarketOpen(at:)`. See `StockServiceTests.swift:65-102`. Match this exact structure.
- The test class is `@MainActor final class StockServiceTests: XCTestCase`. Tests that only call the `nonisolated static` heuristic still live in this class.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat c0c912e..HEAD -- TickerBar/Services/StockService.swift TickerBar/Models/StockItem.swift TickerBar/Views/WatchlistView.swift TickerBarTests/StockServiceTests.swift` | empty output (no drift) |
| Build (Release) | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` | ends with `** BUILD SUCCEEDED **` |
| Test | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` | ends with `** TEST SUCCEEDED **` |
| Confirm scope | `git status --porcelain` | only in-scope files listed |

Notes for the executor:
- This is a Swift 6 / SwiftUI + AppKit macOS 14 app under App Sandbox. `TickerBar.xcodeproj/project.pbxproj` is the source of truth for the build; the `project.yml` XcodeGen spec is stale — do not use or regenerate it.
- New `.swift` files are not auto-discovered: this project's pbxproj does **not** use file-system synchronized groups for new files unless they sit in an existing synchronized folder. You are NOT creating any new source files in this plan (all edits go into existing, already-referenced files), so no pbxproj edits are required. If the build fails with "file not found" or a missing symbol after editing only existing files, treat it as a STOP condition.
- Tests run with XCTest. There is no SwiftLint/swift-format step.

## Scope

**In scope** (the only files you may modify):
- `TickerBar/Services/StockService.swift`
- `TickerBarTests/StockServiceTests.swift`

**Out of scope** (do NOT touch):
- `TickerBar/Models/StockItem.swift` — read-only here; `marketState` already exists. Do not add fields.
- `TickerBar/Views/WatchlistView.swift` — the banner and per-row dimming already call `anyMarketOpen` / `isMarketOpen` and will pick up the improved verdict automatically; do not change view code.
- Any exchange-holiday / half-day calendar — deferred (see Maintenance notes).
- `project.yml`, `TickerBar.xcodeproj/project.pbxproj` — no project-file changes needed.
- The v7 parsing (`StockService.swift:456, 484`) — `marketState` is already parsed; do not alter parsing.

## Git workflow

- Branch: `fix/010-market-hours-accuracy` (create from current `HEAD`).
- Commit per tier/logical unit. Imperative subjects matching `git log` style, e.g.:
  - `Add Asian exchange lunch breaks to market-hours heuristic`
  - `Prefer Yahoo marketState over clock heuristic for open/closed`
- HARD RULES: NO `Co-Authored-By` lines, NO "Generated with Claude Code" or any AI attribution anywhere in commits.
- Do NOT push or open a PR unless explicitly instructed.

## Steps

### Step 1 (Tier 1): Encode Asian lunch breaks in `isMarketOpen`

In `TickerBar/Services/StockService.swift`, modify `isMarketOpen(timezoneName:at:)` (`:177-208`) so the open-window check excludes the lunch session for Tokyo, Hong Kong and Shanghai.

Keep the existing `(marketOpen, marketClose)` `switch` exactly as is. Add a parallel computed lunch interval and exclude it. Concretely, after the existing `switch` that produces `(marketOpen, marketClose)`, add a second expression-`switch` producing an optional lunch interval, then exclude it in the final return:

```swift
// Lunch break (local minutes-of-day) for exchanges that close midday.
// Tokyo Stock Exchange: 11:30-12:30. HKEX / SSE: 12:00-13:00.
let lunch: (start: Int, end: Int)? = switch tzID {
case let tz where tz.starts(with: "Asia/Tokyo"):
    (11 * 60 + 30, 12 * 60 + 30)
case let tz where tz.starts(with: "Asia/Hong_Kong"), let tz where tz.starts(with: "Asia/Shanghai"):
    (12 * 60, 13 * 60)
default:
    nil
}

let inSession = minuteOfDay >= marketOpen && minuteOfDay < marketClose
if let lunch, minuteOfDay >= lunch.start && minuteOfDay < lunch.end {
    return false
}
return inSession
```

Replace the existing final line `return minuteOfDay >= marketOpen && minuteOfDay < marketClose` with the block above. Also update the `// Approximate market hours...` comment (`:191-193`) to note lunch breaks are now handled, e.g. append `Asian lunch breaks are excluded below.`

Boundary semantics that the tests will enforce (half-open intervals, matching the existing `>= open && < close` convention):
- Lunch is closed on `[start, end)`: at exactly `lunch.start` minute it is CLOSED; at exactly `lunch.end` minute it is OPEN again.
- Outside lunch but inside `[marketOpen, marketClose)` it is OPEN.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → ends with `** BUILD SUCCEEDED **`.

### Step 2 (Tier 1 tests): Add lunch-break boundary tests

In `TickerBarTests/StockServiceTests.swift`, add tests modeled exactly on `testIsMarketClosedAfterHours` (`:91-102`) — build a `Date` via `DateComponents` in the exchange timezone, then assert `StockService.isMarketOpen(timezoneName:at:)`. Use a known weekday (e.g. 2026-02-18 is a Wednesday, already used by the existing weekday test). Add at minimum:

- `testTokyoOpenBeforeLunch` — `Asia/Tokyo`, 10:00 → `XCTAssertTrue`.
- `testTokyoClosedDuringLunch` — `Asia/Tokyo`, 12:00 → `XCTAssertFalse`.
- `testTokyoLunchStartBoundaryClosed` — `Asia/Tokyo`, 11:30 → `XCTAssertFalse` (closed at exact start).
- `testTokyoLunchEndBoundaryOpen` — `Asia/Tokyo`, 12:30 → `XCTAssertTrue` (open at exact end).
- `testTokyoOpenAfternoon` — `Asia/Tokyo`, 13:00 → `XCTAssertTrue`.
- `testHongKongClosedDuringLunch` — `Asia/Hong_Kong`, 12:30 → `XCTAssertFalse`.
- `testHongKongLunchEndBoundaryOpen` — `Asia/Hong_Kong`, 13:00 → `XCTAssertTrue`.
- `testShanghaiClosedDuringLunch` — `Asia/Shanghai`, 12:30 → `XCTAssertFalse`.
- `testNewYorkNoLunchBreak` — `America/New_York`, 12:00 → `XCTAssertTrue` (regression: US has no lunch exclusion).

Each test passes both `timezoneName:` and `at:` to `isMarketOpen`. Example shape:

```swift
func testTokyoClosedDuringLunch() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    var components = DateComponents()
    components.year = 2026
    components.month = 2
    components.day = 18      // Wednesday
    components.hour = 12
    components.minute = 0
    let date = calendar.date(from: components)!
    XCTAssertFalse(StockService.isMarketOpen(timezoneName: "Asia/Tokyo", at: date))
}
```

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → ends with `** TEST SUCCEEDED **`, and the new `testTokyo*`/`testHongKong*`/`testShanghai*`/`testNewYorkNoLunchBreak` tests appear in the run output as passing.

### Step 3 (Tier 2): Add a marketState-aware open check

In `TickerBar/Services/StockService.swift`, add a new `nonisolated static` helper that decides open/closed for a *specific stock*, preferring its `marketState` and falling back to the clock heuristic. Place it directly below `isMarketOpen(timezoneName:at:)` (after `:208`):

```swift
/// Whether the given stock's market is open. Prefers the Yahoo-reported
/// `marketState` when present (the source of truth from the v7 fetch);
/// falls back to the clock heuristic when `marketState` is nil
/// (e.g. before the first fetch).
nonisolated static func isMarketOpen(for stock: StockItem, at date: Date = Date()) -> Bool {
    switch stock.marketState?.uppercased() {
    case "REGULAR":
        return true
    case "PRE", "POST", "CLOSED", "PREPRE", "POSTPOST":
        return false
    default:
        // nil or unrecognized — fall back to the clock heuristic.
        return isMarketOpen(timezoneName: stock.exchangeTimezoneName, at: date)
    }
}
```

Rationale for mapping: regular session is "open"; PRE/POST/CLOSED and Yahoo's extended PREPRE/POSTPOST states are not regular trading, so for this app's "Markets Closed" / rotation purposes they count as closed (matching the existing heuristic, which is also false outside the regular session). Keep `isMarketOpen(timezoneName:at:)` unchanged as the nonisolated fallback so existing tests hold.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → ends with `** BUILD SUCCEEDED **`.

### Step 4 (Tier 2): Route stock-level callers through the new helper

In `TickerBar/Services/StockService.swift`, switch the callers that hold a `StockItem` from `Self.isMarketOpen(timezoneName: $0.exchangeTimezoneName)` to `Self.isMarketOpen(for: $0)`:

- `currentDisplayStock` (`:135-136`): change `!Self.isMarketOpen(timezoneName: current.exchangeTimezoneName)` → `!Self.isMarketOpen(for: current)`, and `Self.isMarketOpen(timezoneName: $0.exchangeTimezoneName)` → `Self.isMarketOpen(for: $0)`.
- `advanceDisplay` (`:154`): `Self.isMarketOpen(timezoneName: $0.element.exchangeTimezoneName)` → `Self.isMarketOpen(for: $0.element)`.
- `advanceDisplay` (`:165`): `Self.isMarketOpen(timezoneName: stocks[candidate].exchangeTimezoneName)` → `Self.isMarketOpen(for: stocks[candidate])`.
- `anyMarketOpen` (`:213`): `stocks.contains { Self.isMarketOpen(timezoneName: $0.exchangeTimezoneName) }` → `stocks.contains { Self.isMarketOpen(for: $0) }`. Leave the `stocks.isEmpty` early-return (`:212`) calling the plain `isMarketOpen()` heuristic unchanged (no stock, no marketState).

Do NOT change `WatchlistView.swift:473` — it is out of scope (view code) and will continue to use the clock heuristic for per-row dimming; that is acceptable for this plan.

After editing, confirm no stock-holding caller inside `StockService.swift` still uses the timezone-only form:

**Verify**: `grep -n "isMarketOpen(timezoneName: .*exchangeTimezoneName" TickerBar/Services/StockService.swift` → no matches (all stock-level callers now use `isMarketOpen(for:)`); and `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`.

### Step 5 (Tier 2 tests): Test that marketState wins over the clock

In `TickerBarTests/StockServiceTests.swift`, add tests for `isMarketOpen(for:at:)`. Construct `StockItem` literals (it is `Codable`/`Equatable` with defaulted optional fields — only `symbol`, `name`, `price`, `previousClose` are required; set `exchangeTimezoneName` and `marketState` as needed). Pick an `at:` date that the clock heuristic would judge OPEN (e.g. `America/New_York`, weekday 2026-02-18 12:00, the same instant the existing `testIsMarketOpenWeekday` uses) and assert `marketState` overrides it:

- `testMarketStateClosedOverridesOpenClock` — stock with `exchangeTimezoneName: "America/New_York"`, `marketState: "CLOSED"`, `at:` the noon weekday date → `XCTAssertFalse(StockService.isMarketOpen(for: stock, at: date))`.
- `testMarketStateRegularIsOpen` — same stock but `marketState: "REGULAR"` at a date the clock would call closed (e.g. 17:00) → `XCTAssertTrue`.
- `testNilMarketStateFallsBackToClock` — `marketState: nil`, `at:` the noon weekday date → `XCTAssertTrue` (falls back to heuristic, which is open).

Example shape:

```swift
func testMarketStateClosedOverridesOpenClock() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    var components = DateComponents()
    components.year = 2026; components.month = 2; components.day = 18
    components.hour = 12; components.minute = 0
    let date = calendar.date(from: components)!
    let stock = StockItem(
        symbol: "AAPL", name: "Apple", price: 100, previousClose: 99,
        exchangeTimezoneName: "America/New_York", marketState: "CLOSED"
    )
    XCTAssertFalse(StockService.isMarketOpen(for: stock, at: date))
}
```
If the `StockItem` memberwise initializer does not accept those argument labels (it is the synthesized init over the stored properties in declaration order at `StockItem.swift:4-19`), construct it by setting the required positional fields and assigning the optional fields after init; treat a compile failure here as a normal fix, not a STOP condition.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → ends with `** TEST SUCCEEDED **`, with `testMarketStateClosedOverridesOpenClock`, `testMarketStateRegularIsOpen`, `testNilMarketStateFallsBackToClock` shown passing.

## Test plan

- New tests in `TickerBarTests/StockServiceTests.swift`, modeled structurally on `testIsMarketClosedAfterHours` (`:91-102`):
  - Tier 1 lunch boundaries (Step 2): Tokyo before/during/after lunch incl. both `[start, end)` boundaries; Hong Kong + Shanghai during lunch and at the end boundary; a US no-lunch regression case.
  - Tier 2 (Step 5): `marketState == "CLOSED"` treated closed even when the clock says open; `marketState == "REGULAR"` treated open even when the clock says closed; `marketState == nil` falls back to the clock.
- Existing tests `testIsMarketOpenWeekday`, `testIsMarketClosedWeekend`, `testIsMarketClosedAfterHours` (`:65-102`) must still pass unchanged — the `isMarketOpen(timezoneName:at:)` signature and behavior outside lunch are preserved.
- Verification: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`, all existing + all new tests pass.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` ends with `** BUILD SUCCEEDED **`.
- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` ends with `** TEST SUCCEEDED **`.
- [ ] `grep -n "isMarketOpen(for:" TickerBar/Services/StockService.swift` returns at least the new helper definition plus the rewired callers in `currentDisplayStock`, `advanceDisplay`, and `anyMarketOpen`.
- [ ] `grep -n "isMarketOpen(timezoneName: .*exchangeTimezoneName" TickerBar/Services/StockService.swift` returns no matches.
- [ ] `grep -n "11 \* 60 + 30, 12 \* 60 + 30\|12 \* 60, 13 \* 60" TickerBar/Services/StockService.swift` returns the two new lunch intervals.
- [ ] `git status --porcelain` lists only `TickerBar/Services/StockService.swift` and `TickerBarTests/StockServiceTests.swift` as modified (no other files).
- [ ] `plans/README.md` status row for plan 010 updated.

## STOP conditions

Stop and report back (do not improvise) if:

- The drift check shows any in-scope file changed since `c0c912e`, or the "Current state" excerpts (especially `isMarketOpen` at `:177-208`, `enriched[i].marketState = ...` at `:318`, `marketState` field at `StockItem.swift:17`) do not match the live code.
- Plan 009's market-hours tests are not present in `StockServiceTests.swift` (this plan declares a dependency on them) — confirm with `grep -n "isMarketOpen" TickerBarTests/StockServiceTests.swift`; if only the three baseline tests at `:75/:88/:101` exist, report that 009 has not landed before continuing.
- The build fails with a missing-file/missing-symbol error after editing only the two in-scope files (would indicate the pbxproj does not reference them as expected).
- Any verification command fails twice after a reasonable fix attempt.
- The fix appears to require touching an out-of-scope file (e.g. `StockItem.swift` or `WatchlistView.swift`).
- You discover the assumption "Yahoo's `marketState` values are PRE/REGULAR/POST/CLOSED (plus PREPRE/POSTPOST)" is contradicted by an actual observed value the parser stores — report the unexpected value rather than guessing its mapping.

## Maintenance notes

For the owner of this code after the change lands:

- **Holidays and half-days are deliberately OUT OF SCOPE.** The clock heuristic still reports exchanges open on exchange holidays and full duration on half-days. Tier 2 mitigates this for any stock that has a fresh `marketState` (Yahoo reports `CLOSED` on holidays), but before the first fetch — and for any stock without `marketState` — the heuristic is still holiday-blind. A maintained per-exchange holiday calendar is a separate effort; do not bolt a partial holiday list onto `isMarketOpen`.
- `marketState` freshness: the value is only as current as the last successful v7 fetch (`StockService.swift:308-323`). When `marketHoursOnly` skips timer refreshes (`:265`), `marketState` can go stale. This is self-correcting (manual refresh / market reopen triggers a fetch) but is the reason `isMarketOpen(for:)` keeps the clock as a fallback rather than trusting a possibly-stale state when nil.
- `WatchlistView.swift:473` still uses the clock-only `isMarketOpen(timezoneName:)` for per-row dimming, intentionally left out of scope. If you want per-row dimming to also honor `marketState`, switch it to `isMarketOpen(for: stock)` in a follow-up (view-only change).
- Reviewer should scrutinize: the half-open `[start, end)` boundary semantics of the lunch interval (off-by-one at exactly the lunch start/end minute), and the `marketState` string mapping in `isMarketOpen(for:)` (case-insensitivity via `.uppercased()`, and that unrecognized values fall through to the heuristic rather than defaulting to open or closed).
