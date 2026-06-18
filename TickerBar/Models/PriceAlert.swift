import Foundation

enum AlertKind: String, Codable {
    case absolutePrice   // target is an absolute price
    case percentChange   // target is a % change from the previous close
}

struct PriceAlert: Identifiable, Codable, Equatable {
    let id: UUID
    let symbol: String
    let targetPrice: Double   // absolute price, or percent threshold when kind == .percentChange
    let isAbove: Bool         // true = trigger at/above target, false = at/below
    var kind: AlertKind
    var repeating: Bool       // if true, re-arms after firing instead of being removed
    var armed: Bool           // false on creation, set true after first check to avoid immediate trigger

    init(symbol: String, targetPrice: Double, isAbove: Bool, kind: AlertKind = .absolutePrice, repeating: Bool = false) {
        self.id = UUID()
        self.symbol = symbol
        self.targetPrice = targetPrice
        self.isAbove = isAbove
        self.kind = kind
        self.repeating = repeating
        self.armed = false
    }

    enum CodingKeys: String, CodingKey { case id, symbol, targetPrice, isAbove, kind, repeating, armed }

    // Custom decode so v1 alerts (no kind/repeating keys) still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        symbol = try c.decode(String.self, forKey: .symbol)
        targetPrice = try c.decode(Double.self, forKey: .targetPrice)
        isAbove = try c.decode(Bool.self, forKey: .isAbove)
        kind = try c.decodeIfPresent(AlertKind.self, forKey: .kind) ?? .absolutePrice
        repeating = try c.decodeIfPresent(Bool.self, forKey: .repeating) ?? false
        armed = try c.decodeIfPresent(Bool.self, forKey: .armed) ?? false
    }

    var directionLabel: String {
        isAbove ? "above" : "below"
    }

    /// Whether the alert's condition is currently met (regardless of arming).
    func conditionMet(currentPrice: Double, changePercent: Double) -> Bool {
        let value = kind == .percentChange ? changePercent : currentPrice
        return isAbove ? value >= targetPrice : value <= targetPrice
    }

    func isTriggered(currentPrice: Double, changePercent: Double) -> Bool {
        armed && conditionMet(currentPrice: currentPrice, changePercent: changePercent)
    }
}
