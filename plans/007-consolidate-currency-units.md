# Plan 007: Consolidate the triplicated sub-unit currency normalization into one source of truth

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c0c912e..HEAD -- TickerBar/Models/StockItem.swift TickerBar/Services/StockService.swift TickerBarTests/StockItemTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (pairs with plans/009-*.md, but does not depend on it)
- **Category**: tech-debt
- **Planned at**: commit `c0c912e`, 2026-06-17

## Why this matters

The rule that "GBp/GBX prices are in pence (divide by 100, FX as GBP)" and "ILA prices are in agorot (divide by 100, FX as ILS)" is currently implemented **three separate times** in two files. `StockItem.isSubUnit` drives a `/100` display scaling; `StockService` has an inline copy inside its FX-currency-collection loop; and `StockService.normalizedCurrency(for:)` has a fourth identical mapping for rate lookup. Adding a new sub-unit currency (or correcting an existing one) requires editing all three in lockstep — and missing any one silently mis-scales a price by 100x or mis-converts the FX rate. This plan creates **one source of truth** for the sub-unit rule and routes all three call sites through it, so a future change is a single edit. The change is strictly behavior-preserving.

## Current state

Files involved:

- `TickerBar/Models/StockItem.swift` — the `StockItem` model (a `struct`). Holds copy #1 of the rule.
- `TickerBar/Services/StockService.swift` — the `@MainActor @Observable class StockService`. Holds copies #2 and #3.
- `TickerBarTests/StockItemTests.swift` — XCTest for the model; the structural pattern for the new test.

### Copy #1 — `StockItem.isSubUnit` / `subUnitScale` (`TickerBar/Models/StockItem.swift:23-49`)

```swift
    // MARK: - Sub-unit currency handling (GBX = pence, ILA = agorot)

    /// Whether the API price is in sub-units (pence, agorot, etc.)
    var isSubUnit: Bool {
        let c = currency ?? ""
        // GBp / GBX = British pence, ILA = Israeli agorot
        return c == "GBp" || c.uppercased() == "GBX" || c == "ILA"
    }

    /// Divisor to convert sub-units to major currency units
    private var subUnitScale: Double {
        isSubUnit ? 100.0 : 1.0
    }

    // MARK: - Display values (converted to major currency units)

    var displayPrice: Double { price / subUnitScale }
    var displayPreviousClose: Double { previousClose / subUnitScale }
    // ... 9 more display* properties all dividing by subUnitScale (lines 41-49)
```

### Copy #2 — inline FX normalization (`TickerBar/Services/StockService.swift:329-333`)

```swift
                // Normalize sub-unit currencies to their major unit
                let raw = stock.currency ?? "USD"
                if raw == "GBp" || raw.uppercased() == "GBX" { return "GBP" }
                if raw == "ILA" { return "ILS" }
                return raw.uppercased()
```

(This closure runs over `enriched` to build the set of currencies needing FX rates.)

### Copy #3 — `normalizedCurrency(for:)` (`TickerBar/Services/StockService.swift:655-661`)

```swift
    /// Get the normalized major-unit currency code for a stock (GBp/GBX -> GBP, ILA -> ILS)
    private func normalizedCurrency(for stock: StockItem) -> String {
        let raw = stock.currency ?? "USD"
        if raw == "GBp" || raw.uppercased() == "GBX" { return "GBP" }
        if raw == "ILA" { return "ILS" }
        return raw.uppercased()
    }
```

### Behavioral details that MUST be preserved

There are two subtly different behaviors across the copies — do **not** unify them away:

1. **The nil/empty default differs.** `StockItem.isSubUnit` treats `currency == nil` as `""`. The two `StockService` copies treat `currency == nil` as `"USD"` (i.e. they substitute `"USD"` *before* mapping). Keep that distinction: the model side asks "is this currency a sub-unit?" (answer for nil = false); the service side asks "what is the major-unit code?" (answer for nil = `"USD"`). The new helper must support both questions without changing either outcome.
2. **`majorUnitCode` upper-cases the passthrough.** Copies #2 and #3 return `raw.uppercased()` for non-sub-unit codes (so `"usd"` → `"USD"`). The major-unit helper must preserve this `.uppercased()` on the fallthrough path.
3. **Sub-unit detection is case-sensitive for `GBp`/`ILA` but case-insensitive for `GBX`.** All three copies use exactly: `c == "GBp" || c.uppercased() == "GBX" || c == "ILA"`. Preserve this exact predicate — do not "tidy" it into all-uppercased comparison, as that would change which strings match.

### Conventions to follow

