import SwiftUI
import UserNotifications

@main
struct TickerBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
