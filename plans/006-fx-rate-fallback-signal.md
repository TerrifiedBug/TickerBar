# Plan 006: Stop silently valuing holdings at 1.0 when an FX rate is missing

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c0c912e..HEAD -- TickerBar/Services/StockService.swift TickerBar/Views/WatchlistView.swift TickerBarTests/StockServiceTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none (loosely related to plans/008-*.md for UserDefaults injection — only relevant if you choose to write isolation-sensitive tests; this plan does not require it)
- **Category**: bug
- **Planned at**: commit `c0c912e`, 2026-06-17
- **Issue**: <omit>

## Why this matters

When a holding is denominated in a non-base currency (e.g. a JPY stock with USD as the base currency), the portfolio total must multiply the position value by an FX rate. Today `rateToBase(for:)` returns `exchangeRates[cur] ?? 1.0` — so when the rate is **missing**, it silently substitutes `1.0`. `exchangeRates` starts empty (`[:]`), is populated only by a network fetch that returns `[:]` on any failure, and is reassigned wholesale every cycle (the previous-snapshot merge preserves stale *stocks* but NOT *exchangeRates*). The net effect: a failed or partial FX fetch makes a JPY position value as if 1 JPY = 1 USD — roughly 150x too high — and the inflated number is shown in the Watchlist portfolio summary with no warning. This plan makes a missing rate **explicit**: positions whose rate is unknown are excluded from the totals, and the summary surfaces a "rates unavailable" indicator instead of presenting a silently wrong total. Last-good rates are preserved across cycles so a single transient FX-fetch failure does not wipe a working conversion.

## Current state

Files this plan touches:

- `TickerBar/Services/StockService.swift` — `@MainActor @Observable` service; owns `exchangeRates`, FX fetch/merge, `rateToBase`, and the `totalPortfolio*` computed properties.
- `TickerBar/Views/WatchlistView.swift` — SwiftUI menu-bar dropdown; renders the portfolio summary block.
- `TickerBarTests/StockServiceTests.swift` — XCTest target for the service (create or extend).

### The bug: silent 1.0 fallback (`StockService.swift:663-668`)

```swift
    /// Exchange rate from a stock's currency to baseCurrency. Returns 1.0 if same or unknown.
    private func rateToBase(for stock: StockItem) -> Double {
        let cur = normalizedCurrency(for: stock)
        if cur == baseCurrency { return 1.0 }
        return exchangeRates[cur] ?? 1.0
    }
```

### Totals fold the bad multiplier in (`StockService.swift:670-690`)

```swift
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

    var totalPortfolioGain: Double {
        totalPortfolioValue - totalPortfolioCost
    }

    var totalPortfolioGainPercent: Double {
        totalPortfolioCost > 0 ? (totalPortfolioGain / totalPortfolioCost) * 100 : 0
    }
```

### `exchangeRates` declared empty and reassigned wholesale (`StockService.swift:50-51` and `:326-348`)

```swift
    // MARK: - Exchange Rates (e.g. "GBP" -> 1.27 means 1 GBP = 1.27 base currency units)
    var exchangeRates: [String: Double] = [:]
```

```swift
        // Fetch exchange rates for portfolio currency conversion
        if let crumbValue = crumb, !holdings.isEmpty {
            let currencies = Set(enriched.compactMap { stock -> String? in
                guard holdings[stock.symbol] != nil else { return nil }
                // Normalize sub-unit currencies to their major unit
                let raw = stock.currency ?? "USD"
                if raw == "GBp" || raw.uppercased() == "GBX" { return "GBP" }
                if raw == "ILA" { return "ILS" }
                return raw.uppercased()
            })
            let neededRates = currencies.filter { $0 != baseCurrency }
            if !neededRates.isEmpty {
                let rateSymbols = neededRates.map { "\($0)\(baseCurrency)=X" }
                let rates = await Self.fetchExchangeRates(symbols: Array(rateSymbols), crumb: crumbValue)
                for (pair, rate) in rates {
                    // Extract source currency from "GBPUSD=X" -> "GBP"
                    let source = String(pair.prefix(3))
                    exchangeRates[source] = rate
                }
                // Base currency to itself is always 1
                exchangeRates[baseCurrency] = 1.0
            } else {
                exchangeRates = [baseCurrency: 1.0]
            }
        }
```

