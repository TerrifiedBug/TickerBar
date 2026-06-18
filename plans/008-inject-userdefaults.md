# Plan 008: Inject UserDefaults into StockService so tests stop polluting real preferences

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c0c912e..HEAD -- TickerBar/Services/StockService.swift TickerBar/TickerBarApp.swift TickerBarTests/StockServiceTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `c0c912e`, 2026-06-17
- **Issue**: (omit)

## Why this matters

`StockService` hardcodes `UserDefaults.standard` in its initializer, in all 11 settings `didSet` blocks, and in the `holdings`/`priceAlerts` persistence `didSet` blocks. Its unit tests construct `StockService()` and read/write `UserDefaults.standard` directly. Because the test host is the real sandboxed app (`com.tickerbar.app`), running the test suite **overwrites the installed app's actual saved preferences** (watchlist, font size, holdings, etc.) on the developer's machine. The tests also leak state between runs: `setUp` clears only 8 of the persisted keys (it misses `holdings`, `priceAlerts`, `baseCurrency`, `compactMenuBar`, `showPercentChange`, `rotationSpeed`... actually it clears `rotationSpeed`; it misses `holdings`, `priceAlerts`, `baseCurrency`, `compactMenuBar`, `showPercentChange`), and there is no `tearDown`, so tests are order-dependent.

After this change, `StockService` accepts an injected `UserDefaults` (defaulting to `.standard`, so production wiring is unchanged), and the tests run against a throwaway per-test suite that is destroyed in `tearDown`. Tests become hermetic and order-independent, and they stop touching the developer's real app preferences. This is the prerequisite seam for plan 009's clean test rewrite.

## Current state

Files involved:

- `TickerBar/Services/StockService.swift` — the `@MainActor @Observable final class StockService`; contains the init (lines 99–126) and all `UserDefaults.standard` references (14 total). This is the only file whose production logic changes.
- `TickerBar/TickerBarApp.swift` — the single production call site; line 7 constructs `StockService()` with no arguments. Adding a defaulted parameter leaves this line valid and unchanged.
- `TickerBarTests/StockServiceTests.swift` — the XCTest suite; `setUp` (lines 7–18) clears 8 keys from `UserDefaults.standard`; persistence tests (lines 222–239) write to and read back from `UserDefaults.standard`.

### `StockService.swift` — init reads from `UserDefaults.standard` (lines 99–126)

```swift
    init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.stringArray(forKey: "watchlist"), !saved.isEmpty {
            self.watchlist = saved
        } else {
            self.watchlist = Self.defaultWatchlist
        }
        self.refreshInterval = defaults.double(forKey: "refreshInterval").nonZero ?? 60
        ...
        self.solidPopoverBackground = defaults.bool(forKey: "solidPopoverBackground")

        if let alertData = defaults.data(forKey: "priceAlerts"), ...
        if let holdingsData = defaults.data(forKey: "holdings"), ...
    }
```

Note: the init already binds a local `let defaults = UserDefaults.standard` and uses `defaults.…` throughout its body. The `let defaults = UserDefaults.standard` line is the ONLY `UserDefaults.standard` reference inside the init body — the rest of the init already goes through the `defaults` local.

### `StockService.swift` — `didSet` blocks write to `UserDefaults.standard` (lines 16–76)

There are 11 settings `didSet` blocks of this shape, e.g. line 16–18:

```swift
    var watchlist: [String] {
        didSet { UserDefaults.standard.set(watchlist, forKey: "watchlist") }
    }
```

The full list of stored-property `didSet` blocks each containing one `UserDefaults.standard.set(...)`:
`watchlist` (17), `refreshInterval` (20), `rotationEnabled` (23), `rotationSpeed` (26), `pinnedSymbol` (29), `marketHoursOnly` (32), `showPercentChange` (35), `compactMenuBar` (38), `baseCurrency` (41), `menuBarFontSize` (44), `solidPopoverBackground` (47).

Plus two collection `didSet` blocks:

