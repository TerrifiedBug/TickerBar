import SwiftUI

@main
struct TickerBarApp: App {
    @State private var stockService = StockService()
    @StateObject private var updateChecker = UpdateChecker()

    var body: some Scene {
        MenuBarExtra {
            WatchlistView(service: stockService, updateChecker: updateChecker)
        } label: {
            MenuBarLabel(service: stockService)
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 300, height: 400)
    }

    init() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [stockService] in
            stockService.startTimers()
        }
    }
}
