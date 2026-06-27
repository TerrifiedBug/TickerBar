import Foundation
import Sparkle

@MainActor
final class UpdateChecker: ObservableObject {
    let updaterController: SPUStandardUpdaterController

    init() {
        // Always run Sparkle — including for Homebrew installs. The app is
        // notarization-agnostic here; the cask sets `auto_updates true` so brew
        // defers to Sparkle instead of fighting it. (Previously this disabled
        // Sparkle whenever a /Caskroom/tickerbar dir existed, which left brew
        // users with no way to update from inside the app.)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var updater: SPUUpdater { updaterController.updater }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    var canCheckForUpdates: Bool {
        updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }
}
