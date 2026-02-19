# macOS Stock Ticker Menu Bar App -- Design

## Overview

A macOS menu bar app built with pure SwiftUI that displays live stock prices. It rotates through a configurable watchlist in the menu bar and shows a full watchlist dropdown on click. Uses Yahoo Finance for price data.

## Architecture

Pure SwiftUI using `MenuBarExtra` (macOS 13+). No main window -- the app lives entirely in the menu bar. No external dependencies.

**Approach**: `MenuBarExtra` + `@Observable` + async/await. No AppKit bridging, no Combine.

## Components

- **`StockTickerApp`** -- `@main` App struct, declares `MenuBarExtra` scene
- **`StockService`** -- `@Observable` class managing API calls, timers, rotation, state
- **`StockItem`** -- Data model (symbol, price, change, changePercent)
- **`WatchlistView`** -- Dropdown popover with stock list, add/remove, settings access
- **`SettingsView`** -- Inline settings panel in the dropdown

## Menu Bar Display

Shows one stock at a time, rotating through the watchlist:

```
AAPL $185.23 ▲1.2%
```

- Green ▲ for positive, red ▼ for negative
- Rotates every N seconds (configurable, default 5s)
- Rotation can be disabled; a pinned stock is shown instead

## Dropdown Popover

Clicking the menu bar item shows:

1. **Watchlist** -- All stocks with symbol, price, change, % change
2. **Click a row** -- Opens Yahoo Finance page in browser
3. **Add stock** -- Text field + button
4. **Remove stock** -- Swipe-to-delete or minus button
5. **Market status** -- "Market Closed" indicator when outside hours
6. **Last updated** -- Timestamp
7. **Settings** -- Button to toggle settings panel
8. **Quit** -- Exit the app

## Data Source

**Yahoo Finance** unofficial API (no key required):

```
GET https://query1.finance.yahoo.com/v7/finance/quote?symbols=AAPL,GOOGL,MSFT
```

Response fields: `regularMarketPrice`, `regularMarketChange`, `regularMarketChangePercent`

Batch request for all watchlist stocks in one call.

## Data Flow

```
Yahoo Finance API --> StockService (@Observable) --> MenuBarExtra label + WatchlistView
      ^                        |
      |                   Timer (refresh interval)
      +------------------------+
                          Timer (rotation interval)
```

## Settings

| Setting | Type | Default | Storage |
|---------|------|---------|---------|
| Refresh interval | Picker: 30s, 60s, 5min, 15min | 60s | UserDefaults |
| Enable rotation | Toggle | On | UserDefaults |
| Rotation speed | Picker: 3s, 5s, 10s | 5s | UserDefaults |
| Pinned stock | Picker (from watchlist) | First in list | UserDefaults |
| Launch at login | Toggle | Off | SMAppService |
| Only refresh during market hours | Toggle | On | UserDefaults |

**Rotation off behavior**: Shows only the pinned stock in the menu bar. Dropdown still shows all stocks.

## Market Hours Awareness

- US market hours: 9:30am-4pm ET, Monday-Friday
- Outside hours: auto-refresh pauses, "Market Closed" shown in dropdown
- Manual refresh still available outside hours

## Persistence

- Watchlist: `UserDefaults` (string array of ticker symbols)
- Settings: `UserDefaults` (via `@AppStorage`)
- Default watchlist: `["AAPL", "GOOGL", "MSFT", "AMZN", "TSLA"]`

## Error Handling

- Network failure: show "Unable to fetch" in menu bar, retry next interval
- Invalid ticker: inline error on add, don't persist
- Rate limiting (429): back off, double refresh interval temporarily

## Project Structure

```
StockTicker/
├── StockTicker.xcodeproj/
├── StockTicker/
│   ├── StockTickerApp.swift
│   ├── Models/
│   │   └── StockItem.swift
│   ├── Services/
│   │   └── StockService.swift
│   ├── Views/
│   │   ├── WatchlistView.swift
│   │   └── SettingsView.swift
│   └── Assets.xcassets/
└── Info.plist                      # LSUIElement = true
```

## Key Configuration

- `LSUIElement = true` -- Agent app, no dock icon
- Deployment target: macOS 14.0
- Launch at login: `SMAppService.mainApp`
- Click stock row: `NSWorkspace.shared.open()` to Yahoo Finance page

## Default Watchlist

AAPL, GOOGL, MSFT, AMZN, TSLA
