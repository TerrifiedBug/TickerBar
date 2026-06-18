# Plan 009: Add unit tests for portfolio/FX, sub-unit scaling, price alerts, and market-hours rotation

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c0c912e..HEAD -- TickerBar/Models/StockItem.swift TickerBar/Models/PriceAlert.swift TickerBar/Services/StockService.swift TickerBarTests/StockServiceTests.swift TickerBarTests/StockItemTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: plans/008-*.md (UserDefaults test isolation). Benefits from plans 006 (missing-rate FX handling) and 007 (sub-unit display helper) landing first, but this plan can characterize current behavior if they have not.
- **Category**: tests
- **Planned at**: commit `c0c912e`, 2026-06-17

## Why this matters

The most bug-prone logic in the app — portfolio/FX math, currency sub-unit scaling, price-alert arming/firing, and market-hours rotation across timezones — currently has zero test coverage. Only US market hours, the all-open rotation wrap, the quote parser, `mergedStocks`, and a few settings are tested. A regression in FX conversion silently misreports a user's portfolio value; a regression in alert arming fires (or fails to fire) notifications; a regression in market-hours rotation parks the menu bar on a closed-market stock. This plan adds characterization tests that pin down the current behavior so future refactors (the StockService god-object split, plans 006/007) are caught by a red test instead of a user bug report. It is purely additive: no production code changes.

## Current state

Files involved (only test files are modified; the three source files are read-only references):

- `TickerBar/Models/StockItem.swift` — value type for a quote. Sub-unit scaling and currency-symbol mapping live here.
- `TickerBar/Models/PriceAlert.swift` — alert value type with `isTriggered` and `armed` flag.
- `TickerBar/Services/StockService.swift` — `@MainActor @Observable` service. Holds portfolio/FX math, `checkPriceAlerts`, `advanceDisplay`, and the `nonisolated static isMarketOpen`.
- `TickerBarTests/StockServiceTests.swift` — existing `@MainActor` XCTest suite (the structural pattern for service-instance and `isMarketOpen` tests).
- `TickerBarTests/StockItemTests.swift` — existing non-`@MainActor` XCTest suite (the structural pattern for pure value-type tests).

### Sub-unit scaling and currency symbol (`StockItem.swift:26-81`)

```swift
var isSubUnit: Bool {
    let c = currency ?? ""
    return c == "GBp" || c.uppercased() == "GBX" || c == "ILA"
}
private var subUnitScale: Double { isSubUnit ? 100.0 : 1.0 }
...
var displayPrice: Double { price / subUnitScale }
var displayChange: Double { change / subUnitScale }
...
var currencySymbol: String {
    switch currency?.uppercased() {
    case "GBP", "GBX": return "£"
    case "EUR": return "€"
    case "JPY": return "¥"
    case "CNY", "CNH": return "¥"
    case "HKD": return "HK$"
    case "CHF": return "CHF "
    case "CAD": return "C$"
    case "AUD": return "A$"
    case "INR": return "₹"
    case "KRW": return "₩"
    case "ILA", "ILS": return "₪"
    default: return "$"
    }
}
```

Note: `isSubUnit` matches `"GBp"` (exact case) and `"GBX"` (case-insensitive) and `"ILA"` (exact case). `change` is `price - previousClose`, so `displayChange` for sub-unit currencies is `(price - previousClose) / 100`.

### PriceAlert (`PriceAlert.swift:10-25`)

```swift
init(symbol: String, targetPrice: Double, isAbove: Bool) {
    self.id = UUID()
    ...
    self.armed = false
}
func isTriggered(currentPrice: Double) -> Bool {
    guard armed else { return false }
    return isAbove ? currentPrice >= targetPrice : currentPrice <= targetPrice
}
```

`armed` is `false` on construction. `isTriggered` short-circuits to `false` while disarmed. The crossing comparison is inclusive on both sides (`>=` / `<=`). `armed` is a `var`, so a test can flip it directly: `var alert = PriceAlert(...); alert.armed = true`.

### checkPriceAlerts (`StockService.swift:608-629`) — private, instance, `@MainActor`

