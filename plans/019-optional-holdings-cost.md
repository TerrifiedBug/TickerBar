# Plan 019: Multi-lot holdings with RSU (value-only) and Purchase (cost) lots

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c0c912e..HEAD -- TickerBar/Services/StockService.swift TickerBar/Views/WatchlistView.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MED
- **Depends on**: plans/008-inject-userdefaults.md (test isolation); coordinate with plans/006-fx-rate-fallback-signal.md, plans/009-tests-money-alert-markethours.md, and plans/015-direction-export-import.md (all touch holdings / portfolio totals — land 006 and 008 first; do this before 009 and 015 so they build on the multi-lot shape, or note coordination if they land first)
- **Category**: direction
- **Planned at**: commit `c0c912e`, 2026-06-17

## Why this matters

A holding today is **one record per symbol** (`holdings: [String: Holding]`) and **requires** a cost basis. Two real cases break that:

1. **Vested RSUs** (e.g. ticker SRAD): awarded with no meaningful purchase price — the user wants **value** (`shares × current price`), not gain. Forcing a cost (and prefilling it with the *current* price, `WatchlistView.swift:136`) is misleading.
2. **RSUs *and* self-purchased shares of the same symbol**: e.g. 50 vested shares plus 10 bought at $130. One record per symbol cannot represent both.

This plan moves to a **multi-lot** model: `holdings[symbol]` becomes a list of lots, each tagged **RSU** (shares, no cost → value-only) or **Purchase** (shares + cost → contributes to gain). A symbol may hold **any number of lots of either kind** — multiple RSU vests *and* multiple separate purchases (e.g. buy 50 @ $X, then 100 @ $Y later); each "Add Purchase…" appends a new lot, so cost averaging across buys is automatic. Total **value** sums all lots; **gain/loss** sums only lots that have a cost. The UI gains two explicit actions — **Add RSUs…** (shares only) and **Add Purchase…** (shares + cost) — with existing lots listed for edit/remove. Existing single-record holdings are migrated to a one-element Purchase lot.

## Current state

The facts the executor needs, inlined:

- `TickerBar/Services/StockService.swift`:
  - `Holding` is a nested non-optional-cost struct (lines 56–59):
    ```swift
    struct Holding: Codable, Equatable {
        var shares: Double
        var costBasis: Double  // average price per share
    }
    ```
  - `holdings` is `[String: Holding]`, persisted as JSON via `didSet` (61–67) and decoded in `init` (122–125):
    ```swift
    var holdings: [String: Holding] = [:] {
        didSet {
            if let data = try? JSONEncoder().encode(holdings) {
                UserDefaults.standard.set(data, forKey: "holdings")
            }
        }
    }
    // init:
    if let holdingsData = defaults.data(forKey: "holdings"),
       let savedHoldings = try? JSONDecoder().decode([String: Holding].self, from: holdingsData) {
        self.holdings = savedHoldings
    }
    ```
  - `setHolding` / `holdingFor` (643–653):
    ```swift
    func setHolding(symbol: String, shares: Double, costBasis: Double) {
        if shares > 0 { holdings[symbol] = Holding(shares: shares, costBasis: costBasis) }
        else { holdings.removeValue(forKey: symbol) }
    }
    func holdingFor(_ symbol: String) -> Holding? { holdings[symbol] }
    ```
  - `removeSymbol` clears the holding (line 557): `holdings.removeValue(forKey: symbol)`.
  - Portfolio totals (670–690) — `totalPortfolioValue` sums all holdings, `totalPortfolioCost` sums `costBasis * shares`, gain/percent derive from them (full excerpt):
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
    var totalPortfolioGain: Double { totalPortfolioValue - totalPortfolioCost }
    var totalPortfolioGainPercent: Double {
        totalPortfolioCost > 0 ? (totalPortfolioGain / totalPortfolioCost) * 100 : 0
    }
    ```

- `TickerBar/Views/WatchlistView.swift`:
  - `@State` for the holdings editor (lines 16–18): `holdingsSymbol`, `holdingsSharesText`, `holdingsCostText`.
  - Context menu holdings block (133–143) — single Add/Edit + Remove, with the misleading current-price prefill:
    ```swift
    let holding = service.holdingFor(stock.symbol)
    Button(holding != nil ? "Edit Holdings (\(String(format: "%.2f", holding!.shares)) shares)..." : "Add Holdings...") {
        holdingsSharesText = holding != nil ? String(format: "%.2f", holding!.shares) : ""
        holdingsCostText = holding != nil ? String(format: "%.2f", holding!.costBasis) : String(format: "%.2f", stock.displayPrice)
        holdingsSymbol = stock.symbol
    }
    if holding != nil {
        Button("Remove Holdings") { service.setHolding(symbol: stock.symbol, shares: 0, costBasis: 0) }
    }
    ```
  - Holdings input form (191–240) with shares + Avg Cost fields and a Save gated on both being Doubles (233).
  - Portfolio summary (71–86) shows value + gain whenever `totalPortfolioValue > 0`.
  - `StockRowView` takes `holding: StockService.Holding?` (427), shows a briefcase icon when non-nil (468–472), and builds a tooltip holdings line (445–449) using `h.costBasis`.
  - Row passes the holding in (97): `StockRowView(stock: stock, hasAlert: ..., holding: service.holdingFor(stock.symbol))`.

- Conventions: persisted settings use `didSet` → UserDefaults. Swift synthesizes `Codable`. For the migration, a manual decode fallback is required because the persisted top-level shape changes from `[String: Holding]` to `[String: [Holding]]`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` | `** BUILD SUCCEEDED **`, exit 0 |
| Test | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` | `** TEST SUCCEEDED **`, exit 0 |
| Find references | `grep -rn "costBasis\|holdingFor\|setHolding\|holdings\[" TickerBar/` | every site updated |
| Git status | `git status --porcelain` | only in-scope paths |

## Scope

**In scope**:
- `TickerBar/Services/StockService.swift` — `Holding`/`LotKind`, `holdings` shape + migration, lot CRUD, portfolio totals, `removeSymbol`
- `TickerBar/Views/WatchlistView.swift` — context menu (two add buttons + lot list), editor form, summary gate, tooltip, `StockRowView` signature
- `TickerBarTests/StockServiceTests.swift` (or new `HoldingTests.swift`) — tests
- `plans/README.md` (status row)

**Out of scope**:
- `rateToBase` / `exchangeRates` — plan 006 owns FX. Use `rateToBase(for:)` unchanged.
- Export/import schema — plan 015; if landed, make its `Holding` encode/decode compile with the new shape and flag for that reviewer, no further edits.
- Price-alert and watchlist models.

## Git workflow

- Branch: `feat/019-multi-lot-holdings`
- Commit per logical unit; imperative subject matching `git log` (e.g. `Add multi-lot RSU and purchase holdings`).
- No "Co-Authored-By", no "Generated with Claude Code", no AI attribution.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: New lot model + migration

Replace the `Holding` struct (StockService.swift:56–59) with a lot type carrying identity, kind, and optional cost, and change `holdings` to a list-per-symbol with a backward-compatible decode.

```swift
enum LotKind: String, Codable, Equatable {
    case rsu        // vested/awarded — value only, no cost basis
    case purchase   // bought — has a cost basis
}

