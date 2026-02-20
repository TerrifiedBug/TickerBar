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

            Divider()

            // Stock list
            if service.stocks.isEmpty && !service.isLoading {
                Text("No data yet")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(Array(service.stocks.enumerated()), id: \.element.id) { index, stock in
                    StockRowView(stock: stock, hasAlert: !service.alertsForSymbol(stock.symbol).isEmpty)
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
                                alertPriceText = String(format: "%.2f", stock.price)
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
                Text("\(stock.currencySymbol)\(String(format: "%.2f", stock.price))")
                    .font(.system(.body, design: .monospaced))

                HStack(spacing: 2) {
                    Image(systemName: stock.isPositive ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.caption2)
                    Text(String(format: "%.2f (%.1f%%)", abs(stock.change), abs(stock.changePercent)))
                        .font(.caption)
                }
                .foregroundStyle(stock.isPositive ? .green : .red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

