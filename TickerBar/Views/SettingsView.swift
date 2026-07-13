import SwiftUI
import ServiceManagement
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var service: StockService
    @ObservedObject var updateChecker: UpdateChecker
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Refresh interval
            HStack {
                Text("Refresh interval")
                Spacer()
                Picker("", selection: $service.refreshInterval) {
                    Text("30s").tag(30.0)
                    Text("1 min").tag(60.0)
                    Text("5 min").tag(300.0)
                    Text("15 min").tag(900.0)
                }
                .labelsHidden()
                .frame(width: 100)
            }

            // Rotation toggle
            Toggle("Rotate stocks in menu bar", isOn: $service.rotationEnabled)

            // Rotation speed (only when enabled)
            if service.rotationEnabled {
                HStack {
                    Text("Rotation speed")
                    Spacer()
                    Picker("", selection: $service.rotationSpeed) {
                        Text("3s").tag(3.0)
                        Text("5s").tag(5.0)
                        Text("10s").tag(10.0)
                        Text("15s").tag(15.0)
                        Text("30s").tag(30.0)
                        Text("1 min").tag(60.0)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

            // Pinned stock (only when rotation disabled)
            if !service.rotationEnabled {
                HStack {
                    Text("Show stock")
                    Spacer()
                    Picker("", selection: $service.pinnedSymbol) {
                        ForEach(service.watchlist, id: \.self) { symbol in
                            Text(service.displayName(for: symbol)).tag(symbol)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

            // Menu bar display
            Toggle("Compact menu bar", isOn: $service.compactMenuBar)

            // Show percent change in menu bar
            Toggle("Show % change in menu bar", isOn: $service.showPercentChange)

            Toggle("Show extended-hours prices", isOn: $service.extendedHoursEnabled)
                .help("Use pre-market, after-hours, and overnight quotes when Yahoo provides them")
                .onChange(of: service.extendedHoursEnabled) {
                    Task { await service.fetchAllQuotes() }
                }

            // Menu bar text size (normal mode)
            HStack {
                Text("Menu bar text size")
                Spacer()
                Picker("", selection: $service.menuBarFontSize) {
                    Text("10").tag(10.0)
                    Text("11").tag(11.0)
                    Text("12").tag(12.0)
                    Text("13").tag(13.0)
                    Text("14").tag(14.0)
                    Text("15").tag(15.0)
                    Text("16").tag(16.0)
                }
                .labelsHidden()
                .frame(width: 100)
            }

            // Opaque dropdown background for readability over busy wallpapers
            Toggle("Solid dropdown background", isOn: $service.solidPopoverBackground)

            // Base currency for portfolio
            HStack {
                Text("Portfolio currency")
                Spacer()
                Picker("", selection: $service.baseCurrency) {
                    ForEach(StockService.supportedBaseCurrencies, id: \.self) { currency in
                        Text(currency).tag(currency)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
            }

            // Launch at login
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = !newValue // revert on failure
                    }
                }

            Divider()

            // About / Updates
            HStack {
                Text("Version")
                Spacer()
                Text("v\(appVersion)")
                    .foregroundStyle(.secondary)
            }

            Toggle("Automatically check for updates", isOn: Binding(
                get: { updateChecker.automaticallyChecksForUpdates },
                set: { updateChecker.automaticallyChecksForUpdates = $0 }
            ))

            Button("Check for Updates") {
                updateChecker.checkForUpdates()
            }
            .disabled(!updateChecker.canCheckForUpdates)

            Divider()

            // Backup: export/import watchlist, holdings, alerts, and currency.
            HStack {
                Text("Backup")
                Spacer()
                Button("Export…") { exportPortfolio() }
                Button("Import…") { importPortfolio() }
            }
        }
        .padding(12)
    }

    private func exportPortfolio() {
        guard let data = try? service.exportBackupData() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "TickerBar-backup.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func importPortfolio() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            if service.importBackupData(data) {
                Task { await service.fetchAllQuotes() }
            }
        }
    }
}
