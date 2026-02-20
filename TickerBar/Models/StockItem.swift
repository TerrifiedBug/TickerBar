import Foundation

struct StockItem: Identifiable, Codable, Equatable {
    let symbol: String
    let name: String
    let price: Double
    let previousClose: Double
    var exchangeTimezoneName: String? = nil
    var currency: String? = nil

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

    var currencySymbol: String {
        switch currency?.uppercased() {
        case "GBP", "GBp": return "£"
        case "EUR": return "€"
        case "JPY": return "¥"
        case "CNY", "CNH": return "¥"
        case "HKD": return "HK$"
        case "CHF": return "CHF "
        case "CAD": return "C$"
        case "AUD": return "A$"
        case "INR": return "₹"
        case "KRW": return "₩"
        default: return "$"
        }
    }

    var menuBarText: String {
        let arrow = isPositive ? "▲" : "▼"
        let pctFormatted = String(format: "%.1f%%", abs(changePercent))
        return "\(symbol) \(currencySymbol)\(String(format: "%.2f", price)) \(arrow)\(pctFormatted)"
    }
}
