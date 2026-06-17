# Plan 017: Add percent-change and recurring price alerts (spike + build)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c0c912e..HEAD -- TickerBar/Models/PriceAlert.swift TickerBar/Services/StockService.swift TickerBar/Views/WatchlistView.swift TickerBar/Models/StockItem.swift TickerBarTests/StockServiceTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `c0c912e`, 2026-06-17

## Why this matters

`PriceAlert` today is absolute-price and one-shot only: it carries just `targetPrice` + `isAbove`, and `checkPriceAlerts()` deletes any alert the moment it fires. The two most common watchlist asks — "notify me when X moves +/-5% today" and "keep alerting me whenever it crosses this level" — are impossible. `changePercent` is already computed on `StockItem` and `checkPriceAlerts()` already runs every refresh cycle, so the data and the loop exist; only the model and the trigger/removal logic need to grow. The hard part is that `PriceAlert` is `Codable` and persisted to `UserDefaults` under key `"priceAlerts"`, so adding fields **must** still decode alerts users already have stored (created before this change) without losing them. When this lands, users get percent-change alerts and re-arming recurring alerts, and existing stored alerts continue to load unchanged.

## Current state

Files and roles:
- `TickerBar/Models/PriceAlert.swift` — the persisted alert model (`Codable`, `Equatable`). The whole file today (lines 1–26):

```swift
import Foundation

struct PriceAlert: Identifiable, Codable, Equatable {
    let id: UUID
    let symbol: String
    let targetPrice: Double
    let isAbove: Bool  // true = alert when price goes above target, false = below
    var armed: Bool  // false on creation, set true after first price check to avoid immediate trigger

    init(symbol: String, targetPrice: Double, isAbove: Bool) {
        self.id = UUID()
        self.symbol = symbol
        self.targetPrice = targetPrice
        self.isAbove = isAbove
        self.armed = false
    }

    var directionLabel: String {
        isAbove ? "above" : "below"
    }

    func isTriggered(currentPrice: Double) -> Bool {
        guard armed else { return false }
        return isAbove ? currentPrice >= targetPrice : currentPrice <= targetPrice
    }
}
```

- `TickerBar/Services/StockService.swift` — `@Observable @MainActor` service. Relevant excerpts:
  - Persistence (lines 70–76): `priceAlerts` `didSet` JSON-encodes to `UserDefaults.standard` key `"priceAlerts"`:

```swift
var priceAlerts: [PriceAlert] = [] {
    didSet {
        if let data = try? JSONEncoder().encode(priceAlerts) {
            UserDefaults.standard.set(data, forKey: "priceAlerts")
        }
    }
}
```

  - Load on init (lines 117–120):

```swift
if let alertData = defaults.data(forKey: "priceAlerts"),
   let savedAlerts = try? JSONDecoder().decode([PriceAlert].self, from: alertData) {
    self.priceAlerts = savedAlerts
}
```

  - `addAlert` (lines 573–577):

```swift
func addAlert(symbol: String, targetPrice: Double, isAbove: Bool) {
    let alert = PriceAlert(symbol: symbol, targetPrice: targetPrice, isAbove: isAbove)
    priceAlerts.append(alert)
    ensureNotificationPermission()
}
```

  - `checkPriceAlerts()` (lines 608–629) — note the unconditional self-delete of triggered alerts at the end:

```swift
private func checkPriceAlerts() {
    var triggeredAlertIDs: Set<UUID> = []

    for i in priceAlerts.indices {
        guard let stock = stocks.first(where: { $0.symbol == priceAlerts[i].symbol }) else { continue }

        if !priceAlerts[i].armed {
            // Arm on first check — skips the fetch cycle where alert was created
            priceAlerts[i].armed = true
            continue
        }

        if priceAlerts[i].isTriggered(currentPrice: stock.displayPrice) {
            triggeredAlertIDs.insert(priceAlerts[i].id)
            sendAlertNotification(alert: priceAlerts[i], currentPrice: stock.displayPrice, currency: stock.currencySymbol)
        }
    }

    if !triggeredAlertIDs.isEmpty {
        priceAlerts.removeAll { triggeredAlertIDs.contains($0.id) }
    }
}
```

  - `sendAlertNotification` (lines 631–639) — builds the notification body using `alert.directionLabel` and `alert.targetPrice`.

