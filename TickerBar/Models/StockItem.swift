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
    var preMarketPrice: Double? = nil
    var preMarketChange: Double? = nil
    var marketState: String? = nil  // PRE, REGULAR, POST, CLOSED
    var fiftyTwoWeekHigh: Double? = nil
    var fiftyTwoWeekLow: Double? = nil

    var id: String { symbol }

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
    var display52WeekHigh: Double? { fiftyTwoWeekHigh.map { $0 / subUnitScale } }
    var display52WeekLow: Double? { fiftyTwoWeekLow.map { $0 / subUnitScale } }

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