struct Holding: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: LotKind
    var shares: Double
    var costBasis: Double?   // nil for rsu; set for purchase

    init(id: UUID = UUID(), kind: LotKind, shares: Double, costBasis: Double?) {
        self.id = id; self.kind = kind; self.shares = shares; self.costBasis = costBasis
    }
}
```

Change the property to `var holdings: [String: [Holding]] = [:]` keeping the same `didSet` (it encodes whatever the current shape is). In `init`, decode the new shape, falling back to the legacy single-record shape:

```swift
if let holdingsData = defaults.data(forKey: "holdings") {
    if let modern = try? JSONDecoder().decode([String: [Holding]].self, from: holdingsData) {
        self.holdings = modern
    } else {
        // Legacy: [String: {shares, costBasis}] — wrap each as a single Purchase lot.
        struct LegacyHolding: Codable { var shares: Double; var costBasis: Double }
        if let legacy = try? JSONDecoder().decode([String: LegacyHolding].self, from: holdingsData) {
            self.holdings = legacy.mapValues { [Holding(kind: .purchase, shares: $0.shares, costBasis: $0.costBasis)] }
        }
    }
}
```

**Verify**: `xcodebuild ... build` → compile errors only at the old `Holding`/`setHolding`/`holdingFor`/portfolio sites (expected; fixed next).

### Step 2: Lot CRUD API

Replace `setHolding`/`holdingFor` (643–653) with list-aware operations:

```swift
func lots(for symbol: String) -> [Holding] { holdings[symbol] ?? [] }

func addLot(symbol: String, kind: LotKind, shares: Double, costBasis: Double?) {
    guard shares > 0 else { return }
    let cost = kind == .rsu ? nil : costBasis
    holdings[symbol, default: []].append(Holding(kind: kind, shares: shares, costBasis: cost))
}

func updateLot(symbol: String, id: UUID, shares: Double, costBasis: Double?) {
    guard var list = holdings[symbol], let idx = list.firstIndex(where: { $0.id == id }) else { return }
    if shares > 0 {
        list[idx].shares = shares
        list[idx].costBasis = list[idx].kind == .rsu ? nil : costBasis
        holdings[symbol] = list
    } else {
        removeLot(symbol: symbol, id: id)
    }
}