```swift
private func checkPriceAlerts() {
    ...
    for i in priceAlerts.indices {
        guard let stock = stocks.first(where: { $0.symbol == priceAlerts[i].symbol }) else { continue }
        if !priceAlerts[i].armed {
            priceAlerts[i].armed = true   // arm on first check
            continue
        }
        if priceAlerts[i].isTriggered(currentPrice: stock.displayPrice) {
            triggeredAlertIDs.insert(priceAlerts[i].id)
            sendAlertNotification(...)
        }
    }
    if !triggeredAlertIDs.isEmpty {
        priceAlerts.removeAll { triggeredAlertIDs.contains($0.id) }
    }
}
```

`checkPriceAlerts` is `private`, so it cannot be called directly from tests. It is invoked at the end of `fetchAllQuotes()` (`StockService.swift:360`), which performs live network I/O and is not callable offline. **Therefore this plan tests the alert behavior at two layers it CAN reach: (a) `PriceAlert.isTriggered` directly (public), and (b) the arm-then-fire state machine reconstructed in the test by manually toggling `armed` and calling `isTriggered`, mirroring `checkPriceAlerts`'s two-cycle logic.** Do NOT attempt to make `checkPriceAlerts` non-private or call `fetchAllQuotes`. See STOP conditions.

### advanceDisplay (`StockService.swift:150-171`) — instance, `@MainActor`

```swift
func advanceDisplay() {
    guard !stocks.isEmpty, rotationEnabled else { return }
    let openStocks = stocks.enumerated().filter {
        Self.isMarketOpen(timezoneName: $0.element.exchangeTimezoneName)
    }
    if openStocks.isEmpty {
        currentDisplayIndex = (currentDisplayIndex + 1) % stocks.count
    } else {
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

`advanceDisplay` calls `isMarketOpen(timezoneName:)` with the **current** wall-clock date (it has no date parameter). To make rotation tests deterministic regardless of when CI runs, a stock is "open" iff its `exchangeTimezoneName` resolves to a market that is open right now. **You cannot control the current time**, so do NOT assert specific open/closed states based on real clock time. Instead, construct stocks whose timezones you can reason about only via `isMarketOpen` evaluated at the same instant — see Step 5 for the deterministic technique (compare `advanceDisplay`'s landing index against `isMarketOpen` evaluated inline in the test, so the assertion holds whatever the wall clock says). `rotationEnabled` defaults to `true`.

### isMarketOpen (`StockService.swift:177-208`) — `nonisolated static`, takes `at date:`

```swift
nonisolated static func isMarketOpen(timezoneName: String? = nil, at date: Date = Date()) -> Bool {
    let tzID = timezoneName ?? "America/New_York"
    ...
    let weekday = calendar.component(.weekday, from: date)
    guard weekday >= 2 && weekday <= 6 else { return false }   // Mon-Fri only
    ...
    let (marketOpen, marketClose): (Int, Int) = switch tzID {
    case let tz where tz.starts(with: "Europe/London"): (8*60, 16*60+30)   // 08:00–16:30
    case let tz where tz.starts(with: "Europe/"):        (9*60, 17*60+30)   // 09:00–17:30
    case let tz where tz.starts(with: "Asia/Tokyo"):     (9*60, 15*60)      // 09:00–15:00
    case let tz where tz.starts(with: "Asia/Hong_Kong"), let tz where tz.starts(with: "Asia/Shanghai"):
                                                         (9*60+30, 16*60)   // 09:30–16:00
    default:                                              (9*60+30, 16*60)   // US 09:30–16:00
    }
    return minuteOfDay >= marketOpen && minuteOfDay < marketClose
}
```

Boundaries: open is inclusive (`>=`), close is exclusive (`<`). For Europe/London the close at exactly `16:30` returns `false`. Because this takes an explicit `at date:`, it IS fully deterministic — construct dates with `DateComponents` in the target timezone, exactly as `testIsMarketOpenWeekday` does.

### Portfolio/FX math (`StockService.swift:656-690`) — instance, `@MainActor`; rate helpers are private

```swift
private func normalizedCurrency(for stock: StockItem) -> String {
    let raw = stock.currency ?? "USD"
    if raw == "GBp" || raw.uppercased() == "GBX" { return "GBP" }
    if raw == "ILA" { return "ILS" }
    return raw.uppercased()
}
private func rateToBase(for stock: StockItem) -> Double {
    let cur = normalizedCurrency(for: stock)
    if cur == baseCurrency { return 1.0 }
    return exchangeRates[cur] ?? 1.0
}
var totalPortfolioValue: Double {
    stocks.reduce(0) { total, stock in
        guard let h = holdings[stock.symbol] else { return total }
        return total + stock.displayPrice * h.shares * rateToBase(for: stock)
    }
}
var totalPortfolioCost: Double {
    stocks.reduce(0) { total, stock in
        guard let h = holdings[stock.symbol] else { return total }
        return total + h.costBasis * h.shares * rateToBase(for: stock)
    }
}
var totalPortfolioGain: Double { totalPortfolioValue - totalPortfolioCost }
var totalPortfolioGainPercent: Double {
    totalPortfolioCost > 0 ? (totalPortfolioGain / totalPortfolioCost) * 100 : 0
}
```

Key behaviors to characterize:
- `rateToBase` is `private`, so tests drive it by seeding `service.exchangeRates`, `service.holdings`, `service.baseCurrency`, and `service.stocks`, then reading the public `totalPortfolio*` computed properties.
- `Holding` is `StockService.Holding(shares:costBasis:)` — public nested struct.
- `holdings` and `priceAlerts` have `didSet` that writes to `UserDefaults.standard` (JSON-encoded). This is exactly why Step 1 depends on plan 008's isolation.
- **Missing-rate behavior (current, characterizes plan 006)**: when a stock's normalized currency is NOT `baseCurrency` and NOT present in `exchangeRates`, `rateToBase` returns `1.0` — the holding is silently counted at a 1:1 rate, not excluded. Plan 006 intends to change this to exclude/flag. This plan asserts the **current** 1.0 fallback so plan 006 will turn the test red and force a conscious update. Label that test clearly as characterizing current (pre-006) behavior.
- `cost == 0` branch: `totalPortfolioGainPercent` returns `0` when `totalPortfolioCost <= 0` (guards divide-by-zero).

### Conventions to follow

- Pure value-type logic (`StockItem`, `PriceAlert`, `isMarketOpen`) is tested in a non-`@MainActor` or static context — model after `StockItemTests.swift` and the `isMarketOpen`/`mergedStocks` tests in `StockServiceTests.swift`.
- Any test that constructs a `StockService` instance or reads its instance properties must be in a `@MainActor` class — the whole `StockServiceTests` class is already `@MainActor`; put service-instance tests there.
- Fixed dates via `DateComponents` in an explicit `TimeZone`, exactly like `testIsMarketOpenWeekday` (`StockServiceTests.swift:65-76`).
- `XCTAssertEqual(..., accuracy:)` for `Double` comparisons, like `StockItemTests.swift:21`.
- Test method names are descriptive `testXxx` with no doc comments, matching both files.
- The `setUp()` in `StockServiceTests` clears persisted keys (`StockServiceTests.swift:7-18`). Plan 008 changes how isolation is achieved — see Step 1.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build (Release) | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` | `** BUILD SUCCEEDED **` |
| Run tests | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` | `** TEST SUCCEEDED **` |
| Run only new alert tests | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test -only-testing:TickerBarTests/PriceAlertTests` | `** TEST SUCCEEDED **` |
| Count test methods in a file | `grep -c "func test" TickerBarTests/StockServiceTests.swift` | integer |
| Confirm no source changed | `git status --porcelain TickerBar/` | empty output |