Note: when `neededRates` is non-empty the code already mutates `exchangeRates[source] = rate` in place (so it does NOT wipe on a failed fetch within this branch — a failed `fetchExchangeRates` returns `[:]`, the loop adds nothing, prior keys survive). The only wholesale reassignment is the `else` branch (`exchangeRates = [baseCurrency: 1.0]`), reached when no non-base rates are needed. That branch is fine to keep. The real defect is purely in `rateToBase` substituting `1.0` for an absent key; preserving last-good rates is already mostly satisfied here. Do not "fix" the in-place mutation — it is correct.

### `normalizedCurrency` helper used by `rateToBase` (`StockService.swift:655-661`)

```swift
    /// Get the normalized major-unit currency code for a stock (GBp/GBX -> GBP, ILA -> ILS)
    private func normalizedCurrency(for stock: StockItem) -> String {
        let raw = stock.currency ?? "USD"
        if raw == "GBp" || raw.uppercased() == "GBX" { return "GBP" }
        if raw == "ILA" { return "ILS" }
        return raw.uppercased()
    }
```

### Portfolio summary in the view (`WatchlistView.swift:70-86`)

```swift
            // Portfolio summary (converted to base currency)
            if service.totalPortfolioValue > 0 {
                HStack {
                    Image(systemName: "chart.pie.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(service.baseCurrencySymbol)\(String(format: "%.0f", service.totalPortfolioValue))")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(String(format: "%@%+.0f (%.1f%%)", service.baseCurrencySymbol, service.totalPortfolioGain, service.totalPortfolioGainPercent))
                        .font(.caption)
                        .foregroundStyle(service.totalPortfolioGain >= 0 ? .green : .red)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 2)
            }
```

### Conventions to honor

- Pure, deterministic logic is factored as `nonisolated static` funcs so it is unit-testable without the `@MainActor` service. Exemplars in this same file: `mergedStocks(watchlist:fresh:previous:)` at `:366-370`, `isMarketOpen(timezoneName:at:)` at `:177-208`, `parseQuoteResponse(data:)` at `:414-447`. Follow this: factor the new "sum positions that have a known rate" logic into a `nonisolated static` function that takes plain inputs (holdings, stocks/prices, a `rates` dictionary, base currency) and returns the total plus a "missing currencies" set. The instance computed properties then delegate to it.
- Tests are XCTest, annotated `@MainActor` where they touch the service. See `TickerBarTests/StockServiceTests.swift` (extend it) and `TickerBarTests/StockItemTests.swift` for structural patterns.
- `exchangeRates` map semantics: key is the **normalized major-unit currency code** (e.g. `"GBP"`, `"JPY"`), value is units-of-base-per-one-source-unit. The base currency maps to `1.0`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build (Release) | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` | `** BUILD SUCCEEDED **` |
| Test | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` | `** TEST SUCCEEDED **` |
| Working tree state | `git status --porcelain` | only in-scope files listed |

There is no SwiftLint/swift-format/editorconfig in this repo; match the surrounding code style by hand. The committed `TickerBar.xcodeproj/project.pbxproj` is the source of truth — ignore `project.yml` (it is stale/broken).

## Scope

**In scope** (the only files you should modify):
- `TickerBar/Services/StockService.swift`
- `TickerBar/Views/WatchlistView.swift`
- `TickerBarTests/StockServiceTests.swift` (extend; create only if absent)

**Out of scope** (do NOT touch, even though they look related):
- The FX fetch network code `fetchExchangeRates(symbols:crumb:)` at `StockService.swift:498-525` and the rate-population block at `:326-348` — the in-place mutation there already preserves last-good rates; changing it risks regressions and is unnecessary for this fix.
- The `else` branch `exchangeRates = [baseCurrency: 1.0]` at `:347` — correct as-is (only reached when no non-base rates are needed).
- `StockItem`, `PriceAlert`, and any persistence/`didSet` logic.
- `TickerBarTests/StockItemTests.swift` — read for structure only; do not modify.
- The public/persisted shape of `holdings` and `exchangeRates` — do not rename or re-key them.

