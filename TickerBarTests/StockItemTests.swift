import XCTest
@testable import TickerBar

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
