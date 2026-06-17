# Plan 015: Export & import watchlist, holdings, and alerts (design + build)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c0c912e..HEAD -- TickerBar/Services/StockService.swift TickerBar/Views/SettingsView.swift TickerBar/TickerBar.entitlements TickerBarTests/StockServiceTests.swift`
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

All user data — watchlist, portfolio holdings, price alerts, and base currency — is persisted **only** to `UserDefaults` (see `StockService.swift:16-17, 61-76`). There is no export path. If a user moves to a new Mac, resets defaults, or reinstalls the app, every symbol, holding, and alert is lost and must be re-entered one at a time through the popovers in `WatchlistView`. Because `StockItem`, `PriceAlert`, and `StockService.Holding` are all already `Codable`, adding a JSON export/import is low-cost and gives users backup, migration, and recovery. After this lands, a user can click **Export** in Settings to write a `.json` backup and **Import** to restore it (replacing or merging existing data), then the app re-fetches quotes.

## Current state

Files involved:

- `TickerBar/Services/StockService.swift` — the `@MainActor @Observable` model. Owns all user data and the persistence pattern. Add the pure encode/decode logic and the import-apply method here.
- `TickerBar/Views/SettingsView.swift` — the inline settings panel (shown by `WatchlistView.swift:361`). Add the Export/Import buttons here.
- `TickerBar/TickerBar.entitlements` — App Sandbox entitlements. Must gain user-selected file read-write.
- `TickerBar/Models/StockItem.swift` — `struct StockItem: Identifiable, Codable, Equatable` (line 3). Already `Codable`. Do not modify.
- `TickerBar/Models/PriceAlert.swift` — `struct PriceAlert: Identifiable, Codable, Equatable` (line 3). Already `Codable`. Do not modify.
- `TickerBarTests/StockServiceTests.swift` — XCTest, `@MainActor final class` (line 4-5). Add round-trip + malformed-import tests here.

The data to export, all on `StockService`:

```swift
// StockService.swift:16-17
var watchlist: [String] {
    didSet { UserDefaults.standard.set(watchlist, forKey: "watchlist") }
}
// :40-42
var baseCurrency: String {
    didSet { UserDefaults.standard.set(baseCurrency, forKey: "baseCurrency") }
}
// :56-67  — Holding is a NESTED type: StockService.Holding
struct Holding: Codable, Equatable {
    var shares: Double
    var costBasis: Double  // average price per share
}
var holdings: [String: Holding] = [:] {
    didSet { if let data = try? JSONEncoder().encode(holdings) { UserDefaults.standard.set(data, forKey: "holdings") } }
}
// :70-76
var priceAlerts: [PriceAlert] = [] {
    didSet { if let data = try? JSONEncoder().encode(priceAlerts) { UserDefaults.standard.set(data, forKey: "priceAlerts") } }
}
```

Existing watchlist-mutation methods to reuse for re-fetch semantics:

```swift
// StockService.swift:529-533
func addSymbol(_ symbol: String) {
    let uppercased = symbol.uppercased().trimmingCharacters(in: .whitespaces)
    guard !uppercased.isEmpty, !watchlist.contains(uppercased) else { return }
    watchlist.append(uppercased)
}
// :641-649
func setHolding(symbol: String, shares: Double, costBasis: Double) {
    if shares > 0 { holdings[symbol] = Holding(shares: shares, costBasis: costBasis) }
    else { holdings.removeValue(forKey: symbol) }
}
```

`fetchAllQuotes(isTimerTriggered:)` is the re-fetch entry point (`:262`); call `await service.fetchAllQuotes()` after a successful import, matching how `WatchlistView.addSymbol()` does it (`WatchlistView.swift:397`).

Current entitlements — note the **absence** of any user-selected-files key:

```xml
<!-- TickerBar/TickerBar.entitlements:4-14 -->
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
    <array>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spks</string>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spki</string>
    </array>
</dict>
```

