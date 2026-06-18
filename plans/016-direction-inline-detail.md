# Plan 016: Surface the already-fetched 52-week / pre-post-market / day-range data inline

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c0c912e..HEAD -- TickerBar/Views/WatchlistView.swift TickerBar/Models/StockItem.swift TickerBar/Services/StockService.swift TickerBar/Views/SettingsView.swift TickerBarTests/StockItemTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `c0c912e`, 2026-06-17

## Why this matters

The app already fetches and parses pre/post-market price & change, `marketState`, 52-week high/low, and day high/low for every watchlist stock (`StockService.swift:314-320`, `StockItem.swift:13-19`), and exposes correctly sub-unit-scaled `display*` computed properties for all of it (`StockItem.swift:42-49`). But this data is rendered **only** inside a hover `.help()` tooltip on the row (`WatchlistView.swift:429-455,508`). A tooltip is undiscoverable (you have to know to hover and wait), is unavailable at a glance, and does not exist on touch/trackpad-tap interactions. We are paying the network and parse cost for rich data and then hiding it. This plan surfaces that data inline in the dropdown via a per-row expandable detail section (toggled by a chevron control), so users can see day range, 52-week range, and after-hours movement without hunting. No `StockService` changes — pure UI surfacing of existing model properties.

## Current state

Files involved:

- `TickerBar/Views/WatchlistView.swift` — the dropdown UI. `WatchlistView` (the list) and `StockRowView` (one row). The whole-row tap opens Yahoo Finance; the row data lives in `StockRowView`. **This is the only file with real behavior changes.**
- `TickerBar/Models/StockItem.swift` — the model. All `display*` properties already exist; **read-only reference, do not modify** (a test is added against it).
- `TickerBar/Views/SettingsView.swift` — settings form; pattern reference for an optional "always-on" toggle (see Step 5, optional).
- `TickerBar/Services/StockService.swift` — settings storage pattern reference (see Step 5, optional). **Only touched if you do the optional always-on toggle.**
- `TickerBarTests/StockItemTests.swift` — XCTest suite for `StockItem`; new sub-unit scaling test added here.

The data already exists on the model (`StockItem.swift:11-19`):

```swift
var dayHigh: Double? = nil
var dayLow: Double? = nil
var postMarketPrice: Double? = nil
var postMarketChange: Double? = nil
var preMarketPrice: Double? = nil
var preMarketChange: Double? = nil
var marketState: String? = nil  // PRE, REGULAR, POST, CLOSED
var fiftyTwoWeekHigh: Double? = nil
var fiftyTwoWeekLow: Double? = nil
```

The sub-unit-scaled display accessors already exist (`StockItem.swift:42-49`) and are what you MUST render (never the raw `dayHigh` etc.):

```swift
var displayDayHigh: Double? { dayHigh.map { $0 / subUnitScale } }
var displayDayLow: Double? { dayLow.map { $0 / subUnitScale } }
var displayPostMarketPrice: Double? { postMarketPrice.map { $0 / subUnitScale } }
var displayPostMarketChange: Double? { postMarketChange.map { $0 / subUnitScale } }
var displayPreMarketPrice: Double? { preMarketPrice.map { $0 / subUnitScale } }
var displayPreMarketChange: Double? { preMarketChange.map { $0 / subUnitScale } }
var display52WeekHigh: Double? { fiftyTwoWeekHigh.map { $0 / subUnitScale } }
var display52WeekLow: Double? { fiftyTwoWeekLow.map { $0 / subUnitScale } }
```

`subUnitScale` is `100.0` for sub-unit currencies (GBp/GBX = pence, ILA = agorot — see `isSubUnit` at `StockItem.swift:26-30`) and `1.0` otherwise. `stock.currencySymbol` (`StockItem.swift:66-81`) is the symbol to prefix prices with.

Today the data is built into a tooltip string only (`WatchlistView.swift:429-455`), and applied via `.help(tooltipText)` at the bottom of `StockRowView.body` (`WatchlistView.swift:508`):

