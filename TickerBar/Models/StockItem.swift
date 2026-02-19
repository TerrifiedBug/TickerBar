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
