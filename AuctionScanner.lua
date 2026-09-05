local _, F = ...

-- Verified against Blizzard's classic_anniversary 2.5.6 UI; see README.
-- Classic accepts a localized exact NAME, not an item ID. Validate returned IDs too.
local PAGE_SIZE = 50

function F:ToggleScanMode()
    self.db.lowestPageOnly = not self.db.lowestPageOnly
    self:Reset()
    self:Notice(self.db.lowestPageOnly and "Lowest-page mode: cheapest buyouts first; using My Auctions for your listings."
        or "All-pages mode: scan every matching market page.")
end

function F:ReadOwnAuctions()
    -- Blizzard requests this list when AH opens and subsequently updates it.
    -- Do not turn an unloaded/partial owner buffer into a missing-auction alert.
    if not self.ownersReady then return end
    local batch, total = GetNumAuctionItems("owner")
    if not batch or batch ~= total then return end
    local lowest, count = nil, 0
    for index = 1, batch do
        local name, _, quantity, _, _, _, _, _, _, buyout, _, _, _, _, _, saleStatus, itemID =
            GetAuctionItemInfo("owner", index)
        if not name or not itemID or not quantity or quantity < 1 or not buyout or saleStatus == nil then return end
        if itemID == self.db.itemID and saleStatus == 0 then
            count = count + 1
            if buyout > 0 then lowest = lowest and math.min(lowest, buyout / quantity) or buyout / quantity end
        end
    end
    return true, lowest, count
end

function F:ManualRefresh()
    if not self.open then self:Notice("Open the Auction House to refresh."); return end
    if self.scan or self.manualRequested then return end
    -- Run exactly one complete scan without changing the automatic mode.
    self.manualRequested = true
    self.nextScan = GetTime()
    self:Notice("Manual refresh requested; waiting for the Auction House.")
    self:Tick()
end

function F:ToggleScanning()
    self.paused = not self.paused
    -- A sent request cannot be recalled, but its response must not update us.
    self.scan = nil
    self.manualRequested = nil
    if self.paused then
        self:Notice("Automatic checks are off. Use Refresh now for a single check.")
    else
        -- Do not infer sales across a gap in monitoring.
        self.previousCount, self.missingScans, self.possiblySold = nil, nil, nil
        self.nextScan = GetTime()
        self:Notice("Checks resumed. Waiting for a fresh scan.")
    end
end

function F:InstallHooks()
    self.apiOK = type(QueryAuctionItems) == "function" and type(CanSendAuctionQuery) == "function"
        and type(GetNumAuctionItems) == "function" and type(GetAuctionItemInfo) == "function"
    if not self.apiOK then return end
    hooksecurefunc("QueryAuctionItems", function()
        if F.sending then return end
        -- The Classic result buffer is shared with Browse and other addons.
        -- Never interpret someone else's query as a missing/sold flask.
        if F.open and (not F.paused or F.manualRequested) then
            F.scan = nil
            F.manualRequested = nil
            F.nextScan = GetTime() + F.db.interval
            F:Notice(F.paused and "Refresh interrupted by another search. Click Refresh now to retry."
                or "Other auction search detected; waiting before resuming.")
        end
    end)
    -- An external sort can reorder the shared buffer while we are reading it.
    local function otherSort(kind)
        if kind == "list" and F.scan and not F.sending then
            F:AbortScan("Auction sorting changed; scan interrupted.")
        end
    end
    if SortAuctionClearSort then hooksecurefunc("SortAuctionClearSort", otherSort) end
    if SortAuctionSetSort then hooksecurefunc("SortAuctionSetSort", otherSort) end
    -- Observe Blizzard's posting call; never invoke it ourselves. Record only
    -- after AUCTION_MULTISELL_UPDATE reports a successful creation.
    if type(PostAuction) == "function" and type(GetAuctionSellItemInfo) == "function" then
        hooksecurefunc("PostAuction", function(_, buyout, _, quantity)
            local itemID = select(10, GetAuctionSellItemInfo())
            F.pendingPost = nil
            if F.open and itemID == F.db.itemID and buyout and buyout > 0 and quantity and quantity > 0 then
                F.pendingPost = math.floor(buyout / quantity)
            end
        end)
    end
end

function F:AbortScan(note)
    self.scan = nil
    self.manualRequested = nil
    self.nextScan = GetTime() + self.db.interval
    self:Notice(note .. " Keeping the last complete result.")
end