func removeLot(symbol: String, id: UUID) {
    guard var list = holdings[symbol] else { return }
    list.removeAll { $0.id == id }
    if list.isEmpty { holdings.removeValue(forKey: symbol) } else { holdings[symbol] = list }
}

/// True when any lot anywhere has a cost basis (so gain/loss is meaningful).
var hasCostBasis: Bool {
    holdings.values.contains { lots in lots.contains { $0.costBasis != nil } }
}
```

`removeSymbol` (line 557) keeps `holdings.removeValue(forKey: symbol)` — still correct.

**Verify**: builds past these sites.

### Step 3: Portfolio math over all lots

Replace the totals (670–690) to iterate every lot:

```swift
var totalPortfolioValue: Double {
    stocks.reduce(0) { total, stock in
        let rate = rateToBase(for: stock)
        return total + lots(for: stock.symbol).reduce(0) { $0 + stock.displayPrice * $1.shares * rate }
    }
}

var totalPortfolioCost: Double {
    stocks.reduce(0) { total, stock in
        let rate = rateToBase(for: stock)
        return total + lots(for: stock.symbol).reduce(0) { acc, lot in
            guard let cost = lot.costBasis else { return acc }
            return acc + cost * lot.shares * rate
        }
    }
}

/// Current value of only the cost-bearing lots — the basis for gain.
private var costBasisLotsValue: Double {
    stocks.reduce(0) { total, stock in
        let rate = rateToBase(for: stock)
        return total + lots(for: stock.symbol).reduce(0) { acc, lot in
            lot.costBasis == nil ? acc : acc + stock.displayPrice * lot.shares * rate
        }
    }
}

var totalPortfolioGain: Double { costBasisLotsValue - totalPortfolioCost }
var totalPortfolioGainPercent: Double {
    totalPortfolioCost > 0 ? (totalPortfolioGain / totalPortfolioCost) * 100 : 0
}
```

**Verify**: `xcodebuild ... build` succeeds once views (Step 4) are fixed.

### Step 4: UI — two add actions, lot list, gated gain, tooltip

In `WatchlistView.swift`:

1. **Editor state** (16–18): replace the single-edit state with enough to drive a typed form. Add:
   ```swift
   @State private var holdingsSymbol: String?
   @State private var holdingsKind: StockService.LotKind = .purchase
   @State private var editingLotID: UUID?          // nil = adding a new lot
   @State private var holdingsSharesText = ""
   @State private var holdingsCostText = ""
   ```

2. **Context menu** (replace 133–143): two add buttons + a list of existing lots with edit/remove. No current-price prefill.
   ```swift
   Button("Add RSUs...") {
       holdingsKind = .rsu; editingLotID = nil
       holdingsSharesText = ""; holdingsCostText = ""
       holdingsSymbol = stock.symbol
   }
   Button("Add Purchase...") {
       holdingsKind = .purchase; editingLotID = nil
       holdingsSharesText = ""; holdingsCostText = ""
       holdingsSymbol = stock.symbol
   }
   let lots = service.lots(for: stock.symbol)
   if !lots.isEmpty {
       Divider()
       ForEach(lots) { lot in
           let label = lot.kind == .rsu
               ? "RSU \(String(format: "%.2f", lot.shares)) sh"
               : "Buy \(String(format: "%.2f", lot.shares)) sh @ \(stock.currencySymbol)\(String(format: "%.2f", lot.costBasis ?? 0))"
           Menu(label) {
               Button("Edit...") {
                   holdingsKind = lot.kind; editingLotID = lot.id
                   holdingsSharesText = String(format: "%.2f", lot.shares)
                   holdingsCostText = lot.costBasis.map { String(format: "%.2f", $0) } ?? ""
                   holdingsSymbol = stock.symbol
               }
               Button("Remove") { service.removeLot(symbol: stock.symbol, id: lot.id) }
           }
       }
   }
   ```

3. **Editor form** (191–240): title reflects kind (`"Add RSUs for \(symbol)"` / `"Add Purchase for \(symbol)"` / `"Edit ..."`). Show the Avg Cost field **only** when `holdingsKind == .purchase`. Save:
   ```swift
   Button("Save") {
       if let shares = Double(holdingsSharesText) {
           let cost = holdingsKind == .rsu ? nil
               : Double(holdingsCostText.trimmingCharacters(in: .whitespaces))
           if let id = editingLotID {
               service.updateLot(symbol: symbol, id: id, shares: shares, costBasis: cost)
           } else {
               service.addLot(symbol: symbol, kind: holdingsKind, shares: shares, costBasis: cost)
           }
       }
       holdingsSymbol = nil
   }
   .disabled(
       Double(holdingsSharesText) == nil ||
       (holdingsKind == .purchase && Double(holdingsCostText) == nil)
   )
   ```
   (RSU mode: cost hidden, never required. Purchase mode: cost required, as today.)

4. **Summary gate** (71–86): value always; gain `Text` only when `service.hasCostBasis`.

5. **`StockRowView`** (427, 468–472, 445–449, and the call at 97): change the param from `holding: StockService.Holding?` to `lots: [StockService.Holding]` (pass `service.lots(for: stock.symbol)`). Show the briefcase icon when `!lots.isEmpty`. Build the tooltip from all lots — per lot show value, and gain only if it has cost:
   ```swift
   for lot in lots {
       let value = stock.displayPrice * lot.shares
       if let cost = lot.costBasis {
           let gain = (stock.displayPrice - cost) * lot.shares
           lines.append("\(lot.kind == .rsu ? "RSU" : "Buy") \(String(format: "%.2f", lot.shares)) @ \(cs)\(String(format: "%.2f", cost)) = \(cs)\(String(format: "%.2f", value)) (\(String(format: "%+.2f", gain)))")
       } else {
           lines.append("RSU \(String(format: "%.2f", lot.shares)) sh = \(cs)\(String(format: "%.2f", value))")
       }
   }
   ```
   Update the `hasAlert`/`holding` call site (97) accordingly.

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`. `grep -rn "holdingFor\|setHolding\|h.costBasis\|holding!" TickerBar/` returns no stale single-holding API use.