**Sandbox implication**: the app is sandboxed (`com.apple.security.app-sandbox = true`). Reading/writing an arbitrary user-chosen file therefore requires `com.apple.security.files.user-selected.read-write`. `NSSavePanel`/`NSOpenPanel` grant a temporary, user-consented access scope to exactly the file the user picks — no broad disk access — so this is the minimal, App-Store-acceptable entitlement for this feature.

Repo conventions to honor:

- **Pure logic is `nonisolated static`** so it is unit-testable without the `@MainActor` service. Examples already in the file: `parseQuoteResponse` (`:414`), `mergedStocks` (`:366`), `isMarketOpen` (`:177`). The encode/decode payload logic in this plan MUST follow that pattern — put it in `nonisolated static func`s that take/return plain values, and keep only the panel presentation and state mutation on the `@MainActor` instance methods.
- **Persisted settings use `didSet` → `UserDefaults.standard`** (`:16-48`); when import assigns to `watchlist`, `holdings`, `priceAlerts`, `baseCurrency` those `didSet`s persist automatically. Do not add a separate persistence call.
- **Settings UI** is plain SwiftUI `HStack`/`Button`/`Toggle` rows inside one `VStack(alignment: .leading, spacing: 12)` with `.padding(12)` (`SettingsView.swift:13-145`). Match that. There is no separate settings window — `SettingsView` is embedded inline (`WatchlistView.swift:359-362`).
- **Tests**: XCTest, `@testable import TickerBar`, `@MainActor final class ...: XCTestCase`; `setUp` clears UserDefaults keys (`StockServiceTests.swift:7-18`). Encode-then-decode style is already used (`testParseYahooResponse` builds JSON `Data` and asserts on parsed fields).

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` | `** BUILD SUCCEEDED **` |
| Test      | `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` | `** TEST SUCCEEDED **` |
| Drift     | `git diff --stat c0c912e..HEAD -- TickerBar/Services/StockService.swift TickerBar/Views/SettingsView.swift TickerBar/TickerBar.entitlements TickerBarTests/StockServiceTests.swift` | no output (no drift) |

Run all commands from the repo root `/Users/danny/VSCode/workspace/macos-stock-ticker`. The committed `TickerBar.xcodeproj/project.pbxproj` is the source of truth; **do NOT** use or regenerate from `project.yml` (it is stale/broken).

## Scope

**In scope** (the only files you should modify):
- `TickerBar/Services/StockService.swift`
- `TickerBar/Views/SettingsView.swift`
- `TickerBar/TickerBar.entitlements`
- `TickerBarTests/StockServiceTests.swift`

**Out of scope** (do NOT touch, even though they look related):
- `TickerBar/Models/StockItem.swift`, `TickerBar/Models/PriceAlert.swift` — already `Codable`; no change needed. Adding/altering `CodingKeys` would risk breaking the existing `UserDefaults` persistence format.
- `TickerBar/Views/WatchlistView.swift` — the popovers and the `SettingsView` call site are fine as-is; the new buttons live in `SettingsView`.
- `project.yml` — stale XcodeGen spec; never edit or run it.
- `.github/workflows/release.yml` — CI runs only on `v*` tags; not relevant here.
- Do NOT introduce CSV export in this plan (see Open questions). JSON only.

## Git workflow

- Branch: `feat/015-direction-export-import`
- Commit per logical unit; imperative subjects matching `git log` style (e.g. "Add", "Fix"). Example existing subject: `Fix dropdown empty space after collapsing Settings`.
- HARD RULES: NO `Co-Authored-By` lines. NO "Generated with Claude Code" or any AI attribution anywhere in commits or PR body.
- Do NOT push or open a PR unless the operator explicitly instructs it.

## Open questions / design (resolve as specified; do not expand scope)

These are decided for this plan — implement exactly as stated; the notes record the rationale and the deferred alternatives:

- **Merge vs replace UX**: Import presents an `NSAlert` with three buttons: **Replace**, **Merge**, **Cancel**. Replace overwrites watchlist/holdings/alerts/baseCurrency from the file. Merge unions the watchlist (append symbols not already present, preserving existing order then appended new ones), overlays holdings by symbol (file wins on key collision), appends only alerts whose `id` is not already present, and adopts the file's `baseCurrency` only on Replace (Merge keeps the current `baseCurrency`). This is implemented as a `MergeStrategy` enum so the pure apply-logic is testable.
- **Conflict handling**: On Merge, holdings collisions resolve file-wins; alert collisions are de-duplicated by `id`. Symbols are uppercased/trimmed on import (reuse the normalization rule from `addSymbol`).
- **CSV second format**: deferred. JSON round-trips all three data types losslessly; CSV would need a per-type schema and lossy holdings/alerts encoding. Noted in Maintenance notes as a future follow-up.
- **schemaVersion**: payload carries `schemaVersion: Int = 1`. On import, if `schemaVersion > 1`, reject with a clear message ("This backup was created by a newer version of TickerBar."). This is the forward-compat guard.

## Steps

### Step 1: Add the user-selected file entitlement

Edit `TickerBar/TickerBar.entitlements`. Inside the top-level `<dict>` (after the `com.apple.security.network.client` entry, before the mach-lookup key), add:

```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

