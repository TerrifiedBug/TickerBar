import WidgetKit
import SwiftUI

// A small/medium home-screen widget showing live prices for the default
// watchlist. It reuses the app's StockItem model and YahooFinanceClient
// (shared target membership) and fetches directly on its own timeline.
//
// SPIKE SCOPE: this fetches the default watchlist, not the user's, because
// reading the user's watchlist requires an App Group (a provisioned shared
// UserDefaults suite) wired into both the app and this extension. Once the
// App Group is added in Xcode, swap `StockService.defaultWatchlist` for the
// shared suite's "watchlist" key. See plans/018-direction-widgetkit-spike.md.

struct TickerEntry: TimelineEntry {
    let date: Date
    let stocks: [StockItem]
}

/// Wraps WidgetKit's non-Sendable completion handler so it can be forwarded
/// from the async fetch Task under Swift 6 strict concurrency. WidgetKit owns
/// the handler's threading; we only call it once.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

struct TickerProvider: TimelineProvider {
    func placeholder(in context: Context) -> TickerEntry {
        TickerEntry(date: Date(), stocks: TickerWidgetSampleData.stocks)
    }

    func getSnapshot(in context: Context, completion: @escaping (TickerEntry) -> Void) {
        completion(TickerEntry(date: Date(), stocks: TickerWidgetSampleData.stocks))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TickerEntry>) -> Void) {
        let box = UncheckedSendableBox(completion)
        Task {
            let fetched = await TickerWidgetFetcher.fetchDefault()
            let entry = TickerEntry(date: Date(),
                                    stocks: fetched.isEmpty ? TickerWidgetSampleData.stocks : fetched)
            // Refresh ~every 30 minutes to respect Yahoo rate limits and the
            // widget refresh budget.
            let next = Date().addingTimeInterval(30 * 60)
            box.value(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

@MainActor
enum TickerWidgetFetcher {
    static func fetchDefault() async -> [StockItem] {
        let client = YahooFinanceClient()
        do {
            try await client.ensureAuth()
        } catch {
            return []
        }
        let symbols = StockService.defaultWatchlist
        if let batch = await client.fetchBatch(symbols: symbols, crumb: client.currentCrumb),
           batch.count == symbols.count {
            return batch
        }
        return await client.fetchQuotes(symbols: symbols, crumb: client.currentCrumb).items
    }
}

struct TickerWidgetEntryView: View {
    var entry: TickerEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(entry.stocks.prefix(4)) { stock in
                HStack(spacing: 6) {
                    Text(stock.symbol)
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                    Spacer()
                    Text("\(stock.currencySymbol)\(String(format: "%.2f", stock.displayPrice))")
                        .font(.caption)
                    Text(String(format: "%+.1f%%", stock.changePercent))
                        .font(.caption2)
                        .foregroundStyle(stock.isPositive ? .green : .red)
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct TickerBarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TickerBarWidget", provider: TickerProvider()) { entry in
            TickerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("TickerBar")
        .description("Live prices at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

enum TickerWidgetSampleData {
    static let stocks: [StockItem] = [
        StockItem(symbol: "AAPL", name: "Apple", price: 185, previousClose: 183, currency: "USD"),
        StockItem(symbol: "MSFT", name: "Microsoft", price: 420, previousClose: 418, currency: "USD"),
        StockItem(symbol: "GOOGL", name: "Alphabet", price: 170, previousClose: 171, currency: "USD"),
    ]
}
