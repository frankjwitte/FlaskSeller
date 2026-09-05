## API verification and automation boundaries

Inspected Blizzard-authored interface files from the [Gethe source mirror, pinned Anniversary commit d1a0a86](https://github.com/Gethe/wow-ui-source/tree/d1a0a86b449c78ee352e8851ef4b011add16a2ff) (2.5.6.69546):

- [Classic auction Lua](https://github.com/Gethe/wow-ui-source/blob/d1a0a86b449c78ee352e8851ef4b011add16a2ff/Interface/AddOns/Blizzard_AuctionUI/Classic/Blizzard_AuctionUI.lua): `QueryAuctionItems(text, minLevel, maxLevel, page, usable, rarity, getAll, exactMatch, filterData)`, `CanSendAuctionQuery("list")`, `GetNumAuctionItems`, and `GetAuctionItemInfo` (buyout position 10; owner/full owner 14/15; sale status 16; item ID 17; completeness 18).
- [Auction data](https://github.com/Gethe/wow-ui-source/blob/d1a0a86b449c78ee352e8851ef4b011add16a2ff/Interface/AddOns/Blizzard_AuctionUI/Classic/Blizzard_AuctionData.lua): 50 results per page.
- [Classic auction XML](https://github.com/Gethe/wow-ui-source/blob/d1a0a86b449c78ee352e8851ef4b011add16a2ff/Interface/AddOns/Blizzard_AuctionUI/Classic/Blizzard_AuctionUI.xml): native stack/quantity/money inputs and `AuctionPostMixin` button. Its Lua calls **`PostAuction`**, with a possible confirmation flow, rather than assuming historical `StartAuction` behavior.
- [Item API documentation](https://github.com/Gethe/wow-ui-source/blob/d1a0a86b449c78ee352e8851ef4b011add16a2ff/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua): `C_Item.GetItemInfo` and `C_Item.RequestLoadItemDataByID` for uncached localized names.

FlaskSeller does **not** use Retail's `C_AuctionHouse`. A capability check disables scanning if the verified Classic globals are missing. Native preparation controls are separately checked; if missing, the panel gives manual instructions.

Post 1 calls `C_Container.PickupContainerItem` for one matching equipped-bag item, then `ClickAuctionSellItemButton(AuctionsItemButton, "LeftButton", false)` to place that cursor item into Blizzard's sell slot. Both APIs were verified for TBC Anniversary. It then calls the verified `AuctionsCreateAuctionButton:StartPost(bid, buyout, duration, 1, 1, false)` method synchronously from the same `OnClick` handler. Blizzard's method invokes `PostAuction` and caches any pending confirmation on the native button; Blizzard's existing dialog calls its `ConfirmPost` method after the user's acceptance. FlaskSeller does not synthesize a native button click or acknowledge warnings itself. The selected item, quantity, price and duration are revalidated before the call. A failed path clears the cursor to return the bag item.

The C-side hardware-event/security implementation is not included in the interface Lua mirror, so live client testing remains necessary. Custom posting uses the direct user-click flow and does not attempt to bypass client enforcement. A rejected call produces a native-button fallback message, with no automatic retry. There is no posting from timers, scans or slash commands and no cancellation code.

Drag selection uses `C_Cursor.GetCursorItem()` to obtain an item location, `C_Item.GetItemID(location)` to read its ID, and `ClearCursor()` after successful selection. These APIs were verified in the same pinned commit's `CursorDocumentation.lua`, `ItemDocumentation.lua`, and `GameCursorDocumentation.lua` under `Blizzard_APIDocumentationGenerated`. The selector handles `OnReceiveDrag` and cursor clicks; it never picks up an item or places it into another inventory/sell slot. Unavailable APIs, non-item cursors and combat are rejected without clearing the cursor.

The addon passively hooks `PostAuction` and saves its per-flask price only after `AUCTION_MULTISELL_UPDATE` reports a created auction. Failure clears the candidate. This relies on the inspected native posting/event flow and must be checked in game; if your build differs, the configured fallback remains available.

The positive sale sound is driven by the yellow global `CHAT_MSG_SYSTEM` notification, not by scan-count changes or an open AH panel. FlaskSeller matches the localized Blizzard `ERR_AUCTION_SOLD_S` format string. A matching sale of the currently configured item plays `Interface\\AddOns\\FlaskSeller\\ffnice.ogg` on the Master channel; other sales use the native coin sound. It does not try to infer a sale from `POSSIBLY_SOLD`.

## Validation

The development `tests/` directory (outside the installed addon) contains a Lua 5.1 mock harness. From the repository root run `lua tests/test_flaskseller.lua`, or `python tests/run_tests.py` with `lupa` installed. No testing dependency is needed in WoW.

Before relying on it in game:

1. Open AH with no flask auction; verify market prices against Browse and the NO_AUCTION state.
2. Keep one configured flask in an equipped bag, then click Post 1. Verify exactly one auction is created and any Blizzard confirmation requires your acceptance. Wait for a complete scan and verify your price and status. Check that a missing bag item, changed form field, stale scan, and client rejection do not post.
3. Check a lower competitor, equal-price competitors, stacks, and a result set over 50 auctions.
4. Confirm a disappeared auction only produces a tentative alert after two completed scans.
5. Close AH during a scan, reopen, and run a different Browse search during scanning. Check that stale responses never become sale alerts.
6. Check that successful posting preserves the price after `/reload`, while a failed attempt does not.

Mock tests verify addon logic and API call shapes, not live server throttling, protected-action enforcement, taint, or visual layout. No live WoW session was available during development.