## Git workflow

- Branch: `fix/006-fx-rate-fallback-signal` (create from current `HEAD` / `master`).
- Commit per logical unit. Imperative subjects matching `git log` style (e.g. "Add", "Fix"). Example existing subject: `Fix dropdown empty space after collapsing Settings`. Suggested subjects: `Make missing FX rate explicit in portfolio totals`, `Surface FX-rates-unavailable indicator in watchlist summary`, `Add tests for missing-FX-rate portfolio handling`.
- HARD RULES: NO `Co-Authored-By` lines. NO "Generated with Claude Code" or any AI attribution anywhere in commits or PR text.
- Do NOT push or open a PR unless the operator explicitly instructs it.

## Steps

### Step 1: Add a pure helper and an optional rate accessor

In `TickerBar/Services/StockService.swift`, change `rateToBase(for:)` (`:663-668`) to return `Double?` — `nil` when a required non-base rate is absent:

```swift
    /// Exchange rate from a stock's currency to baseCurrency.
    /// Returns 1.0 for same-currency holdings, and nil when a required
    /// non-base rate is not yet known (so callers can exclude/flag it
    /// instead of silently assuming parity).
    private func rateToBase(for stock: StockItem) -> Double? {
        let cur = normalizedCurrency(for: stock)
        if cur == baseCurrency { return 1.0 }
        return exchangeRates[cur]
    }
```

Then add a `nonisolated static` pure function (place it near `mergedStocks` at `:366`, following that exemplar) that folds a list of per-position `(value, rateKey)` inputs into a total, returning the set of currencies it had to skip:

```swift
    /// Sum a set of per-position base-currency values, skipping any position
    /// whose currency has no known rate. Pure — unit-testable without the service.
    /// - Parameters:
    ///   - positions: (amountInLocalCurrency, normalizedCurrency) per holding.
    ///   - rates: known currency -> base-per-unit rates.
    ///   - baseCurrency: the user's selected base currency code.
    /// - Returns: total in base currency, and the set of currencies skipped for lack of a rate.
    nonisolated static func sumInBase(
        positions: [(amount: Double, currency: String)],
        rates: [String: Double],
        baseCurrency: String
    ) -> (total: Double, missing: Set<String>) {
        var total = 0.0
        var missing: Set<String> = []
        for p in positions {
            if p.currency == baseCurrency {
                total += p.amount
            } else if let rate = rates[p.currency] {
                total += p.amount * rate
            } else {
                missing.insert(p.currency)
            }
        }
        return (total, missing)
    }
```

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **` (it will FAIL here because callers at `:673` and `:680` still treat `rateToBase` as non-optional — that is expected; proceed to Step 2 before re-verifying). If you prefer a green build between steps, do Steps 1 and 2 together and verify once at the end of Step 2.

### Step 2: Rewrite the totals to exclude unknown-rate positions and expose a "missing currencies" flag

Replace the `totalPortfolioValue` and `totalPortfolioCost` computed properties (`:670-682`) so both delegate to `sumInBase`, and add a published-readable computed property reporting whether any held currency lacks a rate. Keep `normalizedCurrency(for:)` as the single source of currency normalization.

Target shape:

```swift
    /// Currencies among current holdings that have no known FX rate yet.
    /// Non-empty means the portfolio totals exclude those positions.
    var missingRateCurrencies: Set<String> {
        var missing: Set<String> = []
        for stock in stocks {
            guard holdings[stock.symbol] != nil else { continue }
            let cur = normalizedCurrency(for: stock)
            if cur != baseCurrency && exchangeRates[cur] == nil {
                missing.insert(cur)
            }
        }
        return missing
    }

    var hasMissingRates: Bool { !missingRateCurrencies.isEmpty }

    var totalPortfolioValue: Double {
        let positions: [(amount: Double, currency: String)] = stocks.compactMap { stock in
            guard let h = holdings[stock.symbol] else { return nil }
            return (stock.displayPrice * h.shares, normalizedCurrency(for: stock))
        }
        return Self.sumInBase(positions: positions, rates: exchangeRates, baseCurrency: baseCurrency).total
    }

    var totalPortfolioCost: Double {
        let positions: [(amount: Double, currency: String)] = stocks.compactMap { stock in
            guard let h = holdings[stock.symbol] else { return nil }
            return (h.costBasis * h.shares, normalizedCurrency(for: stock))
        }
        return Self.sumInBase(positions: positions, rates: exchangeRates, baseCurrency: baseCurrency).total
    }
