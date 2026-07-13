import Foundation

/// Single source of truth for exchange sub-unit currencies. Some venues quote
/// prices in 1/100 of the major unit: GBp/GBX = British pence, ILA = Israeli
/// agorot. Centralised here so the scaling and FX-normalisation rules can't
/// drift between `StockItem` display values and `StockService` portfolio math.
enum CurrencyUnit {
    /// True when prices for this currency code are quoted in sub-units (×1/100).
    static func isSubUnit(_ currency: String?) -> Bool {
        let c = currency ?? ""
        return c == "GBp" || c.uppercased() == "GBX" || c == "ILA"
    }

    /// Divisor converting a sub-unit price to its major unit (100 for sub-units, else 1).
    static func subUnitDivisor(_ currency: String?) -> Double {
        isSubUnit(currency) ? 100.0 : 1.0
    }

    /// Major-unit ISO code for a quote currency (GBp/GBX -> GBP, ILA -> ILS).
    /// nil defaults to USD; anything else is upper-cased.
    static func majorUnitCode(_ currency: String?) -> String {
        let raw = currency ?? "USD"
        if raw == "GBp" || raw.uppercased() == "GBX" { return "GBP" }
        if raw == "ILA" { return "ILS" }
        return raw.uppercased()
    }
}

/// Pure portfolio math, extracted from `StockService` so value/cost/gain are
/// unit-testable without the @MainActor service, networking, or UserDefaults.
/// All functions take the data they need explicitly and have no side effects.
enum PortfolioCalculator {
    /// FX rate from a stock's currency to `baseCurrency`; nil when a required
    /// non-base rate is missing (caller should exclude the holding rather than
    /// value it at parity).
    static func rate(for stock: StockItem, baseCurrency: String, rates: [String: Double]) -> Double? {
        let cur = CurrencyUnit.majorUnitCode(stock.currency)
        if cur == baseCurrency { return 1.0 }
        return rates[cur]
    }

    struct Position: Equatable, Identifiable {
        let stock: StockItem
        let shares: Double
        let value: Double?
        let gain: Double?
        let gainPercent: Double?

        var id: String { stock.symbol }
    }

    static func positions(stocks: [StockItem], holdings: [String: [StockService.Holding]],
                          baseCurrency: String, rates: [String: Double]) -> [Position] {
        stocks.compactMap { stock in
            let lots = holdings[stock.symbol] ?? []
            guard !lots.isEmpty else { return nil }

            var shares = 0.0
            var cost = 0.0
            var costedValue = 0.0
            var hasCostBasis = false
            for lot in lots {
                shares += lot.shares
                if let lotCost = lot.costBasis {
                    hasCostBasis = true
                    cost += lotCost * lot.shares
                    costedValue += stock.displayPrice * lot.shares
                }
            }

            guard let rate = rate(for: stock, baseCurrency: baseCurrency, rates: rates) else {
                return Position(stock: stock, shares: shares, value: nil, gain: nil, gainPercent: nil)
            }

            let convertedCost = cost * rate
            let gain = hasCostBasis ? (costedValue - cost) * rate : nil
            let gainPercent = convertedCost > 0 ? gain.map { ($0 / convertedCost) * 100 } : nil
            return Position(
                stock: stock,
                shares: shares,
                value: stock.displayPrice * shares * rate,
                gain: gain,
                gainPercent: gainPercent
            )
        }
    }

    static func totalValue(stocks: [StockItem], holdings: [String: [StockService.Holding]],
                           baseCurrency: String, rates: [String: Double]) -> Double {
        stocks.reduce(0) { total, stock in
            guard let r = rate(for: stock, baseCurrency: baseCurrency, rates: rates) else { return total }
            return total + (holdings[stock.symbol] ?? []).reduce(0) { $0 + stock.displayPrice * $1.shares * r }
        }
    }

    static func totalCost(stocks: [StockItem], holdings: [String: [StockService.Holding]],
                          baseCurrency: String, rates: [String: Double]) -> Double {
        stocks.reduce(0) { total, stock in
            guard let r = rate(for: stock, baseCurrency: baseCurrency, rates: rates) else { return total }
            return total + (holdings[stock.symbol] ?? []).reduce(0) { acc, lot in
                guard let cost = lot.costBasis else { return acc }
                return acc + cost * lot.shares * r
            }
        }
    }

    /// Current value of only the cost-bearing lots — the basis for gain so a
    /// mixed RSU + purchase portfolio compares like with like.
    static func costBasisValue(stocks: [StockItem], holdings: [String: [StockService.Holding]],
                               baseCurrency: String, rates: [String: Double]) -> Double {
        stocks.reduce(0) { total, stock in
            guard let r = rate(for: stock, baseCurrency: baseCurrency, rates: rates) else { return total }
            return total + (holdings[stock.symbol] ?? []).reduce(0) { acc, lot in
                lot.costBasis == nil ? acc : acc + stock.displayPrice * lot.shares * r
            }
        }
    }

    static func gain(stocks: [StockItem], holdings: [String: [StockService.Holding]],
                     baseCurrency: String, rates: [String: Double]) -> Double {
        costBasisValue(stocks: stocks, holdings: holdings, baseCurrency: baseCurrency, rates: rates)
            - totalCost(stocks: stocks, holdings: holdings, baseCurrency: baseCurrency, rates: rates)
    }

    static func hasCostBasis(holdings: [String: [StockService.Holding]]) -> Bool {
        holdings.values.contains { lots in lots.contains { $0.costBasis != nil } }
    }

