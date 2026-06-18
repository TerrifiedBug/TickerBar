# Plan 012: Use the batched v7 quote as the primary price source; fetch v8 chart only for sparklines

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c0c912e..HEAD -- TickerBar/Services/StockService.swift TickerBar/Models/StockItem.swift TickerBarTests/StockServiceTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/009-*.md (price/portfolio behavior pinned by tests first), plans/005-*.md (URL encoding of symbols) — both should ideally land before this. If neither exists yet, see STOP conditions.
- **Category**: perf
- **Planned at**: commit `c0c912e`, 2026-06-17

## Why this matters

Every refresh currently issues **N+1 HTTP round-trips**: one `/v8/finance/chart/{symbol}` request *per* watchlist symbol (spawned concurrently in `fetchQuotes`), **plus** one already-batched `/v7/finance/quote?symbols=a,b,c` call. The v7 batch call already returns the core fields the app displays (price, day high/low, 52-week range, currency, market state, pre/post-market). The per-symbol v8 chart is only strictly needed for the **intraday sparkline series** (`intradayPrices`). Sourcing core price data from the single v7 batch — and treating v8 purely as the sparkline source — removes the dependency of *displayed prices* on N separate requests, so a watchlist still shows correct numbers even when some v8 chart calls fail or rate-limit. Yahoo also rate-limits aggressive callers; fewer critical requests means more reliable refreshes.

This plan deliberately does **not** remove the v8 calls (the dropdown renders a sparkline for *every* row — see `WatchlistView.swift:487`). It re-wires which response is authoritative for price/previousClose/day-range, so a missing/failed v8 chart degrades to "no sparkline" instead of "no price".

## Current state

Files involved:

- `TickerBar/Services/StockService.swift` — `@Observable @MainActor` service holding all networking. Contains the N+1: `fetchQuotes` (one task per symbol) → `fetchQuote` → `/v8/finance/chart`, plus the batched `fetchV7Quotes` → `/v7/finance/quote`.
- `TickerBar/Models/StockItem.swift` — the `struct StockItem` value type all fields land on. `symbol`, `name`, `price`, `previousClose` are `let`; everything else (`intradayPrices`, `dayHigh`, `dayLow`, `currency`, `exchangeTimezoneName`, `fiftyTwoWeek*`, `marketState`, pre/post-market) is a `var` with a default.
- `TickerBar/Views/WatchlistView.swift` — renders a sparkline per row (load-bearing design fact, see below).
- `TickerBarTests/StockServiceTests.swift` — XCTest suite; `parseQuoteResponse` is already unit-tested here.

Key facts and excerpts (verify these are still exact before editing):

The orchestration that issues the N+1, `StockService.swift:308-323`:

```swift
// Fetch v7 quote data for pre/post market prices (single batch call)
var enriched = result.items
if let crumbValue = crumb, !symbols.isEmpty {
    let v7Data = await Self.fetchV7Quotes(symbols: symbols, crumb: crumbValue)
    for i in enriched.indices {
        if let extra = v7Data[enriched[i].symbol] {
            enriched[i].postMarketPrice = extra.postMarketPrice
            ...
            enriched[i].fiftyTwoWeekHigh = extra.fiftyTwoWeekHigh
            enriched[i].fiftyTwoWeekLow = extra.fiftyTwoWeekLow
        }
    }
}
```

The per-symbol v8 fetch, `StockService.swift:395-412`:

```swift
private nonisolated static func fetchQuote(for symbol: String, crumb: String?) async -> FetchOutcome {
    guard let crumb else { return .failure }
    let urlString = "\(baseURL)/v8/finance/chart/\(symbol)?interval=5m&range=1d&crumb=\(crumb)"
    ...
    return .success(try parseQuoteResponse(data: data))
}
```

The v8 parser that currently produces the authoritative `StockItem` (price comes from `meta["regularMarketPrice"]`, previousClose from `meta["chartPreviousClose"]`), `StockService.swift:414-447`:

```swift
nonisolated static func parseQuoteResponse(data: Data) throws -> StockItem {
    ...
    guard let chart = json?["chart"] as? [String: Any],
          ...
          let price = meta["regularMarketPrice"] as? Double,
          let previousClose = meta["chartPreviousClose"] as? Double
    else { throw StockServiceError.parseError }
    ...
    // Parse intraday close prices for sparkline
    var intradayPrices: [Double] = []
    if let indicators = result["indicators"] as? [String: Any], ... { intradayPrices = ... }
    let dayHigh = meta["regularMarketDayHigh"] as? Double
    let dayLow = meta["regularMarketDayLow"] as? Double
    return StockItem(symbol: symbol, name: name, price: price, previousClose: previousClose, exchangeTimezoneName: exchangeTZ, currency: currency, intradayPrices: intradayPrices, dayHigh: dayHigh, dayLow: dayLow)
}
```

