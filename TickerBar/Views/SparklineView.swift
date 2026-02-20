import SwiftUI

struct SparklineView: View {
    let prices: [Double]
    let isPositive: Bool

    var body: some View {
        if prices.count >= 2 {
            GeometryReader { geo in
                let minPrice = prices.min() ?? 0
                let maxPrice = prices.max() ?? 1
                let range = maxPrice - minPrice
                let safeRange = range > 0 ? range : 1

                Path { path in
                    for (index, price) in prices.enumerated() {
                        let x = geo.size.width * CGFloat(index) / CGFloat(prices.count - 1)
                        let y = geo.size.height * (1 - CGFloat((price - minPrice) / safeRange))
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(isPositive ? Color.green : Color.red, lineWidth: 1.2)
            }
        }
    }
}
