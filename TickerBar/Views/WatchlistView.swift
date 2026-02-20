import SwiftUI

struct WatchlistView: View {
    @Bindable var service: StockService
    @ObservedObject var updateChecker: UpdateChecker
    @State private var newSymbol = ""
    @State private var showSettings = false
    @State private var addError: String?
    @State private var isValidating = false
    @State private var searchResults: [StockService.SymbolSearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var alertSymbol: String?
    @State private var alertPriceText = ""
    @State private var alertIsAbove = true
    @State private var holdingsSymbol: String?
    @State private var holdingsSharesText = ""
    @State private var holdingsCostText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Watchlist")
                    .font(.headline)
                if let lastUpdated = service.lastUpdated {
                    Text(lastUpdated.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if service.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(action: {
                    Task { await service.fetchAllQuotes() }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Market status
            if service.marketHoursOnly && !service.anyMarketOpen {
                HStack {
                    Image(systemName: "moon.fill")
                        .foregroundStyle(.secondary)
                    Text("Markets Closed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }

            // Error
            if let error = service.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            // Portfolio summary (converted to base currency)
            if service.totalPortfolioValue > 0 {
                HStack {
                    Image(systemName: "chart.pie.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(service.baseCurrencySymbol)\(String(format: "%.0f", service.totalPortfolioValue))")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(String(format: "%@%+.0f (%.1f%%)", service.baseCurrencySymbol, service.totalPortfolioGain, service.totalPortfolioGainPercent))
                        .font(.caption)
                        .foregroundStyle(service.totalPortfolioGain >= 0 ? .green : .red)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 2)
            }

            Divider()

            // Stock list
            if service.stocks.isEmpty && !service.isLoading {
                Text("No data yet")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(Array(service.stocks.enumerated()), id: \.element.id) { index, stock in
                    StockRowView(stock: stock, hasAlert: !service.alertsForSymbol(stock.symbol).isEmpty, holding: service.holdingFor(stock.symbol))
                        .onTapGesture {
                            openYahooFinance(symbol: stock.symbol)
                        }
                        .contextMenu {
                            if index > 0 {
                                Button("Move Up") {
                                    withAnimation { service.moveSymbol(from: index, to: index - 1) }
                                }
                            }
                            if index < service.stocks.count - 1 {
                                Button("Move Down") {
                                    withAnimation { service.moveSymbol(from: index, to: index + 1) }
                                }
                            }

                            Divider()

                            Button("Set Price Alert...") {
                                alertPriceText = String(format: "%.2f", stock.displayPrice)
                                alertIsAbove = true
                                alertSymbol = stock.symbol
                            }

                            let alerts = service.alertsForSymbol(stock.symbol)
                            if !alerts.isEmpty {
                                Divider()
                                ForEach(alerts) { alert in
                                    Button("Remove: \(alert.directionLabel) \(stock.currencySymbol)\(String(format: "%.2f", alert.targetPrice))") {
                                        service.removeAlert(alert)
                                    }
                                }
                            }

                            Divider()

                            let holding = service.holdingFor(stock.symbol)
                            Button(holding != nil ? "Edit Holdings (\(String(format: "%.2f", holding!.shares)) shares)..." : "Add Holdings...") {
                                holdingsSharesText = holding != nil ? String(format: "%.2f", holding!.shares) : ""
                                holdingsCostText = holding != nil ? String(format: "%.2f", holding!.costBasis) : String(format: "%.2f", stock.displayPrice)
                                holdingsSymbol = stock.symbol
                            }
                            if holding != nil {
                                Button("Remove Holdings") {
                                    service.setHolding(symbol: stock.symbol, shares: 0, costBasis: 0)
                                }
                            }

                            Divider()
                            Button("Remove \(stock.symbol)") {
                                service.removeSymbol(stock.symbol)
                            }
                        }
                }
            }

            // Price alert input
            if let symbol = alertSymbol {
                VStack(spacing: 8) {
                    HStack {
                        Text("Alert for \(symbol)")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                        Button(action: { alertSymbol = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: 8) {
                        Picker("", selection: $alertIsAbove) {
                            Text("Above").tag(true)
                            Text("Below").tag(false)
                        }
                        .labelsHidden()
                        .frame(width: 70)
                        TextField("Price", text: $alertPriceText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Button("Set") {
                            if let price = Double(alertPriceText) {
                                service.addAlert(symbol: symbol, targetPrice: price, isAbove: alertIsAbove)
                                alertSymbol = nil
                            }
                        }
                        .disabled(Double(alertPriceText) == nil)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.background.opacity(0.5))
            }

            // Holdings input
            if let symbol = holdingsSymbol {
                VStack(spacing: 8) {
                    HStack {
                        Text("Holdings for \(symbol)")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                        Button(action: { holdingsSymbol = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shares")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextField("0", text: $holdingsSharesText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Avg Cost")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextField("0.00", text: $holdingsCostText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        Spacer()
                        VStack(spacing: 2) {
                            Text(" ")
                                .font(.caption2)
                            Button("Save") {
                                if let shares = Double(holdingsSharesText),
                                   let cost = Double(holdingsCostText) {
                                    service.setHolding(symbol: symbol, shares: shares, costBasis: cost)
                                }
                                holdingsSymbol = nil
                            }
                            .disabled(Double(holdingsSharesText) == nil || Double(holdingsCostText) == nil)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.background.opacity(0.5))
            }

            // Notification warning
            if let warning = service.notificationWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings") {
                        service.openNotificationSettings()
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.yellow.opacity(0.1))
            }

            Divider()

            // Add stock
            HStack {
                TextField("Add symbol...", text: $newSymbol)
                    .textFieldStyle(.plain)
                    .onSubmit { addSymbol() }
                    .onChange(of: newSymbol) { _, newValue in
                        searchTask?.cancel()
                        let query = newValue.trimmingCharacters(in: .whitespaces)
                        if query.isEmpty {
                            searchResults = []
                            return
                        }
                        searchTask = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            let results = await service.searchSymbols(query)
                            if !Task.isCancelled {
                                searchResults = results
                            }
                        }
                    }
                if isValidating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: addSymbol) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(newSymbol.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Search results dropdown
            if !searchResults.isEmpty && !newSymbol.trimmingCharacters(in: .whitespaces).isEmpty {
                VStack(spacing: 0) {
                    ForEach(searchResults) { result in
                        Button(action: {
                            selectSearchResult(result)
                        }) {
                            HStack {
                                Text(result.symbol)
                                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                                Text(result.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(result.exchange)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(.background.opacity(0.5))
            }

            if let addError {
                Text(addError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            Divider()

            // Bottom bar
            HStack {
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Inline settings
            if showSettings {
                Divider()
                SettingsView(service: service, updateChecker: updateChecker)
            }
        }
        .frame(width: 300)
    }

    private func addSymbol() {
        let symbol = newSymbol.uppercased().trimmingCharacters(in: .whitespaces)
        guard !symbol.isEmpty else { return }

        if service.watchlist.contains(symbol) {
            addError = "\(symbol) is already in your watchlist"
            newSymbol = ""
            return
        }

        addError = nil
        isValidating = true
        let symbolToAdd = symbol
        newSymbol = ""

        Task {
            if let error = await service.validateSymbol(symbolToAdd) {
                addError = error
            } else {
                service.addSymbol(symbolToAdd)
                await service.fetchAllQuotes()
            }
            isValidating = false
        }
    }

    private func selectSearchResult(_ result: StockService.SymbolSearchResult) {
        let symbol = result.symbol
        searchResults = []
        newSymbol = ""

        if service.watchlist.contains(symbol) {
            addError = "\(symbol) is already in your watchlist"
            return
        }

        addError = nil
        service.addSymbol(symbol)
        Task { await service.fetchAllQuotes() }
    }

    private func openYahooFinance(symbol: String) {
        guard let url = URL(string: "https://finance.yahoo.com/quote/\(symbol)") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct StockRowView: View {
    let stock: StockItem
    var hasAlert: Bool = false
    var holding: StockService.Holding? = nil

    private var tooltipText: String {
        var lines: [String] = []
        let cs = stock.currencySymbol

        if let high = stock.displayDayHigh, let low = stock.displayDayLow {
            lines.append("Day: \(cs)\(String(format: "%.2f", low)) - \(cs)\(String(format: "%.2f", high))")
        }
        if let h52 = stock.display52WeekHigh, let l52 = stock.display52WeekLow {
            lines.append("52w: \(cs)\(String(format: "%.2f", l52)) - \(cs)\(String(format: "%.2f", h52))")
        }
        if let ahPrice = stock.displayPostMarketPrice, let ahChange = stock.displayPostMarketChange {
            lines.append("After Hours: \(cs)\(String(format: "%.2f", ahPrice)) (\(String(format: "%+.2f", ahChange)))")
        }
        if let pmPrice = stock.displayPreMarketPrice, let pmChange = stock.displayPreMarketChange {
            lines.append("Pre-Market: \(cs)\(String(format: "%.2f", pmPrice)) (\(String(format: "%+.2f", pmChange)))")
        }
        if let h = holding {
            let value = stock.displayPrice * h.shares
            let gain = (stock.displayPrice - h.costBasis) * h.shares
            lines.append("\(String(format: "%.2f", h.shares)) shares @ \(cs)\(String(format: "%.2f", h.costBasis)) = \(cs)\(String(format: "%.2f", value)) (\(String(format: "%+.2f", gain)))")
        }
        if let state = stock.marketState {
            lines.append("Market: \(state)")
        }

        return lines.isEmpty ? stock.name : lines.joined(separator: "\n")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(stock.symbol)
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                    if hasAlert {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if holding != nil {
                        Image(systemName: "briefcase.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !StockService.isMarketOpen(timezoneName: stock.exchangeTimezoneName) {
                        Image(systemName: "moon.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(stock.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if stock.intradayPrices.count >= 2 {
                SparklineView(prices: stock.intradayPrices, isPositive: stock.isPositive)
                    .frame(width: 50, height: 20)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(stock.currencySymbol)\(String(format: "%.2f", stock.displayPrice))")
                    .font(.system(.body, design: .monospaced))

                HStack(spacing: 2) {
                    Image(systemName: stock.isPositive ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.caption2)
                    Text(String(format: "%.2f (%.1f%%)", abs(stock.displayChange), abs(stock.changePercent)))
                        .font(.caption)
                }
                .foregroundStyle(stock.isPositive ? .green : .red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .help(tooltipText)
    }
}