```

Leave `totalPortfolioGain` (`:684-686`) and `totalPortfolioGainPercent` (`:688-690`) unchanged — they derive from the two totals above.

After this step `rateToBase(for:)` may be unused. If the build warns it is unused, you may delete it (it is `private`); if you keep it for clarity, that is fine. Do not leave a `// TODO`.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`

### Step 3: Surface the indicator in the Watchlist summary

In `TickerBar/Views/WatchlistView.swift`, update the portfolio summary block (`:70-86`). Show the summary when there are any holdings (totals may legitimately be small) but, when `service.hasMissingRates` is true, append a clear "rates unavailable" note and a count of how many positions are excluded. Keep existing styling (`.caption`, the `chart.pie.fill` icon, horizontal padding 12).

Target shape — replace the existing `if service.totalPortfolioValue > 0 { ... }` block with:

```swift
            // Portfolio summary (converted to base currency)
            if service.totalPortfolioValue > 0 || service.hasMissingRates {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "chart.pie.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(service.baseCurrencySymbol)\(String(format: "%.0f", service.totalPortfolioValue))")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(String(format: "%@%+.0f (%.1f%%)", service.baseCurrencySymbol, service.totalPortfolioGain, service.totalPortfolioGainPercent))
                            .font(.caption)
                            .foregroundStyle(service.totalPortfolioGain >= 0 ? .green : .red)
                    }
                    if service.hasMissingRates {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                            Text("Rates unavailable — \(service.missingRateCurrencies.count) holding currency(ies) excluded")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 2)
            }
```

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`

### Step 4: Add tests

Extend `TickerBarTests/StockServiceTests.swift` (create it modeled on `TickerBarTests/StockItemTests.swift` if it does not exist) with tests against the `nonisolated static func sumInBase` — these need no `@MainActor` and no UserDefaults isolation. Add at minimum:

1. `test_sumInBase_excludesMissingRateCurrency`: positions `[(amount: 1000, currency: "JPY"), (amount: 500, currency: "USD")]`, `rates: [:]` (or a map lacking `"JPY"`), `baseCurrency: "USD"` → `total == 500` and `missing == ["JPY"]`. This is the core regression: the JPY position is excluded, NOT folded in at 1.0 (which would have given `1500`).
2. `test_sumInBase_baseCurrencyHoldingsSumWithoutRate`: positions all in base currency, `rates: [:]`, base `"USD"` → total equals the plain sum, `missing` empty.
3. `test_sumInBase_appliesKnownRate`: position `(amount: 100, currency: "GBP")`, `rates: ["GBP": 1.25]`, base `"USD"` → `total == 125`, `missing` empty.

Example structure:

```swift
import XCTest
@testable import TickerBar

final class StockServiceTests: XCTestCase {
    func test_sumInBase_excludesMissingRateCurrency() {
        let result = StockService.sumInBase(
            positions: [(amount: 1000, currency: "JPY"), (amount: 500, currency: "USD")],
            rates: [:],
            baseCurrency: "USD"
        )
        XCTAssertEqual(result.total, 500, accuracy: 0.001)
        XCTAssertEqual(result.missing, ["JPY"])
    }

    func test_sumInBase_baseCurrencyHoldingsSumWithoutRate() {
        let result = StockService.sumInBase(
            positions: [(amount: 200, currency: "USD"), (amount: 300, currency: "USD")],
            rates: [:],
            baseCurrency: "USD"
        )
        XCTAssertEqual(result.total, 500, accuracy: 0.001)
        XCTAssertTrue(result.missing.isEmpty)
    }

