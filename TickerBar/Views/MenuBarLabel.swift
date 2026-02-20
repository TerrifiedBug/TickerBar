import SwiftUI
import AppKit

struct MenuBarLabel: View {
    let service: StockService

    var body: some View {
        if let stock = service.currentDisplayStock {
            if service.compactMenuBar {
                compactImage(stock)
            } else {
                normalText(stock)
            }
        } else {
            Text("⏳")
        }
    }

    // Compact: render two-line stacked layout as an NSImage
    // Line 1: AMZN
    // Line 2: 204.86 ▲
    @ViewBuilder
    private func compactImage(_ stock: StockItem) -> some View {
        let image = renderCompactImage(stock)
        Image(nsImage: image)
    }

    private func renderCompactImage(_ stock: StockItem) -> NSImage {
        let arrow = stock.isPositive ? "▲" : "▼"
        let arrowColor: NSColor = stock.isPositive ? .systemGreen : .systemRed
        let textColor = NSColor.white

        let symbolFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let priceFont = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular)
        let arrowFont = NSFont.systemFont(ofSize: 6, weight: .regular)
        let percentFont = NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .regular)

        // Build line 1: symbol
        let line1 = NSAttributedString(string: stock.symbol, attributes: [
            .font: symbolFont,
            .foregroundColor: textColor
        ])

        // Build line 2: price + arrow (+ optional percent)
        let line2 = NSMutableAttributedString()
        line2.append(NSAttributedString(string: "\(stock.currencySymbol)\(String(format: "%.2f", stock.price))", attributes: [
            .font: priceFont,
            .foregroundColor: textColor
        ]))
        line2.append(NSAttributedString(string: " \(arrow)", attributes: [
            .font: arrowFont,
            .foregroundColor: arrowColor
        ]))
        if service.showPercentChange {
            line2.append(NSAttributedString(string: String(format: "%.1f%%", abs(stock.changePercent)), attributes: [
                .font: percentFont,
                .foregroundColor: arrowColor
            ]))
        }

        let line1Size = line1.size()
        let line2Size = line2.size()
        let width = max(line1Size.width, line2Size.width)
        let height: CGFloat = 22 // menu bar height
        let lineSpacing: CGFloat = 1
        let totalTextHeight = line1Size.height + lineSpacing + line2Size.height
        let yOffset = (height - totalTextHeight) / 2

        let image = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { rect in
            // Line 2 at bottom (flipped=false means origin is bottom-left)
            line2.draw(at: NSPoint(
                x: (width - line2Size.width) / 2,
                y: yOffset
            ))
            // Line 1 on top
            line1.draw(at: NSPoint(
                x: (width - line1Size.width) / 2,
                y: yOffset + line2Size.height + lineSpacing
            ))
            return true
        }

        image.isTemplate = false
        return image
    }

    // Normal: single-line "AAPL $150.00 ▲1.5%" rendered as NSImage for reliable color
    @ViewBuilder
    private func normalText(_ stock: StockItem) -> some View {
        let image = renderNormalImage(stock)
        Image(nsImage: image)
    }

    private func renderNormalImage(_ stock: StockItem) -> NSImage {
        let arrow = stock.isPositive ? "▲" : "▼"
        let arrowColor: NSColor = stock.isPositive ? .systemGreen : .systemRed
        let textColor = NSColor.white

        let symbolFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let priceFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        let arrowFont = NSFont.systemFont(ofSize: 7, weight: .regular)
        let percentFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)

        let str = NSMutableAttributedString()
        str.append(NSAttributedString(string: stock.symbol, attributes: [
            .font: symbolFont,
            .foregroundColor: textColor
        ]))
        str.append(NSAttributedString(string: " \(stock.currencySymbol)\(String(format: "%.2f", stock.price))", attributes: [
            .font: priceFont,
            .foregroundColor: textColor
        ]))
        str.append(NSAttributedString(string: " \(arrow)", attributes: [
            .font: arrowFont,
            .foregroundColor: arrowColor
        ]))
        if service.showPercentChange {
            str.append(NSAttributedString(string: String(format: "%.1f%%", abs(stock.changePercent)), attributes: [
                .font: percentFont,
                .foregroundColor: arrowColor
            ]))
        }

        let size = str.size()
        let height: CGFloat = 22
        let yOffset = (height - size.height) / 2

        let image = NSImage(size: NSSize(width: ceil(size.width), height: height), flipped: false) { _ in
            str.draw(at: NSPoint(x: 0, y: yOffset))
            return true
        }

        image.isTemplate = false
        return image
    }
}