- `TickerBar/Models/StockItem.swift` — `changePercent` already exists (lines 57–60), and `displayPrice` (line 39):

```swift
var changePercent: Double {
    guard previousClose != 0 else { return 0.0 }
    return (change / previousClose) * 100
}
```

- `TickerBar/Views/WatchlistView.swift` — the alert UI. Alert `@State` (lines 13–15): `alertSymbol: String?`, `alertPriceText = ""`, `alertIsAbove = true`. The "Set Price Alert..." context-menu button (lines 115–119) seeds those. The existing-alerts list in the context menu (lines 121–129) renders `Button("Remove: \(alert.directionLabel) ...")`. The alert input form (lines 154–189): an Above/Below `Picker` bound to `$alertIsAbove`, a `TextField` bound to `$alertPriceText`, and a `Set` button calling `service.addAlert(symbol:targetPrice:isAbove:)`.

Conventions that apply here (follow them):
- **Pure logic is `nonisolated static`** so it is unit-testable without the `@MainActor` service. Examples already in the codebase: `StockService.parseQuoteResponse`, `StockService.mergedStocks`, `StockService.isMarketOpen`, and `StockService.defaultWatchlist` (line 96: `nonisolated static let defaultWatchlist`). The new trigger logic must follow this pattern: put the trigger decision in a `nonisolated` (or pure `func` on the value-type model) so a test can exercise it directly.
- **Persisted settings use a `didSet` that writes to `UserDefaults.standard`** — already true for `priceAlerts` (line 70). Do not change the persistence mechanism; only the encoded shape changes.
- **Tests are XCTest, `@MainActor` when they touch the service.** `StockServiceTests` is annotated `@MainActor` (line 4) and clears `UserDefaults` keys in `setUp()` (lines 7–18). `StockItemTests` is a plain `XCTestCase` (no `@MainActor`) because `StockItem` is a value type. Match `StockItemTests` for pure model tests, and `StockServiceTests` for service tests.
- No SwiftLint / swift-format — match the brace/indentation style of the surrounding file exactly (4-space indent, K&R braces).