Run all `xcodebuild` commands from the repo root `/Users/danny/VSCode/workspace/macos-stock-ticker` (where `TickerBar.xcodeproj` lives). Use absolute paths if your shell working directory resets between commands. Note: `TickerBar.xcodeproj/project.pbxproj` is the source of truth; `project.yml` (XcodeGen) is stale — do NOT regenerate the project from it.

## Scope

**In scope** (the only files you should modify):
- `TickerBarTests/StockItemTests.swift` — add sub-unit scaling + currency-symbol tests
- `TickerBarTests/StockServiceTests.swift` — add portfolio/FX tests + market-hours timezone tests + rotation test
- `TickerBarTests/PriceAlertTests.swift` (create) — `PriceAlert.isTriggered` + alert state-machine tests

**Out of scope** (do NOT touch):
- `TickerBar/Models/StockItem.swift`, `TickerBar/Models/PriceAlert.swift`, `TickerBar/Services/StockService.swift` — production code; this is a tests-only plan. If a test reveals a bug, record it in your report; do NOT fix it here.
- `checkPriceAlerts` visibility — do NOT change `private` to internal. Test the reachable layers instead (Step 4).
- `fetchAllQuotes` and any network path — not callable offline.
- `TickerBar.xcodeproj/project.pbxproj` — adding a new test file may require registering it; see Step 3 STOP note.
- `project.yml` — stale XcodeGen spec.

