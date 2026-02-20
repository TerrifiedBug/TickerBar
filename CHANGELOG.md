# Changelog

All notable changes to TickerBar will be documented in this file.

## [Unreleased]

## [1.1.0] - 2026-02-20

### Added
- Sparkline charts — tiny intraday price graphs inline with each stock in the watchlist dropdown
- Price alerts — right-click any stock to set above/below price targets, get macOS notifications when triggered
- Bell icon indicator on stocks with active price alerts
- Moon icon on stocks with closed markets in the watchlist
- Reorder stocks via Move Up/Move Down in the right-click context menu
- Currency symbols in both compact and normal menu bar display
- Foreground notification delivery — alerts show as popup banners even while app is running
- Notification permission prompt with link to System Settings when disabled

### Fixed
- Price alerts no longer trigger immediately when set at the current price
- Removing a stock from the watchlist now also removes its price alerts
- Normal (non-compact) menu bar mode now reliably shows colored prices (rendered as NSImage)
- Stock rotation skips closed-market stocks when open markets are available
- Initial display no longer shows a closed-market stock when open ones exist

### Changed
- "Updated" timestamp moved to header bar alongside "Watchlist"
- Removed duplicate "Settings" header in settings panel

## [1.0.2] - 2026-02-20

### Added
- Homebrew distribution (`brew tap TerrifiedBug/tickerbar && brew install tickerbar`)
- Sparkle auto-update framework for in-app updates
- GitHub Actions release pipeline with Homebrew cask auto-update
- Appcast.xml for Sparkle update feed

### Fixed
- CFBundleVersion aligned to semver format for correct Sparkle version comparison

## [1.0.1] - 2026-02-20

### Added
- Compact menu bar mode (stacked two-line display)
- Color-coded prices in normal menu bar mode (green/red)
- Multi-exchange market hours support (US, UK, EU, Tokyo, Hong Kong, Shanghai)
- Currency symbols for international stocks (GBP, EUR, JPY, etc.)
- Ticker autocomplete search from Yahoo Finance
- Symbol validation before adding to watchlist
- Rotation speed options up to 1 minute
- "You're on the latest version" feedback for manual update checks
- App icon
- README

### Fixed
- Invalid ticker symbols could be added to watchlist without validation

## [1.0.0] - 2026-02-20

### Added
- Initial release
- Menu bar stock ticker with Yahoo Finance data
- Watchlist management (add/remove symbols)
- Stock rotation with configurable speed
- Pin a single stock to menu bar
- Refresh interval settings
- Market hours filtering
- Launch at login option