- **Pure logic lives as `nonisolated static` funcs** so it is unit-testable without the `@MainActor` service. Confirmed exemplars in this repo: `StockService.parseQuoteResponse` (`TickerBar/Services/StockService.swift:414`), `StockService.mergedStocks` (`:366`), `StockService.isMarketOpen` (`:177`). Follow this pattern for the new helper.
- The new helper must be usable from **both** `StockItem` (a `struct`, non-isolated) and `StockService` (`@MainActor`). A free enum/struct with `static` functions, or static functions on `StockItem` itself, satisfies both. Recommended: a small `enum CurrencyUnit` with `static` functions, in its own file under `TickerBar/Models/`, so the model layer owns it and the service layer can call it. `enum` (no cases) is the idiomatic Swift namespace for static-only helpers.
- Tests are XCTest. Model after `TickerBarTests/StockItemTests.swift` (plain `XCTestCase`, no `@MainActor` needed since the helper is non-isolated).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` | `** BUILD SUCCEEDED **` |
| Test | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` | `** TEST SUCCEEDED **`, 0 failures |
| Drift check | `git diff --stat c0c912e..HEAD -- TickerBar/Models/StockItem.swift TickerBar/Services/StockService.swift TickerBarTests/StockItemTests.swift` | no output (no drift) |
| Status check | `git status --porcelain` | only in-scope files listed |

Notes:
- All `xcodebuild` commands run from the repo root `/Users/danny/VSCode/workspace/macos-stock-ticker`.
- There is no SwiftLint / swift-format / editorconfig in this repo — match the surrounding code style by eye (4-space indent, no trailing semicolons).
- **A new `.swift` file must be added to the Xcode project's build target.** The source of truth for the project is the committed `TickerBar.xcodeproj/project.pbxproj` (the `project.yml` XcodeGen spec is stale/broken — do NOT use it). See Step 1's STOP note if you cannot get a new file compiled into the target. To avoid project-file editing entirely, the recommended approach in Step 1 places the helper inside the existing `StockItem.swift` file, which is already in the target.

## Scope