## Git workflow

- Branch: `test/009-tests-money-alert-markethours` (create off the up-to-date base before editing).
- Commit per logical unit (e.g. one commit per step), imperative subject matching `git log` style — examples from history: "Add...", "Fix...". Example for this plan: `Add portfolio/FX unit tests for StockService`.
- HARD RULES: NO "Co-Authored-By" lines, NO "Generated with Claude Code" or any AI attribution anywhere in commits or PR.
- Do NOT push or open a PR unless the operator explicitly tells you to.

## Suggested executor toolkit

- This is XCTest, not swift-testing. Use `XCTAssert*` only.
- There is no SwiftLint/swift-format config — match the surrounding code style by eye.

## Steps

### Step 1: Confirm plan 008 test isolation is in place and create the branch

Plan 008 (dependency) provides isolated `UserDefaults` so tests that touch `holdings`/`priceAlerts`/settings `didSet` don't pollute the real domain. Determine how 008 exposes isolation before writing service-instance tests.

1. Create the branch `test/009-tests-money-alert-markethours`.
2. Read `TickerBarTests/StockServiceTests.swift` `setUp()` and any helper 008 added (e.g. an injected `UserDefaults`, a `StockService(defaults:)` initializer, or a shared test-suite helper). Inline the mechanism you find into the tests you write in Steps 2–5: construct the service exactly the way 008's tests do.

**If plan 008 has NOT landed** (no isolation mechanism exists; `setUp()` still only calls `UserDefaults.standard.removeObject`): this is a blocking dependency — STOP and report that 009 requires 008. Do not proceed by writing to `UserDefaults.standard` directly.

**Verify**: `git branch --show-current` → `test/009-tests-money-alert-markethours`

### Step 2: Add sub-unit scaling + currency-symbol tests to `StockItemTests.swift`

Append new `testXxx` methods to the existing `StockItemTests` class (non-`@MainActor`; `StockItem` is a pure value type). Cover:

- `displayPrice`/`displayChange` for `currency = "GBp"` equals `price / 100` and `change / 100`. Example: `StockItem(symbol:"VOD.L", name:"Vodafone", price: 7000, previousClose: 6800, currency: "GBp")` → `displayPrice == 70.0`, `displayChange == 2.0` (accuracy `0.0001`).
- Same for `currency = "GBX"` (case-insensitive match) and `currency = "ILA"`.
- A lowercase-`"gbx"` case to pin the `.uppercased()` branch (`isSubUnit` true).
- A plain currency (`currency = "USD"`) and `nil` currency → `displayPrice == price`, `displayChange == change` (scale 1.0).
- `currencySymbol` mapping for the major currencies present in the switch: GBP→`£`, GBX→`£`, EUR→`€`, JPY→`¥`, CNY→`¥`, CNH→`¥`, HKD→`HK$`, CHF→`CHF ` (trailing space), CAD→`C$`, AUD→`A$`, INR→`₹`, KRW→`₩`, ILA→`₪`, ILS→`₪`, an unknown code (e.g. `"ZZZ"`)→`$`, and `nil`→`$`.