**Verify**: `plutil -lint TickerBar/TickerBar.entitlements` → `TickerBar/TickerBar.entitlements: OK`, and `grep -c "files.user-selected.read-write" TickerBar/TickerBar.entitlements` → `1`.

### Step 2: Add the Codable payload type and pure encode/decode logic to StockService

In `StockService.swift`, add a new top-level (file-scope, NOT nested in `StockService`) struct so it is trivially testable, plus `nonisolated static` encode/decode helpers and a `MergeStrategy` enum on `StockService`.

Add near the bottom of the file (after the `StockServiceError` enum closes the class at `:783`, before the `private extension Double` at `:787`), a file-scope struct:

```swift
/// Versioned, Codable snapshot of all user data for backup/restore.
struct TickerBarBackup: Codable, Equatable {
    var schemaVersion: Int
    var watchlist: [String]
    var holdings: [String: StockService.Holding]
    var priceAlerts: [PriceAlert]
    var baseCurrency: String

    static let currentSchemaVersion = 1
}
```

Then inside `StockService` (e.g. just before the `// MARK: - Errors` section at `:777`), add:

```swift
// MARK: - Backup (Export / Import)

enum MergeStrategy { case replace, merge }

enum BackupError: Error { case unsupportedVersion, decodeFailed }

/// Build the export payload from the current state. Pure-ish read of state;
/// keep encoding itself in `encodeBackup` so it is unit-testable.
func makeBackup() -> TickerBarBackup {
    TickerBarBackup(
        schemaVersion: TickerBarBackup.currentSchemaVersion,
        watchlist: watchlist,
        holdings: holdings,
        priceAlerts: priceAlerts,
        baseCurrency: baseCurrency
    )
}

/// Encode a backup to pretty JSON Data. Pure & testable.
nonisolated static func encodeBackup(_ backup: TickerBarBackup) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(backup)
}

/// Decode + validate a backup from Data. Throws BackupError on bad version or
/// malformed JSON. Pure & testable.
nonisolated static func decodeBackup(from data: Data) throws -> TickerBarBackup {
    let backup: TickerBarBackup
    do {
        backup = try JSONDecoder().decode(TickerBarBackup.self, from: data)
    } catch {
        throw BackupError.decodeFailed
    }
    guard backup.schemaVersion <= TickerBarBackup.currentSchemaVersion else {
        throw BackupError.unsupportedVersion
    }
    return backup
}

/// Compute the merged result of an existing snapshot with an imported backup.
/// Pure & testable — does not mutate the service.
nonisolated static func applyBackup(
    _ backup: TickerBarBackup,
    to existing: TickerBarBackup,
    strategy: MergeStrategy
) -> TickerBarBackup {
    switch strategy {
    case .replace:
        let cleaned = backup.watchlist
            .map { $0.uppercased().trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var seen = Set<String>(); let dedup = cleaned.filter { seen.insert($0).inserted }
        return TickerBarBackup(
            schemaVersion: TickerBarBackup.currentSchemaVersion,
            watchlist: dedup,
            holdings: backup.holdings,
            priceAlerts: backup.priceAlerts,
            baseCurrency: backup.baseCurrency
        )
    case .merge:
        var mergedWatchlist = existing.watchlist
        for raw in backup.watchlist {
            let sym = raw.uppercased().trimmingCharacters(in: .whitespaces)
            guard !sym.isEmpty, !mergedWatchlist.contains(sym) else { continue }
            mergedWatchlist.append(sym)
        }
        var mergedHoldings = existing.holdings
        for (k, v) in backup.holdings { mergedHoldings[k] = v }  // file wins
        let existingIDs = Set(existing.priceAlerts.map(\.id))
        let mergedAlerts = existing.priceAlerts
            + backup.priceAlerts.filter { !existingIDs.contains($0.id) }
        return TickerBarBackup(
            schemaVersion: TickerBarBackup.currentSchemaVersion,
            watchlist: mergedWatchlist,
            holdings: mergedHoldings,
            priceAlerts: mergedAlerts,
            baseCurrency: existing.baseCurrency  // merge keeps current currency
        )
    }
}

/// Apply a decoded+merged backup to the live service state. The `didSet`
/// observers persist each property to UserDefaults automatically.
func importBackup(_ backup: TickerBarBackup, strategy: MergeStrategy) {
    let merged = Self.applyBackup(backup, to: makeBackup(), strategy: strategy)
    watchlist = merged.watchlist
    holdings = merged.holdings
    priceAlerts = merged.priceAlerts
    baseCurrency = merged.baseCurrency
}
```