```swift
    var holdings: [String: Holding] = [:] {        // line 61
        didSet {
            if let data = try? JSONEncoder().encode(holdings) {
                UserDefaults.standard.set(data, forKey: "holdings")   // line 64
            }
        }
    }

    var priceAlerts: [PriceAlert] = [] {           // line 70
        didSet {
            if let data = try? JSONEncoder().encode(priceAlerts) {
                UserDefaults.standard.set(data, forKey: "priceAlerts")  // line 72
            }
        }
    }
```

Total: 1 (init local) + 11 (settings didSet) + 2 (collection didSet) = **14** `UserDefaults.standard` references inside the class (confirmed via `grep -c`).

### `TickerBar/TickerBarApp.swift` — the only call site (line 7)

```swift
    @State private var stockService = StockService()
```

### `TickerBarTests/StockServiceTests.swift` — current `setUp` (lines 7–18), no `tearDown`

```swift
    override func setUp() {
        super.setUp()
        // Clear persisted watchlist so each test starts fresh
        UserDefaults.standard.removeObject(forKey: "watchlist")
        UserDefaults.standard.removeObject(forKey: "refreshInterval")
        UserDefaults.standard.removeObject(forKey: "rotationEnabled")
        UserDefaults.standard.removeObject(forKey: "rotationSpeed")
        UserDefaults.standard.removeObject(forKey: "pinnedSymbol")
        UserDefaults.standard.removeObject(forKey: "marketHoursOnly")
        UserDefaults.standard.removeObject(forKey: "menuBarFontSize")
        UserDefaults.standard.removeObject(forKey: "solidPopoverBackground")
    }
```

Persistence tests that read/write `UserDefaults.standard` and construct a second `StockService()` to verify reload (lines 222–239):

```swift
    func testMenuBarFontSizePersists() {
        let service = StockService()
        service.menuBarFontSize = 13
        XCTAssertEqual(UserDefaults.standard.double(forKey: "menuBarFontSize"), 13)
        XCTAssertEqual(StockService().menuBarFontSize, 13)
    }
    ...
    func testSolidPopoverBackgroundPersists() {
        let service = StockService()
        service.solidPopoverBackground = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "solidPopoverBackground"))
        XCTAssertTrue(StockService().solidPopoverBackground)
    }
```

### Conventions that apply here

- Match existing Swift style in neighbouring files: 4-space indent, `self.` in the init, single-line `didSet { ... }` for the settings.
- Persisted settings use a `didSet` that writes to UserDefaults — keep that pattern, just route through the injected instance instead of `.standard`.
- Tests are XCTest, `@MainActor` on the class because they touch the `@MainActor` service. Keep that annotation.
- `StockService` is `@Observable @MainActor`. A stored `let defaults: UserDefaults` is fine — `UserDefaults` is a reference type and the property is on a `@MainActor` class, so no concurrency annotation is needed. Do NOT mark the new property `@ObservationIgnored` unless the build demands it (it should not, since it is a `let`).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build (Release) | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` | ends with `BUILD SUCCEEDED` |
| Test | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` | ends with `TEST SUCCEEDED` |
| Grep for residual refs | `grep -n "UserDefaults.standard" TickerBar/Services/StockService.swift` | no output (exit 1) |
| Confirm only in-scope files changed | `git status --porcelain` | only the 3 in-scope paths listed |

Run all commands from the repo root `/Users/danny/VSCode/workspace/macos-stock-ticker`.

## Scope

**In scope** (the only files you should modify):
- `TickerBar/Services/StockService.swift`
- `TickerBarTests/StockServiceTests.swift`

**Allowed to read, expected to remain unchanged:**
- `TickerBar/TickerBarApp.swift` — verify line 7 still compiles after the signature change; because the new parameter has a default, this file should NOT need editing. If it does need editing, that is a STOP condition (see below).

**Out of scope** (do NOT touch, even though they look related):
- `TickerBar/Views/` (MenuBarLabel, WatchlistView, SettingsView, etc.) — they receive an already-constructed `StockService`; they never call the init.
- The actual test logic/assertions of non-persistence tests beyond swapping how the service is constructed — do not rewrite test bodies or add new test cases; that is plan 009's job. This plan only adds the injection seam and isolates the suite.
- `UpdateChecker`, networking, or any other behavior.

## Git workflow

