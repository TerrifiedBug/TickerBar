# Stock Ticker Menu Bar App Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS menu bar app that shows live stock prices rotating in the menu bar, with a dropdown watchlist, configurable settings, and Yahoo Finance data.

**Architecture:** Pure SwiftUI app using `MenuBarExtra`, `@Observable` model, async/await networking. No external dependencies. Yahoo Finance v8 chart API (one request per symbol). XcodeGen for project generation.

**Tech Stack:** Swift 6.2, SwiftUI, macOS 14+ deployment target, XcodeGen, XCTest

---

### Task 1: Project Scaffolding + XcodeGen Setup

**Files:**
- Create: `project.yml`
- Create: `StockTicker/StockTickerApp.swift`
- Create: `StockTicker/Info.plist`
- Create: `StockTicker/StockTicker.entitlements`
- Create: `StockTicker/Assets.xcassets/Contents.json`
- Create: `StockTicker/Assets.xcassets/AppIcon.appiconset/Contents.json`

**Step 1: Create directory structure**

```bash
mkdir -p StockTicker/Models StockTicker/Services StockTicker/Views
mkdir -p StockTicker/Assets.xcassets/AppIcon.appiconset
mkdir -p StockTickerTests
```

**Step 2: Create `project.yml` (XcodeGen spec)**

```yaml
name: StockTicker
options:
  bundleIdPrefix: com.stockticker
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "16.0"
  generateEmptyDirectories: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
targets:
  StockTicker:
    type: application
    platform: macOS
    sources:
      - StockTicker
    settings:
      base:
        INFOPLIST_FILE: StockTicker/Info.plist
        CODE_SIGN_ENTITLEMENTS: StockTicker/StockTicker.entitlements
        PRODUCT_BUNDLE_IDENTIFIER: com.stockticker.app
        PRODUCT_NAME: StockTicker
        ENABLE_HARDENED_RUNTIME: true
    info:
      path: StockTicker/Info.plist
      properties:
        LSUIElement: true
        CFBundleName: StockTicker
        CFBundleDisplayName: Stock Ticker
        CFBundleIdentifier: com.stockticker.app
        CFBundleVersion: "1"
        CFBundleShortVersionString: "1.0"
        LSMinimumSystemVersion: "14.0"
    entitlements:
      path: StockTicker/StockTicker.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.network.client: true
  StockTickerTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - StockTickerTests
    dependencies:
      - target: StockTicker
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.stockticker.tests
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/StockTicker.app/Contents/MacOS/StockTicker"
        BUNDLE_LOADER: "$(TEST_HOST)"
```

**Step 3: Create minimal `StockTickerApp.swift`**

```swift
import SwiftUI

@main
struct StockTickerApp: App {
    var body: some Scene {
        MenuBarExtra("StockTicker", systemImage: "chart.line.uptrend.xyaxis") {
            Text("Stock Ticker Loading...")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
```

**Step 4: Create `Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleName</key>
    <string>StockTicker</string>
    <key>CFBundleDisplayName</key>
    <string>Stock Ticker</string>
    <key>CFBundleIdentifier</key>
    <string>com.stockticker.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
```

**Step 5: Create entitlements file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

**Step 6: Create Asset Catalog files**

