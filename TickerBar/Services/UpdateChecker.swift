import Foundation

@MainActor
@Observable
final class UpdateChecker {
    var availableVersion: String?
    var downloadURL: URL?
    var dismissed: Bool = false

    private static let repoAPI = "https://api.github.com/repos/TerrifiedBug/TickerBar/releases/latest"

    var hasUpdate: Bool {
        availableVersion != nil && !dismissed
    }

    func checkForUpdates() async {
        guard let url = URL(string: Self.repoAPI) else { return }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let tagName = json?["tag_name"] as? String else { return }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }

            // Skip if user already dismissed this version
            let dismissedVersion = UserDefaults.standard.string(forKey: "dismissedUpdateVersion")
            if dismissedVersion == remoteVersion { return }

            if isNewer(remote: remoteVersion, current: currentVersion) {
                availableVersion = remoteVersion

                // Find the zip asset download URL
                if let assets = json?["assets"] as? [[String: Any]],
                   let zipAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
                   let urlString = zipAsset["browser_download_url"] as? String {
                    downloadURL = URL(string: urlString)
                } else if let htmlURL = json?["html_url"] as? String {
                    downloadURL = URL(string: htmlURL)
                }
            }
        } catch {
            // Silently fail — update check is best-effort
        }
    }

    func dismiss() {
        dismissed = true
        if let version = availableVersion {
            UserDefaults.standard.set(version, forKey: "dismissedUpdateVersion")
        }
    }

    private func isNewer(remote: String, current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, currentParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }
}
