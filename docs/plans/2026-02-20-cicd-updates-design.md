# TickerBar CI/CD, Auto-Updates & Market Hours

## 1. GitHub Actions Release Workflow

**Trigger:** Push tag matching `v*` (e.g., `v1.0.0`)

**Steps:**
1. Checkout code
2. Build Release .app with xcodebuild on macos-latest runner
3. Zip the .app bundle
4. Create GitHub Release with the zip attached
5. Include release notes from tag annotation or commit message

**File:** `.github/workflows/release.yml`

## 2. Update Checker (GitHub Release API)

**On app launch**, check `https://api.github.com/repos/TerrifiedBug/TickerBar/releases/latest` for the latest release tag. Compare against the app's `CFBundleShortVersionString`. If a newer version exists, show a subtle notification in the watchlist popover with a download link.

**New file:** `TickerBar/Services/UpdateChecker.swift`
- Runs once on launch (with 5s delay to not block startup)
- Caches check result; only checks once per session
- Stores last-dismissed version in UserDefaults so user isn't nagged

**UI:** Small banner at top of WatchlistView: "Update available: v1.1.0" with a clickable link.

## 3. Multi-Exchange Market Hours

Yahoo Finance API `meta` field includes `exchangeTimezoneName` (e.g., "America/New_York", "Europe/London"). Parse this per-stock and use it to determine if THAT stock's exchange is open, rather than hardcoding US hours.

**Changes to StockService:**
- Store `exchangeTimezoneName` on StockItem
- Replace global `isMarketOpen()` with per-stock check
- Timer-based refresh skips only if ALL stocks' markets are closed

## Implementation Order

1. GitHub Actions workflow (no code changes, just add workflow file)
2. Update checker service + UI banner
3. Multi-exchange market hours
