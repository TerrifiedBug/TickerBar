import XCTest
@testable import TickerBar

@MainActor
final class StockServiceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        // Isolate persistence to a throwaway suite so tests never touch the
        // real app defaults and run order-independently.
        suiteName = "TickerBarTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultWatchlist() {
        let service = StockService(defaults: defaults)
        XCTAssertEqual(service.watchlist, ["AAPL", "GOOGL", "MSFT", "AMZN", "TSLA"])
    }

    func testAddSymbol() {
        let service = StockService(defaults: defaults)
        service.addSymbol("NVDA")
        XCTAssertTrue(service.watchlist.contains("NVDA"))
    }

    func testAddDuplicateSymbolIsIgnored() {
        let service = StockService(defaults: defaults)
        let before = service.watchlist.count
        service.addSymbol("AAPL")
        XCTAssertEqual(service.watchlist.count, before)
    }

    func testAddSymbolUppercased() {
        let service = StockService(defaults: defaults)
        service.addSymbol("nvda")
        XCTAssertTrue(service.watchlist.contains("NVDA"))
    }

    func testRemoveSymbol() {
        let service = StockService(defaults: defaults)
        service.removeSymbol("TSLA")
        XCTAssertFalse(service.watchlist.contains("TSLA"))
    }

    func testCurrentDisplayIndexWraps() {
        let service = StockService(defaults: defaults)
        // Populate stocks so advanceDisplay doesn't bail
        service.stocks = [
            StockItem(symbol: "A", name: "A", price: 1, previousClose: 1),
            StockItem(symbol: "B", name: "B", price: 2, previousClose: 2),
            StockItem(symbol: "C", name: "C", price: 3, previousClose: 3),
            StockItem(symbol: "D", name: "D", price: 4, previousClose: 4),
            StockItem(symbol: "E", name: "E", price: 5, previousClose: 5),
        ]
        service.currentDisplayIndex = 4
        service.advanceDisplay()
        XCTAssertEqual(service.currentDisplayIndex, 0)
    }

    func testIsMarketOpenWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 18
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
        components.day = 21
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
        components.day = 18
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

    func testParseYahooResponseFallsBackToShortName() throws {
        let json = """
        {
            "chart": {
                "result": [{
                    "meta": {
                        "symbol": "AAPL",
                        "shortName": "Apple Inc",
                        "regularMarketPrice": 185.23,
                        "chartPreviousClose": 183.00
                    }
                }]
            }
        }
        """.data(using: .utf8)!

        let stock = try StockService.parseQuoteResponse(data: json)
        XCTAssertEqual(stock.name, "Apple Inc")
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

    func testParseCrumbResponse() {
        let crumb = "abc123XYZ"
        XCTAssertEqual(crumb.count, 9)
        XCTAssertFalse(crumb.contains("<html>"))
    }

    // MARK: - mergedStocks (last-good preservation)

    func testMergedStocksPrefersFreshFollowsWatchlistOrderAndKeepsLastGood() {
        let prevA = StockItem(symbol: "A", name: "A Inc", price: 10, previousClose: 9)
        let prevB = StockItem(symbol: "B", name: "B Inc", price: 20, previousClose: 19)
        let prevC = StockItem(symbol: "C", name: "C Inc", price: 30, previousClose: 29)
        let freshA = StockItem(symbol: "A", name: "A Inc", price: 11, previousClose: 9)
        let freshC = StockItem(symbol: "C", name: "C Inc", price: 33, previousClose: 29)

        // B is absent from fresh; fresh is deliberately out of watchlist order.
        let merged = StockService.mergedStocks(
            watchlist: ["A", "B", "C"],
            fresh: [freshC, freshA],
            previous: [prevA, prevB, prevC]
        )

        XCTAssertEqual(merged.map(\.symbol), ["A", "B", "C"])  // watchlist order
        XCTAssertEqual(merged[0].price, 11)  // fresh A wins over previous A
        XCTAssertEqual(merged[1].price, 20)  // B kept from previous (last-good)
        XCTAssertEqual(merged[2].price, 33)  // fresh C wins
    }

    func testMergedStocksFallsBackEntirelyToPreviousWhenFreshEmpty() {
        let prevA = StockItem(symbol: "A", name: "A Inc", price: 10, previousClose: 9)
        let prevB = StockItem(symbol: "B", name: "B Inc", price: 20, previousClose: 19)

        let merged = StockService.mergedStocks(
            watchlist: ["A", "B"],
            fresh: [],
            previous: [prevA, prevB]
        )

        XCTAssertEqual(merged.map(\.symbol), ["A", "B"])
        XCTAssertEqual(merged[0].price, 10)
        XCTAssertEqual(merged[1].price, 20)
    }

    func testMergedStocksDropsSymbolMissingFromFreshAndPrevious() {
        let prevA = StockItem(symbol: "A", name: "A Inc", price: 10, previousClose: 9)

        // "Z" appears in neither fresh nor previous and must be omitted.
        let merged = StockService.mergedStocks(
            watchlist: ["A", "Z"],
            fresh: [],
            previous: [prevA]
        )

        XCTAssertEqual(merged.map(\.symbol), ["A"])
    }

    // MARK: - New settings (defaults + persistence)

    func testMenuBarFontSizeDefaultsToTen() {
        let service = StockService(defaults: defaults)
        XCTAssertEqual(service.menuBarFontSize, 10)
    }

    func testMenuBarFontSizePersists() {
        let service = StockService(defaults: defaults)
        service.menuBarFontSize = 13
        XCTAssertEqual(defaults.double(forKey: "menuBarFontSize"), 13)
        XCTAssertEqual(StockService(defaults: defaults).menuBarFontSize, 13)
    }

    func testSolidPopoverBackgroundDefaultsToFalse() {
        let service = StockService(defaults: defaults)
        XCTAssertFalse(service.solidPopoverBackground)
    }

    func testSolidPopoverBackgroundPersists() {
        let service = StockService(defaults: defaults)
        service.solidPopoverBackground = true
        XCTAssertTrue(defaults.bool(forKey: "solidPopoverBackground"))
        XCTAssertTrue(StockService(defaults: defaults).solidPopoverBackground)
    }

    // MARK: - URL building (encoding)

    func testChartURLEscapesPlusInCrumb() {
        // A '+' in a query value must become %2B; servers decode a literal '+'
        // as a space, which corrupts the crumb and breaks auth.
        let url = StockService.chartURL(symbol: "AAPL", crumb: "ab+cd")
        XCTAssertNotNil(url)
        let s = url!.absoluteString
        XCTAssertTrue(s.contains("crumb=ab%2Bcd"), s)
        XCTAssertFalse(s.contains("crumb=ab+cd"), s)
    }

    func testChartURLResolvesCaretIndexSymbol() {
        // "^GSPC" previously made URL(string:) return nil and silently failed.
        let url = StockService.chartURL(symbol: "^GSPC", crumb: "x")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("%5EGSPC"), url!.absoluteString)
    }

    func testQuoteURLEscapesPlusAndKeepsCommaSeparator() {
        let url = StockService.quoteURL(symbols: ["AAPL", "MSFT"], crumb: "a+b")
        XCTAssertNotNil(url)
        let s = url!.absoluteString
        XCTAssertTrue(s.contains("symbols=AAPL,MSFT"), s)
        XCTAssertTrue(s.contains("crumb=a%2Bb"), s)
    }

    func testQuoteURLEscapesEqualsInFXSymbols() {
        let url = StockService.quoteURL(symbols: ["GBPUSD=X"], crumb: "x")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("symbols=GBPUSD%3DX"), url!.absoluteString)
    }

    func testSearchURLEscapesSpaceAndAmpersand() {
        let url = StockService.searchURL(query: "a b&c")
        XCTAssertNotNil(url)
        let s = url!.absoluteString
        XCTAssertTrue(s.contains("q=a%20b%26c"), s)
    }

    // MARK: - Holdings (multi-lot)

    private func stock(_ symbol: String, price: Double, currency: String = "USD") -> StockItem {
        StockItem(symbol: symbol, name: symbol, price: price, previousClose: price, currency: currency)
    }

    func testAddRSULotValueOnlyNoGain() {
        let service = StockService(defaults: defaults)
        service.stocks = [stock("AAPL", price: 100)]
        service.addLot(symbol: "AAPL", kind: .rsu, shares: 10, costBasis: nil)
        XCTAssertEqual(service.totalPortfolioValue, 1000, accuracy: 0.001)
        XCTAssertEqual(service.totalPortfolioGain, 0, accuracy: 0.001)
        XCTAssertFalse(service.hasCostBasis)
    }

    func testRSULotIgnoresAnyCost() {
        let service = StockService(defaults: defaults)
        service.addLot(symbol: "AAPL", kind: .rsu, shares: 10, costBasis: 50)
        XCTAssertNil(service.lots(for: "AAPL").first?.costBasis)
    }

    func testPurchaseLotGain() {
        let service = StockService(defaults: defaults)
        service.stocks = [stock("AAPL", price: 130)]
        service.addLot(symbol: "AAPL", kind: .purchase, shares: 10, costBasis: 100)
        XCTAssertEqual(service.totalPortfolioValue, 1300, accuracy: 0.001)
        XCTAssertEqual(service.totalPortfolioCost, 1000, accuracy: 0.001)
        XCTAssertEqual(service.totalPortfolioGain, 300, accuracy: 0.001)
        XCTAssertTrue(service.hasCostBasis)
    }

    func testMixedRSUAndPurchaseValueIncludesBothGainExcludesRSU() {
        let service = StockService(defaults: defaults)
        service.stocks = [stock("AAPL", price: 100)]
        service.addLot(symbol: "AAPL", kind: .rsu, shares: 50, costBasis: nil)
        service.addLot(symbol: "AAPL", kind: .purchase, shares: 10, costBasis: 80)
        XCTAssertEqual(service.totalPortfolioValue, 6000, accuracy: 0.001)   // (50+10)*100
        XCTAssertEqual(service.totalPortfolioCost, 800, accuracy: 0.001)     // 10*80
        XCTAssertEqual(service.totalPortfolioGain, 200, accuracy: 0.001)     // 10*100 - 800
        XCTAssertTrue(service.hasCostBasis)
    }

    func testMultiplePurchaseLotsCostAveraging() {
        let service = StockService(defaults: defaults)
        service.stocks = [stock("AAPL", price: 150)]
        service.addLot(symbol: "AAPL", kind: .purchase, shares: 50, costBasis: 100)
        service.addLot(symbol: "AAPL", kind: .purchase, shares: 100, costBasis: 130)
        XCTAssertEqual(service.lots(for: "AAPL").count, 2)
        XCTAssertEqual(service.totalPortfolioCost, 50 * 100 + 100 * 130, accuracy: 0.001)  // 18000
        XCTAssertEqual(service.totalPortfolioValue, 150 * 150, accuracy: 0.001)            // 22500
        XCTAssertEqual(service.totalPortfolioGain, 22500 - 18000, accuracy: 0.001)         // 4500
    }

    func testLotCRUDRemovesSymbolKeyWhenEmpty() {
        let service = StockService(defaults: defaults)
        service.addLot(symbol: "AAPL", kind: .purchase, shares: 10, costBasis: 100)
        service.addLot(symbol: "AAPL", kind: .rsu, shares: 5, costBasis: nil)
        XCTAssertEqual(service.lots(for: "AAPL").count, 2)
        service.removeLot(symbol: "AAPL", id: service.lots(for: "AAPL")[0].id)
        XCTAssertEqual(service.lots(for: "AAPL").count, 1)
        service.removeLot(symbol: "AAPL", id: service.lots(for: "AAPL")[0].id)
        XCTAssertTrue(service.lots(for: "AAPL").isEmpty)
        XCTAssertNil(service.holdings["AAPL"])
    }

    func testUpdateLot() {
        let service = StockService(defaults: defaults)
        service.addLot(symbol: "AAPL", kind: .purchase, shares: 10, costBasis: 100)
        let id = service.lots(for: "AAPL")[0].id
        service.updateLot(symbol: "AAPL", id: id, shares: 20, costBasis: 110)
        XCTAssertEqual(service.lots(for: "AAPL")[0].shares, 20)
        XCTAssertEqual(service.lots(for: "AAPL")[0].costBasis, 110)
    }

    func testLegacyHoldingsMigratedToPurchaseLot() {
        // Legacy single-record shape {shares, costBasis} must migrate to one
        // purchase lot, not be dropped.
        let legacy = ["AAPL": ["shares": 10.0, "costBasis": 130.0]]
        let data = try! JSONSerialization.data(withJSONObject: legacy)
        defaults.set(data, forKey: "holdings")
        let service = StockService(defaults: defaults)
        let lots = service.lots(for: "AAPL")
        XCTAssertEqual(lots.count, 1)
        XCTAssertEqual(lots.first?.kind, .purchase)
        XCTAssertEqual(lots.first?.shares, 10)
        XCTAssertEqual(lots.first?.costBasis, 130)
    }

    func testModernHoldingsRoundTrip() {
        let service = StockService(defaults: defaults)
        service.addLot(symbol: "AAPL", kind: .rsu, shares: 50, costBasis: nil)
        service.addLot(symbol: "AAPL", kind: .purchase, shares: 10, costBasis: 80)
        let reloaded = StockService(defaults: defaults)
        let lots = reloaded.lots(for: "AAPL")
        XCTAssertEqual(lots.count, 2)
        XCTAssertEqual(lots.filter { $0.kind == .rsu }.count, 1)
        XCTAssertEqual(lots.filter { $0.kind == .purchase }.first?.costBasis, 80)
    }

    func testHoldingMissingFXRateExcludedFromTotals() {
        let service = StockService(defaults: defaults)   // baseCurrency USD
        service.stocks = [stock("7203.T", price: 3000, currency: "JPY")]
        service.addLot(symbol: "7203.T", kind: .purchase, shares: 10, costBasis: 2000)
        // No exchangeRates["JPY"] -> excluded, NOT valued at parity (the 006 fix).
        XCTAssertEqual(service.totalPortfolioValue, 0, accuracy: 0.001)
        XCTAssertTrue(service.hasUnconvertedHoldings)
        // Provide the rate -> now included.
        service.exchangeRates["JPY"] = 0.0067
        XCTAssertEqual(service.totalPortfolioValue, 3000 * 10 * 0.0067, accuracy: 0.01)
        XCTAssertFalse(service.hasUnconvertedHoldings)
    }

    // MARK: - Market hours (non-US exchanges)

    private func date(tz: String, year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz)!
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
        return cal.date(from: c)!
    }

    func testLondonMarketOpenDuringHours() {
        // 2026-02-18 is a Wednesday. LSE 08:00–16:30.
        let open = date(tz: "Europe/London", year: 2026, month: 2, day: 18, hour: 10)
        XCTAssertTrue(StockService.isMarketOpen(timezoneName: "Europe/London", at: open))
    }

    func testLondonMarketClosedAtCloseBoundary() {
        let atClose = date(tz: "Europe/London", year: 2026, month: 2, day: 18, hour: 16, minute: 30)
        XCTAssertFalse(StockService.isMarketOpen(timezoneName: "Europe/London", at: atClose))
        let justBefore = date(tz: "Europe/London", year: 2026, month: 2, day: 18, hour: 16, minute: 29)
        XCTAssertTrue(StockService.isMarketOpen(timezoneName: "Europe/London", at: justBefore))
    }

    func testLondonMarketClosedOnWeekend() {
        // 2026-02-21 is a Saturday.
        let sat = date(tz: "Europe/London", year: 2026, month: 2, day: 21, hour: 10)
        XCTAssertFalse(StockService.isMarketOpen(timezoneName: "Europe/London", at: sat))
    }

    func testTokyoMarketHours() {
        // TSE 09:00–15:00.
        XCTAssertTrue(StockService.isMarketOpen(timezoneName: "Asia/Tokyo",
            at: date(tz: "Asia/Tokyo", year: 2026, month: 2, day: 18, hour: 10)))
        XCTAssertFalse(StockService.isMarketOpen(timezoneName: "Asia/Tokyo",
            at: date(tz: "Asia/Tokyo", year: 2026, month: 2, day: 18, hour: 15)))
    }

    func testHongKongMarketHours() {
        // HKEX 09:30–16:00.
        XCTAssertTrue(StockService.isMarketOpen(timezoneName: "Asia/Hong_Kong",
            at: date(tz: "Asia/Hong_Kong", year: 2026, month: 2, day: 18, hour: 10)))
        XCTAssertFalse(StockService.isMarketOpen(timezoneName: "Asia/Hong_Kong",
            at: date(tz: "Asia/Hong_Kong", year: 2026, month: 2, day: 18, hour: 9, minute: 0)))
    }

    // MARK: - Price alerts

    func testPriceAlertNotTriggeredUntilArmed() {
        var alert = PriceAlert(symbol: "AAPL", targetPrice: 100, isAbove: true)
        XCTAssertFalse(alert.isTriggered(currentPrice: 150))
        alert.armed = true
        XCTAssertTrue(alert.isTriggered(currentPrice: 150))
    }

    func testPriceAlertAboveBoundaryInclusive() {
        var alert = PriceAlert(symbol: "AAPL", targetPrice: 100, isAbove: true)
        alert.armed = true
        XCTAssertTrue(alert.isTriggered(currentPrice: 100))
        XCTAssertFalse(alert.isTriggered(currentPrice: 99.99))
    }

    func testPriceAlertBelowBoundaryInclusive() {
        var alert = PriceAlert(symbol: "AAPL", targetPrice: 100, isAbove: false)
        alert.armed = true
        XCTAssertTrue(alert.isTriggered(currentPrice: 100))
        XCTAssertTrue(alert.isTriggered(currentPrice: 50))
        XCTAssertFalse(alert.isTriggered(currentPrice: 100.01))
    }

    func testCheckPriceAlertsArmsFirstCycleThenFiresAndRemoves() {
        let service = StockService(defaults: defaults)
        service.stocks = [stock("AAPL", price: 150)]
        service.priceAlerts = [PriceAlert(symbol: "AAPL", targetPrice: 100, isAbove: true)]
        // First cycle arms only (skips the creation cycle).
        service.checkPriceAlerts()
        XCTAssertEqual(service.priceAlerts.count, 1)
        XCTAssertTrue(service.priceAlerts[0].armed)
        // Second cycle: 150 >= 100 -> fires and removes.
        service.checkPriceAlerts()
        XCTAssertTrue(service.priceAlerts.isEmpty)
    }

    func testCheckPriceAlertsDoesNotFireWhenNotCrossed() {
        let service = StockService(defaults: defaults)
        service.stocks = [stock("AAPL", price: 90)]
        service.priceAlerts = [PriceAlert(symbol: "AAPL", targetPrice: 100, isAbove: true)]
        service.checkPriceAlerts()  // arm
        service.checkPriceAlerts()  // 90 < 100 -> no fire
        XCTAssertEqual(service.priceAlerts.count, 1)
    }

    // MARK: - Market hours (lunch breaks + marketState preference)

    func testTokyoLunchBreakClosed() {
        let lunch = date(tz: "Asia/Tokyo", year: 2026, month: 2, day: 18, hour: 12)
        XCTAssertFalse(StockService.isMarketOpen(timezoneName: "Asia/Tokyo", at: lunch))
        let afterLunch = date(tz: "Asia/Tokyo", year: 2026, month: 2, day: 18, hour: 13)
        XCTAssertTrue(StockService.isMarketOpen(timezoneName: "Asia/Tokyo", at: afterLunch))
    }

    func testHongKongLunchBreakClosed() {
        let lunch = date(tz: "Asia/Hong_Kong", year: 2026, month: 2, day: 18, hour: 12, minute: 30)
        XCTAssertFalse(StockService.isMarketOpen(timezoneName: "Asia/Hong_Kong", at: lunch))
    }

    func testIsOpenPrefersMarketStateOverClock() {
        var s = stock("AAPL", price: 100)
        s.marketState = "CLOSED"
        XCTAssertFalse(StockService.isOpen(s))
        s.marketState = "REGULAR"
        XCTAssertTrue(StockService.isOpen(s))
    }

    func testIsOpenFallsBackToClockWhenNoMarketState() {
        var s = stock("VOD.L", price: 100, currency: "GBP")
        s.exchangeTimezoneName = "Europe/London"
        s.marketState = nil
        XCTAssertTrue(StockService.isOpen(s, at: date(tz: "Europe/London", year: 2026, month: 2, day: 18, hour: 10)))
        XCTAssertFalse(StockService.isOpen(s, at: date(tz: "Europe/London", year: 2026, month: 2, day: 18, hour: 20)))
    }

    func testAdvanceDisplaySkipsClosedMarkets() {
        let service = StockService(defaults: defaults)
        var a = stock("A", price: 1); a.marketState = "CLOSED"
        var b = stock("B", price: 2); b.marketState = "REGULAR"
        var c = stock("C", price: 3); c.marketState = "CLOSED"
        service.stocks = [a, b, c]
        service.currentDisplayIndex = 0   // at A (closed)
        service.advanceDisplay()          // should skip to B (the only open one)
        XCTAssertEqual(service.currentDisplayIndex, 1)
    }
}