### Step 5: Tests

In `TickerBarTests/StockServiceTests.swift` (isolated `UserDefaults` per plan 008 if landed):

- **Legacy migration**: persist a legacy blob `{"AAPL":{"shares":10,"costBasis":130.0}}` under key `holdings`, init a service, assert `lots(for:"AAPL")` is one `.purchase` lot with `costBasis == 130.0`.
- **Modern round-trip**: add an RSU lot and a purchase lot for the same symbol, re-init from the same defaults, assert both lots persist with correct kinds/costs.
- **Value includes RSU lot, gain excludes it**: stocks + an RSU lot (no cost) + a purchase lot; assert `totalPortfolioValue` includes both, `totalPortfolioCost`/`totalPortfolioGain` reflect only the purchase lot, `hasCostBasis == true`.
- **Pure RSU portfolio**: only RSU lots → `hasCostBasis == false`, `totalPortfolioGain == 0`, value > 0.
- **Multiple purchase lots (cost averaging)**: add two `.purchase` lots for the same symbol (e.g. 50 @ 100 and 100 @ 130); assert both persist, `totalPortfolioCost` = 50·100 + 100·130 (× rate), and gain is computed across both.
- **Lot CRUD**: addLot twice then removeLot one by id leaves the other; removing the last lot drops the symbol key.

**Verify**: `xcodebuild ... test` → `** TEST SUCCEEDED **` with new tests passing.

## Test plan

- Tests in `TickerBarTests/StockServiceTests.swift` (or new `HoldingTests.swift` modeled on `StockItemTests.swift`).
- Cases listed in Step 5: legacy migration, modern round-trip, mixed value/gain, pure-RSU, lot CRUD.
- Verification: `xcodebuild ... test` → all pass.

## Done criteria

ALL must hold:

- [ ] `xcodebuild ... build` exits 0
- [ ] `xcodebuild ... test` exits 0; new multi-lot tests exist and pass
- [ ] `grep -n "holdings: \[String: \[Holding\]\]" TickerBar/Services/StockService.swift` matches
- [ ] `grep -rn "holdingFor\|func setHolding" TickerBar/` returns nothing (old API gone)
- [ ] current-price prefill removed (no `String(format: "%.2f", stock.displayPrice)` in the holdings-add buttons)
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- "Current state" excerpts don't match live code (drift).
- The legacy-migration test fails — report before changing the persisted key name or shape further (do NOT silently drop users' existing holdings).
- The change forces edits to plan 006 FX code or plan 015 export schema beyond compiling.
- A step's verification fails twice after a reasonable fix.

## Maintenance notes

- Persisted shape changed `[String: Holding]` → `[String: [Holding]]` under the same `holdings` UserDefaults key; the legacy fallback decode must stay until all users have re-saved. Don't rename the key.
- Export/import (plan 015) must encode the lot array and the `LotKind`/optional cost; add a round-trip test there.
- Gain compares cost against the value of cost-bearing **lots only** (`costBasisLotsValue`); confirm that's the intended semantics for mixed RSU+purchase portfolios in review.
- RSU cost basis for tax is the vest price; this plan treats RSUs as value-only per the owner's use case. A future "RSU with vest cost" mode could set `costBasis` on an `.rsu` lot — the model already allows it (only the UI hides the field).
- `Holding` is now `Identifiable` (UUID) so SwiftUI `ForEach` over lots is stable across edits.