    static func hasUnconverted(stocks: [StockItem], holdings: [String: [StockService.Holding]],
                               baseCurrency: String, rates: [String: Double]) -> Bool {
        stocks.contains { !(holdings[$0.symbol] ?? []).isEmpty && rate(for: $0, baseCurrency: baseCurrency, rates: rates) == nil }
    }
}

struct StockItem: Identifiable, Codable, Equatable {
    let symbol: String
    let name: String
    let price: Double
    let previousClose: Double
    var exchangeTimezoneName: String? = nil
    var currency: String? = nil
    var intradayPrices: [Double] = []
    var dayHigh: Double? = nil
    var dayLow: Double? = nil
    var postMarketPrice: Double? = nil
    var postMarketChange: Double? = nil
    var postMarketChangePercent: Double? = nil
    var preMarketPrice: Double? = nil
    var preMarketChange: Double? = nil
    var preMarketChangePercent: Double? = nil
    var extendedMarketPrice: Double? = nil
    var extendedMarketChange: Double? = nil
    var extendedMarketChangePercent: Double? = nil
    var marketState: String? = nil  // PREPRE, PRE, REGULAR, POST, POSTPOST, CLOSED
    var fiftyTwoWeekHigh: Double? = nil
    var fiftyTwoWeekLow: Double? = nil

    var id: String { symbol }

    struct DisplayQuote: Equatable {
        enum Session: Equatable {
            case regular
            case preMarket
            case postMarket
            case overnight
        }

        let price: Double
        let change: Double
        let changePercent: Double
        let session: Session

        var isPositive: Bool { change >= 0 }
    }

    var hasExtendedTradingSession: Bool {
        switch marketState {
        case "PRE", "PREPRE", "POST", "POSTPOST": true
        default: false
        }
    }

    // MARK: - Sub-unit currency handling (GBX = pence, ILA = agorot)

    /// Whether the API price is in sub-units (pence, agorot, etc.)
    var isSubUnit: Bool {
        CurrencyUnit.isSubUnit(currency)
    }

    /// Divisor to convert sub-units to major currency units
    private var subUnitScale: Double {
        CurrencyUnit.subUnitDivisor(currency)
    }

    // MARK: - Display values (converted to major currency units)

    var displayPrice: Double { price / subUnitScale }
    var displayPreviousClose: Double { previousClose / subUnitScale }
    var displayChange: Double { change / subUnitScale }
    var displayDayHigh: Double? { dayHigh.map { $0 / subUnitScale } }
    var displayDayLow: Double? { dayLow.map { $0 / subUnitScale } }
    var displayPostMarketPrice: Double? { postMarketPrice.map { $0 / subUnitScale } }
    var displayPostMarketChange: Double? { postMarketChange.map { $0 / subUnitScale } }
    var displayPreMarketPrice: Double? { preMarketPrice.map { $0 / subUnitScale } }
    var displayPreMarketChange: Double? { preMarketChange.map { $0 / subUnitScale } }
    var displayExtendedMarketPrice: Double? { extendedMarketPrice.map { $0 / subUnitScale } }
    var display52WeekHigh: Double? { fiftyTwoWeekHigh.map { $0 / subUnitScale } }
    var display52WeekLow: Double? { fiftyTwoWeekLow.map { $0 / subUnitScale } }

    func displayQuote(includeExtendedHours: Bool) -> DisplayQuote {
        let regular = DisplayQuote(
            price: displayPrice,
            change: displayChange,
            changePercent: changePercent,
            session: .regular
        )
        guard includeExtendedHours else { return regular }

        let extended: (price: Double?, change: Double?, percent: Double?, session: DisplayQuote.Session)
        switch marketState {
        case "PRE":
            extended = (
                preMarketPrice ?? extendedMarketPrice,
                preMarketChange ?? extendedMarketChange,
                preMarketChangePercent ?? extendedMarketChangePercent,
                .preMarket
            )
        case "POST":
            extended = (
                postMarketPrice ?? extendedMarketPrice,
                postMarketChange ?? extendedMarketChange,
                postMarketChangePercent ?? extendedMarketChangePercent,
                .postMarket
            )
        case "PREPRE", "POSTPOST":
            extended = (
                extendedMarketPrice,
                extendedMarketChange,
                extendedMarketChangePercent,
                .overnight
            )
        default:
            return regular
        }

        guard let rawPrice = extended.price else { return regular }
        let rawChange = extended.change ?? rawPrice - price
        let percent = extended.percent ?? (price == 0 ? 0 : rawChange / price * 100)
        return DisplayQuote(
            price: rawPrice / subUnitScale,
            change: rawChange / subUnitScale,
            changePercent: percent,
            session: extended.session
        )
    }

    // MARK: - Computed

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

    var currencySymbol: String {
        switch currency?.uppercased() {
        case "GBP", "GBX": return "£"
        case "EUR": return "€"
        case "JPY": return "¥"
        case "CNY", "CNH": return "¥"
        case "HKD": return "HK$"
        case "CHF": return "CHF "
        case "CAD": return "C$"
        case "AUD": return "A$"
        case "INR": return "₹"
        case "KRW": return "₩"
        case "ILA", "ILS": return "₪"
        default: return "$"
        }
    }

    var menuBarText: String {
        let arrow = isPositive ? "▲" : "▼"
        let pctFormatted = String(format: "%.1f%%", abs(changePercent))
        return "\(symbol) \(currencySymbol)\(String(format: "%.2f", displayPrice)) \(arrow)\(pctFormatted)"
    }
}