Note `PriceAlert.id` is a `let UUID` with no public initializer that sets it, and `armed` is decoded from the file as-is — that is correct; do not reset it.

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`.

### Step 3: Add Export and Import buttons to SettingsView

In `SettingsView.swift`, add a new section. Insert a `Divider()` and a `HStack` with two buttons after the "Base currency" block (after `SettingsView.swift:102`, before the "Launch at login" block at `:104`). Use `NSSavePanel` for export and `NSOpenPanel` for import, presented from the key window. Add a `@State private var importError: String?` to surface failures inline (mirroring `WatchlistView`'s `addError` text style).

Target shape:

```swift
Divider()

HStack {
    Text("Backup")
    Spacer()
    Button("Export...") { exportBackup() }
    Button("Import...") { importBackup() }
}

if let importError {
    Text(importError)
        .font(.caption2)
        .foregroundStyle(.red)
}
```

Add `import AppKit` at the top (the file currently imports only `SwiftUI` and `ServiceManagement`). Then add these private methods to `SettingsView`:

```swift
private func exportBackup() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "TickerBar-Backup.json"
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
        let data = try StockService.encodeBackup(service.makeBackup())
        try data.write(to: url)
    } catch {
        importError = "Export failed"
    }
}

private func importBackup() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return }

    let data: Data
    let backup: TickerBarBackup
    do {
        data = try Data(contentsOf: url)
        backup = try StockService.decodeBackup(from: data)
    } catch StockService.BackupError.unsupportedVersion {
        importError = "This backup was created by a newer version of TickerBar."
        return
    } catch {
        importError = "Couldn't read that file — it isn't a valid TickerBar backup."
        return
    }

    let alert = NSAlert()
    alert.messageText = "Import Backup"
    alert.informativeText = "Replace your current data, or merge the backup into it?"
    alert.addButton(withTitle: "Replace")
    alert.addButton(withTitle: "Merge")
    alert.addButton(withTitle: "Cancel")
    let response = alert.runModal()

    let strategy: StockService.MergeStrategy
    switch response {
    case .alertFirstButtonReturn: strategy = .replace
    case .alertSecondButtonReturn: strategy = .merge
    default: return  // Cancel
    }

    importError = nil
    service.importBackup(backup, strategy: strategy)
    Task { await service.fetchAllQuotes() }
}
```

`UTType.json` requires `import UniformTypeIdentifiers` — add that import too (AppKit alone does not expose `.json`).

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`.