- Branch: `refactor/008-inject-userdefaults` (create from current `master`).
- Commit per logical unit (one commit for the production change, one for the test change is acceptable; a single commit is also fine). Imperative subject matching `git log` style, e.g. `Inject UserDefaults into StockService for hermetic tests`.
- Do NOT add `Co-Authored-By`, `Generated with Claude Code`, or any AI attribution anywhere in commit messages.
- Do NOT push or open a PR unless the operator instructs it.

## Steps

### Step 1: Create the branch

```bash
git checkout -b refactor/008-inject-userdefaults
```

**Verify**: `git rev-parse --abbrev-ref HEAD` → `refactor/008-inject-userdefaults`

### Step 2: Add a stored `defaults` property and a defaulted init parameter

In `TickerBar/Services/StockService.swift`:

1. Add a stored property. Place it just above the `init` (after line 97, the `baseURL` constant). Shape:

```swift
    // MARK: - Persistence
    private let defaults: UserDefaults
```

2. Change the init signature from `init() {` to:

```swift
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
```

   Then **delete** the existing `let defaults = UserDefaults.standard` line (currently line 100) — it is shadowed/replaced by the stored property. The rest of the init body already uses `defaults.…`, so it now resolves to `self.defaults`. Do not change any other line in the init body.

**Verify**: `grep -n "let defaults = UserDefaults.standard" TickerBar/Services/StockService.swift` → no output (exit 1).

### Step 3: Route every `didSet` through `self.defaults`

In `TickerBar/Services/StockService.swift`, replace `UserDefaults.standard` with `defaults` inside every `didSet` block (11 settings + `holdings` + `priceAlerts`). Each becomes, e.g.:

```swift
    var watchlist: [String] {
        didSet { defaults.set(watchlist, forKey: "watchlist") }
    }
```

and:

```swift
            if let data = try? JSONEncoder().encode(holdings) {
                defaults.set(data, forKey: "holdings")
            }
```

Important: `didSet` runs only on assignments AFTER the initial property assignment in `init`, by which point `self.defaults` is already set (it is assigned on the first line of the init). So routing `didSet` through `self.defaults` is safe. Do NOT change anything other than the `UserDefaults.standard` → `defaults` token.

**Verify**: `grep -n "UserDefaults.standard" TickerBar/Services/StockService.swift` → no output (exit 1).

### Step 4: Build to confirm the production change compiles

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → ends with `BUILD SUCCEEDED`.

If the build fails because `TickerBar/TickerBarApp.swift:7` no longer compiles (i.e. the defaulted parameter did not preserve the no-arg call), STOP and report — see STOP conditions.

### Step 5: Isolate the test suite with a per-test suite and tearDown

In `TickerBarTests/StockServiceTests.swift`:

1. Add a stored property and a unique suite name in `setUp`, and a `tearDown` that destroys it. Replace the entire current `setUp` (lines 7–18) with:

```swift
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.tickerbar.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }
```

2. Replace every `StockService()` construction in this file with `StockService(defaults: defaults)`. There are constructions in: `testDefaultWatchlist`, `testAddSymbol`, `testAddDuplicateSymbolIsIgnored`, `testAddSymbolUppercased`, `testRemoveSymbol`, `testCurrentDisplayIndexWraps`, `testMenuBarFontSizeDefaultsToTen`, `testMenuBarFontSizePersists` (TWO constructions — `let service` and the inline `StockService()`), `testSolidPopoverBackgroundDefaultsToFalse`, `testSolidPopoverBackgroundPersists` (TWO constructions). The pure-function tests (`mergedStocks`, `parseQuoteResponse`, `isMarketOpen`, crumb) do not construct the service — leave them untouched.

3. In the two persistence tests, replace the `UserDefaults.standard` reads with `defaults`:
   - `testMenuBarFontSizePersists`: `XCTAssertEqual(UserDefaults.standard.double(forKey: "menuBarFontSize"), 13)` → `XCTAssertEqual(defaults.double(forKey: "menuBarFontSize"), 13)`, and the reload `StockService().menuBarFontSize` → `StockService(defaults: defaults).menuBarFontSize`.
   - `testSolidPopoverBackgroundPersists`: `XCTAssertTrue(UserDefaults.standard.bool(forKey: "solidPopoverBackground"))` → `XCTAssertTrue(defaults.bool(forKey: "solidPopoverBackground"))`, and `StockService().solidPopoverBackground` → `StockService(defaults: defaults).solidPopoverBackground`.

