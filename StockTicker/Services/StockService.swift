import Foundation
import SwiftUI

@MainActor
@Observable
final class StockService {
    // MARK: - Published State
    var stocks: [StockItem] = []
    var currentDisplayIndex: Int = 0
    var lastUpdated: Date?
    var errorMessage: String?
    var isLoading: Bool = false

    // MARK: - Settings (backed by UserDefaults)
    var watchlist: [String] {
        didSet { UserDefaults.standard.set(watchlist, forKey: "watchlist") }
    }
    var refreshInterval: TimeInterval {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval"); restartRefreshTimer() }
    }
    var rotationEnabled: Bool {
        didSet { UserDefaults.standard.set(rotationEnabled, forKey: "rotationEnabled"); restartRotationTimer() }
    }
    var rotationSpeed: TimeInterval {
        didSet { UserDefaults.standard.set(rotationSpeed, forKey: "rotationSpeed"); restartRotationTimer() }
    }
    var pinnedSymbol: String {
        didSet { UserDefaults.standard.set(pinnedSymbol, forKey: "pinnedSymbol") }
    }
    var marketHoursOnly: Bool {
        didSet { UserDefaults.standard.set(marketHoursOnly, forKey: "marketHoursOnly") }
    }

    // MARK: - Timers
    private var refreshTimer: Timer?
    private var rotationTimer: Timer?