### Step 4: Add round-trip and malformed-import tests

In `TickerBarTests/StockServiceTests.swift`, add a new `// MARK:` section with tests. Use the existing `@MainActor` class. Construct a known `TickerBarBackup`, encode it, decode it, and assert equality (all four data fields). Add a malformed-JSON case asserting `decodeBackup` throws, and a future-version case asserting it throws `unsupportedVersion`. Add merge/replace apply tests against the pure `applyBackup`.

```swift
// MARK: - Backup (export / import)

func testBackupRoundTrip() throws {
    let backup = TickerBarBackup(
        schemaVersion: TickerBarBackup.currentSchemaVersion,
        watchlist: ["AAPL", "GOOGL"],
        holdings: ["AAPL": StockService.Holding(shares: 10, costBasis: 150)],
        priceAlerts: [PriceAlert(symbol: "AAPL", targetPrice: 200, isAbove: true)],
        baseCurrency: "GBP"
    )
    let data = try StockService.encodeBackup(backup)
    let decoded = try StockService.decodeBackup(from: data)
    XCTAssertEqual(decoded, backup)
}

func testDecodeBackupRejectsMalformedJSON() {
    let junk = "not json at all".data(using: .utf8)!
    XCTAssertThrowsError(try StockService.decodeBackup(from: junk)) { error in
        XCTAssertEqual(error as? StockService.BackupError, .decodeFailed)
    }
}

func testDecodeBackupRejectsNewerSchemaVersion() throws {
    let future = TickerBarBackup(
        schemaVersion: TickerBarBackup.currentSchemaVersion + 1,
        watchlist: [], holdings: [:], priceAlerts: [], baseCurrency: "USD"
    )
    let data = try StockService.encodeBackup(future)
    XCTAssertThrowsError(try StockService.decodeBackup(from: data)) { error in
        XCTAssertEqual(error as? StockService.BackupError, .unsupportedVersion)
    }
}

func testApplyBackupReplaceOverwrites() {
    let existing = TickerBarBackup(schemaVersion: 1, watchlist: ["TSLA"], holdings: [:], priceAlerts: [], baseCurrency: "USD")
    let incoming = TickerBarBackup(schemaVersion: 1, watchlist: ["aapl", " msft "], holdings: ["AAPL": .init(shares: 1, costBasis: 1)], priceAlerts: [], baseCurrency: "EUR")
    let result = StockService.applyBackup(incoming, to: existing, strategy: .replace)
    XCTAssertEqual(result.watchlist, ["AAPL", "MSFT"])  // uppercased + trimmed
    XCTAssertEqual(result.baseCurrency, "EUR")
    XCTAssertEqual(result.holdings["AAPL"]?.shares, 1)
}

func testApplyBackupMergeUnionsAndKeepsCurrency() {
    let existing = TickerBarBackup(schemaVersion: 1, watchlist: ["AAPL"], holdings: ["AAPL": .init(shares: 5, costBasis: 100)], priceAlerts: [], baseCurrency: "USD")
    let incoming = TickerBarBackup(schemaVersion: 1, watchlist: ["AAPL", "GOOGL"], holdings: ["AAPL": .init(shares: 9, costBasis: 100)], priceAlerts: [], baseCurrency: "EUR")
    let result = StockService.applyBackup(incoming, to: existing, strategy: .merge)
    XCTAssertEqual(result.watchlist, ["AAPL", "GOOGL"])      // union, no dupes
    XCTAssertEqual(result.holdings["AAPL"]?.shares, 9)        // file wins on collision
    XCTAssertEqual(result.baseCurrency, "USD")               // merge keeps current
}
```