local function isMine(owner, fullName)
    local player, realm = UnitFullName("player")
    realm = (realm or GetRealmName()):gsub("%s", "")
    if fullName and fullName ~= "" then
        local name, otherRealm = fullName:match("^([^-]+)%-(.+)$")
        if name then return name == player and otherRealm:gsub("%s", "") == realm end
        return fullName == player
    end
    return owner == player
end

function F:ReadPage()
    local scan = self.scan
    local batch, total = GetNumAuctionItems("list")
    if not batch or not total then return end
    if scan.total and scan.total ~= total then
        self:AbortScan("Auction count changed during pagination; retrying."); return
    end
    if batch ~= math.min(PAGE_SIZE, math.max(0, total - scan.page * PAGE_SIZE)) then return end
    local own, market, count = scan.own, scan.market, scan.count
    for index = 1, batch do
        local name, _, quantity, _, _, _, _, _, _, buyout, _, _, _, owner, fullName, saleStatus, itemID, complete =
            GetAuctionItemInfo("list", index)
        -- Missing owners/data must never be interpreted as a competitor or disappearance.
        if not name or not complete or not itemID or not quantity or quantity < 1
            or not buyout or (not owner or owner == "") and (not fullName or fullName == "") then return end
        if itemID == self.db.itemID and (not saleStatus or saleStatus == 0) then
            local mine = isMine(owner, fullName)
            if mine then count = count + 1 end
            if buyout > 0 then
                local unit = buyout / quantity
                if mine then own = own and math.min(own, unit) or unit
                else market = market and math.min(market, unit) or unit end
            end
        end
    end
    scan.total, scan.own, scan.market, scan.count = total, own, market, count
    local morePages = (scan.page + 1) * PAGE_SIZE < total
    local usedOwners = false
    if morePages and scan.lowestFirst and market then
        local ready, ownerLowest, ownerCount = self:ReadOwnAuctions()
        -- Cross-check any own listings already seen against the owner cache.
        if ready and ownerCount >= count and (not own or (ownerLowest and ownerLowest <= own)) then
            own, count, morePages, usedOwners = ownerLowest, ownerCount, false, true
        end
    end
    if morePages then
        scan.page = scan.page + 1
        scan.waiting, scan.received = false, false
    else
        self.scan = nil
        self.manualRequested = nil
        self.nextScan = GetTime() + self.db.interval
        self:CommitScan(own, market, count)
        if usedOwners then
            self:Notice(self.state.note .. " Cheapest market prices checked; your listings verified in My Auctions.")
        end
    end
end

function F:Tick()
    if not self.open or (self.paused and not self.manualRequested) then return end
    if not self.apiOK then
        self.manualRequested = nil
        self:Notice("Classic auction APIs unavailable. This client is unsupported."); return
    end
    local now = GetTime()
    if self.scan then
        if now - self.scan.started > 120 or (self.scan.sentAt and now - self.scan.sentAt > 20 and self.scan.waiting) then
            self:AbortScan("Scan timed out or item data incomplete; retrying."); return
        end
        if self.scan.waiting then
            if self.scan.received and now >= self.scan.readAt then self:ReadPage() end
            return
        end
    elseif now < (self.nextScan or 0) then return
    else
        local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
        local name = getInfo and getInfo(self.db.itemID)
        if not name then
            if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(self.db.itemID) end
            self.nextScan = now + self.db.interval
            self.manualRequested = nil
            self:Notice("Loading item name; refresh again shortly. Check /flask item if this persists."); return
        end
        self.itemName = name
        self.scan = { name = name, page = 0, count = 0, started = now,
            lowestFirst = self.db.lowestPageOnly and type(SortAuctionClearSort) == "function"
                and type(SortAuctionSetSort) == "function" }
    end
    if not CanSendAuctionQuery("list") then
        self:Notice("Waiting for the Auction House query throttle."); return
    end
    local scan = self.scan
    scan.waiting, scan.received, scan.sentAt = true, false, now
    self:Notice("Scanning item, page " .. (scan.page + 1) .. "... Previous prices may be stale.")
    self.sending = true
    local ok = pcall(function()
        if scan.lowestFirst then
            -- Same sort key used by Blizzard's per-unit buyout sort, ascending.
            SortAuctionClearSort("list")
            SortAuctionSetSort("list", "unitprice", false)
        end
        QueryAuctionItems(scan.name, nil, nil, scan.page, false, nil, false, true, nil)
    end)
    self.sending = false
    if not ok then self:AbortScan("Classic query rejected by the client; retrying.") end
end