    // MARK: - Auth State (cookie + crumb for Yahoo Finance)
    private var crumb: String?
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        ]
        return URLSession(configuration: config)
    }()

    // MARK: - Constants
    nonisolated static let defaultWatchlist = ["AAPL", "GOOGL", "MSFT", "AMZN", "TSLA"]
    nonisolated private static let baseURL = "https://query2.finance.yahoo.com"

    init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.stringArray(forKey: "watchlist"), !saved.isEmpty {
            self.watchlist = saved
        } else {
            self.watchlist = Self.defaultWatchlist
        }
        self.refreshInterval = defaults.double(forKey: "refreshInterval").nonZero ?? 60
        self.rotationEnabled = defaults.object(forKey: "rotationEnabled") as? Bool ?? true
        self.rotationSpeed = defaults.double(forKey: "rotationSpeed").nonZero ?? 5
        self.pinnedSymbol = defaults.string(forKey: "pinnedSymbol") ?? Self.defaultWatchlist[0]
        self.marketHoursOnly = defaults.object(forKey: "marketHoursOnly") as? Bool ?? true
    }

    // MARK: - Display

    var currentDisplayStock: StockItem? {
        guard !stocks.isEmpty else { return nil }
        if rotationEnabled {
            let index = currentDisplayIndex % stocks.count
            return stocks[index]
        } else {
            return stocks.first { $0.symbol == pinnedSymbol } ?? stocks.first
        }
    }

    var menuBarText: String {
        currentDisplayStock?.menuBarText ?? "Loading..."
    }

    func advanceDisplay() {
        guard !stocks.isEmpty, rotationEnabled else { return }
        currentDisplayIndex = (currentDisplayIndex + 1) % stocks.count
    }

    // MARK: - Market Hours

    nonisolated static func isMarketOpen(at date: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        guard let et = TimeZone(identifier: "America/New_York") else { return true }
        calendar.timeZone = et

        let weekday = calendar.component(.weekday, from: date)
        // 1 = Sunday, 7 = Saturday
        guard weekday >= 2 && weekday <= 6 else { return false }

        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let minuteOfDay = hour * 60 + minute

        let marketOpen = 9 * 60 + 30  // 9:30 AM
        let marketClose = 16 * 60     // 4:00 PM

        return minuteOfDay >= marketOpen && minuteOfDay < marketClose
    }

    // MARK: - Cookie + Crumb Authentication
    //
    // Yahoo Finance requires a session cookie + crumb token for API access.
    // Flow (based on yfinance library):
    //   1. GET https://fc.yahoo.com -> sets Yahoo session cookie (response 404s, but cookie is set)
    //   2. GET https://query2.finance.yahoo.com/v1/test/getcrumb -> returns plaintext crumb
    //   3. Append &crumb={crumb} to all API requests

    private func ensureAuth() async throws {
        if crumb != nil { return }

        // Step 1: Get cookie by hitting fc.yahoo.com
        let cookieURL = URL(string: "https://fc.yahoo.com")!
        let _ = try? await Self.session.data(from: cookieURL)

        // Step 2: Get crumb using the cookie
        let crumbURL = URL(string: "\(Self.baseURL)/v1/test/getcrumb")!
        let (crumbData, crumbResponse) = try await Self.session.data(from: crumbURL)

        guard let httpResponse = crumbResponse as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StockServiceError.authError
        }

        guard let crumbString = String(data: crumbData, encoding: .utf8),
              !crumbString.isEmpty,
              !crumbString.contains("<html>") else {
            throw StockServiceError.authError
        }

        self.crumb = crumbString
    }

    /// Invalidate auth so next request re-fetches cookie + crumb
    private func invalidateAuth() {
        crumb = nil
    }

    // MARK: - Networking

    func fetchAllQuotes() async {
        if marketHoursOnly && !Self.isMarketOpen() {
            return
        }

        isLoading = true
        errorMessage = nil

        // Ensure we have a valid crumb before fetching
        do {
            try await ensureAuth()
        } catch {
            errorMessage = "Authentication failed"
            isLoading = false
            return
        }

        // Capture values needed for concurrent fetching
        let symbols = watchlist
        let crumbValue = crumb

        let fetched = await withTaskGroup(of: StockItem?.self, returning: [StockItem].self) { group in
            for symbol in symbols {
                group.addTask {
                    await Self.fetchQuote(for: symbol, crumb: crumbValue)
                }
            }
            var results: [StockItem] = []
            for await result in group {
                if let stock = result {
                    results.append(stock)
                }
            }
            return results
        }

        // Sort to match watchlist order
        stocks = watchlist.compactMap { symbol in
            fetched.first { $0.symbol == symbol }
        }

        lastUpdated = Date()
        isLoading = false

        if fetched.isEmpty && !watchlist.isEmpty {
            errorMessage = "Unable to fetch quotes"
            // Auth might have expired -- invalidate so next attempt re-authenticates
            invalidateAuth()
        }
    }

    private nonisolated static func fetchQuote(for symbol: String, crumb: String?) async -> StockItem? {
        guard let crumb else { return nil }
        let urlString = "\(baseURL)/v8/finance/chart/\(symbol)?interval=1d&range=1d&crumb=\(crumb)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return nil
            }

            return try parseQuoteResponse(data: data)
        } catch {
            return nil
        }
    }

    nonisolated static func parseQuoteResponse(data: Data) throws -> StockItem {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let chart = json?["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let result = results.first,
              let meta = result["meta"] as? [String: Any],
              let symbol = meta["symbol"] as? String,
              let price = meta["regularMarketPrice"] as? Double,
              let previousClose = meta["chartPreviousClose"] as? Double
        else {
            throw StockServiceError.parseError
        }

        let name = meta["longName"] as? String
            ?? meta["shortName"] as? String
            ?? symbol

        return StockItem(symbol: symbol, name: name, price: price, previousClose: previousClose)
    }

    // MARK: - Watchlist Management

    func addSymbol(_ symbol: String) {
        let uppercased = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        guard !uppercased.isEmpty, !watchlist.contains(uppercased) else { return }
        watchlist.append(uppercased)
    }

    func removeSymbol(_ symbol: String) {
        watchlist.removeAll { $0 == symbol }
        stocks.removeAll { $0.symbol == symbol }
    }

    // MARK: - Timer Management

    func startTimers() {
        restartRefreshTimer()
        restartRotationTimer()

        // Initial fetch
        Task { @MainActor in
            await fetchAllQuotes()
        }
    }

    func stopTimers() {
        refreshTimer?.invalidate()
        rotationTimer?.invalidate()
        refreshTimer = nil
        rotationTimer = nil
    }

    private func restartRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchAllQuotes()
            }
        }
    }

    private func restartRotationTimer() {
        rotationTimer?.invalidate()
        guard rotationEnabled else { return }
        rotationTimer = Timer.scheduledTimer(withTimeInterval: rotationSpeed, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceDisplay()
            }
        }
    }

    // MARK: - Errors

    enum StockServiceError: Error {
        case parseError
        case authError
    }
}

// MARK: - Helpers

private extension Double {
    var nonZero: Double? {
        self == 0 ? nil : self
    }
}