If plan 007 added a shared sub-unit helper and the executor sees the `displayPrice`/`subUnitScale` shape has changed in the drift check, adapt the assertions to the new helper's surface but keep the same numeric expectations (70.0 etc.).

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test -only-testing:TickerBarTests/StockItemTests` → `** TEST SUCCEEDED **`

### Step 3: Create `PriceAlertTests.swift` and register it with the Xcode project

Create `TickerBarTests/PriceAlertTests.swift` with a non-`@MainActor` `final class PriceAlertTests: XCTestCase` (`PriceAlert` is a pure value type). Cover `isTriggered`:

- Disarmed short-circuit: a freshly-constructed alert (`armed == false`) returns `false` from `isTriggered` even when the price has crossed. e.g. `PriceAlert(symbol:"AAPL", targetPrice: 100, isAbove: true).isTriggered(currentPrice: 150) == false`.
- Above crossing, armed: `targetPrice: 100, isAbove: true`, `armed = true` → `isTriggered(101) == true`, `isTriggered(99) == false`.
- Below crossing, armed: `targetPrice: 100, isAbove: false`, `armed = true` → `isTriggered(99) == true`, `isTriggered(101) == false`.
- Exact-target inclusive boundary (both directions): armed `isAbove: true` → `isTriggered(100) == true`; armed `isAbove: false` → `isTriggered(100) == true`.

To arm: `var alert = PriceAlert(...); alert.armed = true`.

**Registering the file**: this repo's `TickerBar.xcodeproj/project.pbxproj` is hand-maintained (XcodeGen `project.yml` is stale). Adding a brand-new test file means the project must reference it or the test won't compile/run. After creating the file, run the test command (Step 3 Verify). **If the build fails with "no such file" / the new tests do not appear in the run**, the file is not registered: STOP and report that `PriceAlertTests.swift` needs adding to the `TickerBarTests` target in `project.pbxproj` and ask whether to edit `project.pbxproj` (it is otherwise out of scope). Do NOT silently hand-edit `project.pbxproj` without flagging it.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test -only-testing:TickerBarTests/PriceAlertTests` → `** TEST SUCCEEDED **` and the run reports the new test methods executed.

### Step 4: Add the alert arm-then-fire state-machine test to `StockServiceTests.swift`

`checkPriceAlerts` is `private` and only reachable via the network path, so reconstruct its two-cycle contract at the layer you CAN reach. Add a `@MainActor` test (the class is already `@MainActor`) that mirrors `checkPriceAlerts` (`StockService.swift:608-629`):

1. Build a stock whose `displayPrice` is past the target, and an alert against it (`armed == false`).
2. Cycle 1 — arming: assert that while `armed == false`, `isTriggered(currentPrice:)` returns `false` (the fetch cycle that creates the alert must not fire). Then set `armed = true` (this is what `checkPriceAlerts` does on the first check).
3. Cycle 2 — firing: assert `isTriggered(currentPrice:)` now returns `true` (would be inserted into `triggeredAlertIDs` and removed).

Use `stock.displayPrice` (not raw `price`) as the input to `isTriggered`, because `checkPriceAlerts` passes `stock.displayPrice` — exercise this with a sub-unit stock (e.g. `currency:"GBp", price: 15000` → `displayPrice == 150`, target `100`, `isAbove: true`) so the test also pins the sub-unit-aware alert path.

This is a characterization of the contract; it does not call the private method. Name it e.g. `testAlertArmsOnFirstCycleThenFiresOnSecond`.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test -only-testing:TickerBarTests/StockServiceTests` → `** TEST SUCCEEDED **`

### Step 5: Add market-hours timezone tests + rotation test to `StockServiceTests.swift`

**5a — `isMarketOpen` per timezone (fully deterministic, uses `at date:`)**. Model after `testIsMarketOpenWeekday`. Pick a fixed weekday (e.g. 2026-02-18, a Wednesday) and build dates with `DateComponents` in the target `TimeZone`:

- Europe/London open: `12:00` local → `true`. Closed before open: `07:00` → `false`. Close boundary: `16:30` exactly → `false` (close is exclusive). Just inside: `16:29` → `true`.
- Asia/Tokyo: `12:00` → `true`; `15:00` exactly → `false`; `08:59` → `false`.
- Asia/Hong_Kong: `10:00` → `true`; `09:29` → `false`; `16:00` exactly → `false`.
- Weekend for one non-US tz (e.g. Europe/London on Sat 2026-02-21, `12:00`) → `false`.

Build each date in the **same** timezone you pass to `isMarketOpen(timezoneName:)`, so the local wall-clock components are what you intend. Example:
```swift
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Europe/London")!
var c = DateComponents(); c.year = 2026; c.month = 2; c.day = 18; c.hour = 16; c.minute = 30
let d = cal.date(from: c)!
XCTAssertFalse(StockService.isMarketOpen(timezoneName: "Europe/London", at: d))
```

**5b — `advanceDisplay` mixing open + closed timezones (clock-independent)**. `advanceDisplay` uses the live clock with no date hook, so do NOT hard-code which stock is open. Instead make the assertion self-consistent with `isMarketOpen` evaluated at the same instant:

1. Seed `service.stocks` with several stocks carrying different `exchangeTimezoneName` values (mix US, Europe/London, Asia/Tokyo, and at least one designed to be closed-now). Set `service.rotationEnabled = true`.
2. Capture, in the test, `let openIndices = service.stocks.indices.filter { StockService.isMarketOpen(timezoneName: service.stocks[$0].exchangeTimezoneName) }`.
3. **If `openIndices` is non-empty**: set `currentDisplayIndex = 0`, call `advanceDisplay()`, and assert `openIndices.contains(service.currentDisplayIndex)` — it must land on an OPEN stock, and specifically the next open index after the start (compute the expected next-open index in the test by scanning offsets `1...count` the same way the production code does, and assert equality).
4. **If `openIndices` is empty** (all markets happen to be closed at run time): assert the all-closed branch — `advanceDisplay()` advances by exactly one (`currentDisplayIndex` goes from `0` to `1 % count`). This mirrors the existing all-open wrap test (`StockServiceTests.swift:50-63`) but for the all-closed branch.

This structure makes the test pass regardless of when CI runs while still proving `advanceDisplay` prefers the next OPEN index. Name it e.g. `testAdvanceDisplayLandsOnNextOpenStock`.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test -only-testing:TickerBarTests/StockServiceTests` → `** TEST SUCCEEDED **`

