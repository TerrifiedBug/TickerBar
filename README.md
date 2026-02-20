<p align="center">
  <img src="TickerBar/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="TickerBar icon">
</p>

<h1 align="center">TickerBar</h1>

<p align="center">A lightweight macOS menu bar app for tracking stock prices in real-time using Yahoo Finance data.</p>

## Features

- **Menu bar stock ticker** — see live prices at a glance without opening any app
- **Compact mode** — stacked two-line display to minimize menu bar space
- **Stock rotation** — automatically cycle through your watchlist, or pin a single stock; skips closed markets
- **Sparkline charts** — tiny intraday price charts inline with each stock in the watchlist
- **Price alerts** — set above/below price targets and get macOS notifications when triggered
- **Drag to reorder** — rearrange your watchlist via right-click Move Up/Down
- **Color-coded prices** — green for gains, red for losses
- **Multi-exchange support** — tracks market hours for US, UK (LSE), EU, Tokyo, Hong Kong, and Shanghai exchanges
- **Correct currency symbols** — displays prices in the stock's native currency (USD, GBP, EUR, JPY, etc.)
- **Ticker search** — autocomplete suggestions from Yahoo Finance when adding symbols
- **Symbol validation** — prevents adding invalid ticker symbols
- **Auto-updates** — in-app updates via Sparkle, no manual re-downloading needed
- **Launch at login** — optional auto-start via macOS Login Items

## Installation

### Homebrew (recommended)

```bash
brew tap TerrifiedBug/tickerbar
brew install tickerbar
```

Update with `brew upgrade tickerbar`.

### Manual download

1. Download `TickerBar.zip` from the [latest release](https://github.com/TerrifiedBug/TickerBar/releases/latest)
2. Unzip and drag `TickerBar.app` to your Applications folder
3. On first launch, macOS may show a Gatekeeper warning since the app is not notarized:
   - Right-click the app and select **Open**, then click **Open** in the dialog
   - Or run `xattr -cr /Applications/TickerBar.app` in Terminal to remove the quarantine flag

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

## Disclaimer

TickerBar is not affiliated, endorsed, or vetted by Yahoo, Inc. It uses Yahoo Finance's publicly available APIs. The data is intended for personal use only. You should refer to Yahoo!'s terms of use for any details on your rights to use the actual data downloaded.

## License

MIT
