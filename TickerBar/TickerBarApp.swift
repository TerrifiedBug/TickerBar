import SwiftUI

@main
struct TickerBarApp: App {
    @State private var stockService = StockService()

    var body: some Scene {
        MenuBarExtra {
            WatchlistView(service: stockService)
        } label: {
            MenuBarLabel(service: stockService)
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
