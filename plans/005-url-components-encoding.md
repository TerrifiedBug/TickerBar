# Plan 005: Build all Yahoo URLs with URLComponents so crumb and symbols are correctly encoded

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c0c912e..HEAD -- TickerBar/Services/StockService.swift TickerBarTests/StockServiceTests.swift`
> If either in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none (benefits from plans/001 CI, but independently verifiable via the test suite)
- **Category**: bug
- **Planned at**: commit `c0c912e`, 2026-06-17

## Why this matters

Yahoo Finance crumb tokens routinely contain `+`, `/`, and `=`. Every Yahoo request in `StockService` builds its URL by raw string interpolation of the crumb (and symbols) into the query string, then — for three of the four — wraps the *whole* URL in `addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)`. `.urlQueryAllowed` treats `+`, `&`, and `#` as already-legal query characters and does **not** escape them. A `+` in the crumb is therefore sent literally and decoded server-side as a space, corrupting the crumb. That yields 401/403 on the v8 chart call, so `fetchAllQuotes` sees `result.items.isEmpty && result.authFailures > 0`, enters its re-auth-and-retry path, fails again, and surfaces "Couldn't refresh — showing last update" — a re-authentication loop where no symbol ever loads. The v7 quote and FX calls fail more quietly: a corrupted crumb returns a non-200 and they return `[:]`, so pre/post-market prices and portfolio currency conversion silently break.

Separately, the v8 chart URL interpolates the raw `symbol` straight into the path. For index symbols like `^GSPC` the caret is not a legal path character, so `URL(string:)` returns `nil` and `fetchQuote` returns `.failure` with no diagnostic — the symbol silently never appears.

After this plan, every Yahoo URL is assembled with `URLComponents` + `[URLQueryItem]` (which percent-encodes each query value per-component, correctly escaping `+`/`/`/`=`), and the v8 chart symbol is percent-encoded for the path segment so `^`-prefixed indices resolve. The URL construction is extracted into `nonisolated static` helpers so it is unit-testable, matching the existing pattern (`parseQuoteResponse`, `mergedStocks`, `isMarketOpen`).

## Current state

Files:

- `TickerBar/Services/StockService.swift` — the only networking layer; contains all four Yahoo fetch functions plus the getcrumb auth flow. `StockService` is `@MainActor @Observable`; pure logic is factored as `nonisolated static` funcs.
- `TickerBarTests/StockServiceTests.swift` — XCTest suite, `@MainActor final class`. Pure-logic tests (e.g. `testParseYahooResponse`, `testMergedStocks*`) call `StockService.<staticFunc>` directly with no service instance.

The base URL constant (line 97):

```swift
nonisolated private static let baseURL = "https://query2.finance.yahoo.com"
```

`fetchQuote` — raw path + raw crumb, no encoding anywhere (lines 395–399):

```swift
private nonisolated static func fetchQuote(for symbol: String, crumb: String?) async -> FetchOutcome {
    guard let crumb else { return .failure }
    let urlString = "\(baseURL)/v8/finance/chart/\(symbol)?interval=5m&range=1d&crumb=\(crumb)"
    guard let url = URL(string: urlString) else { return .failure }
```

`fetchV7Quotes` — whole-string `.urlQueryAllowed` wrap (lines 462–465):

```swift
private nonisolated static func fetchV7Quotes(symbols: [String], crumb: String) async -> [String: V7QuoteData] {
    let joined = symbols.joined(separator: ",")
    let urlString = "\(baseURL)/v7/finance/quote?symbols=\(joined)&formatted=false&crumb=\(crumb)"
    guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) else { return [:] }
```

`fetchExchangeRates` — same whole-string wrap (lines 498–502):

```swift
private nonisolated static func fetchExchangeRates(symbols: [String], crumb: String) async -> [String: Double] {
    let joined = symbols.joined(separator: ",")
    let urlString = "\(baseURL)/v7/finance/quote?symbols=\(joined)&formatted=false&crumb=\(crumb)"
    guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let url = URL(string: encoded) else { return [:] }
```

