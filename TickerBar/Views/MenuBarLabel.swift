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
        let quote = stock.displayQuote(includeExtendedHours: service.extendedHoursEnabled)
        let arrow = quote.isPositive ? "▲" : "▼"
        let arrowColor: NSColor = quote.isPositive ? .systemGreen : .systemRed
        let textColor = NSColor.labelColor
        let displayName = service.displayName(for: stock.symbol)
        let currencySymbol = displayName == stock.symbol ? stock.currencySymbol : ""

        // Scale the compact two-line glyphs with the menu bar text size
        // (size 10 reproduces the historical defaults). Two stacked lines are
        // bounded by the menu bar height, so very large sizes are most effective
        // in normal (single-line) mode.
        let scale = CGFloat(service.menuBarFontSize) / 10
        let symbolFont = NSFont.systemFont(ofSize: 9 * scale, weight: .semibold)
        let priceFont = NSFont.monospacedDigitSystemFont(ofSize: 8 * scale, weight: .regular)
        let arrowFont = NSFont.systemFont(ofSize: 6 * scale, weight: .regular)
        let percentFont = NSFont.monospacedDigitSystemFont(ofSize: 7 * scale, weight: .regular)
        let sessionFont = NSFont.systemFont(ofSize: 6 * scale, weight: .semibold)

        // Build line 1: symbol
        let line1 = NSAttributedString(string: displayName, attributes: [
            .font: symbolFont,
            .foregroundColor: textColor
        ])

        // Build line 2: price + arrow (+ optional percent)
        let line2 = NSMutableAttributedString()
        line2.append(NSAttributedString(string: "\(currencySymbol)\(String(format: "%.2f", quote.price))", attributes: [
            .font: priceFont,
            .foregroundColor: textColor
        ]))
        line2.append(NSAttributedString(string: " \(arrow)", attributes: [
            .font: arrowFont,
            .foregroundColor: arrowColor
        ]))
        if service.showPercentChange {
            line2.append(NSAttributedString(string: String(format: "%.1f%%", abs(quote.changePercent)), attributes: [
                .font: percentFont,
                .foregroundColor: arrowColor
            ]))
        }
        if let sessionLabel = quote.session.label {
            line2.append(NSAttributedString(string: " \(sessionLabel)", attributes: [
                .font: sessionFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
        }

        let line1Size = line1.size()
        let line2Size = line2.size()
        let width = max(line1Size.width, line2Size.width)
        let lineSpacing: CGFloat = 1
        let totalTextHeight = line1Size.height + lineSpacing + line2Size.height
        let height = max(22, ceil(totalTextHeight))
        let yOffset = (height - totalTextHeight) / 2

        // Resolve dynamic colors against the system (menu bar) appearance so the
        // text stays legible in both Light and Dark mode.
        let appearance = NSApp.effectiveAppearance
        let image = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
            appearance.performAsCurrentDrawingAppearance {
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
            }
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
        let quote = stock.displayQuote(includeExtendedHours: service.extendedHoursEnabled)
        let arrow = quote.isPositive ? "▲" : "▼"
        let arrowColor: NSColor = quote.isPositive ? .systemGreen : .systemRed
        let textColor = NSColor.labelColor
        let displayName = service.displayName(for: stock.symbol)
        let currencySymbol = displayName == stock.symbol ? stock.currencySymbol : ""

        // Menu bar text size is user-configurable; size 10 reproduces the
        // historical default. Secondary glyphs scale proportionally.
        let size = CGFloat(service.menuBarFontSize)
        let symbolFont = NSFont.systemFont(ofSize: size, weight: .medium)
        let priceFont = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        let arrowFont = NSFont.systemFont(ofSize: size * 0.7, weight: .regular)
        let percentFont = NSFont.monospacedDigitSystemFont(ofSize: size * 0.9, weight: .regular)
        let sessionFont = NSFont.systemFont(ofSize: size * 0.7, weight: .semibold)

        let str = NSMutableAttributedString()
        str.append(NSAttributedString(string: displayName, attributes: [
            .font: symbolFont,
            .foregroundColor: textColor
        ]))
        str.append(NSAttributedString(string: " \(currencySymbol)\(String(format: "%.2f", quote.price))", attributes: [
            .font: priceFont,
            .foregroundColor: textColor
        ]))
        str.append(NSAttributedString(string: " \(arrow)", attributes: [
            .font: arrowFont,
            .foregroundColor: arrowColor
        ]))
        if service.showPercentChange {
            str.append(NSAttributedString(string: String(format: "%.1f%%", abs(quote.changePercent)), attributes: [
                .font: percentFont,
                .foregroundColor: arrowColor
            ]))
        }
        if let sessionLabel = quote.session.label {
            str.append(NSAttributedString(string: " \(sessionLabel)", attributes: [
                .font: sessionFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
        }

        let textSize = str.size()
        // Grow the canvas for larger fonts so taller text isn't clipped; never
        // shrink below the standard menu bar height.
        let height = max(22, ceil(textSize.height))
        let yOffset = (height - textSize.height) / 2

        // Resolve dynamic colors against the system (menu bar) appearance.
        let appearance = NSApp.effectiveAppearance
        let image = NSImage(size: NSSize(width: ceil(textSize.width), height: height), flipped: false) { _ in
            appearance.performAsCurrentDrawingAppearance {
                str.draw(at: NSPoint(x: 0, y: yOffset))
            }
            return true
        }

        image.isTemplate = false
        return image
    }
}