Codable backward-compatibility constraint (the core risk): existing users have a JSON array under `UserDefaults` key `"priceAlerts"` whose objects have **only** keys `id`, `symbol`, `targetPrice`, `isAbove`, `armed`. After this change, decoding that legacy JSON into the new `PriceAlert` **must succeed** and produce sensible values for the new fields (kind = absolute price, repeating = false). Swift's synthesized `Codable` will **fail** to decode if you add non-optional stored properties without defaults and without a custom `init(from:)`. You will provide a custom `init(from:)` (or make the new fields decode with fallbacks) so legacy blobs load.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build (Release) | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` | ends with `** BUILD SUCCEEDED **`, exit 0 |
| Test | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` | ends with `** TEST SUCCEEDED **`, exit 0 |
| Drift check | `git diff --stat c0c912e..HEAD -- TickerBar/Models/PriceAlert.swift TickerBar/Services/StockService.swift TickerBar/Views/WatchlistView.swift TickerBar/Models/StockItem.swift TickerBarTests/StockServiceTests.swift` | empty (no drift) |

Notes:
- The committed `TickerBar.xcodeproj/project.pbxproj` is the source of truth. The `project.yml` XcodeGen spec is **stale/broken** — do not regenerate the project from it. New source files added to `TickerBar/` are compiled automatically only if the build phase globs the folder; if a newly added file is reported as not found / not compiled, that is a STOP condition (see STOP conditions). To avoid this, prefer editing existing files rather than adding new source files. New **test** code should go into the existing `TickerBarTests/StockServiceTests.swift` and `TickerBarTests/StockItemTests.swift`, which are already in the test target.

## Scope

**In scope** (the only files you should modify):
- `TickerBar/Models/PriceAlert.swift`
- `TickerBar/Services/StockService.swift`
- `TickerBar/Views/WatchlistView.swift`
- `TickerBarTests/StockServiceTests.swift` (add tests)
- `TickerBarTests/StockItemTests.swift` (add tests — optional, only if you put pure trigger tests here)
- `plans/README.md` (status row update only, if the index exists)

**Out of scope** (do NOT touch, even though they look related):
- The notification permission flow (`ensureNotificationPermission`, `openNotificationSettings`, `notificationWarning`) — unchanged.
- `TickerBar.xcodeproj/project.pbxproj` and `project.yml` — do not edit the project files; do not add new source files that would require editing them.
- `StockItem.swift` beyond reading `changePercent` — no new fields on `StockItem`.
- The persistence key `"priceAlerts"` and the encode/decode mechanism in the `didSet`/init — keep the same key and the same `JSONEncoder`/`JSONDecoder` calls.
- Any refactor of `StockService` (it is a known large file; not this plan's job).

## Git workflow

- Branch: `feat/017-direction-percent-recurring-alerts` (create from current `master`).
- Commit per logical step; imperative subjects matching `git log` style (e.g. "Add alert kind and repeating fields to PriceAlert", "Trigger percent-change alerts and re-arm recurring alerts").
- HARD rules: NO "Co-Authored-By", NO "Generated with Claude Code" or any AI attribution anywhere in commits or PR text.
- Do NOT push or open a PR unless the operator explicitly instructs it.

## Steps

### Step 1: Extend the `PriceAlert` model with `kind` and `repeating`, preserving backward-compatible decode

In `TickerBar/Models/PriceAlert.swift`:

1. Add a nested enum:

```swift
enum Kind: String, Codable {
    case absolutePrice
    case percentChange
}
```

2. Add two stored properties: `let kind: Kind` and `let repeating: Bool`.
3. Reinterpret `targetPrice`: for `.absolutePrice` it remains an absolute price (unchanged meaning); for `.percentChange` it is a percent threshold (e.g. `5.0` means ±5%), and `isAbove` means "gained at least +threshold%" when true, "lost at least threshold% (changePercent <= -threshold)" when false. Keep the field name `targetPrice` to avoid a persistence rename (renaming the JSON key would break decode); document this dual meaning in a comment.
4. Update the designated `init` to take `kind` and `repeating` with **defaults** so existing call sites compile minimally, but plan to update `addAlert` in Step 3:

```swift
init(symbol: String, targetPrice: Double, isAbove: Bool, kind: Kind = .absolutePrice, repeating: Bool = false) {
    self.id = UUID()
    self.symbol = symbol
    self.targetPrice = targetPrice
    self.isAbove = isAbove
    self.kind = kind
    self.repeating = repeating
    self.armed = false
}
```

5. **Add a custom `init(from decoder:)`** so legacy JSON (no `kind`, no `repeating` keys) decodes. Use `decodeIfPresent` with fallbacks:

```swift
init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try c.decode(UUID.self, forKey: .id)
    self.symbol = try c.decode(String.self, forKey: .symbol)
    self.targetPrice = try c.decode(Double.self, forKey: .targetPrice)
    self.isAbove = try c.decode(Bool.self, forKey: .isAbove)
    self.armed = try c.decodeIfPresent(Bool.self, forKey: .armed) ?? false
    self.kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .absolutePrice
    self.repeating = try c.decodeIfPresent(Bool.self, forKey: .repeating) ?? false
}
```

You will need to declare `enum CodingKeys: String, CodingKey { case id, symbol, targetPrice, isAbove, armed, kind, repeating }`. Synthesized `encode(to:)` is fine (it writes all keys); only `init(from:)` needs to be custom. `Equatable` stays synthesized.

6. Update `directionLabel` and add a `thresholdLabel` (or similar) so notifications/UI can describe percent alerts. Add a pure trigger method that handles both kinds:

```swift
func isTriggered(currentPrice: Double, currentChangePercent: Double) -> Bool {
    guard armed else { return false }
    switch kind {
    case .absolutePrice:
        return isAbove ? currentPrice >= targetPrice : currentPrice <= targetPrice
    case .percentChange:
        return isAbove ? currentChangePercent >= targetPrice
                       : currentChangePercent <= -targetPrice
    }
}
```

Keep the old `isTriggered(currentPrice:)` only if something still calls it; otherwise replace its single caller in Step 2 and remove it to avoid dead code.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`.

