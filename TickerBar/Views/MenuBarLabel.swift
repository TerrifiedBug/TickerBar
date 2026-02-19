import SwiftUI

struct MenuBarLabel: View {
    let service: StockService

    var body: some View {
        if let stock = service.currentDisplayStock {
            if service.compactMenuBar {
                compactText(stock)
            } else {
                normalText(stock)
            }
        } else {
            Text("⏳")
        }
    }

    // Compact: "AAPL 150.00 ▲1.5%"
    private func compactText(_ stock: StockItem) -> Text {
        let arrow = stock.isPositive ? "▲" : "▼"
        let color: Color = stock.isPositive ? .green : .red

        var result = Text(stock.symbol).font(.system(size: 10, weight: .medium))
            + Text(" ")
            + Text(String(format: "%.2f", stock.price)).font(.system(size: 10, design: .monospaced))
            + Text(" ") + Text(arrow).font(.system(size: 7)).foregroundColor(color)

        if service.showPercentChange {
            result = result + Text(String(format: "%.1f%%", abs(stock.changePercent)))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(color)
        }

        return result
    }

    // Normal: "AAPL  $150.00  ▲ 1.5%"
    private func normalText(_ stock: StockItem) -> Text {
        let arrow = stock.isPositive ? "▲" : "▼"
        let color: Color = stock.isPositive ? .green : .red

        var result = Text(stock.symbol).font(.system(size: 12, weight: .medium))
            + Text("  ")
            + Text("$\(String(format: "%.2f", stock.price))").font(.system(size: 12, design: .monospaced))
            + Text("  ") + Text(arrow).font(.system(size: 8)).foregroundColor(color)

        if service.showPercentChange {
            result = result + Text(String(format: " %.1f%%", abs(stock.changePercent)))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(color)
        }

        return result
    }
}
