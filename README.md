# FlaskSeller

A small Auction House watcher with a four-item watchlist for **WoW Classic TBC Anniversary**, targeting interfaces 20506/20505. No external libraries.

## Install

Extract the `FlaskSeller` folder into your Anniversary client's `Interface/AddOns/` directory, normally `World of Warcraft/_anniversary_/Interface/AddOns/FlaskSeller`. The TOC should be directly inside that folder. Restart WoW and enable the addon.

Defaults: **22851 — Flask of Fortification**, **10-second** polling, **1-copper** undercut, **25g** fallback. Set a fallback you are willing to use before posting. Settings are saved per character.

To add an item, open the AH and drag it from your bags onto the add area in the FlaskSeller panel. The watchlist holds up to four IDs and each item keeps its own prices, status, sale baseline, last check, suggested price, and last posted price. Click a row to select that item for **Post 1**. The red **x** removes a row; the final row cannot be removed.

## Use

1. Open the AH. A small draggable panel scans one watched item at a time and shows compact rows for every watched item: name, status, your lowest buyout, market price, and suggested price.
2. If the panel is green, no action is needed. If it asks you to post, click **Post 1 at ...** once.
3. FlaskSeller finds one selected item in your equipped bags, puts it in Blizzard's sell slot, sets stack size **1**, number of stacks **1**, and posts it at the suggestion.
4. Accept any Blizzard confirmation yourself. If the client rejects one-click posting, use Blizzard's normal sell form; the panel explains the next step.

**Post 1 posts one flask in one auction per click.** It requires a recent complete scan, finds the selected item in bags 0–4, and checks that the native sell slot, quantity, bid, buyout and duration match before posting. The addon never posts automatically or cancels auctions. Older auctions stay listed. Posting requires no combat lockdown.

Use **Refresh now** for one complete manual check, whether automatic checking is on or off. It respects throttling and reads every matching page. While a scan is running, the button is disabled to prevent duplicate requests.

Click **Auto: On / Auto: Off** to toggle interval checks independently; the label shows the current mode. Turning Auto off ignores any pending scan result. Manual checks leave automatic mode unchanged. The panel retains the last complete prices and market status while Auto is off. With no complete result yet, status is PAUSED. Auto stays off across closing/reopening the AH and changing items, but resets to On after `/reload` or logging out. Sale detection starts fresh after turning Auto back on.

When Auto is on, its button shows the time until the next scan, for example **Auto: On (8s)**. It changes to **Auto: checking** during an interval scan, **Auto: manual** during a manual refresh, and **Auto: waiting** while the Auction House throttle delays a due scan.

## Commands

Omit the value to show the current setting. Prices use whole **copper**.

| Command | Example |
| --- | --- |
| `/flask show` | Reopen the FlaskSeller panel while the AH is open |
| `/flask status` | Show last complete result and scan message |
| `/flask item [ID]` | `/flask item 22851` |
| `/flask interval [seconds]` | `/flask interval 10` (5–3600) |
| `/flask undercut [copper]` | `/flask undercut 1` |
| `/flask fallback [copper]` | `/flask fallback 250000` (25g) |
| `/flask sound [on/off]` | Undercut alert sound; on by default |

With no competitor, the suggestion uses your last successfully observed posting price, then the fallback. Switching rows preserves each item's saved posting price. Suggestions cannot go below 1 copper.

When a completed scan first requires action—**NO_AUCTION** or **UNDERCUT**—FlaskSeller plays the raid-warning sound once. **POSSIBLY_SOLD** remains a scan-based estimate and is silent. For Blizzard’s yellow “buyer found” system message, every auction sale plays `ffnice.ogg` on the Master channel, even with the AH panel closed. Turn sounds off with `/flask sound off`.

## Indicators

- **NO_AUCTION**, gray: no active auction found in a complete scan.
- **COMPETITIVE**, green: your lowest buyout matches or beats competitors. Matching does not guarantee first position.
- **UNDERCUT**, red: a competitor is cheaper, or your auctions have no buyout.
- **POSSIBLY_SOLD**, yellow: two complete scans show fewer of your auctions. Expiry or cancellation can look the same; check before replacing. UNDERCUT takes priority when both apply.

Prices are per flask, including stacks; fractional copper is rounded down for display. Bid-only competitors are ignored. WAITING means no complete result yet. Sale tracking resets when reopening the AH or changing settings.

## Limits and restrictions

Scans query only the item's localized exact name, validate returned item IDs, and read all matching pages. Every query respects Classic throttling. Scans stop when AH closes; pagination/throttling can extend the interval. Incomplete results retain the previous snapshot with a warning. Paginated market data is not atomic.

Classic shares its Browse results between addons: scans replace that list. Another search interrupts FlaskSeller and delays its next scan. Avoid running simultaneous scanners.

Posting always needs your explicit click. Post 1 uses Blizzard's native posting method directly from its click handler and leaves confirmation to Blizzard's dialog. No timers, scans or slash commands post auctions, and no protected-action restrictions are bypassed. If the client rejects custom posting, use Blizzard's Create Auction button. The item selector only reads your dragged item and clears its pickup cursor. Missing native preparation controls produce manual instructions instead.

Verified against Blizzard's Anniversary **2.5.6.69546** interface source and tested with a Lua 5.1 mock harness. **Live WoW testing is still required.** See [API notes and in-game checks](API_NOTES.md) for pinned sources, compatibility boundaries and test instructions.

## Panel helpers

The panel shows equipped-bag count, the age of the selected item's last complete check, and its last three status changes. The scanner rotates only after a complete result and remains on the same item while Classic throttling delays a query. Next recent selects from up to five previously dragged items without changing the scanning rotation.

Use /flask minimum COPPER to require a second Post 1 click when the suggested buyout is below that price. Use 0 to disable the guard. Use /flask quiet on or /flask quiet off to choose whether ordinary status transitions make a sound; quiet mode is on by default.