The current batched v7 fetcher, which parses inline (no separate testable parser) and only extracts pre/post/52w/marketState, `StockService.swift:451-493`:

```swift
struct V7QuoteData {
    var postMarketPrice: Double?
    var postMarketChange: Double?
    var preMarketPrice: Double?
    var preMarketChange: Double?
    var marketState: String?
    var fiftyTwoWeekHigh: Double?
    var fiftyTwoWeekLow: Double?
}

private nonisolated static func fetchV7Quotes(symbols: [String], crumb: String) async -> [String: V7QuoteData] {
    let joined = symbols.joined(separator: ",")
    let urlString = "\(baseURL)/v7/finance/quote?symbols=\(joined)&formatted=false&crumb=\(crumb)"
    ...
    for quote in results {
        guard let symbol = quote["symbol"] as? String else { continue }
        dict[symbol] = V7QuoteData( postMarketPrice: quote["postMarketPrice"] as? Double, ... )
    }
}
```

Shared statics referenced by all parsers/fetchers (do not change): `baseURL` (`StockService.swift:97`, `"https://query2.finance.yahoo.com"`), `session` (`StockService.swift:84`), and the error enum `StockServiceError { case parseError; case authError }` (`StockService.swift:779-781`).

`StockItem` field shape — what the merged item must carry, `StockItem.swift:3-19`:

```swift
struct StockItem: Identifiable, Codable, Equatable {
    let symbol: String
    let name: String
    let price: Double
    let previousClose: Double
    var exchangeTimezoneName: String? = nil
    var currency: String? = nil
    var intradayPrices: [Double] = []
    var dayHigh: Double? = nil
    var dayLow: Double? = nil
    ... // pre/post-market + fiftyTwoWeek*
}
```

**Load-bearing design fact**: the dropdown renders a sparkline for *every* row whose `intradayPrices.count >= 2`, not just the pinned/displayed one — `WatchlistView.swift:487-490`:

```swift
if stock.intradayPrices.count >= 2 {
    SparklineView(prices: stock.intradayPrices, isPositive: stock.isPositive)
        .frame(width: 50, height: 20)
}
```

Therefore the v8 chart still has to be fetched for all symbols to keep sparklines on every row. This plan's win is **decoupling displayed price from v8 success**, not eliminating v8 calls. Do NOT remove the per-symbol v8 fetch or change the sparkline UI.

Conventions to honor (match exactly):

- Pure, testable logic is factored as `nonisolated static` funcs — `parseQuoteResponse`, `mergedStocks`, `isMarketOpen`. The new v7 parser MUST follow this pattern (a `nonisolated static func` that takes `Data` and returns parsed values, with the network call kept in a thin wrapper) so it is unit-testable exactly like `parseQuoteResponse`.
- Swift 6 strict concurrency is on; `nonisolated static` funcs touching only locals/`Data` compile cleanly. Match the existing `fetchV7Quotes` signature style.
- Tests are XCTest, `@MainActor` on the class, JSON built as a multiline string literal `.data(using: .utf8)!` — see `StockServiceTests.swift:104-125`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build (Release) | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` | ends `** BUILD SUCCEEDED **`, exit 0 |
| Test | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` | ends `** TEST SUCCEEDED **`, exit 0 |
| Drift check | `git diff --stat c0c912e..HEAD -- TickerBar/Services/StockService.swift TickerBar/Models/StockItem.swift TickerBarTests/StockServiceTests.swift` | empty (no drift) |
| Confirm scope | `git status --porcelain` | only the three in-scope files modified |

Note: there is no SwiftLint/swift-format/editorconfig in this repo and no PR-level CI (CI runs only on `v*` tags via `.github/workflows/release.yml`). Build + test are the only gates.

## Scope

**In scope** (the only files you should modify):
- `TickerBar/Services/StockService.swift`
- `TickerBarTests/StockServiceTests.swift`
- `TickerBar/Models/StockItem.swift` — only if Step 2 requires widening `V7QuoteData` usage; do not change existing `StockItem` fields, only consume them.

**Out of scope** (do NOT touch, even though they look related):
- `TickerBar/Views/WatchlistView.swift` and `TickerBar/Views/SparklineView.swift` — the sparkline UI stays as-is; v8 is still fetched per-symbol to feed it.
- `TickerBar/Services/StockService.swift:495-525` `fetchExchangeRates` — separate concern (FX), leave its v7 call alone.
- `fetchQuote` / `parseQuoteResponse` signatures and the v8 URL — keep them; they remain the sparkline source. You may keep their price/previousClose parsing as a **fallback** but must not make displayed price *depend* on them.
- Auth/crumb flow (`ensureAuth`, `invalidateAuth`, the re-auth retry at `StockService.swift:288-296`) — preserve exactly.