**In scope** (the only files you should modify):
- `TickerBar/Models/StockItem.swift` (modify — add helper + route `isSubUnit`/`subUnitScale` through it)
- `TickerBar/Services/StockService.swift` (modify — route copies #2 and #3 through the helper)
- `TickerBarTests/StockItemTests.swift` (modify — add the table-driven test)

**Out of scope** (do NOT touch, even though they look related):
- `TickerBar/Models/StockItem.swift` `currencySymbol` (lines 66-81) — that is a display-symbol map, a *different* concern; consolidating it is not part of this plan.
- The 11 `display*` computed properties (`StockItem.swift:39-49) — they should keep dividing by `subUnitScale`; only `subUnitScale`'s *definition* changes.
- `project.yml` — stale XcodeGen spec, not the build source of truth.
- Any change to FX-fetch logic, rate math, or the public/persisted shape of `StockItem` (it is `Codable`; do not add/remove/rename stored properties).
- Splitting up `StockService` (tracked separately; not this plan).

## Git workflow

- Branch: `refactor/007-consolidate-currency-units` (create from `master`).
- Commit per logical unit; imperative subjects matching `git log` style (e.g. `Add CurrencyUnit helper as single source of truth for sub-unit currencies`, `Route StockService FX normalization through CurrencyUnit`).
- **HARD rule**: NO `Co-Authored-By`, NO "Generated with Claude Code", NO AI attribution anywhere in commits or PR.
- Do NOT push or open a PR unless the operator explicitly instructs it.

## Steps

### Step 1: Add the single source of truth `CurrencyUnit`

In `TickerBar/Models/StockItem.swift`, add a new `enum CurrencyUnit` namespace (recommended: in the **same file**, below the `StockItem` struct, so no Xcode project-file edit is required and both the model and service can reference it). Implement exactly two `static` functions that capture the two distinct questions identified in "Current state":

```swift
/// Single source of truth for sub-unit currency handling.
/// GBp / GBX = British pence, ILA = Israeli agorot — all 1/100 of their major unit.
enum CurrencyUnit {
    /// Divisor to convert a raw (sub-unit) price into major currency units.
    /// 100 for sub-unit currencies, 1 otherwise. `nil`/empty -> 1 (not a sub-unit).
    static func subUnitDivisor(forCurrency currency: String?) -> Double {
        let c = currency ?? ""
        let isSubUnit = c == "GBp" || c.uppercased() == "GBX" || c == "ILA"
        return isSubUnit ? 100.0 : 1.0
    }

    /// The major-unit currency code for FX lookup (GBp/GBX -> GBP, ILA -> ILS,
    /// others upper-cased unchanged). `nil` defaults to "USD" before mapping.
    static func majorUnitCode(forCurrency currency: String?) -> String {
        let raw = currency ?? "USD"
        if raw == "GBp" || raw.uppercased() == "GBX" { return "GBP" }
        if raw == "ILA" { return "ILS" }
        return raw.uppercased()
    }
}
```

Note the deliberate asymmetry preserved: `subUnitDivisor` defaults nil → `""` (not a sub-unit), `majorUnitCode` defaults nil → `"USD"`. This matches the existing copies exactly.

If you instead create a separate new file (e.g. `TickerBar/Models/CurrencyUnit.swift`), you MUST add it to the `TickerBar` target in `TickerBar.xcodeproj/project.pbxproj`. If the build cannot find the new type after that, treat it as a STOP condition (see STOP conditions) — the same-file approach above avoids this risk.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build 2>&1 | tail -3` → ends with `** BUILD SUCCEEDED **`

### Step 2: Route `StockItem.subUnitScale` (and remove the duplicated predicate)

In `TickerBar/Models/StockItem.swift`, replace the body of `subUnitScale` to delegate to the helper, and rewrite `isSubUnit` to derive from it so there is no second copy of the predicate inside the struct:

```swift
    /// Whether the API price is in sub-units (pence, agorot, etc.)
    var isSubUnit: Bool {
        CurrencyUnit.subUnitDivisor(forCurrency: currency) != 1.0
    }

    /// Divisor to convert sub-units to major currency units
    private var subUnitScale: Double {
        CurrencyUnit.subUnitDivisor(forCurrency: currency)
    }
```

Leave all 11 `display*` properties (lines 39-49) unchanged — they still divide by `subUnitScale`. Do not touch `currencySymbol`.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build 2>&1 | tail -3` → ends with `** BUILD SUCCEEDED **`

### Step 3: Route StockService copy #2 (inline FX normalization)

In `TickerBar/Services/StockService.swift`, in the currency-collection closure (currently lines 327-333), replace the inline `if/return` block with a single call. The closure becomes:

```swift
            let currencies = Set(enriched.compactMap { stock -> String? in
                guard holdings[stock.symbol] != nil else { return nil }
                // Normalize sub-unit currencies to their major unit
                return CurrencyUnit.majorUnitCode(forCurrency: stock.currency)
            })
```

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build 2>&1 | tail -3` → ends with `** BUILD SUCCEEDED **`

### Step 4: Route StockService copy #3 (`normalizedCurrency(for:)`)

In `TickerBar/Services/StockService.swift`, replace the body of `normalizedCurrency(for:)` (currently lines 656-661) to delegate. Keep the function (its callers, e.g. `rateToBase` at line 665, are out of scope):

```swift
    /// Get the normalized major-unit currency code for a stock (GBp/GBX -> GBP, ILA -> ILS)
    private func normalizedCurrency(for stock: StockItem) -> String {
        CurrencyUnit.majorUnitCode(forCurrency: stock.currency)
    }
```

**Verify**: `grep -n 'raw == "GBp"\|raw == "ILA"\|== "GBX"' TickerBar/Services/StockService.swift` → no matches (both inline copies in StockService are gone). Then: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build 2>&1 | tail -3` → `** BUILD SUCCEEDED **`

### Step 5: Add the table-driven test

In `TickerBarTests/StockItemTests.swift`, add one new test method modeled on the existing plain-`XCTestCase` style (no `@MainActor` needed; `CurrencyUnit` is non-isolated). It must enumerate the cases below and assert both functions:

```swift
    func testCurrencyUnitDivisorAndMajorCode() {
        // (input, expectedDivisor, expectedMajorCode)
        let cases: [(String?, Double, String)] = [
            ("GBp", 100.0, "GBP"),
            ("GBX", 100.0, "GBP"),
            ("gbx", 100.0, "GBP"),   // GBX match is case-insensitive
            ("ILA", 100.0, "ILS"),
            ("USD", 1.0, "USD"),
            ("GBP", 1.0, "GBP"),
            ("usd", 1.0, "USD"),     // passthrough is upper-cased
        ]
        for (input, divisor, major) in cases {
            XCTAssertEqual(CurrencyUnit.subUnitDivisor(forCurrency: input), divisor,
                           "divisor for \(String(describing: input))")
            XCTAssertEqual(CurrencyUnit.majorUnitCode(forCurrency: input), major,
                           "majorUnitCode for \(String(describing: input))")
        }
        // nil defaults: not a sub-unit (divisor 1), but major code is USD
        XCTAssertEqual(CurrencyUnit.subUnitDivisor(forCurrency: nil), 1.0)
        XCTAssertEqual(CurrencyUnit.majorUnitCode(forCurrency: nil), "USD")
    }
```

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test 2>&1 | tail -5` → contains `** TEST SUCCEEDED **` and `Executed N tests, with 0 failures` (N = previous count + 1).

### Step 6: Final whole-suite confirmation

Run the full build and test once more to confirm nothing regressed, and confirm only in-scope files changed.

**Verify**:
- `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test 2>&1 | tail -3` → `** TEST SUCCEEDED **`
- `git status --porcelain` → lists only `TickerBar/Models/StockItem.swift`, `TickerBar/Services/StockService.swift`, `TickerBarTests/StockItemTests.swift` (plus `plans/README.md` once you update the index).

## Test plan

- **New test**: `testCurrencyUnitDivisorAndMajorCode` in `TickerBarTests/StockItemTests.swift`, table-driven, covering:
  - Sub-unit currencies: `GBp`, `GBX`, lowercase `gbx`, `ILA` → divisor `100`; major code `GBP`/`GBP`/`GBP`/`ILS`.
  - Plain currencies: `USD`, `GBP` → divisor `1`; major code unchanged.
  - Case normalization: `usd` → major code `USD` (passthrough upper-cases).
  - `nil` input: divisor `1` (not a sub-unit) **and** major code `USD` (the deliberate asymmetry — this is the regression guard for the two different nil-defaults).
- **Structural pattern**: model after the existing methods in `TickerBarTests/StockItemTests.swift` (plain `XCTestCase`, `XCTAssertEqual` with `accuracy:` only where floating-point math is involved — exact equality is fine for these divisor/string values).
- **Verification**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`, all existing tests still pass plus the 1 new test.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` ends with `** BUILD SUCCEEDED **`
- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` ends with `** TEST SUCCEEDED **`, 0 failures, and `testCurrencyUnitDivisorAndMajorCode` is in the executed list
- [ ] `grep -rn 'raw == "GBp"\|raw == "ILA"\|c == "GBp"' TickerBar/Services/StockService.swift` returns no matches (both StockService copies removed)
- [ ] `grep -c 'enum CurrencyUnit' TickerBar/Models/StockItem.swift` returns `1` (single source of truth exists)
- [ ] `grep -rn 'CurrencyUnit.subUnitDivisor\|CurrencyUnit.majorUnitCode' TickerBar` shows the helper is called from both `StockItem.swift` and `StockService.swift`
- [ ] No files outside the in-scope list are modified (`git status --porcelain` — aside from `plans/README.md`)
- [ ] `plans/README.md` status row for plan 007 updated to DONE

## STOP conditions

Stop and report back (do not improvise) if:

- The drift check shows any in-scope file changed since `c0c912e` and the "Current state" excerpts no longer match the live code.
- The exact predicate `c == "GBp" || c.uppercased() == "GBX" || c == "ILA"` (or its StockService twin) is not found verbatim at the cited lines — the codebase has drifted; do not guess the new mapping.
- You created a separate `CurrencyUnit.swift` file and the build fails to find the type even after editing `TickerBar.xcodeproj/project.pbxproj` — fall back to the same-file approach in Step 1, or stop and report (do NOT spend effort hand-editing pbxproj UUIDs).
- Any build or test verification fails twice after a reasonable fix attempt.
- You find a **fourth** copy of the sub-unit rule anywhere (`grep -rn 'GBp\|GBX\|ILA' TickerBar`) outside the three documented sites and `currencySymbol` — report it; routing it may be in scope but confirm first.
- Removing/renaming a stored property of `StockItem` appears necessary — it is `Codable`; this is out of scope and would change persisted/decoded shape.

## Maintenance notes

For the human/agent who owns this code after the change lands:

- **Adding a new sub-unit currency is now a single edit** in `CurrencyUnit` (`TickerBar/Models/StockItem.swift`): add the code to both `subUnitDivisor`'s predicate and `majorUnitCode`'s mapping, and add a row to `testCurrencyUnitDivisorAndMajorCode`. No need to touch `StockService` or the `display*` properties.
- The two nil-defaults are intentionally different (`subUnitDivisor` nil → not-sub-unit; `majorUnitCode` nil → `USD`). A reviewer should confirm the test still pins both, and not "simplify" them to a shared default.
- `currencySymbol` (`StockItem.swift:66-81`) remains a separate, un-consolidated map of display symbols. If a future change adds a currency, that map may also need updating — it was deliberately left out of this plan's scope.
- Pairs with plan 009 (same area). If 009 also touches `StockItem`/`StockService` currency handling, land them in an order that avoids overlapping edits to the same lines.
- A reviewer should scrutinize that all 11 `display*` properties still divide by `subUnitScale` and that no FX rate math changed — this plan is strictly behavior-preserving.