### Step 2: Update `checkPriceAlerts()` to pass percent, and to re-arm (not delete) repeating alerts

In `TickerBar/Services/StockService.swift`, `checkPriceAlerts()` (currently lines 608–629):

1. Replace the trigger call with the two-argument form, passing `stock.changePercent` (use `displayChange`-consistent percent — `changePercent` is currency-neutral so it is correct as-is):

```swift
if priceAlerts[i].isTriggered(currentPrice: stock.displayPrice, currentChangePercent: stock.changePercent) {
    sendAlertNotification(alert: priceAlerts[i], currentPrice: stock.displayPrice, currency: stock.currencySymbol)
    if priceAlerts[i].repeating {
        // Re-arm with debounce: disarm so it must leave the trigger zone before firing again
        priceAlerts[i].armed = false
    } else {
        triggeredAlertIDs.insert(priceAlerts[i].id)
    }
}
```

2. Re-arming debounce: a `repeating` alert is set `armed = false` after firing. The existing arm-on-first-check block (the `if !priceAlerts[i].armed { armed = true; continue }`) will then re-arm it on a **subsequent** cycle. To prevent firing every cycle while the condition stays true, the re-arm must only happen once the condition is no longer met. Modify the arm block so a disarmed repeating alert only re-arms when `isTriggered(...)` is currently **false**:

```swift
if !priceAlerts[i].armed {
    // (Re-)arm only when not currently in the trigger zone, so a repeating
    // alert won't immediately re-fire while the condition still holds.
    if !priceAlerts[i].isTriggered2(...)  // see note
    {
        priceAlerts[i].armed = true
    }
    continue
}
```

Implementation note: `isTriggered(...)` returns `false` when `armed == false` (the `guard armed` short-circuits). To evaluate the raw condition independent of `armed`, factor the condition into a separate pure method on `PriceAlert`, e.g. `conditionMet(currentPrice:currentChangePercent:) -> Bool` (no `armed` guard), and have `isTriggered(...)` call it after the `guard armed`. Then the arm block checks `if !conditionMet(...)`. This keeps the first-fire behavior for fresh alerts (a brand-new alert created inside the zone stays disarmed until price leaves and re-enters — acceptable and matches "avoid immediate trigger"). Update Step 1's model accordingly: split into `conditionMet(...)` + `isTriggered(...)`.

3. The non-repeating deletion at the end (`priceAlerts.removeAll { triggeredAlertIDs.contains($0.id) }`) stays — only non-repeating alerts get added to `triggeredAlertIDs`, so repeating alerts are never removed.

4. Mutating `priceAlerts[i].armed` triggers the `didSet` re-encode each call; that is existing behavior (the current code already mutates `armed` in place). No change needed there.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`.

### Step 3: Update `addAlert` and the notification text

In `TickerBar/Services/StockService.swift`:

1. Change `addAlert` to accept the new parameters and forward them:

```swift
func addAlert(symbol: String, targetPrice: Double, isAbove: Bool, kind: PriceAlert.Kind = .absolutePrice, repeating: Bool = false) {
    let alert = PriceAlert(symbol: symbol, targetPrice: targetPrice, isAbove: isAbove, kind: kind, repeating: repeating)
    priceAlerts.append(alert)
    ensureNotificationPermission()
}
```

2. Update `sendAlertNotification` (lines 631–639) so the body reads correctly for percent alerts. For `.percentChange`, describe it as e.g. `"AAPL is +5.2% today, past your ±5% alert"`; for `.absolutePrice` keep the existing wording. Branch on `alert.kind`. Keep using `String(format: "%.2f", ...)` for prices and `%.1f%%` for percents (matches `menuBarText` formatting in `StockItem.swift:85`).

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`.

