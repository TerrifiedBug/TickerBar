import Foundation
import Sparkle

@MainActor
final class UpdateChecker: ObservableObject {
    let updaterController: SPUStandardUpdaterController?
    let installedViaBrew: Bool

    init() {
        let brewPaths = [
            "/opt/homebrew/Caskroom/tickerbar",
            "/usr/local/Caskroom/tickerbar"
        ]
        installedViaBrew = brewPaths.contains { FileManager.default.fileExists(atPath: $0) }

        if installedViaBrew {
            updaterController = nil
        } else {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }
    }

    var updater: SPUUpdater? {
        updaterController?.updater
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    var canCheckForUpdates: Bool {
        updater?.canCheckForUpdates ?? false
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }
}