**Verify**: `grep -n "UserDefaults.standard" TickerBarTests/StockServiceTests.swift` → no output (exit 1).

### Step 6: Run the full test suite

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → ends with `TEST SUCCEEDED`. Every previously-passing test still passes.

### Step 7: Confirm scope and real-defaults safety

**Verify**:
- `git status --porcelain` → lists only `TickerBar/Services/StockService.swift` and `TickerBarTests/StockServiceTests.swift` as modified (TickerBarApp.swift must NOT appear).
- `grep -rn "UserDefaults.standard" TickerBar/Services/StockService.swift TickerBarTests/StockServiceTests.swift` → no output (exit 1).

## Test plan

- No NEW test cases are added in this plan (that is plan 009). This plan changes how the existing tests construct the service and where they persist, so that the suite is hermetic.
- The two persistence tests (`testMenuBarFontSizePersists`, `testSolidPopoverBackgroundPersists`) now prove the injected `defaults` round-trips through a fresh `StockService(defaults: defaults)`, which directly exercises the new injection seam.
- Order-independence check (recommended): run the test command twice in a row; both must end `TEST SUCCEEDED`. Because each `setUp` mints a fresh UUID suite and `tearDown` removes it, no state leaks between runs or between tests.
- Structural pattern: keep the existing `@MainActor final class StockServiceTests: XCTestCase` shape; model the new `setUp`/`tearDown` on standard XCTest lifecycle.
- Verification: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `TEST SUCCEEDED`.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` ends with `BUILD SUCCEEDED`
- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` ends with `TEST SUCCEEDED`
- [ ] `grep -n "UserDefaults.standard" TickerBar/Services/StockService.swift` returns no matches (exit 1)
- [ ] `grep -n "UserDefaults.standard" TickerBarTests/StockServiceTests.swift` returns no matches (exit 1)
- [ ] `grep -n "init(defaults: UserDefaults = .standard)" TickerBar/Services/StockService.swift` returns one match
- [ ] `git status --porcelain` shows ONLY `TickerBar/Services/StockService.swift` and `TickerBarTests/StockServiceTests.swift` modified (TickerBarApp.swift unchanged)
- [ ] `plans/README.md` status row for plan 008 updated

## STOP conditions

Stop and report back (do not improvise) if:

- The code at the locations in "Current state" doesn't match the excerpts (the codebase drifted since this plan was written) — e.g. the init no longer has `let defaults = UserDefaults.standard`, or the `didSet` count differs.
- Adding `init(defaults: UserDefaults = .standard)` forces a change to `TickerBar/TickerBarApp.swift` or any `TickerBar/Views/*` file to keep building — i.e. the defaulted parameter did NOT preserve the existing `StockService()` call sites. Report which call site broke rather than editing it.
- The build fails because `@Observable`/`@MainActor` rejects the stored `private let defaults: UserDefaults` property (e.g. demands `@ObservationIgnored` or a concurrency annotation). Report the exact compiler diagnostic; do not invent annotations beyond a single `@ObservationIgnored` attempt if the error explicitly names observation macro expansion.
- A verification command fails twice after a reasonable fix attempt.
- Any in-scope grep still finds `UserDefaults.standard` after the edits and you cannot locate the remaining occurrence.

## Maintenance notes

- For the owner after this lands: any NEW persisted setting added to `StockService` must use `defaults.set(...)` in its `didSet`, never `UserDefaults.standard`, to keep tests hermetic.
- Reviewer should scrutinize: (1) that `self.defaults = defaults` is the FIRST statement in the init, so every `didSet` that fires during init-time assignments has a valid backing store; (2) that no production call site was forced to change (the whole point of the `.standard` default); (3) that `tearDown` actually removes the per-test domain so the test container does not accumulate orphan suite plists.
- Deferred to plan 009 (intentionally): broadening test coverage of holdings/priceAlerts/baseCurrency persistence and adding the missing-key default assertions. This plan only builds the injection seam and isolates the suite; it does not expand assertions.
