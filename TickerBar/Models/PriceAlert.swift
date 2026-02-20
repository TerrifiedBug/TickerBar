import Foundation

struct PriceAlert: Identifiable, Codable, Equatable {
    let id: UUID
    let symbol: String
    let targetPrice: Double
    let isAbove: Bool  // true = alert when price goes above target, false = below
    var armed: Bool  // false on creation, set true after first price check to avoid immediate trigger

    init(symbol: String, targetPrice: Double, isAbove: Bool) {
        self.id = UUID()
        self.symbol = symbol
        self.targetPrice = targetPrice
        self.isAbove = isAbove
        self.armed = false
    }

    var directionLabel: String {
        isAbove ? "above" : "below"
    }

    func isTriggered(currentPrice: Double) -> Bool {
        guard armed else { return false }
        return isAbove ? currentPrice >= targetPrice : currentPrice <= targetPrice
    }
}
