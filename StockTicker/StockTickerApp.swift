import SwiftUI

@main
struct StockTickerApp: App {
    @State private var stockService = StockService()

    var body: some Scene {
        MenuBarExtra {
            WatchlistView(service: stockService)
        } label: {
            Text(stockService.menuBarText)
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 300, height: 400)
    }

    init() {
        // Start timers after a brief delay to allow initialization
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [stockService] in
            stockService.startTimers()
        }
    }
}