## Git workflow

- Branch: `perf/012-reduce-n-plus-1-fetch` (create from current `master`; do work in a git worktree per repo convention).
- Commit per logical step; imperative subjects matching `git log` style, e.g. `Add parseV7Quote pure parser with unit tests`, `Source core price from batched v7 quote`.
- **No** `Co-Authored-By`, **no** "Generated with Claude Code" / any AI attribution anywhere in commits or PR.
- Do NOT push or open a PR unless the operator explicitly instructs it.

## Steps

### Step 1: Extend `V7QuoteData` and add a testable `parseV7Quotes` pure parser

In `StockService.swift`, widen `struct V7QuoteData` (currently `:451-459`) to also carry the core fields v7 supplies:

```swift
struct V7QuoteData {
    var regularMarketPrice: Double?
    var regularMarketPreviousClose: Double?
    var regularMarketDayHigh: Double?
    var regularMarketDayLow: Double?
    var longName: String?
    var shortName: String?
    var exchangeTimezoneName: String?
    var currency: String?
    // existing:
    var postMarketPrice: Double?
    var postMarketChange: Double?
    var preMarketPrice: Double?
    var preMarketChange: Double?
    var marketState: String?
    var fiftyTwoWeekHigh: Double?
    var fiftyTwoWeekLow: Double?
}
```

Factor the JSON decoding out of `fetchV7Quotes` into a new pure func (mirror `parseQuoteResponse`), keeping the network call in `fetchV7Quotes`:

```swift
nonisolated static func parseV7Quotes(data: Data) -> [String: V7QuoteData] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let quoteResponse = json?["quoteResponse"] as? [String: Any],
          let results = quoteResponse["result"] as? [[String: Any]] else { return [:] }
    var dict: [String: V7QuoteData] = [:]
    for quote in results {
        guard let symbol = quote["symbol"] as? String else { continue }
        dict[symbol] = V7QuoteData(
            regularMarketPrice: quote["regularMarketPrice"] as? Double,
            regularMarketPreviousClose: quote["regularMarketPreviousClose"] as? Double,
            regularMarketDayHigh: quote["regularMarketDayHigh"] as? Double,
            regularMarketDayLow: quote["regularMarketDayLow"] as? Double,
            longName: quote["longName"] as? String,
            shortName: quote["shortName"] as? String,
            exchangeTimezoneName: quote["exchangeTimezoneName"] as? String,
            currency: quote["currency"] as? String,
            postMarketPrice: quote["postMarketPrice"] as? Double,
            postMarketChange: quote["postMarketChange"] as? Double,
            preMarketPrice: quote["preMarketPrice"] as? Double,
            preMarketChange: quote["preMarketChange"] as? Double,
            marketState: quote["marketState"] as? String,
            fiftyTwoWeekHigh: quote["fiftyTwoWeekHigh"] as? Double,
            fiftyTwoWeekLow: quote["fiftyTwoWeekLow"] as? Double
        )
    }
    return dict
}
```

Then make `fetchV7Quotes` call it: replace its inline `for quote in results { ... }` block (`StockService.swift:476-489`) with `return Self.parseV7Quotes(data: data)`, keeping the HTTP/status-code guards above it intact.

Note: Yahoo v7 numbers may decode as `Int` for whole values when `formatted=false`. The existing code uses `as? Double` and has shipped, so keep `as? Double` for consistency — but be aware this is a known fragility (see Maintenance notes). Do not change the cast in this step.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → ends `** BUILD SUCCEEDED **`.

### Step 2: Make v7 the authoritative source for core fields in `fetchAllQuotes`

In `fetchAllQuotes`, the enrich block (`StockService.swift:308-323`) currently only overlays pre/post/52w/marketState onto items whose price already came from v8. Change it so that when v7 returns a value for a symbol, v7's core fields take precedence; v8's `parseQuoteResponse` item is used only for the **sparkline (`intradayPrices`)** and as a per-field fallback when v7 omits a value.

Because `StockItem.price`, `previousClose`, `symbol`, `name` are `let`, you cannot mutate them on the existing item — you must **construct a new `StockItem`** when v7 has the core data. Target shape inside the loop over `enriched.indices`:

