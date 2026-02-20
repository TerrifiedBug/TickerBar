# TickerBar

A lightweight macOS menu bar app for tracking stock prices in real-time using Yahoo Finance data.

## Features

- **Menu bar stock ticker** — see live prices at a glance without opening any app
- **Compact mode** — stacked two-line display to minimize menu bar space
- **Stock rotation** — automatically cycle through your watchlist, or pin a single stock
- **Color-coded prices** — green for gains, red for losses
- **Multi-exchange support** — tracks market hours for US, UK (LSE), EU, Tokyo, Hong Kong, and Shanghai exchanges
- **Correct currency symbols** — displays prices in the stock's native currency (USD, GBP, EUR, JPY, etc.)
- **Ticker search** — autocomplete suggestions from Yahoo Finance when adding symbols
- **Symbol validation** — prevents adding invalid ticker symbols
- **Update checker** — notifies you when a new version is available
- **Launch at login** — optional auto-start via macOS Login Items

## Installation

1. Download `TickerBar.zip` from the [latest release](https://github.com/TerrifiedBug/TickerBar/releases/latest)
2. Unzip and drag `TickerBar.app` to your Applications folder
3. On first launch, macOS will show a Gatekeeper warning since the app is not notarized. Right-click the app and select **Open**, then click **Open** in the dialog to allow it

## Build from Source

Requires Xcode 15+ and macOS 14+.

```bash
git clone https://github.com/TerrifiedBug/TickerBar.git
cd TickerBar
xcodebuild -scheme TickerBar -configuration Release build
```

The built app will be in `build/Build/Products/Release/TickerBar.app`.

## Settings

Click the TickerBar menu bar item to open the watchlist, then click **Settings** to configure:

- Refresh interval (30s to 15 min)
- Stock rotation toggle and speed (3s to 1 min)
- Compact / normal menu bar display
- Show/hide percentage change
- Only refresh during market hours
- Launch at login
- Automatic update checking

## License

MIT