`searchSymbols` — same whole-string wrap, no crumb (lines 717–718):

```swift
let urlString = "\(Self.baseURL)/v1/finance/search?q=\(trimmed)"esCount=6&newsCount=0&listsCount=0"
guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) else { return [] }
```

The getcrumb auth URLs (lines 228–233) — these have **no** query parameters and are static literal strings, so they are already safe; do not change their behavior:

```swift
let cookieURL = URL(string: "https://fc.yahoo.com")!
let _ = try? await Self.session.data(from: cookieURL)
let crumbURL = URL(string: "\(Self.baseURL)/v1/test/getcrumb")!
```

Conventions to follow:

- Pure, testable logic is `nonisolated static` — exemplars in this same file: `parseQuoteResponse` (line 414), `mergedStocks` (line 366), `isMarketOpen` (line 177).
- Tests call those statics directly: see `testParseYahooResponse` (line 104) and `testMergedStocksPrefersFreshFollowsWatchlistOrderAndKeepsLastGood` (line 167). Model the new URL-builder tests on these — no `StockService()` instance is required for static helpers, though the test class is `@MainActor`.
- Swift 6 strict concurrency is on. New helpers must be `nonisolated static` and operate only on value types (`String`, `URL`, `[String]`) so they stay `Sendable`-clean.
- macOS 14 deployment target — `URLComponents`, `URLQueryItem`, and `URLComponents.percentEncodedQuery` are all available.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat c0c912e..HEAD -- TickerBar/Services/StockService.swift TickerBarTests/StockServiceTests.swift` | no output (no drift) |
| Build (Release) | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` | `** BUILD SUCCEEDED **` |
| Test | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` | `** TEST SUCCEEDED **` |
| Confirm no stray edits | `git status --porcelain` | only the two in-scope files listed |

Run all commands from the repo root `/Users/danny/VSCode/workspace/macos-stock-ticker`. The committed `TickerBar.xcodeproj/project.pbxproj` is the source of truth — ignore `project.yml` (the XcodeGen spec is stale/broken; do not run XcodeGen).

## Scope

**In scope** (the only files you should modify):
- `TickerBar/Services/StockService.swift`
- `TickerBarTests/StockServiceTests.swift`

**Out of scope** (do NOT touch, even though they look related):
- The getcrumb/cookie auth URLs (`fc.yahoo.com`, `/v1/test/getcrumb`) — they carry no query parameters, so encoding is moot; rewriting them adds risk for no fix.
- The session configuration, headers, retry/re-auth logic in `fetchAllQuotes`, and the `parseQuoteResponse`/`mergedStocks` parsing logic — this plan changes only how URLs are *built*, not how responses are handled.
- Any change to the `baseURL` value or the set of query parameters sent (keep `interval`, `range`, `quotesCount`, etc. identical).
- `project.yml`, `TickerBar.xcodeproj/project.pbxproj` — no new files are added, so no project changes are needed.

## Git workflow

- Branch: `fix/005-url-components-encoding` (created from `master`).
- Commit per logical unit. Imperative subjects matching `git log` style (e.g. "Add...", "Fix..."). Example existing subject: `Fix dropdown empty space after collapsing Settings`.
- Do NOT add `Co-Authored-By`, `Generated with Claude Code`, or any AI attribution anywhere in commits or PR text.
- Do NOT push or open a PR unless the operator explicitly instructs it.

## Steps

### Step 1: Create the branch

```bash
git switch -c fix/005-url-components-encoding
```

**Verify**: `git branch --show-current` → `fix/005-url-components-encoding`

### Step 2: Add three `nonisolated static` URL-builder helpers

In `TickerBar/Services/StockService.swift`, add a new helper section. Place it immediately **after** the `baseURL` constant block (after line 97, before `init()`), so the helpers and the constant they use are adjacent. Add exactly these three helpers:

```swift
// MARK: - URL Construction
//
// All Yahoo URLs are built with URLComponents so each query value (crumb,
// symbols, search query) is percent-encoded per-component. A whole-string
// addingPercentEncoding(.urlQueryAllowed) does NOT escape '+'/'&'/'#', which
// corrupts crumbs containing '+'. Pure + nonisolated for unit testing.