    func test_sumInBase_appliesKnownRate() {
        let result = StockService.sumInBase(
            positions: [(amount: 100, currency: "GBP")],
            rates: ["GBP": 1.25],
            baseCurrency: "USD"
        )
        XCTAssertEqual(result.total, 125, accuracy: 0.001)
        XCTAssertTrue(result.missing.isEmpty)
    }
}
```

If you create a new test file, it must be added to the `TickerBarTests` target in `TickerBar.xcodeproj/project.pbxproj` so `xcodebuild test` compiles it. Prefer extending the existing `StockServiceTests.swift` to avoid editing the pbxproj. If `StockServiceTests.swift` does not exist and you cannot get a new file into the test target cleanly, that is a STOP condition (see below).

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`, and the three new `test_sumInBase_*` cases appear in the test log as passed.

## Test plan

- New tests in `TickerBarTests/StockServiceTests.swift` covering: (1) a holding in a currency missing from the rates map is excluded from the total and reported in `missing` — the exact regression (a JPY holding must NOT be valued at 1.0); (2) base-currency holdings still sum correctly with an empty rates map; (3) a known rate is applied correctly. Model the file structure on `TickerBarTests/StockItemTests.swift`.
- This logic is also characterized by plan 009; the cases here are the minimum gate for this fix and should not conflict.
- Verification: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **` with the three new cases passing.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` prints `** BUILD SUCCEEDED **`
- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` prints `** TEST SUCCEEDED **`, and the three `test_sumInBase_*` cases exist and pass
- [ ] `grep -n "exchangeRates\[cur\] ?? 1.0" TickerBar/Services/StockService.swift` returns no matches (the silent fallback is gone)
- [ ] `grep -n "sumInBase" TickerBar/Services/StockService.swift` shows the `nonisolated static` helper and its two call sites in the totals
- [ ] `grep -n "hasMissingRates" TickerBar/Views/WatchlistView.swift` returns at least one match (indicator wired into the view)
- [ ] `git status --porcelain` lists only files in the In-scope set (plus `plans/README.md` if you maintain the index)
- [ ] `plans/README.md` status row for plan 006 updated (unless a reviewer told you they maintain the index)

## STOP conditions

Stop and report back (do not improvise) if:

- The code at `StockService.swift:663-668`, `:670-690`, or `WatchlistView.swift:70-86` does not match the "Current state" excerpts (the codebase has drifted since this plan was written).
- The build or test verification fails twice after a reasonable fix attempt.
- The fix appears to require touching an out-of-scope file — except the one allowed exception: adding a brand-new test file to `TickerBar.xcodeproj/project.pbxproj`. If you must create a new test file AND cannot register it in the test target without broader pbxproj edits, STOP.
- You discover the assumption "`exchangeRates` keys are normalized major-unit currency codes matching `normalizedCurrency(for:)` output" is false (e.g. keys are stored as `"GBPUSD=X"` pairs) — the exclusion logic depends on it.
- Making `rateToBase` return `Double?` reveals additional callers outside the totals (search: `grep -rn "rateToBase" TickerBar/`); if any caller other than `totalPortfolioValue`/`totalPortfolioCost` exists, STOP and report rather than guessing its intended behavior.

## Maintenance notes

For the human/agent who owns this code after the change lands:

- If a currency-conversion feature is added elsewhere (e.g. per-row converted prices), route it through `sumInBase` / the same "skip unknown rate" rule so behavior stays consistent — do not reintroduce a `?? 1.0` default anywhere.
- A reviewer should scrutinize: that `missingRateCurrencies` and `sumInBase` use the identical normalization (`normalizedCurrency(for:)`) as the rate-population block at `:326-334`, so a currency that gets a rate fetched is never simultaneously reported as missing; and that the summary still renders sensibly when ALL holdings are in a missing currency (total `0`, indicator shown).
- Deferred out of this plan: persisting last-good `exchangeRates` across app launches (currently in-memory only, repopulated on first fetch) and a richer "stale rate" timestamp — both are separate concerns and not required to remove the silent-1.0 defect.