### Step 4: Surface the new options in the alert UI

In `TickerBar/Views/WatchlistView.swift`:

1. Add `@State` near lines 13–15: `@State private var alertKind: PriceAlert.Kind = .absolutePrice` and `@State private var alertRepeating = false`.
2. In the "Set Price Alert..." seeding button (lines 115–119) reset `alertKind = .absolutePrice` and `alertRepeating = false` alongside the existing seeds.
3. In the alert input form (lines 154–189), add: a small `Picker` for kind (`Text("Price").tag(PriceAlert.Kind.absolutePrice)`, `Text("% Change").tag(PriceAlert.Kind.percentChange)`) and a `Toggle("Repeat", isOn: $alertRepeating)`. When `alertKind == .percentChange`, the `TextField` placeholder should read `"%"` instead of `"Price"` (the value is a percent threshold). Keep the existing Above/Below picker — it now means gain/loss direction for percent alerts.
4. Update the `Set` button (lines 177–183) to pass the new args: `service.addAlert(symbol: symbol, targetPrice: value, isAbove: alertIsAbove, kind: alertKind, repeating: alertRepeating)`. The existing-alerts "Remove:" labels (lines 121–129) should show whether each alert is `%`/price and repeating — use `alert.kind` and `alert.repeating` to compose the label.

This step is UI-only; there is no headless test for SwiftUI here. Verification is the build plus a manual smoke check.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`.

### Step 5: Add tests

See "Test plan" for the exact cases. Add them to `TickerBarTests/StockServiceTests.swift` (service/persistence cases, `@MainActor`) and pure-model cases to `TickerBarTests/StockItemTests.swift` or `StockServiceTests.swift` (the trigger logic is on the value type `PriceAlert`, so it does not require `@MainActor`).

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`, and the new tests appear in the run.

## Test plan

Add these tests. Model them structurally on `StockItemTests` (plain `XCTestCase` for pure value-type tests) and `StockServiceTests` (`@MainActor`, with `UserDefaults` cleanup in `setUp`).

1. **Legacy decode (the critical migration test)** — decode a hand-written legacy JSON blob with only the old keys and assert it loads with the new defaults:

```swift
func testDecodesLegacyPriceAlertWithoutKindOrRepeating() throws {
    let json = """
    {"id":"\(UUID().uuidString)","symbol":"AAPL","targetPrice":190.0,"isAbove":true,"armed":true}
    """.data(using: .utf8)!
    let alert = try JSONDecoder().decode(PriceAlert.self, from: json)
    XCTAssertEqual(alert.symbol, "AAPL")
    XCTAssertEqual(alert.targetPrice, 190.0)
    XCTAssertTrue(alert.isAbove)
    XCTAssertEqual(alert.kind, .absolutePrice)   // default
    XCTAssertFalse(alert.repeating)              // default
}
```

   Add a variant that decodes a **legacy array** (`[PriceAlert]`) to mirror the real persisted shape.

2. **Round-trip** — encode a new percent/repeating alert and decode it back, asserting all fields survive.

3. **Percent-change trigger logic** (pure, no service):
   - gain alert: `kind: .percentChange, targetPrice: 5, isAbove: true`, armed → triggers at `currentChangePercent: 5.1`, does not trigger at `4.9`.
   - loss alert: `isAbove: false` → triggers at `currentChangePercent: -5.1`, not at `-4.9`.
   - disarmed alert never triggers regardless of percent.

4. **Absolute-price trigger still works** — a `.absolutePrice` alert behaves exactly as before (above/below price).