```swift
private var tooltipText: String {
    var lines: [String] = []
    let cs = stock.currencySymbol
    if let high = stock.displayDayHigh, let low = stock.displayDayLow {
        lines.append("Day: \(cs)\(String(format: "%.2f", low)) - \(cs)\(String(format: "%.2f", high))")
    }
    if let h52 = stock.display52WeekHigh, let l52 = stock.display52WeekLow {
        lines.append("52w: \(cs)\(String(format: "%.2f", l52)) - \(cs)\(String(format: "%.2f", h52))")
    }
    ...
}
```

The whole row currently opens Yahoo on tap (`WatchlistView.swift:96-100`), applied by the **parent** `WatchlistView` (not by `StockRowView`):

```swift
StockRowView(stock: stock, hasAlert: !service.alertsForSymbol(stock.symbol).isEmpty, holding: service.holdingFor(stock.symbol))
    .onTapGesture {
        openYahooFinance(symbol: stock.symbol)
    }
    .contextMenu { ... }
```

`StockRowView` is declared at `WatchlistView.swift:424-510`:

```swift
struct StockRowView: View {
    let stock: StockItem
    var hasAlert: Bool = false
    var holding: StockService.Holding? = nil
    ...
    var body: some View {
        HStack { ... }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .help(tooltipText)
    }
}
```

The dropdown is fixed-width: `.frame(width: 300)` at `WatchlistView.swift:364`. **Detail content must fit within 300pt** (use `.lineLimit(1)` / compact `.caption2` text).

**The tap conflict to resolve**: the entire row already taps-to-open-Yahoo (`WatchlistView.swift:98`). A whole-row tap-to-expand would collide with that. **Resolution chosen by this plan**: add a dedicated chevron `Button` *inside* `StockRowView` that toggles a local `@State private var isExpanded`. A `Button` consumes its own tap, so the chevron expands while the rest of the row still opens Yahoo via the parent's `.onTapGesture`. Do NOT change the parent's tap-to-open behavior.

Conventions (match these):

- SwiftUI views in this file use `VStack(alignment: .leading, spacing: 2)`, `.font(.caption)` / `.font(.caption2)`, `.foregroundStyle(.secondary)` / `.tertiary`, and gain/loss coloring `stock.isPositive ? .green : .red` (see `WatchlistView.swift:457-503`). Reuse these exact modifiers.
- Price formatting style in this file: `"\(cs)\(String(format: "%.2f", value))"` and signed change `String(format: "%+.2f", change)` (see `WatchlistView.swift:434-443`).
- Chevron/disclosure icons use SF Symbols via `Image(systemName:)` with `.font(.caption2)` (see `WatchlistView.swift:464,497`).
- Pure scaling logic lives on the model already; this plan adds **no** new model logic.
- Tests are XCTest (`import XCTest`, `@testable import TickerBar`), `StockItem` tests are plain `XCTestCase` (no `@MainActor` needed because `StockItem` is not actor-isolated) — see `StockItemTests.swift:1-4`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build (Release) | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` | ends with `** BUILD SUCCEEDED **` |
| Test | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` | ends with `** TEST SUCCEEDED **` |
| Run a single test class | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' -only-testing:TickerBarTests/StockItemTests test` | `** TEST SUCCEEDED **` |
| Drift check | `git diff --stat c0c912e..HEAD -- TickerBar/Views/WatchlistView.swift TickerBar/Models/StockItem.swift TickerBar/Services/StockService.swift TickerBar/Views/SettingsView.swift TickerBarTests/StockItemTests.swift` | empty output (no drift) |
| Confirm no stray modified files | `git status --porcelain` | only in-scope files listed |

Run all `xcodebuild` commands from the repo root `/Users/danny/VSCode/workspace/macos-stock-ticker` (use absolute paths; the working directory may reset between commands).

## Scope

**In scope** (the only files you should modify):
- `TickerBar/Views/WatchlistView.swift` — add the expandable detail section + chevron toggle to `StockRowView`.
- `TickerBarTests/StockItemTests.swift` — add a sub-unit scaling test for the `display*` values used by the new UI.

