<p align="center">
  <img src="TickerBar/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="TickerBar icon">
</p>

<h1 align="center">TickerBar</h1>

<p align="center">A lightweight macOS menu bar app for tracking stock prices in real-time using Yahoo Finance data. For Free. No "Pro" features.</p>

<p align="center">
<img width="303" height="504" alt="image" src="https://github.com/user-attachments/assets/9c692459-f68a-43cc-9467-77784943cfc8" />
</p>

## Features

- **Menu bar stock ticker** — see live prices at a glance without opening any app
- **Compact mode** — stacked two-line display to minimize menu bar space
- **Stock rotation** — automatically cycle through your watchlist, or pin a single stock; skips closed markets
- **Sparkline charts** — tiny intraday price charts inline with each stock in the watchlist
- **Price alerts** — set above/below price targets and get macOS notifications when triggered
- **Ticker search** — autocomplete suggestions from Yahoo Finance when adding symbols
- **Custom display names** — replace ticker and currency symbols with private aliases in the menu bar and watchlist
- **Extended-hours prices** — optionally show live pre-market, after-hours, and overnight quotes with clear session labels

## Installation

### Homebrew (recommended)

```bash
brew install --cask terrifiedbug/tap/tickerbar
```

The build is unsigned (no paid Apple Developer ID), so macOS quarantines it. After install, clear it:
`xattr -dr com.apple.quarantine /Applications/TickerBar.app` (or right-click the app → **Open** once).

Updates land automatically via the in-app updater (Sparkle); you can also re-run the command
or `brew upgrade --cask tickerbar`.

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
xcodebuild -project TickerBar.xcodeproj -scheme TickerBar -configuration Release -derivedDataPath build build
```

The built app will be in `build/Build/Products/Release/TickerBar.app`.

`TickerBar.xcodeproj` is the source of truth for the project configuration — there is no project-generation step.

## Settings

Click the TickerBar menu bar item to open the watchlist, then click **Settings** to configure:

- Refresh interval (30s to 15 min)
- Stock rotation toggle and speed (3s to 1 min)
- Compact / normal menu bar display
- Show/hide percentage change
- Launch at login
- Automatic update checking

## Disclaimer

TickerBar is not affiliated, endorsed, or vetted by Yahoo, Inc. It uses Yahoo Finance's publicly available APIs. The data is intended for personal use only. You should refer to Yahoo!'s terms of use for any details on your rights to use the actual data downloaded.

## License

MIT