`StockTicker/Assets.xcassets/Contents.json`:
```json
{
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

`StockTicker/Assets.xcassets/AppIcon.appiconset/Contents.json`:
```json
{
  "images": [
    {
      "idiom": "mac",
      "scale": "1x",
      "size": "128x128"
    },
    {
      "idiom": "mac",
      "scale": "2x",
      "size": "128x128"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

**Step 7: Generate Xcode project and verify build**

```bash
cd /Users/danny/VSCode/workspace/macos-stock-ticker
xcodegen generate
xcodebuild -project StockTicker.xcodeproj -scheme StockTicker -configuration Debug build
```

Expected: BUILD SUCCEEDED

**Step 8: Commit**

```bash
git add project.yml StockTicker/ StockTickerTests/ StockTicker.xcodeproj/
git commit -m "Scaffold Xcode project with MenuBarExtra shell"
```

---

### Task 2: StockItem Model + Tests

**Files:**
- Create: `StockTicker/Models/StockItem.swift`
- Create: `StockTickerTests/StockItemTests.swift`

**Step 1: Write StockItem tests**

```swift
import XCTest
@testable import StockTicker

final class StockItemTests: XCTestCase {

    func testInitialization() {
        let stock = StockItem(
            symbol: "AAPL",
            name: "Apple Inc.",
            price: 185.23,
            previousClose: 183.00
        )
        XCTAssertEqual(stock.symbol, "AAPL")
        XCTAssertEqual(stock.name, "Apple Inc.")
        XCTAssertEqual(stock.price, 185.23)
        XCTAssertEqual(stock.previousClose, 183.00)
    }

    func testChangePositive() {
        let stock = StockItem(symbol: "AAPL", name: "Apple", price: 185.23, previousClose: 183.00)
        XCTAssertEqual(stock.change, 2.23, accuracy: 0.01)
    }

    func testChangeNegative() {
        let stock = StockItem(symbol: "AAPL", name: "Apple", price: 180.00, previousClose: 183.00)
        XCTAssertEqual(stock.change, -3.00, accuracy: 0.01)
    }

    func testChangePercent() {
        let stock = StockItem(symbol: "AAPL", name: "Apple", price: 185.23, previousClose: 183.00)
        let expectedPercent = (2.23 / 183.00) * 100
        XCTAssertEqual(stock.changePercent, expectedPercent, accuracy: 0.01)
    }

    func testChangePercentNegative() {
        let stock = StockItem(symbol: "TSLA", name: "Tesla", price: 240.00, previousClose: 250.00)
        let expectedPercent = (-10.0 / 250.0) * 100
        XCTAssertEqual(stock.changePercent, expectedPercent, accuracy: 0.01)
    }

    func testIsPositiveChange() {
        let up = StockItem(symbol: "A", name: "A", price: 10, previousClose: 9)
        let down = StockItem(symbol: "B", name: "B", price: 8, previousClose: 9)
        let flat = StockItem(symbol: "C", name: "C", price: 9, previousClose: 9)
        XCTAssertTrue(up.isPositive)
        XCTAssertFalse(down.isPositive)
        XCTAssertTrue(flat.isPositive) // zero is treated as non-negative
    }

    func testMenuBarText() {
        let stock = StockItem(symbol: "AAPL", name: "Apple", price: 185.23, previousClose: 183.00)
        let text = stock.menuBarText
        XCTAssertTrue(text.contains("AAPL"))
        XCTAssertTrue(text.contains("$185.23"))
        XCTAssertTrue(text.contains("▲"))
    }

    func testMenuBarTextNegative() {
        let stock = StockItem(symbol: "TSLA", name: "Tesla", price: 240.00, previousClose: 250.00)
        let text = stock.menuBarText
        XCTAssertTrue(text.contains("▼"))
    }

    func testZeroPreviousCloseDoesNotCrash() {
        let stock = StockItem(symbol: "X", name: "X", price: 10, previousClose: 0)
        XCTAssertEqual(stock.changePercent, 0.0)
    }
}
```

**Step 2: Run tests -- expect failure**

```bash
xcodegen generate
xcodebuild test -project StockTicker.xcodeproj -scheme StockTickerTests -configuration Debug
```

Expected: FAIL -- `StockItem` not found

**Step 3: Implement StockItem**

```swift
import Foundation

struct StockItem: Identifiable, Codable, Equatable {
    let symbol: String
    let name: String
    let price: Double
    let previousClose: Double

    var id: String { symbol }

    var change: Double {
        price - previousClose
    }

    var changePercent: Double {
        guard previousClose != 0 else { return 0.0 }
        return (change / previousClose) * 100
    }

    var isPositive: Bool {
        change >= 0
    }

    var menuBarText: String {
        let arrow = isPositive ? "▲" : "▼"
        let pctFormatted = String(format: "%.1f%%", abs(changePercent))
        return "\(symbol) $\(String(format: "%.2f", price)) \(arrow)\(pctFormatted)"
    }
}
```

**Step 4: Run tests -- expect pass**

```bash
xcodegen generate
xcodebuild test -project StockTicker.xcodeproj -scheme StockTickerTests -configuration Debug
```

Expected: All tests PASS

**Step 5: Commit**

```bash
git add StockTicker/Models/StockItem.swift StockTickerTests/StockItemTests.swift
git commit -m "Add StockItem model with computed change/percent properties"
```

---

### Task 3: StockService -- Yahoo Finance API + State Management

**Files:**
- Create: `StockTicker/Services/StockService.swift`
- Create: `StockTickerTests/StockServiceTests.swift`

**Step 1: Write StockService tests**

```swift
import XCTest
@testable import StockTicker

final class StockServiceTests: XCTestCase {

    func testDefaultWatchlist() {
        let service = StockService()
        XCTAssertEqual(service.watchlist, ["AAPL", "GOOGL", "MSFT", "AMZN", "TSLA"])
    }

    func testAddSymbol() {
        let service = StockService()
        service.addSymbol("NVDA")
        XCTAssertTrue(service.watchlist.contains("NVDA"))
    }

    func testAddDuplicateSymbolIsIgnored() {
        let service = StockService()
        let before = service.watchlist.count
        service.addSymbol("AAPL")
        XCTAssertEqual(service.watchlist.count, before)
    }

    func testAddSymbolUppercased() {
        let service = StockService()
        service.addSymbol("nvda")
        XCTAssertTrue(service.watchlist.contains("NVDA"))
    }

    func testRemoveSymbol() {
        let service = StockService()
        service.removeSymbol("TSLA")
        XCTAssertFalse(service.watchlist.contains("TSLA"))
    }

    func testCurrentDisplayIndexWraps() {
        let service = StockService()
        service.currentDisplayIndex = 4
        service.advanceDisplay()
        XCTAssertEqual(service.currentDisplayIndex, 0)
    }

    func testIsMarketOpenWeekday() {
        // Create a date on a known weekday during market hours (ET)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 18 // Wednesday
        components.hour = 12
        components.minute = 0
        let date = calendar.date(from: components)!
        XCTAssertTrue(StockService.isMarketOpen(at: date))
    }

    func testIsMarketClosedWeekend() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 21 // Saturday
        components.hour = 12
        components.minute = 0
        let date = calendar.date(from: components)!
        XCTAssertFalse(StockService.isMarketOpen(at: date))
    }

    func testIsMarketClosedAfterHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 18 // Wednesday
        components.hour = 17
        components.minute = 0
        let date = calendar.date(from: components)!
        XCTAssertFalse(StockService.isMarketOpen(at: date))
    }

    func testParseYahooResponse() throws {
        let json = """
        {
            "chart": {
                "result": [{
                    "meta": {
                        "symbol": "AAPL",
                        "longName": "Apple Inc.",
                        "regularMarketPrice": 185.23,
                        "chartPreviousClose": 183.00
                    }
                }]
            }
        }
        """.data(using: .utf8)!

        let stock = try StockService.parseQuoteResponse(data: json)
        XCTAssertEqual(stock.symbol, "AAPL")
        XCTAssertEqual(stock.name, "Apple Inc.")
        XCTAssertEqual(stock.price, 185.23)
        XCTAssertEqual(stock.previousClose, 183.00)
    }

    func testParseYahooResponseMissingFields() {
        let json = """
        {
            "chart": {
                "result": []
            }
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try StockService.parseQuoteResponse(data: json))
    }
}
```

**Step 2: Run tests -- expect failure**

```bash
xcodegen generate
xcodebuild test -project StockTicker.xcodeproj -scheme StockTickerTests -configuration Debug
```

Expected: FAIL -- `StockService` not found

**Step 3: Implement StockService**

```swift
import Foundation
import SwiftUI

@Observable
final class StockService {
    // MARK: - Published State
    var stocks: [StockItem] = []
    var currentDisplayIndex: Int = 0
    var lastUpdated: Date?
    var errorMessage: String?
    var isLoading: Bool = false

    // MARK: - Settings (backed by UserDefaults)
    var watchlist: [String] {
        didSet { UserDefaults.standard.set(watchlist, forKey: "watchlist") }
    }
    var refreshInterval: TimeInterval {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval"); restartRefreshTimer() }
    }
    var rotationEnabled: Bool {
        didSet { UserDefaults.standard.set(rotationEnabled, forKey: "rotationEnabled"); restartRotationTimer() }
    }
    var rotationSpeed: TimeInterval {
        didSet { UserDefaults.standard.set(rotationSpeed, forKey: "rotationSpeed"); restartRotationTimer() }
    }
    var pinnedSymbol: String {
        didSet { UserDefaults.standard.set(pinnedSymbol, forKey: "pinnedSymbol") }
    }
    var marketHoursOnly: Bool {
        didSet { UserDefaults.standard.set(marketHoursOnly, forKey: "marketHoursOnly") }
    }

    // MARK: - Timers
    private var refreshTimer: Timer?
    private var rotationTimer: Timer?

    // MARK: - Constants
    static let defaultWatchlist = ["AAPL", "GOOGL", "MSFT", "AMZN", "TSLA"]

    init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.stringArray(forKey: "watchlist"), !saved.isEmpty {
            self.watchlist = saved
        } else {
            self.watchlist = Self.defaultWatchlist
        }
        self.refreshInterval = defaults.double(forKey: "refreshInterval").nonZero ?? 60
        self.rotationEnabled = defaults.object(forKey: "rotationEnabled") as? Bool ?? true
        self.rotationSpeed = defaults.double(forKey: "rotationSpeed").nonZero ?? 5
        self.pinnedSymbol = defaults.string(forKey: "pinnedSymbol") ?? Self.defaultWatchlist[0]
        self.marketHoursOnly = defaults.object(forKey: "marketHoursOnly") as? Bool ?? true
    }

    // MARK: - Display

    var currentDisplayStock: StockItem? {
        guard !stocks.isEmpty else { return nil }
        if rotationEnabled {
            let index = currentDisplayIndex % stocks.count
            return stocks[index]
        } else {
            return stocks.first { $0.symbol == pinnedSymbol } ?? stocks.first
        }
    }

    var menuBarText: String {
        currentDisplayStock?.menuBarText ?? "Loading..."
    }

    func advanceDisplay() {
        guard !stocks.isEmpty, rotationEnabled else { return }
        currentDisplayIndex = (currentDisplayIndex + 1) % stocks.count
    }

    // MARK: - Market Hours

    static func isMarketOpen(at date: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        guard let et = TimeZone(identifier: "America/New_York") else { return true }
        calendar.timeZone = et

        let weekday = calendar.component(.weekday, from: date)
        // 1 = Sunday, 7 = Saturday
        guard weekday >= 2 && weekday <= 6 else { return false }

        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let minuteOfDay = hour * 60 + minute

        let marketOpen = 9 * 60 + 30  // 9:30 AM
        let marketClose = 16 * 60     // 4:00 PM

        return minuteOfDay >= marketOpen && minuteOfDay < marketClose
    }

    // MARK: - Networking

    func fetchAllQuotes() async {
        if marketHoursOnly && !Self.isMarketOpen() {
            return
        }

        isLoading = true
        errorMessage = nil

        var fetched: [StockItem] = []

        await withTaskGroup(of: StockItem?.self) { group in
            for symbol in watchlist {
                group.addTask {
                    await self.fetchQuote(for: symbol)
                }
            }
            for await result in group {
                if let stock = result {
                    fetched.append(stock)
                }
            }
        }

        // Sort to match watchlist order
        stocks = watchlist.compactMap { symbol in
            fetched.first { $0.symbol == symbol }
        }

        lastUpdated = Date()
        isLoading = false

        if fetched.isEmpty && !watchlist.isEmpty {
            errorMessage = "Unable to fetch quotes"
        }
    }

    private func fetchQuote(for symbol: String) async -> StockItem? {
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1d&range=1d"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try Self.parseQuoteResponse(data: data)
        } catch {
            return nil
        }
    }

    static func parseQuoteResponse(data: Data) throws -> StockItem {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let chart = json?["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let result = results.first,
              let meta = result["meta"] as? [String: Any],
              let symbol = meta["symbol"] as? String,
              let price = meta["regularMarketPrice"] as? Double,
              let previousClose = meta["chartPreviousClose"] as? Double
        else {
            throw StockServiceError.parseError
        }

        let name = meta["longName"] as? String
            ?? meta["shortName"] as? String
            ?? symbol

        return StockItem(symbol: symbol, name: name, price: price, previousClose: previousClose)
    }

    // MARK: - Watchlist Management

    func addSymbol(_ symbol: String) {
        let uppercased = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        guard !uppercased.isEmpty, !watchlist.contains(uppercased) else { return }
        watchlist.append(uppercased)
    }

    func removeSymbol(_ symbol: String) {
        watchlist.removeAll { $0 == symbol }
        stocks.removeAll { $0.symbol == symbol }
    }

    // MARK: - Timer Management

    func startTimers() {
        restartRefreshTimer()
        restartRotationTimer()

        // Initial fetch
        Task { await fetchAllQuotes() }
    }

    func stopTimers() {
        refreshTimer?.invalidate()
        rotationTimer?.invalidate()
        refreshTimer = nil
        rotationTimer = nil
    }

    private func restartRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.fetchAllQuotes() }
        }
    }

    private func restartRotationTimer() {
        rotationTimer?.invalidate()
        guard rotationEnabled else { return }
        rotationTimer = Timer.scheduledTimer(withTimeInterval: rotationSpeed, repeats: true) { [weak self] _ in
            self?.advanceDisplay()
        }
    }

    // MARK: - Errors

    enum StockServiceError: Error {
        case parseError
    }
}

// MARK: - Helpers

private extension Double {
    var nonZero: Double? {
        self == 0 ? nil : self
    }
}
```

**Step 4: Run tests -- expect pass**

```bash
xcodegen generate
xcodebuild test -project StockTicker.xcodeproj -scheme StockTickerTests -configuration Debug
```

Expected: All tests PASS

**Step 5: Commit**

```bash
git add StockTicker/Services/StockService.swift StockTickerTests/StockServiceTests.swift
git commit -m "Add StockService with Yahoo Finance API, timers, and market hours"
```

---

### Task 4: WatchlistView -- Dropdown Popover UI

**Files:**
- Create: `StockTicker/Views/WatchlistView.swift`

**Step 1: Implement WatchlistView**

```swift
import SwiftUI

struct WatchlistView: View {
    @Bindable var service: StockService
    @State private var newSymbol = ""
    @State private var showSettings = false
    @State private var addError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Watchlist")
                    .font(.headline)
                Spacer()
                if service.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(action: {
                    Task { await service.fetchAllQuotes() }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Market status
            if service.marketHoursOnly && !StockService.isMarketOpen() {
                HStack {
                    Image(systemName: "moon.fill")
                        .foregroundStyle(.secondary)
                    Text("Market Closed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }

            // Error
            if let error = service.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            Divider()

            // Stock list
            if service.stocks.isEmpty && !service.isLoading {
                Text("No data yet")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(service.stocks) { stock in
                    StockRowView(stock: stock)
                        .onTapGesture {
                            openYahooFinance(symbol: stock.symbol)
                        }
                        .contextMenu {
                            Button("Remove \(stock.symbol)") {
                                service.removeSymbol(stock.symbol)
                            }
                        }
                }
            }

            Divider()

            // Add stock
            HStack {
                TextField("Add symbol...", text: $newSymbol)
                    .textFieldStyle(.plain)
                    .onSubmit { addSymbol() }
                Button(action: addSymbol) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(newSymbol.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if let addError {
                Text(addError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            Divider()

            // Last updated
            if let lastUpdated = service.lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }

            // Bottom bar
            HStack {
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Inline settings
            if showSettings {
                Divider()
                SettingsView(service: service)
            }
        }
        .frame(width: 300)
    }

    private func addSymbol() {
        let symbol = newSymbol.uppercased().trimmingCharacters(in: .whitespaces)
        guard !symbol.isEmpty else { return }

        if service.watchlist.contains(symbol) {
            addError = "\(symbol) is already in your watchlist"
        } else {
            service.addSymbol(symbol)
            addError = nil
            Task { await service.fetchAllQuotes() }
        }
        newSymbol = ""
    }

    private func openYahooFinance(symbol: String) {
        guard let url = URL(string: "https://finance.yahoo.com/quote/\(symbol)") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct StockRowView: View {
    let stock: StockItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(stock.symbol)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                Text(stock.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("$\(String(format: "%.2f", stock.price))")
                    .font(.system(.body, design: .monospaced))

                HStack(spacing: 2) {
                    Image(systemName: stock.isPositive ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.caption2)
                    Text(String(format: "%.2f (%.1f%%)", abs(stock.change), abs(stock.changePercent)))
                        .font(.caption)
                }
                .foregroundStyle(stock.isPositive ? .green : .red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
```

**Step 2: Build to verify no compile errors**

```bash
xcodegen generate
xcodebuild -project StockTicker.xcodeproj -scheme StockTicker -configuration Debug build
```

Expected: BUILD SUCCEEDED (SettingsView doesn't exist yet -- we'll stub it or create it in the next task)

**Note:** If build fails due to missing `SettingsView`, create an empty stub first:

```swift
// StockTicker/Views/SettingsView.swift (stub)
import SwiftUI

struct SettingsView: View {
    @Bindable var service: StockService
    var body: some View {
        Text("Settings placeholder")
    }
}
```

**Step 3: Commit**

```bash
git add StockTicker/Views/WatchlistView.swift StockTicker/Views/SettingsView.swift
git commit -m "Add WatchlistView with stock rows, add/remove, and market status"
```

---

### Task 5: SettingsView -- Configuration UI

**Files:**
- Modify: `StockTicker/Views/SettingsView.swift`

**Step 1: Implement full SettingsView**

```swift
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var service: StockService
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)
                .padding(.bottom, 4)

            // Refresh interval
            HStack {
                Text("Refresh interval")
                Spacer()
                Picker("", selection: $service.refreshInterval) {
                    Text("30s").tag(30.0)
                    Text("1 min").tag(60.0)
                    Text("5 min").tag(300.0)
                    Text("15 min").tag(900.0)
                }
                .labelsHidden()
                .frame(width: 100)
            }

            // Rotation toggle
            Toggle("Rotate stocks in menu bar", isOn: $service.rotationEnabled)

            // Rotation speed (only when enabled)
            if service.rotationEnabled {
                HStack {
                    Text("Rotation speed")
                    Spacer()
                    Picker("", selection: $service.rotationSpeed) {
                        Text("3s").tag(3.0)
                        Text("5s").tag(5.0)
                        Text("10s").tag(10.0)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

            // Pinned stock (only when rotation disabled)
            if !service.rotationEnabled {
                HStack {
                    Text("Show stock")
                    Spacer()
                    Picker("", selection: $service.pinnedSymbol) {
                        ForEach(service.watchlist, id: \.self) { symbol in
                            Text(symbol).tag(symbol)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

            // Market hours only
            Toggle("Only refresh during market hours", isOn: $service.marketHoursOnly)

            // Launch at login
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = !newValue // revert on failure
                    }
                }
        }
        .padding(12)
    }
}
```

**Step 2: Build to verify**

```bash
xcodegen generate
xcodebuild -project StockTicker.xcodeproj -scheme StockTicker -configuration Debug build
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add StockTicker/Views/SettingsView.swift
git commit -m "Add SettingsView with refresh, rotation, market hours, and login settings"
```

---

### Task 6: Wire Up StockTickerApp -- Connect Everything

**Files:**
- Modify: `StockTicker/StockTickerApp.swift`

**Step 1: Update StockTickerApp to wire all components**

```swift
import SwiftUI

@main
struct StockTickerApp: App {
    @State private var stockService = StockService()

    var body: some Scene {
        MenuBarExtra {
            WatchlistView(service: stockService)
        } label: {
            Text(stockService.menuBarText)
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 300, height: 400)
    }

    init() {
        // Start timers after a brief delay to allow initialization
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [stockService] in
            stockService.startTimers()
        }
    }
}
```

**Step 2: Build and run**

```bash
xcodegen generate
xcodebuild -project StockTicker.xcodeproj -scheme StockTicker -configuration Debug build
```

Expected: BUILD SUCCEEDED

**Step 3: Run the app to verify it works**

```bash
open /Users/danny/VSCode/workspace/macos-stock-ticker/build/Build/Products/Debug/StockTicker.app
```

Or run from Xcode: `open StockTicker.xcodeproj` then Cmd+R.

Expected: Stock ticker icon appears in menu bar, shows "Loading..." then cycles through stock prices. Clicking shows the dropdown with watchlist.

**Step 4: Commit**

```bash
git add StockTicker/StockTickerApp.swift
git commit -m "Wire up StockTickerApp with MenuBarExtra, service, and watchlist view"
```

---

### Task 7: Run All Tests + Final Build Verification

**Step 1: Run full test suite**

```bash
xcodegen generate
xcodebuild test -project StockTicker.xcodeproj -scheme StockTickerTests -configuration Debug 2>&1 | tail -20
```

Expected: All tests PASS

**Step 2: Clean build**

```bash
xcodebuild clean build -project StockTicker.xcodeproj -scheme StockTicker -configuration Debug
```

Expected: BUILD SUCCEEDED

**Step 3: Add .gitignore**

```gitignore
# Xcode
build/
*.xcodeproj/xcuserdata/
*.xcodeproj/project.xcworkspace/xcuserdata/
DerivedData/
*.hmap
*.ipa
*.dSYM.zip
*.dSYM

# macOS
.DS_Store
```

**Step 4: Final commit**

```bash
git add .gitignore
git commit -m "Add gitignore for Xcode artifacts"
```

---

## Summary

| Task | What | Files |
|------|------|-------|
| 1 | Project scaffolding + XcodeGen | project.yml, App shell, Info.plist, entitlements, assets |
| 2 | StockItem model + tests | Models/StockItem.swift, StockItemTests.swift |
| 3 | StockService + tests | Services/StockService.swift, StockServiceTests.swift |
| 4 | WatchlistView + StockRowView | Views/WatchlistView.swift, Views/SettingsView.swift (stub) |
| 5 | SettingsView (full) | Views/SettingsView.swift |
| 6 | Wire up StockTickerApp | StockTickerApp.swift |
| 7 | Final tests + build verification | .gitignore |