**In scope only if you do the OPTIONAL always-on toggle (Step 5):**
- `TickerBar/Services/StockService.swift` — add a persisted `showInlineDetail` setting following the existing `didSet` + `init` pattern.
- `TickerBar/Views/SettingsView.swift` — add a `Toggle` for it.

**Out of scope** (do NOT touch, even though they look related):
- `TickerBar/Models/StockItem.swift` — all needed `display*` properties already exist; do NOT add or change any. (A test references it; the model itself is not modified.)
- Any `StockService` networking/parsing (`fetchAllQuotes`, `parseQuoteResponse`, lines ~300-320). The data is already fetched; do not touch the fetch path.
- The parent row `.onTapGesture` that opens Yahoo (`WatchlistView.swift:98-100`) and the `.contextMenu` (`WatchlistView.swift:101-149`) — leave both as-is.
- The `.frame(width: 300)` (`WatchlistView.swift:364`) — do NOT widen the dropdown.
- `project.yml` (the XcodeGen spec is stale/broken; the committed `TickerBar.xcodeproj` is the source of truth).

## Git workflow

- Branch: `feat/016-direction-inline-detail` (create from `master`: `git checkout -b feat/016-direction-inline-detail`).
- Commit per logical unit. Imperative subjects matching `git log` style (e.g. "Add expandable detail section to watchlist rows", "Add sub-unit scaling test for inline detail values").
- HARD RULES: NO "Co-Authored-By" lines, NO "Generated with Claude Code" or any AI attribution anywhere in commits or PR text.
- Do NOT push or open a PR unless the operator explicitly tells you to.

## Steps

### Step 1: Add expand state and a chevron toggle to `StockRowView`

In `TickerBar/Views/WatchlistView.swift`, inside `struct StockRowView` (starts at line 424), add a local expand state below the existing stored properties (`stock`, `hasAlert`, `holding` at lines 425-427):

```swift
@State private var isExpanded = false
```

Then add a chevron `Button` as the **last element of the main `HStack`** in `body` (the `HStack` that starts at line 458, after the trailing price `VStack` that ends at line 503). The button toggles `isExpanded`; because it is a `Button`, its tap is consumed locally and does not trigger the parent's tap-to-open-Yahoo:

```swift
Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
        .font(.caption2)
        .foregroundStyle(.tertiary)
}
.buttonStyle(.plain)
```

Do not yet render any detail content. Keep `.help(tooltipText)` (line 508) for now.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → ends with `** BUILD SUCCEEDED **`.

### Step 2: Restructure `body` so the detail can sit below the row

The current `body` is a single `HStack` (lines 458-504) with row-level padding applied to it (lines 505-508). Wrap the existing `HStack` in an outer `VStack(alignment: .leading, spacing: 6)` so the detail section can be appended beneath it. Move the `.padding(.horizontal, 12)` / `.padding(.vertical, 6)` / `.contentShape(Rectangle())` / `.help(tooltipText)` modifiers (lines 505-508) onto the **outer `VStack`**, not the inner `HStack` — this keeps the whole row (including the detail area) tappable and correctly padded.