### Step 6: Add portfolio/FX tests to `StockServiceTests.swift`

Add `@MainActor` tests that seed the service and read the public `totalPortfolio*` properties. For each: build a `StockService()` the way plan 008's tests do (Step 1), then set `service.stocks`, `service.holdings`, `service.exchangeRates`, `service.baseCurrency`.

Cover:

- **Single-currency value/cost/gain/gainPercent** (`baseCurrency = "USD"`, one USD stock, `exchangeRates = ["USD": 1.0]`). e.g. stock price `100`, holding `shares: 10, costBasis: 80` → value `1000`, cost `800`, gain `200`, gainPercent `25.0` (accuracy `0.0001`).
- **Mixed-currency** (`baseCurrency = "USD"`; one USD stock and one GBP stock with `exchangeRates = ["GBP": 1.25, "USD": 1.0]`). Compute the expected total by hand from `displayPrice * shares * rate` and `costBasis * shares * rate`, and assert value, cost, and gain.
- **Sub-unit currency in portfolio**: a `currency: "GBp"` stock — `normalizedCurrency` maps it to `GBP`, and `totalPortfolioValue` uses `stock.displayPrice` (= price/100) × shares × `exchangeRates["GBP"]`. Verify the price is divided by 100 AND converted by the GBP rate (the two effects compose).
- **cost == 0 percent branch**: holdings with `costBasis: 0` (so `totalPortfolioCost == 0`) → `totalPortfolioGainPercent == 0` (not NaN/Inf). Assert `totalPortfolioGainPercent == 0`.
- **Missing-rate characterization (pre-plan-006 behavior)**: a non-base, non-USD stock (e.g. `currency: "EUR"`) whose code is absent from `exchangeRates`. Current behavior: `rateToBase` falls back to `1.0`, so the holding is counted at 1:1, NOT excluded. Assert the value reflects the `1.0` fallback (i.e. EUR holding contributes `displayPrice * shares * 1.0`). Add a comment: `// Characterizes current (pre-006) silent 1.0 fallback; plan 006 will change this to exclude/flag — update this test when 006 lands.` **If the drift check shows plan 006 already landed** (e.g. `rateToBase` no longer has `?? 1.0`, or an exclusion path exists), instead assert the NEW behavior (holding excluded or flagged) and drop the pre-006 comment.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test -only-testing:TickerBarTests/StockServiceTests` → `** TEST SUCCEEDED **`

### Step 7: Full build + test sweep and source-untouched check

**Verify (all of)**:
- `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`
- `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`
- `git status --porcelain TickerBar/` → empty (no production source modified; only `TickerBar.xcodeproj/project.pbxproj` may appear if Step 3 required registration and the operator approved it).

## Test plan

New tests, by file:

- `TickerBarTests/StockItemTests.swift`: sub-unit scaling (`GBp`/`GBX`/lowercase `gbx`/`ILA` → /100; `USD`/`nil` → /1) for `displayPrice` and `displayChange`; `currencySymbol` mapping for all major codes + unknown + nil. (~6–8 new methods.)
- `TickerBarTests/PriceAlertTests.swift` (new): `isTriggered` disarmed short-circuit; above/below crossing armed; exact-target inclusive boundary both directions. (~5 new methods.)
- `TickerBarTests/StockServiceTests.swift`: alert arm-then-fire state machine (sub-unit-aware); `isMarketOpen` for Europe/London (incl. 16:30 close boundary), Asia/Tokyo, Asia/Hong_Kong, plus a non-US weekend; `advanceDisplay` next-open-index (clock-independent); portfolio single-currency, mixed-currency, sub-unit, cost==0 percent, missing-rate characterization. (~10–12 new methods.)

Structural patterns to copy:
- Value-type tests → `StockItemTests.swift` (no `@MainActor`).
- `isMarketOpen` fixed-date tests → `testIsMarketOpenWeekday` (`StockServiceTests.swift:65-76`).
- Service-instance tests → existing `@MainActor` tests like `testCurrentDisplayIndexWraps` (`StockServiceTests.swift:50-63`), but build the service via plan 008's isolation.

Final verification: `xcodebuild ... test` → `** TEST SUCCEEDED **` with all pre-existing tests still passing plus the new ones.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` prints `** BUILD SUCCEEDED **`
- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` prints `** TEST SUCCEEDED **`
- [ ] `TickerBarTests/PriceAlertTests.swift` exists and its tests run (`-only-testing:TickerBarTests/PriceAlertTests` → `** TEST SUCCEEDED **`)
- [ ] `grep -c "func test" TickerBarTests/StockServiceTests.swift` returns a number strictly greater than 27 (the pre-existing count)
- [ ] `grep -c "func test" TickerBarTests/StockItemTests.swift` returns a number strictly greater than 10 (the pre-existing count)
- [ ] `git status --porcelain TickerBar/` is empty except for an approved `project.pbxproj` registration entry (no `.swift` source under `TickerBar/` modified)
- [ ] No `@MainActor`-isolation or concurrency build warnings introduced (test output has no new warnings referencing the added test files)
- [ ] `plans/README.md` status row for plan 009 updated to DONE

## STOP conditions

Stop and report back (do not improvise) if:

- Plan 008's UserDefaults isolation mechanism is absent (Step 1) — 009 depends on it; writing to `UserDefaults.standard` directly is not acceptable.
- Any "Current state" excerpt does not match the live code per the drift check (the codebase drifted — e.g. plans 006/007 changed `rateToBase`/`displayPrice` shape). Re-read the changed file and adapt assertions per the in-step guidance; if the change is structural enough that the documented behavior no longer holds, STOP.
- Creating `PriceAlertTests.swift` does not get picked up by the test runner and requires editing `TickerBar.xcodeproj/project.pbxproj` (Step 3) — confirm with the operator before touching the project file.
- A test you wrote fails and the failure indicates a real production bug (e.g. `isMarketOpen` close boundary behaves differently than documented). Do NOT change production code to make it pass — report the discrepancy.
- A verification command fails twice after a reasonable fix attempt.
- Making any test pass appears to require changing a file in the "Out of scope" list.

## Maintenance notes

For the human/agent who owns this code after the change lands:

- The missing-rate test in Step 6 deliberately pins the **current** silent `1.0` FX fallback. When plan 006 lands (excludes/flags holdings with no rate), that test MUST be updated to the new contract — it is the intended tripwire.
- The sub-unit tests in Steps 2/4/6 assume `displayPrice == price / 100` for `GBp`/`GBX`/`ILA`. If plan 007 refactors sub-unit handling into a shared helper, keep the numeric expectations (70.0, 150.0, etc.) and repoint the assertions at the new surface.
- `advanceDisplay` has no injectable clock, so its rotation test is written to be clock-independent (Step 5b). If a future change adds an `at date:` parameter to `advanceDisplay`/`currentDisplayStock` (recommended for stronger determinism), tighten the test to assert exact indices at a fixed instant.
- `checkPriceAlerts` is private and only reachable via the live network path; this plan characterizes its contract at the reachable layers. If the service is refactored (the god-object split noted in recon) to expose alert evaluation as a `nonisolated static` pure function, migrate the Step 4 test to call it directly — that would be a strictly better test.
- Reviewer should scrutinize: that no production `.swift` under `TickerBar/` was modified; that the missing-rate test is clearly labeled as pre-006 characterization; and that the timezone date construction uses the same timezone for both the `DateComponents` calendar and the `isMarketOpen(timezoneName:)` argument.
