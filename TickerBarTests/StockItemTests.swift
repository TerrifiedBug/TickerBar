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

    // MARK: - CurrencyUnit + sub-unit scaling

    func testCurrencyUnitSubUnitDetection() {
        XCTAssertTrue(CurrencyUnit.isSubUnit("GBp"))
        XCTAssertTrue(CurrencyUnit.isSubUnit("GBX"))
        XCTAssertTrue(CurrencyUnit.isSubUnit("gbx"))
        XCTAssertTrue(CurrencyUnit.isSubUnit("ILA"))
        XCTAssertFalse(CurrencyUnit.isSubUnit("GBP"))
        XCTAssertFalse(CurrencyUnit.isSubUnit("USD"))
        XCTAssertFalse(CurrencyUnit.isSubUnit(nil))
    }

    func testCurrencyUnitDivisor() {
        XCTAssertEqual(CurrencyUnit.subUnitDivisor("GBX"), 100)
        XCTAssertEqual(CurrencyUnit.subUnitDivisor("USD"), 1)
        XCTAssertEqual(CurrencyUnit.subUnitDivisor(nil), 1)
    }

    func testCurrencyUnitMajorUnitCode() {
        XCTAssertEqual(CurrencyUnit.majorUnitCode("GBp"), "GBP")
        XCTAssertEqual(CurrencyUnit.majorUnitCode("GBX"), "GBP")
        XCTAssertEqual(CurrencyUnit.majorUnitCode("ILA"), "ILS")
        XCTAssertEqual(CurrencyUnit.majorUnitCode("eur"), "EUR")
        XCTAssertEqual(CurrencyUnit.majorUnitCode(nil), "USD")
    }

    func testSubUnitDisplayPriceScaling() {
        let pence = StockItem(symbol: "VOD.L", name: "Vodafone", price: 250.0, previousClose: 240.0, currency: "GBX")
        XCTAssertEqual(pence.displayPrice, 2.50, accuracy: 0.0001)
        XCTAssertEqual(pence.displayChange, 0.10, accuracy: 0.0001)
        XCTAssertEqual(pence.currencySymbol, "£")
    }

    func testNonSubUnitDisplayPriceUnchanged() {
        let usd = StockItem(symbol: "AAPL", name: "Apple", price: 185.0, previousClose: 183.0, currency: "USD")
        XCTAssertEqual(usd.displayPrice, 185.0, accuracy: 0.0001)
    }

    // MARK: - PortfolioCalculator (pure)

    func testPortfolioCalculatorValueAndGain() {
        let stocks = [StockItem(symbol: "AAPL", name: "Apple", price: 130, previousClose: 130, currency: "USD")]
        let holdings: [String: [StockService.Holding]] = [
            "AAPL": [StockService.Holding(kind: .purchase, shares: 10, costBasis: 100)]
        ]
        XCTAssertEqual(PortfolioCalculator.totalValue(stocks: stocks, holdings: holdings, baseCurrency: "USD", rates: [:]), 1300, accuracy: 0.001)
        XCTAssertEqual(PortfolioCalculator.gain(stocks: stocks, holdings: holdings, baseCurrency: "USD", rates: [:]), 300, accuracy: 0.001)
    }

    func testPortfolioCalculatorExcludesMissingRate() {
        let stocks = [StockItem(symbol: "7203.T", name: "Toyota", price: 3000, previousClose: 3000, currency: "JPY")]
        let holdings: [String: [StockService.Holding]] = [
            "7203.T": [StockService.Holding(kind: .purchase, shares: 10, costBasis: 2000)]
        ]
        XCTAssertEqual(PortfolioCalculator.totalValue(stocks: stocks, holdings: holdings, baseCurrency: "USD", rates: [:]), 0, accuracy: 0.001)
        XCTAssertTrue(PortfolioCalculator.hasUnconverted(stocks: stocks, holdings: holdings, baseCurrency: "USD", rates: [:]))
    }
}