```swift
if let v7 = v7Data[enriched[i].symbol] {
    let v8 = enriched[i]  // from parseQuoteResponse: carries intradayPrices + v8 fallbacks
    let name = v7.longName ?? v7.shortName ?? v8.name
    let price = v7.regularMarketPrice ?? v8.price
    let prevClose = v7.regularMarketPreviousClose ?? v8.previousClose
    var merged = StockItem(
        symbol: v8.symbol,
        name: name,
        price: price,
        previousClose: prevClose,
        exchangeTimezoneName: v7.exchangeTimezoneName ?? v8.exchangeTimezoneName,
        currency: v7.currency ?? v8.currency,
        intradayPrices: v8.intradayPrices,                       // sparkline stays from v8
        dayHigh: v7.regularMarketDayHigh ?? v8.dayHigh,
        dayLow: v7.regularMarketDayLow ?? v8.dayLow
    )
    merged.postMarketPrice = v7.postMarketPrice
    merged.postMarketChange = v7.postMarketChange
    merged.preMarketPrice = v7.preMarketPrice
    merged.preMarketChange = v7.preMarketChange
    merged.marketState = v7.marketState
    merged.fiftyTwoWeekHigh = v7.fiftyTwoWeekHigh
    merged.fiftyTwoWeekLow = v7.fiftyTwoWeekLow
    enriched[i] = merged
}
```

Leave the surrounding `if let crumbValue = crumb, !symbols.isEmpty { ... }` guard and the rest of `fetchAllQuotes` (FX rates, `mergedStocks`, `errorMessage`/`lastUpdated`/`isLoading`, `checkPriceAlerts`) unchanged. The last-good merge via `mergedStocks` at `StockService.swift:354-355` still runs afterward on `enriched`, so the keep-last-good behavior is preserved.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`.

### Step 3: Add `parseV7Quotes` unit tests (mirror `parseQuoteResponse` tests)

Add to `TickerBarTests/StockServiceTests.swift`, in a new `// MARK: - parseV7Quotes` section, mirroring the structure of `testParseYahooResponse` (`:104-125`). Cover the fields now sourced from v7:

1. `testParseV7QuoteCoreFields` — JSON with one result containing `symbol`, `regularMarketPrice`, `regularMarketPreviousClose`, `regularMarketDayHigh`, `regularMarketDayLow`, `longName`, `exchangeTimezoneName`, `currency`; assert the dict keyed by symbol carries each value.
2. `testParseV7QuoteFallsBackToShortName` — result with `shortName` but no `longName`; assert `longName == nil` and `shortName` populated (the *consumer* in Step 2 does the `?? shortName` fallback, so assert the raw fields here).
3. `testParseV7QuotePreAndPostMarket` — result with `preMarketPrice/Change`, `postMarketPrice/Change`, `marketState`, `fiftyTwoWeekHigh/Low`; assert all populated.
4. `testParseV7QuoteMissingResultIsEmpty` — JSON `{"quoteResponse":{"result":[]}}`; assert `parseV7Quotes(data:)` returns `[:]`.
5. `testParseV7QuoteMalformedIsEmpty` — JSON `{}`; assert returns `[:]` (no throw — the func returns `[:]` on bad input, unlike `parseQuoteResponse` which throws).

Example skeleton (match repo style):

