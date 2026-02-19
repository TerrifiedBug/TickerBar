import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var service: StockService
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)
                .padding(.bottom, 4)

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
                            Text(symbol).tag(symbol)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

            // Market hours only
            Toggle("Only refresh during market hours", isOn: $service.marketHoursOnly)

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
        }
        .padding(12)
    }
}