Target shape:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack {
            ... existing row content (symbol, name, sparkline, price, chevron) ...
        }
        // detail section added in Step 3
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .contentShape(Rectangle())
    .help(tooltipText)
}
```

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → ends with `** BUILD SUCCEEDED **`.

### Step 3: Render the inline detail when expanded

Inside the outer `VStack` from Step 2, after the inner `HStack`, add a detail section gated on `isExpanded`. Render only rows whose data is present (mirror the `if let` guards already used in `tooltipText`, lines 433-452). Use the sub-unit-safe `display*` accessors only. Keep every line `.font(.caption2)`, `.foregroundStyle(.secondary)`, `.lineLimit(1)` so it fits the 300pt width.

```swift
if isExpanded {
    VStack(alignment: .leading, spacing: 2) {
        let cs = stock.currencySymbol

        if let low = stock.displayDayLow, let high = stock.displayDayHigh {
            Text("Day  \(cs)\(String(format: "%.2f", low)) – \(cs)\(String(format: "%.2f", high))")
        }
        if let l52 = stock.display52WeekLow, let h52 = stock.display52WeekHigh {
            Text("52w  \(cs)\(String(format: "%.2f", l52)) – \(cs)\(String(format: "%.2f", h52))")
        }
        if let pmPrice = stock.displayPreMarketPrice, let pmChange = stock.displayPreMarketChange {
            HStack(spacing: 4) {
                Text("Pre  \(cs)\(String(format: "%.2f", pmPrice))")
                Text(String(format: "%+.2f", pmChange))
                    .foregroundStyle(pmChange >= 0 ? .green : .red)
            }
        }
        if let ahPrice = stock.displayPostMarketPrice, let ahChange = stock.displayPostMarketChange {
            HStack(spacing: 4) {
                Text("After  \(cs)\(String(format: "%.2f", ahPrice))")
                Text(String(format: "%+.2f", ahChange))
                    .foregroundStyle(ahChange >= 0 ? .green : .red)
            }
        }
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .frame(maxWidth: .infinity, alignment: .leading)
}
```

Note: the `.foregroundStyle(.green/.red)` on the change `Text` overrides the outer `.secondary` — that is intentional and matches the gain/loss coloring used elsewhere (`WatchlistView.swift:502`).

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → ends with `** BUILD SUCCEEDED **`.

### Step 4: Add an after-hours secondary line emphasis when `marketState` is PRE/POST

This is a small, in-scope refinement (no new file). When `stock.marketState` is `"PRE"` or `"POST"`, the relevant pre/post line in Step 3 is the "live" delta — make it slightly more prominent so an expanded row during extended hours reads at a glance. Apply `.fontWeight(.semibold)` to the corresponding change `Text` when the state matches. Example for the post-market line:

```swift
Text(String(format: "%+.2f", ahChange))
    .foregroundStyle(ahChange >= 0 ? .green : .red)
    .fontWeight(stock.marketState == "POST" ? .semibold : .regular)
```

Do the analogous `stock.marketState == "PRE"` check on the pre-market change `Text`. Do not add any other styling.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → ends with `** BUILD SUCCEEDED **`.

### Step 5 (OPTIONAL — only if the operator asked for an always-on secondary line): add a persisted settings toggle

If, and only if, an always-on (non-collapsed) detail line is requested, add a persisted setting following the exact existing pattern. Otherwise SKIP this step and leave the chevron as the only control.

5a. In `TickerBar/Services/StockService.swift`, add a stored setting next to `solidPopoverBackground` (lines 46-48), matching the `didSet` style:

```swift
var showInlineDetail: Bool {
    didSet { UserDefaults.standard.set(showInlineDetail, forKey: "showInlineDetail") }
}
```

5b. In the same file's `init()`, add a load line next to line 115, defaulting to `false` (collapsed by default, matching `bool(forKey:)` semantics):

```swift
self.showInlineDetail = defaults.object(forKey: "showInlineDetail") as? Bool ?? false
```

5c. In `TickerBar/Views/SettingsView.swift`, add a `Toggle` next to the existing one (line 89), matching its style:

```swift
Toggle("Always show stock details", isOn: $service.showInlineDetail)
```

5d. In `WatchlistView.swift`, pass the flag into `StockRowView` (constructor call at lines 96-97) and use it as the initial value of `isExpanded` (or OR it into the `if isExpanded` gate). Keep the chevron working as a per-row override. The exact wiring is a judgment call; if it requires changing the parent tap behavior, treat as a STOP condition.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **` (the existing init/settings path still compiles and runs).

### Step 6: Add a sub-unit scaling test for the values the new UI renders

This is mostly view code (not unit-testable), so add a model-level guard confirming the `display*` values the inline detail relies on are correctly scaled for a sub-unit currency. In `TickerBarTests/StockItemTests.swift`, add the following test (model after the existing tests at `StockItemTests.swift:19-67`):

```swift
func testSubUnitDisplayValuesForInlineDetail() {
    // GBp/GBX prices come from the API in pence; display* must divide by 100.
    var stock = StockItem(symbol: "VOD.L", name: "Vodafone", price: 7500, previousClose: 7400)
    stock.currency = "GBp"
    stock.dayHigh = 7600
    stock.dayLow = 7350
    stock.fiftyTwoWeekHigh = 9000
    stock.fiftyTwoWeekLow = 6000
    stock.preMarketPrice = 7520
    stock.preMarketChange = 20
    stock.postMarketPrice = 7480
    stock.postMarketChange = -20

    XCTAssertTrue(stock.isSubUnit)
    XCTAssertEqual(stock.displayDayHigh!, 76.00, accuracy: 0.001)
    XCTAssertEqual(stock.displayDayLow!, 73.50, accuracy: 0.001)
    XCTAssertEqual(stock.display52WeekHigh!, 90.00, accuracy: 0.001)
    XCTAssertEqual(stock.display52WeekLow!, 60.00, accuracy: 0.001)
    XCTAssertEqual(stock.displayPreMarketPrice!, 75.20, accuracy: 0.001)
    XCTAssertEqual(stock.displayPreMarketChange!, 0.20, accuracy: 0.001)
    XCTAssertEqual(stock.displayPostMarketPrice!, 74.80, accuracy: 0.001)
    XCTAssertEqual(stock.displayPostMarketChange!, -0.20, accuracy: 0.001)
}

func testNonSubUnitDisplayValuesUnchanged() {
    var stock = StockItem(symbol: "AAPL", name: "Apple", price: 185, previousClose: 183)
    stock.currency = "USD"
    stock.dayHigh = 186
    stock.fiftyTwoWeekHigh = 200
    XCTAssertFalse(stock.isSubUnit)
    XCTAssertEqual(stock.displayDayHigh!, 186.0, accuracy: 0.001)
    XCTAssertEqual(stock.display52WeekHigh!, 200.0, accuracy: 0.001)
}
```

Note: `StockItem`'s stored data fields are `var` with defaults (`StockItem.swift:8-19`), so setting them after init via `stock.currency = ...` compiles. `isSubUnit` is `currency == "GBp" || uppercased == "GBX" || == "ILA"` (`StockItem.swift:26-30`), so `"GBp"` is sub-unit.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' -only-testing:TickerBarTests/StockItemTests test` → `** TEST SUCCEEDED **`, and the test count includes the 2 new tests (`testSubUnitDisplayValuesForInlineDetail`, `testNonSubUnitDisplayValuesUnchanged`).

### Step 7: Full build + test gate

**Verify**:
- `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`
- `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`

### Step 8: Manual verification (cannot be automated — record the result)

Run the app and confirm the UI behaves. These steps are manual; note pass/fail in your report.

1. Launch the built app (open the product from the Xcode build, or `xcodebuild ... build` then open the `.app` from `~/Library/Developer/Xcode/DerivedData/.../Build/Products/Release/TickerBar.app`).
2. Click the menu-bar item to open the dropdown.
3. Confirm each stock row shows a chevron-down on the right.
4. Click a chevron → the row expands to show Day / 52w (and Pre/After when present); chevron flips to chevron-up. Click again → it collapses with no leftover gap (the panel auto-resizes via `MenuBarWindowResizer`, `WatchlistView.swift:540-549`).
5. Click the row **body** (not the chevron) → Yahoo Finance still opens in the browser (parent `.onTapGesture` intact).
6. Confirm the dropdown width is unchanged (still 300pt) and detail text does not clip oddly.

## Test plan

- New tests in `TickerBarTests/StockItemTests.swift`:
  - `testSubUnitDisplayValuesForInlineDetail` — GBp (sub-unit) stock: all `display*` values used by the inline detail (`displayDayHigh/Low`, `display52WeekHigh/Low`, `displayPreMarketPrice/Change`, `displayPostMarketPrice/Change`) are divided by 100. This is the core correctness guarantee for the new UI (overlaps the concern of plan 009).
  - `testNonSubUnitDisplayValuesUnchanged` — USD stock: the same accessors return values unchanged.
- Structural pattern: model after the existing `StockItemTests.swift` cases (`testChangePercent`, etc., lines 29-67) — plain `XCTestCase`, `XCTAssertEqual(..., accuracy:)`.
- View behavior (chevron toggle, tap-to-open vs tap-to-expand, panel resize) is verified manually in Step 8 — SwiftUI view interaction is not unit-testable in this XCTest setup.
- Verification: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`, including the 2 new tests.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` ends with `** BUILD SUCCEEDED **`
- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` ends with `** TEST SUCCEEDED **`
- [ ] `grep -n "testSubUnitDisplayValuesForInlineDetail" TickerBarTests/StockItemTests.swift` returns a match
- [ ] `grep -n "isExpanded" TickerBar/Views/WatchlistView.swift` returns a match (the new toggle state exists)
- [ ] `grep -n "display52WeekHigh\|displayDayLow" TickerBar/Views/WatchlistView.swift` returns matches **outside** `tooltipText` (the data is now rendered inline, not only in the tooltip)
- [ ] `grep -n "frame(width: 300)" TickerBar/Views/WatchlistView.swift` still returns exactly one match (dropdown width unchanged)
- [ ] No files outside the in-scope list are modified (`git status --porcelain` lists only `TickerBar/Views/WatchlistView.swift`, `TickerBarTests/StockItemTests.swift`, and — only if Step 5 was done — `TickerBar/Services/StockService.swift` + `TickerBar/Views/SettingsView.swift`)
- [ ] `TickerBar/Models/StockItem.swift` is unmodified (`git diff --stat c0c912e..HEAD -- TickerBar/Models/StockItem.swift` is empty)
- [ ] `plans/README.md` status row updated (unless a dispatching reviewer maintains the index)
- [ ] Manual Step 8 performed and result recorded in the report

## STOP conditions

Stop and report back (do not improvise) if:

- The drift check shows any in-scope file changed since `c0c912e` and the "Current state" excerpts no longer match the live code (e.g. `StockRowView` no longer at `WatchlistView.swift:424`, or the `display*` accessors at `StockItem.swift:42-49` are gone/renamed).
- Making the chevron expand requires changing the parent `.onTapGesture` at `WatchlistView.swift:98-100` (i.e. you cannot get the chevron to consume its own tap with a `Button` + `.buttonStyle(.plain)`). The two-tap-targets-in-one-row approach is the whole point; if it doesn't work, report rather than reworking the row's open-Yahoo behavior.
- A `display*` property the plan references does not exist on `StockItem` (the model drifted) — do NOT add it to the model (that is out of scope); report instead.
- Any verification command fails twice after a reasonable fix attempt.
- The build forces you to touch `project.yml` or any file outside the in-scope list.

## Maintenance notes

For the owner after this lands:

- If the dropdown is ever made resizable or its `.frame(width: 300)` (`WatchlistView.swift:364`) changes, revisit the `.lineLimit(1)` choices in the detail section — wider widths could show full strings without truncation.
- The detail section duplicates the formatting logic of `tooltipText` (`WatchlistView.swift:429-455`). Now that data is inline, a follow-up could **remove** the `.help(tooltipText)` tooltip entirely (redundant once expandable) — deliberately deferred here to avoid changing two behaviors at once; the tooltip is harmless to keep.
- Reviewer should scrutinize: (1) the chevron `Button` genuinely consumes its tap and does not also open Yahoo; (2) the panel auto-resizes cleanly on collapse (the `MenuBarWindowResizer` at `WatchlistView.swift:540-549` should handle it, but expand/collapse is a new height-change trigger); (3) all rendered prices use `display*` accessors, never raw `dayHigh`/`fiftyTwoWeekHigh` (sub-unit currencies would be off by 100×).
- If Step 5's always-on toggle was implemented, note it adds the project's 12th `didSet` UserDefaults observer in `StockService` (the God-Object growth flagged separately); the persisted key is `"showInlineDetail"`.