```swift
func testParseV7QuoteCoreFields() {
    let json = """
    {"quoteResponse":{"result":[{
        "symbol":"AAPL","regularMarketPrice":185.23,
        "regularMarketPreviousClose":183.00,"regularMarketDayHigh":186.0,
        "regularMarketDayLow":182.5,"longName":"Apple Inc.",
        "exchangeTimezoneName":"America/New_York","currency":"USD"
    }]}}
    """.data(using: .utf8)!
    let dict = StockService.parseV7Quotes(data: json)
    let aapl = dict["AAPL"]
    XCTAssertEqual(aapl?.regularMarketPrice, 185.23)
    XCTAssertEqual(aapl?.regularMarketPreviousClose, 183.00)
    XCTAssertEqual(aapl?.regularMarketDayHigh, 186.0)
    XCTAssertEqual(aapl?.currency, "USD")
    XCTAssertEqual(aapl?.exchangeTimezoneName, "America/New_York")
    XCTAssertEqual(aapl?.longName, "Apple Inc.")
}
```

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`, and the 5 new `testParseV7Quote*` tests appear as passed in the output.

### Step 4: Confirm scope and no regression in existing tests

Confirm no out-of-scope files changed and the full suite (including the existing `testParseYahooResponse*` and `testMergedStocks*` tests) still passes.

**Verify**:
- `git status --porcelain` → only `TickerBar/Services/StockService.swift`, `TickerBarTests/StockServiceTests.swift` (and `TickerBar/Models/StockItem.swift` only if you touched it) listed.
- `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`.

## Test plan

- New tests in `TickerBarTests/StockServiceTests.swift`, modeled structurally on `testParseYahooResponse` (`:104-125`):
  - `testParseV7QuoteCoreFields` (happy path — the fields now sourced from v7)
  - `testParseV7QuoteFallsBackToShortName` (name fallback inputs)
  - `testParseV7QuotePreAndPostMarket` (pre/post/52w/marketState)
  - `testParseV7QuoteMissingResultIsEmpty` (empty result array)
  - `testParseV7QuoteMalformedIsEmpty` (malformed JSON → `[:]`)
- Existing tests that MUST still pass unchanged: `testParseYahooResponse`, `testParseYahooResponseFallsBackToShortName`, `testParseYahooResponseMissingFields`, all `testMergedStocks*`.
- Verification: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → all pass, including the 5 new tests.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` ends `** BUILD SUCCEEDED **` (exit 0)
- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` ends `** TEST SUCCEEDED **` (exit 0)
- [ ] `grep -n "func parseV7Quotes" TickerBar/Services/StockService.swift` returns exactly one match
- [ ] `grep -c "testParseV7Quote" TickerBarTests/StockServiceTests.swift` returns `>= 5`
- [ ] `grep -n "regularMarketPrice" TickerBar/Services/StockService.swift` shows the v7 path now references it (i.e. v7 is wired as a price source)
- [ ] `fetchQuote` / `parseQuoteResponse` and the `/v8/finance/chart` URL still present (`grep -n "v8/finance/chart" TickerBar/Services/StockService.swift` returns a match) — sparkline source preserved
- [ ] `git status --porcelain` lists only in-scope files
- [ ] `plans/README.md` status row updated (unless a dispatching reviewer owns the index)

## STOP conditions

Stop and report back (do not improvise) if:

- The code at the locations in "Current state" doesn't match the excerpts (drift since this plan was written; the drift-check diff is non-empty).
- **v7 field-availability assumption is false.** This plan assumes Yahoo `/v7/finance/quote?formatted=false` reliably returns `regularMarketPrice`, `regularMarketPreviousClose`, `regularMarketDayHigh/Low`, `currency`, and `exchangeTimezoneName` for common symbols (US equities, plus GBX/ILA sub-unit symbols the app supports). If you cannot confirm this (e.g. live spot-check or captured fixture shows these missing/null for common symbols), **STOP** — do not ship a path where displayed `price`/`previousClose`/day-range silently regress. Report which fields are missing for which symbol class.
- v7 returns these core numbers as JSON integers (not floats) such that `as? Double` yields `nil` for whole-number values, causing the `?? v8` fallback to mask the win — if your tests or a fixture surface this, STOP and report (the fix is a `Double`-coercion helper, which is a deliberate follow-up, not part of this plan).
- Dependencies 009 and 005 do not exist in `plans/` AND the operator did not waive them — restructuring the parse/merge path before price behavior is pinned by tests risks an unnoticed regression. Report and ask whether to proceed.
- A step's verification fails twice after a reasonable fix attempt.
- The fix appears to require touching an out-of-scope file (e.g. the sparkline UI).

## Maintenance notes

For the human/agent who owns this code after the change lands:

- **`as? Double` fragility**: Yahoo's `formatted=false` v7 responses can encode whole-number values as JSON integers. `as? Double` returns `nil` for an `Int`-typed `NSNumber` in some cases. A hardening follow-up should add a numeric coercion helper (`(quote["x"] as? NSNumber)?.doubleValue`) for the v7 numeric fields. Deliberately deferred here to keep the change behavior-preserving and reviewable.
- **Sparkline coupling**: the v8 per-symbol chart is still fetched for *every* symbol because `WatchlistView.swift:487` renders a sparkline per row. If the UI later shows the sparkline only for the pinned/expanded row, the v8 fetch can be narrowed to that symbol — that is the larger perf win this plan intentionally leaves on the table (it would change `fetchQuotes` to fetch a subset, and must keep `mergedStocks` last-good behavior for rows without a fresh sparkline).
- **Reviewer focus**: scrutinize Step 2 — confirm `price`/`previousClose` come from v7 with a v8 fallback (not the reverse), that `intradayPrices` still comes from v8, and that the `mergedStocks` last-good merge still runs on the rebuilt `enriched` array. Confirm the auth re-try block at `StockService.swift:288-296` is untouched.
- **Follow-up deferred**: narrowing v8 to displayed rows only (see above); `Double` coercion hardening; both out of scope here.
