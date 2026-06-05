import XCTest
@testable import TickerBar

@MainActor
final class StockServiceTests: XCTestCase {

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
        let service = StockService()
        XCTAssertEqual(service.menuBarFontSize, 10)
    }

    func testMenuBarFontSizePersists() {
        let service = StockService()
        service.menuBarFontSize = 13
        XCTAssertEqual(UserDefaults.standard.double(forKey: "menuBarFontSize"), 13)
        XCTAssertEqual(StockService().menuBarFontSize, 13)
    }

    func testSolidPopoverBackgroundDefaultsToFalse() {
        let service = StockService()
        XCTAssertFalse(service.solidPopoverBackground)
    }

    func testSolidPopoverBackgroundPersists() {
        let service = StockService()
        service.solidPopoverBackground = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "solidPopoverBackground"))
        XCTAssertTrue(StockService().solidPopoverBackground)
    }
}