/// v8 chart URL. The symbol is part of the PATH (e.g. "^GSPC"), so it is
/// percent-encoded for a path segment, while the crumb is a query value.
nonisolated static func chartURL(symbol: String, crumb: String) -> URL? {
    guard let encodedSymbol = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
        return nil
    }
    var components = URLComponents(string: "\(baseURL)/v8/finance/chart/\(encodedSymbol)")
    components?.queryItems = [
        URLQueryItem(name: "interval", value: "5m"),
        URLQueryItem(name: "range", value: "1d"),
        URLQueryItem(name: "crumb", value: crumb)
    ]
    return components?.url
}

/// v7 quote URL used for both pre/post-market data and FX rates.
nonisolated static func quoteURL(symbols: [String], crumb: String) -> URL? {
    var components = URLComponents(string: "\(baseURL)/v7/finance/quote")
    components?.queryItems = [
        URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
        URLQueryItem(name: "formatted", value: "false"),
        URLQueryItem(name: "crumb", value: crumb)
    ]
    return components?.url
}

/// v1 symbol-search URL. No crumb required.
nonisolated static func searchURL(query: String) -> URL? {
    var components = URLComponents(string: "\(baseURL)/v1/finance/search")
    components?.queryItems = [
        URLQueryItem(name: "q", value: query),
        URLQueryItem(name: "quotesCount", value: "6"),
        URLQueryItem(name: "newsCount", value: "0"),
        URLQueryItem(name: "listsCount", value: "0")
    ]
    return components?.url
}
```

Note: `URLComponents` percent-encodes `+` in a query *value* as `%2B`, which is exactly the fix. The `,` separating symbols is left literal by `URLComponents` (legal in a query value) — this matches what Yahoo expects and what the old code produced.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **` (helpers compile; not yet wired in).

### Step 3: Switch `fetchQuote` to `chartURL`

Replace the URL construction in `fetchQuote` (current lines 397–398). Change:

```swift
let urlString = "\(baseURL)/v8/finance/chart/\(symbol)?interval=5m&range=1d&crumb=\(crumb)"
guard let url = URL(string: urlString) else { return .failure }
```

to:

```swift
guard let url = chartURL(symbol: symbol, crumb: crumb) else { return .failure }
```

(`crumb` is already non-optional at this point because of the preceding `guard let crumb else { return .failure }`.)

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`

### Step 4: Switch `fetchV7Quotes` to `quoteURL`

Replace the URL construction in `fetchV7Quotes` (current lines 463–465). Change:

```swift
let joined = symbols.joined(separator: ",")
let urlString = "\(baseURL)/v7/finance/quote?symbols=\(joined)&formatted=false&crumb=\(crumb)"
guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) else { return [:] }
```

to:

```swift
guard let url = quoteURL(symbols: symbols, crumb: crumb) else { return [:] }
```

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`

### Step 5: Switch `fetchExchangeRates` to `quoteURL`

Replace the URL construction in `fetchExchangeRates` (current lines 499–502). Change:

```swift
let joined = symbols.joined(separator: ",")
let urlString = "\(baseURL)/v7/finance/quote?symbols=\(joined)&formatted=false&crumb=\(crumb)"
guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
      let url = URL(string: encoded) else { return [:] }
```

to:

```swift
guard let url = quoteURL(symbols: symbols, crumb: crumb) else { return [:] }
```

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`

### Step 6: Switch `searchSymbols` to `searchURL`

Replace the URL construction in `searchSymbols` (current lines 717–718). Change:

```swift
let urlString = "\(Self.baseURL)/v1/finance/search?q=\(trimmed)"esCount=6&newsCount=0&listsCount=0"
guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) else { return [] }
```

to:

```swift
guard let url = Self.searchURL(query: trimmed) else { return [] }
```

(Note the `Self.` prefix: `searchSymbols` is an instance method, unlike the `nonisolated static` fetch functions, so it must qualify the static helper.)

**Verify**: `grep -n "addingPercentEncoding" TickerBar/Services/StockService.swift` → no matches (all four call sites converted; the auth URLs never used it).

### Step 7: Commit the implementation

```bash
git add TickerBar/Services/StockService.swift
git commit -m "Build Yahoo URLs with URLComponents to encode crumb and symbols"
```

**Verify**: `git log -1 --pretty=%s` → `Build Yahoo URLs with URLComponents to encode crumb and symbols`

### Step 8: Add unit tests for the URL builders

In `TickerBarTests/StockServiceTests.swift`, add a new test section before the final closing `}` of the class (after line 239). Model these on `testParseYahooResponse` — call the statics directly, no instance needed.

```swift
// MARK: - URL construction (per-component encoding)

func testChartURLEncodesCrumbPlusAsPercent2B() throws {
    let url = try XCTUnwrap(StockService.chartURL(symbol: "AAPL", crumb: "ab+cd"))
    let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    // percentEncodedQuery preserves the raw on-wire encoding.
    let query = try XCTUnwrap(comps.percentEncodedQuery)
    XCTAssertTrue(query.contains("crumb=ab%2Bcd"), "got: \(query)")
    XCTAssertFalse(query.contains("crumb=ab+cd"), "raw '+' must not survive: \(query)")
}

func testChartURLEncodesCrumbSlashAndEquals() throws {
    let url = try XCTUnwrap(StockService.chartURL(symbol: "AAPL", crumb: "a/b=c"))
    let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery)
    XCTAssertTrue(query.contains("crumb=a%2Fb%3Dc"), "got: \(query)")
}

func testChartURLResolvesCaretIndexSymbol() throws {
    // "^GSPC" used to make URL(string:) return nil; it must now be non-nil.
    let url = try XCTUnwrap(StockService.chartURL(symbol: "^GSPC", crumb: "abc"))
    XCTAssertTrue(url.path.contains("GSPC"))
    XCTAssertEqual(url.host, "query2.finance.yahoo.com")
}

func testChartURLKeepsExpectedQueryParameters() throws {
    let url = try XCTUnwrap(StockService.chartURL(symbol: "AAPL", crumb: "abc"))
    let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery)
    XCTAssertTrue(query.contains("interval=5m"))
    XCTAssertTrue(query.contains("range=1d"))
}

func testQuoteURLEncodesCrumbAndJoinsSymbols() throws {
    let url = try XCTUnwrap(StockService.quoteURL(symbols: ["GBPUSD=X", "EURUSD=X"], crumb: "x+y"))
    let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery)
    XCTAssertTrue(query.contains("crumb=x%2By"), "got: \(query)")
    // Symbols are comma-joined; '=' inside the symbol is encoded as %3D.
    XCTAssertTrue(query.contains("symbols="))
    XCTAssertTrue(query.contains("GBPUSD%3DX"), "got: \(query)")
    XCTAssertTrue(query.contains("formatted=false"))
}

func testSearchURLEncodesQuery() throws {
    let url = try XCTUnwrap(StockService.searchURL(query: "S&P 500"))
    let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery)
    // '&' in the user query must be escaped so it isn't read as a param separator.
    XCTAssertTrue(query.contains("q=S%26P%20500") || query.contains("q=S%26P+500"), "got: \(query)")
    XCTAssertTrue(query.contains("quotesCount=6"))
}
```

If `chartURL`, `quoteURL`, or `searchURL` is reported as inaccessible from the test target, confirm it is declared `nonisolated static` (not `private`) per Step 2 — the helpers must be internal so `@testable import TickerBar` can reach them. Do NOT mark them `private`.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`, and the 6 new tests appear in the output.

### Step 9: Commit the tests

```bash
git add TickerBarTests/StockServiceTests.swift
git commit -m "Add tests for URLComponents-based Yahoo URL builders"
```