5. **Repeating alert is not removed after firing** — service-level (`@MainActor`): construct a `StockService`, inject a stock and a `repeating: true` armed alert that meets its condition, call the trigger path, and assert the alert is **still present** in `priceAlerts`. A non-repeating alert under the same condition is **removed**. If `checkPriceAlerts()` is `private`, exercise it through whatever public entry point already drives it after a fetch (inspect the file to find the caller), or temporarily verify the removal-vs-keep decision via the pure model + the same `triggeredAlertIDs` logic mirrored in a test. Prefer a public seam; if none exists, STOP and report rather than changing access levels broadly — a single targeted `internal`/`@testable`-visible helper is acceptable since tests already use `@testable import TickerBar`.

6. **Re-arm debounce** — an armed repeating alert that fires becomes disarmed; on the next check while the condition still holds it does **not** re-arm (stays disarmed) and does not fire again; once the condition is no longer met it re-arms.

Verification: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`, all new tests pass.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` ends with `** BUILD SUCCEEDED **` (exit 0).
- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` ends with `** TEST SUCCEEDED **` (exit 0).
- [ ] A test named like `testDecodesLegacyPriceAlertWithoutKindOrRepeating` exists and passes (`grep -rn "Legacy" TickerBarTests/` returns a match).
- [ ] `grep -n "percentChange" TickerBar/Models/PriceAlert.swift` returns a match (the `Kind` case exists).
- [ ] `grep -n "repeating" TickerBar/Models/PriceAlert.swift TickerBar/Services/StockService.swift` returns matches in both files.
- [ ] `grep -n "init(from decoder" TickerBar/Models/PriceAlert.swift` returns a match (custom decode present).
- [ ] No files outside the in-scope list are modified (`git status --porcelain` shows only in-scope paths).
- [ ] `plans/README.md` status row updated to DONE (if `plans/README.md` exists).

## STOP conditions

Stop and report back (do not improvise) if:

- The code at the locations in "Current state" doesn't match the excerpts (drift since this plan was written — the drift-check command shows changes).
- You cannot achieve a clean backward-compatible decode of the legacy JSON blob without data loss (the legacy-decode test cannot be made to pass without dropping or corrupting existing fields). This is the named MED migration risk — do not ship a shape that fails to load existing alerts.
- A newly added file is not compiled by the build (e.g. "no such module" / symbol-not-found referencing a file you added). The `project.pbxproj` is the source of truth and `project.yml` is broken; do not edit project files to fix this — instead, fold the code into an existing in-scope source file, and if that is impossible, STOP and report.
- Making the repeating-alert test pass would require broadening `private` access across `StockService` beyond one narrowly-scoped testable helper.
- A step's verification fails twice after a reasonable fix attempt.
- The fix appears to require touching an out-of-scope file (especially `StockItem.swift` fields or the persistence key/mechanism).

## Maintenance notes

For the human/agent who owns this code after this lands:

- **Persistence shape is now versioned by convention, not by a version field.** The custom `init(from:)` tolerates missing `kind`/`repeating`. Any future field added to `PriceAlert` must follow the same `decodeIfPresent ?? default` pattern, or it will break decoding of alerts saved by this version.
- `targetPrice` carries a **dual meaning** (absolute price vs percent threshold) discriminated by `kind`. A reviewer should confirm every read of `targetPrice` (notification text, UI labels, trigger logic) branches on `kind`. If this becomes error-prone, a follow-up could rename to a neutral `threshold` — but that is a persistence migration and was deliberately deferred here to keep this change backward-compatible.
- The re-arm/debounce relies on `conditionMet(...)` being evaluated in the arm block. If the refresh cadence or `checkPriceAlerts()` call site changes, re-verify that repeating alerts fire at most once per crossing.
- A reviewer should scrutinize: (1) the legacy-decode test actually uses a blob with the old keys only; (2) repeating alerts are never inserted into `triggeredAlertIDs`; (3) percent direction semantics (`isAbove` = gain vs loss) match the UI labels.
- Deferred out of scope: per-alert cooldown timers, intraday vs since-open percent basis selection, and any refactor splitting alert logic out of the `StockService` god object (tracked separately).
