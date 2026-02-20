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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Watchlist")
                    .font(.headline)
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
                ForEach(service.stocks) { stock in
                    StockRowView(stock: stock)
                        .onTapGesture {
                            openYahooFinance(symbol: stock.symbol)
                        }
                        .contextMenu {
                            Button("Remove \(stock.symbol)") {
                                service.removeSymbol(stock.symbol)
                            }
                        }
                }
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

            // Last updated
            if let lastUpdated = service.lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }

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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(stock.symbol)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                Text(stock.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

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
