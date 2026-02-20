import Foundation
import SwiftUI
import UserNotifications

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
    var showPercentChange: Bool {
        didSet { UserDefaults.standard.set(showPercentChange, forKey: "showPercentChange") }
    }
    var compactMenuBar: Bool {
        didSet { UserDefaults.standard.set(compactMenuBar, forKey: "compactMenuBar") }
    }
    var baseCurrency: String {
        didSet { UserDefaults.standard.set(baseCurrency, forKey: "baseCurrency") }
    }

    // MARK: - Exchange Rates (e.g. "GBP" -> 1.27 means 1 GBP = 1.27 base currency units)
    var exchangeRates: [String: Double] = [:]

    static let supportedBaseCurrencies = ["USD", "GBP", "EUR", "JPY", "CAD", "AUD", "CHF"]

    // MARK: - Portfolio Holdings
    struct Holding: Codable, Equatable {
        var shares: Double
        var costBasis: Double  // average price per share
    }

    var holdings: [String: Holding] = [:] {
        didSet {
            if let data = try? JSONEncoder().encode(holdings) {
                UserDefaults.standard.set(data, forKey: "holdings")
            }
        }
    }

    // MARK: - Price Alerts
    var priceAlerts: [PriceAlert] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(priceAlerts) {
                UserDefaults.standard.set(data, forKey: "priceAlerts")
            }
        }
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
        self.showPercentChange = defaults.object(forKey: "showPercentChange") as? Bool ?? true
        self.compactMenuBar = defaults.object(forKey: "compactMenuBar") as? Bool ?? false
        self.baseCurrency = defaults.string(forKey: "baseCurrency") ?? "USD"

        if let alertData = defaults.data(forKey: "priceAlerts"),
           let savedAlerts = try? JSONDecoder().decode([PriceAlert].self, from: alertData) {
            self.priceAlerts = savedAlerts
        }

        if let holdingsData = defaults.data(forKey: "holdings"),
           let savedHoldings = try? JSONDecoder().decode([String: Holding].self, from: holdingsData) {
            self.holdings = savedHoldings
        }
    }

    // MARK: - Display

    var currentDisplayStock: StockItem? {
        guard !stocks.isEmpty else { return nil }
        if rotationEnabled {
            let current = stocks[currentDisplayIndex % stocks.count]
            // If current stock's market is closed, prefer an open one (unless all are closed)
            if !Self.isMarketOpen(timezoneName: current.exchangeTimezoneName) {
                if let openStock = stocks.first(where: { Self.isMarketOpen(timezoneName: $0.exchangeTimezoneName) }) {
                    return openStock
                }
            }
            return current
        } else {
            return stocks.first { $0.symbol == pinnedSymbol } ?? stocks.first
        }
    }

    var menuBarText: String {
        currentDisplayStock?.menuBarText ?? "Loading..."
    }

    func advanceDisplay() {
        guard !stocks.isEmpty, rotationEnabled else { return }

        let openStocks = stocks.enumerated().filter {
            Self.isMarketOpen(timezoneName: $0.element.exchangeTimezoneName)
        }

        if openStocks.isEmpty {
            // All markets closed — rotate through everything
            currentDisplayIndex = (currentDisplayIndex + 1) % stocks.count
        } else {
            // Find the next open stock after current index
            let startIndex = currentDisplayIndex
            for offset in 1...stocks.count {
                let candidate = (startIndex + offset) % stocks.count
                if Self.isMarketOpen(timezoneName: stocks[candidate].exchangeTimezoneName) {
                    currentDisplayIndex = candidate
                    return
                }
            }
        }
    }

    // MARK: - Market Hours

    /// Check if the exchange for a given timezone is open.
    /// Uses the stock's exchangeTimezoneName from Yahoo Finance API.
    nonisolated static func isMarketOpen(timezoneName: String? = nil, at date: Date = Date()) -> Bool {
        let tzID = timezoneName ?? "America/New_York"
        var calendar = Calendar(identifier: .gregorian)
        guard let tz = TimeZone(identifier: tzID) else { return true }
        calendar.timeZone = tz

        let weekday = calendar.component(.weekday, from: date)
        // 1 = Sunday, 7 = Saturday
        guard weekday >= 2 && weekday <= 6 else { return false }

        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let minuteOfDay = hour * 60 + minute

        // Approximate market hours for major exchanges (local time)
        // US (NYSE/NASDAQ): 9:30-16:00, UK (LSE): 8:00-16:30,
        // Europe: 9:00-17:30, Asia varies but ~9:00-15:00
        let (marketOpen, marketClose): (Int, Int) = switch tzID {
        case let tz where tz.starts(with: "Europe/London"):
            (8 * 60, 16 * 60 + 30)       // LSE: 8:00-16:30
        case let tz where tz.starts(with: "Europe/"):
            (9 * 60, 17 * 60 + 30)       // EU: 9:00-17:30
        case let tz where tz.starts(with: "Asia/Tokyo"):
            (9 * 60, 15 * 60)            // TSE: 9:00-15:00
        case let tz where tz.starts(with: "Asia/Hong_Kong"), let tz where tz.starts(with: "Asia/Shanghai"):
            (9 * 60 + 30, 16 * 60)       // HKEX/SSE: 9:30-16:00
        default:
            (9 * 60 + 30, 16 * 60)       // US default: 9:30-16:00
        }

        return minuteOfDay >= marketOpen && minuteOfDay < marketClose
    }

    /// Returns true if any stock in the watchlist has its market open
    var anyMarketOpen: Bool {
        if stocks.isEmpty { return Self.isMarketOpen() }
        return stocks.contains { Self.isMarketOpen(timezoneName: $0.exchangeTimezoneName) }
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

    func fetchAllQuotes(isTimerTriggered: Bool = false) async {
        // Only skip fetching for automatic timer refreshes when all markets are closed.
        // Manual refreshes, initial load, and add-stock fetches always proceed.
        if isTimerTriggered && marketHoursOnly && !anyMarketOpen {
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

        // Fetch v7 quote data for pre/post market prices (single batch call)
        var enriched = fetched
        if let crumbValue, !symbols.isEmpty {
            let v7Data = await Self.fetchV7Quotes(symbols: symbols, crumb: crumbValue)
            for i in enriched.indices {
                if let extra = v7Data[enriched[i].symbol] {
                    enriched[i].postMarketPrice = extra.postMarketPrice
                    enriched[i].postMarketChange = extra.postMarketChange
                    enriched[i].preMarketPrice = extra.preMarketPrice
                    enriched[i].preMarketChange = extra.preMarketChange
                    enriched[i].marketState = extra.marketState
                    enriched[i].fiftyTwoWeekHigh = extra.fiftyTwoWeekHigh
                    enriched[i].fiftyTwoWeekLow = extra.fiftyTwoWeekLow
                }
            }
        }

        // Fetch exchange rates for portfolio currency conversion
        if let crumbValue, !holdings.isEmpty {
            let currencies = Set(enriched.compactMap { stock -> String? in
                guard holdings[stock.symbol] != nil else { return nil }
                // Normalize sub-unit currencies to their major unit
                let raw = stock.currency ?? "USD"
                if raw == "GBp" || raw.uppercased() == "GBX" { return "GBP" }
                if raw == "ILA" { return "ILS" }
                return raw.uppercased()
            })
            let neededRates = currencies.filter { $0 != baseCurrency }
            if !neededRates.isEmpty {
                let rateSymbols = neededRates.map { "\($0)\(baseCurrency)=X" }
                let rates = await Self.fetchExchangeRates(symbols: Array(rateSymbols), crumb: crumbValue)
                for (pair, rate) in rates {
                    // Extract source currency from "GBPUSD=X" -> "GBP"
                    let source = String(pair.prefix(3))
                    exchangeRates[source] = rate
                }
                // Base currency to itself is always 1
                exchangeRates[baseCurrency] = 1.0
            } else {
                exchangeRates = [baseCurrency: 1.0]
            }
        }

        // Sort to match watchlist order
        stocks = watchlist.compactMap { symbol in
            enriched.first { $0.symbol == symbol }
        }

        lastUpdated = Date()
        isLoading = false
        checkPriceAlerts()

        if fetched.isEmpty && !watchlist.isEmpty {
            errorMessage = "Unable to fetch quotes"
            // Auth might have expired -- invalidate so next attempt re-authenticates
            invalidateAuth()
        }
    }

    private nonisolated static func fetchQuote(for symbol: String, crumb: String?) async -> StockItem? {
        guard let crumb else { return nil }
        let urlString = "\(baseURL)/v8/finance/chart/\(symbol)?interval=5m&range=1d&crumb=\(crumb)"
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
        let exchangeTZ = meta["exchangeTimezoneName"] as? String
        let currency = meta["currency"] as? String

        // Parse intraday close prices for sparkline
        var intradayPrices: [Double] = []
        if let indicators = result["indicators"] as? [String: Any],
           let quotes = indicators["quote"] as? [[String: Any]],
           let quote = quotes.first,
           let closes = quote["close"] as? [Any] {
            intradayPrices = closes.compactMap { $0 as? Double }
        }

        // Day high/low from meta
        let dayHigh = meta["regularMarketDayHigh"] as? Double
        let dayLow = meta["regularMarketDayLow"] as? Double

        return StockItem(symbol: symbol, name: name, price: price, previousClose: previousClose, exchangeTimezoneName: exchangeTZ, currency: currency, intradayPrices: intradayPrices, dayHigh: dayHigh, dayLow: dayLow)
    }

    // MARK: - V7 Quote (pre/post market, market state)

    struct V7QuoteData {
        var postMarketPrice: Double?
        var postMarketChange: Double?
        var preMarketPrice: Double?
        var preMarketChange: Double?
        var marketState: String?
        var fiftyTwoWeekHigh: Double?
        var fiftyTwoWeekLow: Double?
    }

    /// Batch fetch v7 quote data for all symbols (single HTTP call).
    private nonisolated static func fetchV7Quotes(symbols: [String], crumb: String) async -> [String: V7QuoteData] {
        let joined = symbols.joined(separator: ",")
        let urlString = "\(baseURL)/v7/finance/quote?symbols=\(joined)&formatted=false&crumb=\(crumb)"
        guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) else { return [:] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [:] }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let quoteResponse = json?["quoteResponse"] as? [String: Any],
                  let results = quoteResponse["result"] as? [[String: Any]] else { return [:] }

            var dict: [String: V7QuoteData] = [:]
            for quote in results {
                guard let symbol = quote["symbol"] as? String else { continue }
                dict[symbol] = V7QuoteData(
                    postMarketPrice: quote["postMarketPrice"] as? Double,
                    postMarketChange: quote["postMarketChange"] as? Double,
                    preMarketPrice: quote["preMarketPrice"] as? Double,
                    preMarketChange: quote["preMarketChange"] as? Double,
                    marketState: quote["marketState"] as? String,
                    fiftyTwoWeekHigh: quote["fiftyTwoWeekHigh"] as? Double,
                    fiftyTwoWeekLow: quote["fiftyTwoWeekLow"] as? Double
                )
            }
            return dict
        } catch {
            return [:]
        }
    }

    // MARK: - Exchange Rates

    /// Fetch exchange rates via v7/quote (e.g. symbols = ["GBPUSD=X", "EURUSD=X"])
    private nonisolated static func fetchExchangeRates(symbols: [String], crumb: String) async -> [String: Double] {
        let joined = symbols.joined(separator: ",")
        let urlString = "\(baseURL)/v7/finance/quote?symbols=\(joined)&formatted=false&crumb=\(crumb)"
        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded) else { return [:] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [:] }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let quoteResponse = json?["quoteResponse"] as? [String: Any],
                  let results = quoteResponse["result"] as? [[String: Any]] else { return [:] }

            var rates: [String: Double] = [:]
            for quote in results {
                guard let symbol = quote["symbol"] as? String,
                      let price = quote["regularMarketPrice"] as? Double else { continue }
                // Symbol is like "GBPUSD=X", we store "GBP" -> rate
                let source = String(symbol.prefix(3))
                rates[source] = price
            }
            return rates
        } catch {
            return [:]
        }
    }

    // MARK: - Watchlist Management

    func addSymbol(_ symbol: String) {
        let uppercased = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        guard !uppercased.isEmpty, !watchlist.contains(uppercased) else { return }
        watchlist.append(uppercased)
    }

    /// Validate a ticker by attempting to fetch its quote. Returns nil on success, or an error message.
    func validateSymbol(_ symbol: String) async -> String? {
        do {
            try await ensureAuth()
        } catch {
            return "Unable to validate (auth failed)"
        }

        let stock = await Self.fetchQuote(for: symbol, crumb: crumb)
        if stock == nil {
            return "\(symbol) is not a valid ticker symbol"
        }
        return nil
    }

    func removeSymbol(_ symbol: String) {
        watchlist.removeAll { $0 == symbol }
        stocks.removeAll { $0.symbol == symbol }
        priceAlerts.removeAll { $0.symbol == symbol }
        holdings.removeValue(forKey: symbol)
    }

    func moveSymbol(from source: Int, to destination: Int) {
        let symbol = watchlist.remove(at: source)
        watchlist.insert(symbol, at: destination)
        // Re-sort stocks to match new watchlist order
        stocks = watchlist.compactMap { sym in
            stocks.first { $0.symbol == sym }
        }
    }

    // MARK: - Price Alert Management

    var notificationWarning: String?

    func addAlert(symbol: String, targetPrice: Double, isAbove: Bool) {
        let alert = PriceAlert(symbol: symbol, targetPrice: targetPrice, isAbove: isAbove)
        priceAlerts.append(alert)
        ensureNotificationPermission()
    }

    private func ensureNotificationPermission() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            case .denied:
                notificationWarning = "Notifications are disabled. Enable in System Settings > Notifications > TickerBar."
            default:
                notificationWarning = nil
            }
        }
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") {
            NSWorkspace.shared.open(url)
        }
        notificationWarning = nil
    }

    func removeAlert(_ alert: PriceAlert) {
        priceAlerts.removeAll { $0.id == alert.id }
    }

    func alertsForSymbol(_ symbol: String) -> [PriceAlert] {
        priceAlerts.filter { $0.symbol == symbol }
    }

    private func checkPriceAlerts() {
        var triggeredAlertIDs: Set<UUID> = []

        for i in priceAlerts.indices {
            guard let stock = stocks.first(where: { $0.symbol == priceAlerts[i].symbol }) else { continue }

            if !priceAlerts[i].armed {
                // Arm on first check — skips the fetch cycle where alert was created
                priceAlerts[i].armed = true
                continue
            }

            if priceAlerts[i].isTriggered(currentPrice: stock.displayPrice) {
                triggeredAlertIDs.insert(priceAlerts[i].id)
                sendAlertNotification(alert: priceAlerts[i], currentPrice: stock.displayPrice, currency: stock.currencySymbol)
            }
        }

        if !triggeredAlertIDs.isEmpty {
            priceAlerts.removeAll { triggeredAlertIDs.contains($0.id) }
        }
    }

    private func sendAlertNotification(alert: PriceAlert, currentPrice: Double, currency: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(alert.symbol) Price Alert"
        content.body = "\(alert.symbol) is now \(currency)\(String(format: "%.2f", currentPrice)), \(alert.directionLabel) your target of \(currency)\(String(format: "%.2f", alert.targetPrice))"
        content.sound = .default

        let request = UNNotificationRequest(identifier: alert.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Portfolio Management

    func setHolding(symbol: String, shares: Double, costBasis: Double) {
        if shares > 0 {
            holdings[symbol] = Holding(shares: shares, costBasis: costBasis)
        } else {
            holdings.removeValue(forKey: symbol)
        }
    }

    func holdingFor(_ symbol: String) -> Holding? {
        holdings[symbol]
    }

    /// Get the normalized major-unit currency code for a stock (GBp/GBX -> GBP, ILA -> ILS)
    private func normalizedCurrency(for stock: StockItem) -> String {
        let raw = stock.currency ?? "USD"
        if raw == "GBp" || raw.uppercased() == "GBX" { return "GBP" }
        if raw == "ILA" { return "ILS" }
        return raw.uppercased()
    }

    /// Exchange rate from a stock's currency to baseCurrency. Returns 1.0 if same or unknown.
    private func rateToBase(for stock: StockItem) -> Double {
        let cur = normalizedCurrency(for: stock)
        if cur == baseCurrency { return 1.0 }
        return exchangeRates[cur] ?? 1.0
    }

    var totalPortfolioValue: Double {
        stocks.reduce(0) { total, stock in
            guard let h = holdings[stock.symbol] else { return total }
            return total + stock.displayPrice * h.shares * rateToBase(for: stock)
        }
    }

    var totalPortfolioCost: Double {
        stocks.reduce(0) { total, stock in
            guard let h = holdings[stock.symbol] else { return total }
            return total + h.costBasis * h.shares * rateToBase(for: stock)
        }
    }

    var totalPortfolioGain: Double {
        totalPortfolioValue - totalPortfolioCost
    }

    var totalPortfolioGainPercent: Double {
        totalPortfolioCost > 0 ? (totalPortfolioGain / totalPortfolioCost) * 100 : 0
    }

    var baseCurrencySymbol: String {
        switch baseCurrency {
        case "GBP": return "£"
        case "EUR": return "€"
        case "JPY": return "¥"
        case "CAD": return "C$"
        case "AUD": return "A$"
        case "CHF": return "CHF "
        default: return "$"
        }
    }

    // MARK: - Symbol Search

    struct SymbolSearchResult: Identifiable {
        let id = UUID()
        let symbol: String
        let name: String
        let exchange: String
    }

    func searchSymbols(_ query: String) async -> [SymbolSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let urlString = "\(Self.baseURL)/v1/finance/search?q=\(trimmed)&quotesCount=6&newsCount=0&listsCount=0"
        guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) else { return [] }

        do {
            let (data, response) = try await Self.session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [] }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let quotes = json?["quotes"] as? [[String: Any]] else { return [] }

            return quotes.compactMap { quote in
                guard let symbol = quote["symbol"] as? String,
                      let name = (quote["shortname"] as? String) ?? (quote["longname"] as? String) else { return nil }
                let exchange = quote["exchDisp"] as? String ?? ""
                return SymbolSearchResult(symbol: symbol, name: name, exchange: exchange)
            }
        } catch {
            return []
        }
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
                await self?.fetchAllQuotes(isTimerTriggered: true)
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
