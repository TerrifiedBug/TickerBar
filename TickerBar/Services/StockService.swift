import Foundation
import SwiftUI
@preconcurrency import UserNotifications

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
        didSet { defaults.set(watchlist, forKey: "watchlist") }
    }
    var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: "refreshInterval"); restartRefreshTimer() }
    }
    var rotationEnabled: Bool {
        didSet { defaults.set(rotationEnabled, forKey: "rotationEnabled"); restartRotationTimer() }
    }
    var rotationSpeed: TimeInterval {
        didSet { defaults.set(rotationSpeed, forKey: "rotationSpeed"); restartRotationTimer() }
    }
    var pinnedSymbol: String {
        didSet { defaults.set(pinnedSymbol, forKey: "pinnedSymbol") }
    }
    var marketHoursOnly: Bool {
        didSet { defaults.set(marketHoursOnly, forKey: "marketHoursOnly") }
    }
    var showPercentChange: Bool {
        didSet { defaults.set(showPercentChange, forKey: "showPercentChange") }
    }
    var compactMenuBar: Bool {
        didSet { defaults.set(compactMenuBar, forKey: "compactMenuBar") }
    }
    var baseCurrency: String {
        didSet { defaults.set(baseCurrency, forKey: "baseCurrency") }
    }
    var menuBarFontSize: Double {
        didSet { defaults.set(menuBarFontSize, forKey: "menuBarFontSize") }
    }
    var solidPopoverBackground: Bool {
        didSet { defaults.set(solidPopoverBackground, forKey: "solidPopoverBackground") }
    }

    // MARK: - Exchange Rates (e.g. "GBP" -> 1.27 means 1 GBP = 1.27 base currency units)
    var exchangeRates: [String: Double] = [:]

    static let supportedBaseCurrencies = ["USD", "GBP", "EUR", "JPY", "CAD", "AUD", "CHF"]

    // MARK: - Portfolio Holdings
    //
    // A symbol can hold multiple lots of either kind: any number of vested RSU
    // lots (value only, no cost) and any number of purchase lots (with a cost
    // basis, e.g. buy 50 @ X then 100 @ Y). Value sums all lots; gain/loss sums
    // only cost-bearing lots.
    enum LotKind: String, Codable, Equatable {
        case rsu        // vested/awarded — value only, no cost basis
        case purchase   // bought — has a cost basis
    }

    struct Holding: Codable, Equatable, Identifiable {
        var id: UUID
        var kind: LotKind
        var shares: Double
        var costBasis: Double?   // nil for rsu; set for purchase

        init(id: UUID = UUID(), kind: LotKind, shares: Double, costBasis: Double?) {
            self.id = id
            self.kind = kind
            self.shares = shares
            self.costBasis = costBasis
        }
    }

    var holdings: [String: [Holding]] = [:] {
        didSet {
            if let data = try? JSONEncoder().encode(holdings) {
                defaults.set(data, forKey: "holdings")
            }
        }
    }

    // MARK: - Price Alerts
    var priceAlerts: [PriceAlert] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(priceAlerts) {
                defaults.set(data, forKey: "priceAlerts")
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

    // MARK: - Persistence
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        self.menuBarFontSize = defaults.double(forKey: "menuBarFontSize").nonZero ?? 10
        self.solidPopoverBackground = defaults.bool(forKey: "solidPopoverBackground")

        if let alertData = defaults.data(forKey: "priceAlerts"),
           let savedAlerts = try? JSONDecoder().decode([PriceAlert].self, from: alertData) {
            self.priceAlerts = savedAlerts
        }

        if let holdingsData = defaults.data(forKey: "holdings") {
            if let modern = try? JSONDecoder().decode([String: [Holding]].self, from: holdingsData) {
                self.holdings = modern
            } else {
                // Migrate the legacy single-record shape {shares, costBasis} into
                // a one-element purchase lot per symbol. Keep the same key so
                // existing users don't lose their holdings.
                struct LegacyHolding: Codable { var shares: Double; var costBasis: Double }
                if let legacy = try? JSONDecoder().decode([String: LegacyHolding].self, from: holdingsData) {
                    self.holdings = legacy.mapValues { [Holding(kind: .purchase, shares: $0.shares, costBasis: $0.costBasis)] }
                }
            }
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

    // MARK: - URL Building
    //
    // Yahoo crumbs commonly contain '+', '/', and '='. A raw interpolated URL,
    // or `.urlQueryAllowed` over a whole URL string, leaves '+' intact — and a
    // server decodes a query '+' as a space, corrupting the crumb. We build
    // every request with explicit per-component encoding so '+', '&', '#', '='
    // in a value are escaped, and symbols like "^GSPC" resolve in the path.

    /// Percent-encode a value for safe use as a URL *query value*, escaping the
    /// sub-delimiters that change a query's meaning ('+' decodes to space; '&',
    /// '=', '#', '?' delimit). Commas survive so `symbols=A,B` stays intact.
    nonisolated static func encodedQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=#?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private nonisolated static func yahooURL(path: String, query: [(name: String, value: String)]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "query2.finance.yahoo.com"
        components.path = path
        components.percentEncodedQuery = query
            .map { "\($0.name)=\(encodedQueryValue($0.value))" }
            .joined(separator: "&")
        return components.url
    }

    /// v8 chart URL — the symbol is a path segment, so encode it (escapes '^'
    /// in index symbols like "^GSPC", which previously made `URL(string:)` nil).
    nonisolated static func chartURL(symbol: String, crumb: String) -> URL? {
        var pathAllowed = CharacterSet.urlPathAllowed
        pathAllowed.remove(charactersIn: "/")
        let encodedSymbol = symbol.addingPercentEncoding(withAllowedCharacters: pathAllowed) ?? symbol
        var components = URLComponents()
        components.scheme = "https"
        components.host = "query2.finance.yahoo.com"
        components.percentEncodedPath = "/v8/finance/chart/\(encodedSymbol)"
        components.percentEncodedQuery = "interval=5m&range=1d&crumb=\(encodedQueryValue(crumb))"
        return components.url
    }

    /// v7 batch quote URL (used for quote enrichment and FX rates).
    nonisolated static func quoteURL(symbols: [String], crumb: String) -> URL? {
        yahooURL(path: "/v7/finance/quote", query: [
            ("symbols", symbols.joined(separator: ",")),
            ("formatted", "false"),
            ("crumb", crumb),
        ])
    }

    /// v1 symbol search URL.
    nonisolated static func searchURL(query: String) -> URL? {
        yahooURL(path: "/v1/finance/search", query: [
            ("q", query),
            ("quotesCount", "6"),
            ("newsCount", "0"),
            ("listsCount", "0"),
        ])
    }

    // MARK: - Networking

    private enum FetchOutcome: Sendable {
        case success(StockItem)
        case authFailure
        case failure
    }

    func fetchAllQuotes(isTimerTriggered: Bool = false) async {
        // Only skip fetching for automatic timer refreshes when all markets are closed.
        // Manual refreshes, initial load, and add-stock fetches always proceed.
        if isTimerTriggered && marketHoursOnly && !anyMarketOpen {
            return
        }

        isLoading = true

        // Ensure we have a valid crumb before fetching
        do {
            try await ensureAuth()
        } catch {
            errorMessage = "Authentication failed"
            isLoading = false
            return
        }

        let symbols = watchlist

        // First attempt with the current crumb.
        var result = await fetchQuotes(symbols: symbols, crumb: crumb)

        // If every symbol failed with an auth error, the crumb/cookie has likely
        // expired. Re-authenticate and retry once — the same recovery a manual
        // refresh used to perform, now done automatically.
        if result.items.isEmpty && result.authFailures > 0 {
            invalidateAuth()
            do {
                try await ensureAuth()
                result = await fetchQuotes(symbols: symbols, crumb: crumb)
            } catch {
                // Re-auth failed; fall through to keep-last-good handling below.
            }
        }

        // Genuine total failure (after the retry). Keep the last good data so the
        // menu bar doesn't blank out, surface a soft message, and invalidate auth
        // so the next cycle re-authenticates. Deliberately leave lastUpdated alone.
        if result.items.isEmpty && !symbols.isEmpty {
            errorMessage = "Couldn't refresh — showing last update"
            invalidateAuth()
            isLoading = false
            return
        }

        // Fetch v7 quote data for pre/post market prices (single batch call)
        var enriched = result.items
        if let crumbValue = crumb, !symbols.isEmpty {
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
        if let crumbValue = crumb, !holdings.isEmpty {
            let currencies = Set(enriched.compactMap { stock -> String? in
                guard holdings[stock.symbol] != nil else { return nil }
                return CurrencyUnit.majorUnitCode(stock.currency)
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

        // Merge fresh quotes with the previous snapshot so a single symbol that
        // transiently failed keeps its last-good values instead of disappearing.
        // Order follows the watchlist.
        let previous = stocks
        stocks = Self.mergedStocks(watchlist: watchlist, fresh: enriched, previous: previous)

        errorMessage = nil
        lastUpdated = Date()
        isLoading = false
        checkPriceAlerts()
    }

    /// Merge freshly-fetched quotes with the previous snapshot, preserving
    /// watchlist order and falling back to the last-good item for any symbol
    /// missing from `fresh`. Pure function — easy to unit test.
    nonisolated static func mergedStocks(watchlist: [String], fresh: [StockItem], previous: [StockItem]) -> [StockItem] {
        watchlist.compactMap { sym in
            fresh.first { $0.symbol == sym } ?? previous.first { $0.symbol == sym }
        }
    }

    /// Fetch all symbols concurrently. Returns successfully-parsed items plus a
    /// count of auth failures (HTTP 401/403) so the caller can decide whether to
    /// re-authenticate and retry.
    private func fetchQuotes(symbols: [String], crumb: String?) async -> (items: [StockItem], authFailures: Int) {
        await withTaskGroup(of: FetchOutcome.self) { group in
            for symbol in symbols {
                group.addTask {
                    await Self.fetchQuote(for: symbol, crumb: crumb)
                }
            }
            var items: [StockItem] = []
            var authFailures = 0
            for await outcome in group {
                switch outcome {
                case .success(let stock): items.append(stock)
                case .authFailure: authFailures += 1
                case .failure: break
                }
            }
            return (items: items, authFailures: authFailures)
        }
    }

    private nonisolated static func fetchQuote(for symbol: String, crumb: String?) async -> FetchOutcome {
        guard let crumb else { return .failure }
        guard let url = chartURL(symbol: symbol, crumb: crumb) else { return .failure }

        do {
            let (data, response) = try await session.data(from: url)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return .authFailure
            }

            return .success(try parseQuoteResponse(data: data))
        } catch {
            return .failure
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
        guard let url = quoteURL(symbols: symbols, crumb: crumb) else { return [:] }

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
        guard let url = quoteURL(symbols: symbols, crumb: crumb) else { return [:] }

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

        switch await Self.fetchQuote(for: symbol, crumb: crumb) {
        case .success:
            return nil
        case .authFailure:
            return "Couldn't validate \(symbol) right now"
        case .failure:
            return "\(symbol) is not a valid ticker symbol"
        }
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

    func lots(for symbol: String) -> [Holding] { holdings[symbol] ?? [] }

    func addLot(symbol: String, kind: LotKind, shares: Double, costBasis: Double?) {
        guard shares > 0 else { return }
        let cost = kind == .rsu ? nil : costBasis
        holdings[symbol, default: []].append(Holding(kind: kind, shares: shares, costBasis: cost))
    }

    func updateLot(symbol: String, id: UUID, shares: Double, costBasis: Double?) {
        guard var list = holdings[symbol], let idx = list.firstIndex(where: { $0.id == id }) else { return }
        if shares > 0 {
            list[idx].shares = shares
            list[idx].costBasis = list[idx].kind == .rsu ? nil : costBasis
            holdings[symbol] = list
        } else {
            removeLot(symbol: symbol, id: id)
        }
    }

    func removeLot(symbol: String, id: UUID) {
        guard var list = holdings[symbol] else { return }
        list.removeAll { $0.id == id }
        if list.isEmpty { holdings.removeValue(forKey: symbol) } else { holdings[symbol] = list }
    }

    /// Exchange rate from a stock's currency to baseCurrency. Returns nil when a
    /// required (non-base) rate hasn't been fetched yet, so callers exclude the
    /// holding instead of silently valuing it at parity — which previously
    /// mis-stated e.g. a JPY holding ~150x against USD. Rates are re-fetched each
    /// cycle while holdings exist.
    private func rateToBase(for stock: StockItem) -> Double? {
        let cur = CurrencyUnit.majorUnitCode(stock.currency)
        if cur == baseCurrency { return 1.0 }
        return exchangeRates[cur]
    }

    var totalPortfolioValue: Double {
        stocks.reduce(0) { total, stock in
            guard let rate = rateToBase(for: stock) else { return total }
            return total + lots(for: stock.symbol).reduce(0) { $0 + stock.displayPrice * $1.shares * rate }
        }
    }

    var totalPortfolioCost: Double {
        stocks.reduce(0) { total, stock in
            guard let rate = rateToBase(for: stock) else { return total }
            return total + lots(for: stock.symbol).reduce(0) { acc, lot in
                guard let cost = lot.costBasis else { return acc }
                return acc + cost * lot.shares * rate
            }
        }
    }

    /// Current value of only the cost-bearing lots — the basis for gain so a
    /// mixed RSU + purchase portfolio compares like with like.
    private var costBasisLotsValue: Double {
        stocks.reduce(0) { total, stock in
            guard let rate = rateToBase(for: stock) else { return total }
            return total + lots(for: stock.symbol).reduce(0) { acc, lot in
                lot.costBasis == nil ? acc : acc + stock.displayPrice * lot.shares * rate
            }
        }
    }

    var totalPortfolioGain: Double {
        costBasisLotsValue - totalPortfolioCost
    }

    var totalPortfolioGainPercent: Double {
        totalPortfolioCost > 0 ? (totalPortfolioGain / totalPortfolioCost) * 100 : 0
    }

    /// True when at least one lot has a cost basis, so gain/loss is meaningful.
    var hasCostBasis: Bool {
        holdings.values.contains { lots in lots.contains { $0.costBasis != nil } }
    }

    /// True when a held symbol's currency has no known FX rate to the base
    /// currency yet, so portfolio totals currently exclude that symbol's lots.
    var hasUnconvertedHoldings: Bool {
        stocks.contains { !lots(for: $0.symbol).isEmpty && rateToBase(for: $0) == nil }
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

        guard let url = Self.searchURL(query: trimmed) else { return [] }

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