**Verify**: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **` and the run includes `testBackupRoundTrip`, `testDecodeBackupRejectsMalformedJSON`, `testDecodeBackupRejectsNewerSchemaVersion`, `testApplyBackupReplaceOverwrites`, `testApplyBackupMergeUnionsAndKeepsCurrency`.

### Step 5: Final full build + test

**Verify**:
- `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` → `** BUILD SUCCEEDED **`
- `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`
- `git status --porcelain` → only the four in-scope files appear as modified.

## Test plan

- New tests in `TickerBarTests/StockServiceTests.swift`, modeled structurally on the existing `testParseYahooResponse` (build `Data`, decode, assert) and the `mergedStocks` pure-function tests:
  - `testBackupRoundTrip` — happy path: encode a known `{watchlist, holdings, priceAlerts, baseCurrency}` and decode back to an equal value.
  - `testDecodeBackupRejectsMalformedJSON` — malformed import rejected gracefully (throws `.decodeFailed`, no crash).
  - `testDecodeBackupRejectsNewerSchemaVersion` — forward-compat guard throws `.unsupportedVersion`.
  - `testApplyBackupReplaceOverwrites` — replace strategy overwrites and normalizes symbols.
  - `testApplyBackupMergeUnionsAndKeepsCurrency` — merge unions watchlist, file-wins on holdings, keeps current currency.
- Verification: `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`, including the 5 new tests above plus all pre-existing tests still passing.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release build` prints `** BUILD SUCCEEDED **`
- [ ] `xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -destination 'platform=macOS' test` prints `** TEST SUCCEEDED **`
- [ ] `grep -c "files.user-selected.read-write" TickerBar/TickerBar.entitlements` returns `1`
- [ ] `grep -q "func makeBackup" TickerBar/Services/StockService.swift && grep -q "nonisolated static func decodeBackup" TickerBar/Services/StockService.swift && grep -q "nonisolated static func applyBackup" TickerBar/Services/StockService.swift` exits 0
- [ ] `grep -q "func exportBackup" TickerBar/Views/SettingsView.swift && grep -q "func importBackup" TickerBar/Views/SettingsView.swift` exits 0
- [ ] `grep -c "testBackupRoundTrip\|testDecodeBackupRejectsMalformedJSON" TickerBarTests/StockServiceTests.swift` returns `2`
- [ ] `git status --porcelain` lists only the four in-scope files (plus `plans/README.md`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The drift check shows any in-scope file changed since `c0c912e` and the "Current state" excerpts no longer match the live code.
- `StockService.Holding` is no longer a nested type or no longer `Codable`, or `StockItem`/`PriceAlert` lost `Codable`/`Equatable` conformance — the payload type depends on all three.
- The build fails because `UTType.json` / `NSSavePanel` / `NSOpenPanel` are unavailable — this would mean the imports (`AppKit`, `UniformTypeIdentifiers`) or the macOS 14 target assumption is wrong; report rather than guessing replacement APIs.
- Any verification command fails twice after a reasonable fix attempt.
- Completing the task appears to require editing a file outside the in-scope list (e.g. modifying `StockItem.swift` to make encoding compile).

## Maintenance notes

For the human/agent who owns this code after this lands:

- **Schema evolution**: when any exported field changes shape, bump `TickerBarBackup.currentSchemaVersion` and add migration handling in `decodeBackup` (currently it only rejects `schemaVersion > current`). Older files (`schemaVersion < current`) must keep decoding.
- **Reviewer should scrutinize**: (1) the merge semantics in `applyBackup` — especially that `baseCurrency` is intentionally NOT taken from the file on Merge; (2) that the `didSet` persistence still fires on each property assignment in `importBackup` (it does — they are stored properties); (3) the entitlement addition is the minimal one and the app still passes sandbox validation.
- **Deferred follow-ups** (intentionally out of this plan): CSV export for holdings (lossy, needs its own schema); auto-backup on a schedule or iCloud sync; per-section selective import (e.g. alerts only); an export confirmation toast. Capture these as separate plans if desired.
- **Interaction risk**: if the `StockService` god-object is later split (see observation about it being 791 lines), the backup methods must move with `watchlist`/`holdings`/`priceAlerts`/`baseCurrency` and stay co-located with their `didSet` persistence.