**Verify**: `git log -1 --pretty=%s` → `Add tests for URLComponents-based Yahoo URL builders`

### Step 10: Update the plans index

If `plans/README.md` exists, set this plan's status row to `DONE`. If it does not exist, skip (a reviewer maintains it).

**Verify**: `test -f plans/README.md && grep -n "005" plans/README.md || echo "no index"` → either the row showing `DONE`, or `no index`.

## Test plan

- New tests in `TickerBarTests/StockServiceTests.swift`, in a new `// MARK: - URL construction` section, covering:
  - `testChartURLEncodesCrumbPlusAsPercent2B` — the core regression: crumb `ab+cd` must serialize to `crumb=ab%2Bcd`, not `crumb=ab+cd`.
  - `testChartURLEncodesCrumbSlashAndEquals` — `/` and `=` in the crumb escaped (`%2F`, `%3D`).
  - `testChartURLResolvesCaretIndexSymbol` — `^GSPC` yields a non-nil URL (was nil before).
  - `testChartURLKeepsExpectedQueryParameters` — `interval=5m` and `range=1d` preserved.
  - `testQuoteURLEncodesCrumbAndJoinsSymbols` — crumb encoded, symbols comma-joined with `=` inside symbol escaped.
  - `testSearchURLEncodesQuery` — `&` in the search query escaped so it cannot inject a parameter.
- Structural pattern: model after `testParseYahooResponse` (line 104) — static call, `try`/`XCTUnwrap`, direct assertions. No `StockService()` instance.
- Verification: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **` with all prior tests plus the 6 new ones passing.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` ends with `** BUILD SUCCEEDED **`
- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` ends with `** TEST SUCCEEDED **`; the 6 new URL tests are present and pass
- [ ] `grep -n "addingPercentEncoding" TickerBar/Services/StockService.swift` returns no matches
- [ ] `grep -cn "chartURL\|quoteURL\|searchURL" TickerBar/Services/StockService.swift` shows the helpers are defined and called (≥ 6 matches: 3 definitions + at least 3 call sites; note `quoteURL` is called twice)
- [ ] `git status --porcelain` lists only `TickerBar/Services/StockService.swift` and `TickerBarTests/StockServiceTests.swift` (plus `plans/README.md` if it exists)
- [ ] `plans/README.md` status row updated to DONE (or no index file present)

## STOP conditions

Stop and report back (do not improvise) if:

- The code at the locations in "Current state" doesn't match the excerpts (drift since this plan was written) — especially if any fetch function has already been refactored to use `URLComponents`, or the file has been split into multiple files (a noted "God Object" refactor is on the radar for this file).
- A step's verification fails twice after a reasonable fix attempt.
- The build fails because `URLComponents`/`URLQueryItem`/`percentEncodedQuery` are unavailable (would indicate the deployment target is below macOS 14 — out of scope to change).
- The test target cannot see the new helpers even after confirming they are `nonisolated static` (non-`private`) — this signals a target-membership or access issue beyond this plan's scope.
- The fix appears to require touching any file outside the in-scope list.

## Maintenance notes

For the human/agent who owns this code after the change lands:

- All future Yahoo endpoints must be built through these helpers (or new ones following the same `URLComponents` pattern). Never reintroduce raw string interpolation of crumb/symbols, and never reach for whole-string `addingPercentEncoding(.urlQueryAllowed)` on a query — it does not escape `+`/`&`/`#`.
- If the "God Object" refactor splits `StockService` into a dedicated networking type, move `chartURL`/`quoteURL`/`searchURL` (and their tests) with the networking code; keep them `nonisolated static` so the tests stay instance-free.
- Reviewer should scrutinize: that the query parameter *set* is byte-for-byte the same as before (only the encoding changed), and that the `,` between symbols is intentionally left literal (Yahoo expects literal commas in the `symbols` value).
- Deferred out of scope: adding a real networking integration test that hits Yahoo (would be flaky/offline-fragile in CI); and surfacing a diagnostic when `fetchQuote` returns `.failure` due to a nil URL (a separate observability improvement).
