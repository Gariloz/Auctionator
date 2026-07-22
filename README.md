# Auctionator (WotLK 3.3.5a)

**Auctionator** is an addon for World of Warcraft 3.3.5a that greatly simplifies working with the auction house:

## Main Features
- Fast and convenient item selling
- Mass auction posting (including single-item stacks)
- Automated search and buying
- Price history and posting recommendations
- **Full Scan** with GetAll (fast, ~15 min cooldown) or class scan (full AH, no cooldown)
- Russian and other localizations supported

## Changes in this version
- **Removed the 40 single-stack auction limit** (now only the server limit applies)
- **Increased error window size** for long messages
- **Improved Russian translation**
- **GetAll Full Scan rework** for large realms (e.g. Warmane Icecrown):
  - Waits for server data (AILU) before reading the auction list
  - Processes auctions in small chunks to reduce disconnect risk
  - Recovers item names when the client returns empty names
- **GetAll cooldown queue**: click **Start Scanning** even while on cooldown — the addon polls the server every 0.25s and **starts automatically** when GetAll is allowed (no need to click again). Use **Cancel** to abort the wait
- **Full class scan** (uncheck GetAll): scans the entire auction house by category, no 15-minute cooldown
- **Scan diagnostics** saved to WTF: `/atr scandiag`, `/atr scandiag trail`, `/atr scandiag clear`
- **Full Scan UI fixes**: correct Start / Cancel / Done button states after scan and during cooldown wait

## Full Scan (GetAll)
1. Open the auction house → **Full Scan...**
2. **GetAll** (checkbox on): fast scan, up to ~55,000 auctions per query (WoW 3.3.5 limit), 15-minute Blizzard cooldown
3. Without checkbox: full class scan (~15–20 min), no GetAll cooldown
4. On very large servers, GetAll may still disconnect — use class scan for full coverage, or check diagnostics after `/reload`

### Cooldown wait (GetAll)
- If GetAll is on cooldown, press **Start Scanning** anyway — status shows the remaining time (seconds/minutes)
- Stay at the auction house with the Full Scan window open; the scan starts on its own when the server allows
- Press **Cancel** to stop waiting without starting a scan

### Diagnostics
After a failed or interrupted scan, run `/reload`, then inspect:
- In game: `/atr scandiag trail` or `/atr scandiag snapshots`
- File: `WTF/Account/<account>/SavedVariables/Auctionator.lua` → `AUCTIONATOR_SCAN_DIAG`

## Installation
1. Copy the `Auctionator` folder to your WoW 3.3.5a `Interface/AddOns` directory
2. Restart the game (or `/reload` after updating)

## GitHub
https://github.com/Gariloz/Auctionator

---

**Original author:** Zirco

**Modifications and support:** Gariloz
