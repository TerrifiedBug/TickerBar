import SwiftUI

@main
struct StockTickerApp: App {
    var body: some Scene {
        MenuBarExtra("StockTicker", systemImage: "chart.line.uptrend.xyaxis") {
            Text("Stock Ticker Loading...")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
