local _, F = ...
local colors = { NO_AUCTION = {0.7, 0.7, 0.7}, COMPETITIVE = {0.25, 1, 0.35},
    UNDERCUT = {1, 0.3, 0.2}, POSSIBLY_SOLD = {1, 0.8, 0.15} }

function F:ReceiveItem()
    if not self.open or InCombatLockdown() then
        self:Notice("Open the AH and leave combat to select an item."); return
    end
    -- Verified Anniversary cursor/item-location APIs. Read the item only;
    -- clearing the cursor cancels its pickup without moving it to a sell slot.
    if not (C_Cursor and C_Cursor.GetCursorItem and C_Item and C_Item.GetItemID and ClearCursor) then
        self:Notice("Drag selection unavailable on this client; use /flask item ID."); return
    end
    local location = C_Cursor.GetCursorItem()
    if not location then self:Notice("Drag an item from your bags onto Drop item here."); return end
    local itemID = C_Item.GetItemID(location)
    if not self:AddWatchItem(itemID) then
        self:Notice("Watchlist is full (four items)."); return
    end
    if not self:SetItem(itemID) then
        self:Notice("Could not identify that item. Try dragging it from your bags again."); return
    end
    ClearCursor()
    self:Notice("Watching " .. (self.itemName or ("item " .. self:SelectedItemID()))
        .. (self.paused and ". Use Refresh now or turn Auto on." or ". Scanning automatically."))
end

function F:Prepare()
    self.prepared = nil
    if not self.open or InCombatLockdown() then self:Notice("Open the AH and leave combat to prepare."); return end
    if self.scan or self.manualRequested or not self.state.checked or GetTime() - self.state.checked > math.max(30, self.db.interval * 2) then
        self:Notice("Wait for a fresh complete scan before preparing."); return
    end
    local price = self.state.suggested
    if not price then return end
    -- Preparation only edits the form; Create 1 requires a separate real click.
    if not (AuctionFrameTab_OnClick and AuctionFrameTab3 and GetAuctionSellItemInfo
        and AuctionsStackSizeEntry and AuctionsNumStacksEntry and StartPrice and BuyoutPrice
        and MoneyInputFrame_SetCopper and UpdateDeposit) then
        self:Notice("Set one flask and buyout " .. self:Money(price) .. " manually in Blizzard's Auctions tab."); return
    end
    AuctionFrameTab_OnClick(AuctionFrameTab3)
    local itemID = select(10, GetAuctionSellItemInfo())
    if itemID ~= self:SelectedItemID() then
        self:Notice("Drag the configured flask into Blizzard's sell slot, then click Prepare 1 again."); return
    end
    AuctionsStackSizeEntry:SetNumber(1)
    AuctionsNumStacksEntry:SetNumber(1)
    MoneyInputFrame_SetCopper(StartPrice, price)
    MoneyInputFrame_SetCopper(BuyoutPrice, price)
    UpdateDeposit()
    self.prepared = {itemID = itemID, price = price,
        duration = AuctionFrameAuctions and AuctionFrameAuctions.duration}
    self:Notice("Prepared 1 at " .. self:Money(price) .. ". Review duration/deposit, then click Create 1 or Blizzard's Create Auction.")
end

function F:FindItemInBags()
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID) then return end
    -- 0 is the backpack; 1-4 are equipped bags in TBC Anniversary.
    for bag = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            if C_Container.GetContainerItemID(bag, slot) == self:SelectedItemID() then
                return bag, slot
            end
        end
    end
end

function F:PostOneProblem()
    if not self.open or InCombatLockdown() then return "Open the AH and leave combat to post." end
    if self.scan or self.manualRequested or not self.state.checked
        or GetTime() - self.state.checked > math.max(30, self.db.interval * 2) then
        return "Refresh first; posting uses the latest complete market result."
    end
    if self.state.status == "COMPETITIVE" then return "Your auction is competitive; no action needed." end
    if not self.state.suggested then return "No suggested price is available yet." end
    if not (AuctionFrameTab_OnClick and AuctionFrameTab3 and AuctionsItemButton
        and ClickAuctionSellItemButton and C_Container and C_Container.PickupContainerItem
        and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID
        and AuctionsStackSizeEntry and AuctionsNumStacksEntry and StartPrice and BuyoutPrice
        and MoneyInputFrame_SetCopper and UpdateDeposit and AuctionsFrameAuctions_ValidateAuction) then
        return "One-click posting is unavailable on this client. Use Prepare 1 instead."
    end
    if not self:FindItemInBags() then return "No configured item was found in your equipped bags." end
end

function F:PostOne()
    -- This runs only in the primary button's physical click handler. It does no
    -- timed posting and always posts exactly one item in one auction.
    local problem = self:PostOneProblem()
    if problem then self:Notice(problem); return end
    local price = self.state.suggested
    if self.db.minimumPrice > 0 and price < self.db.minimumPrice then
        local confirmation = self.lowPriceConfirmation
        if not confirmation or confirmation.price ~= price or GetTime() - confirmation.at > 10 then
            self.lowPriceConfirmation = { price = price, at = GetTime() }
            self:Notice("Price guard: " .. self:Money(price) .. " is below your minimum of "
                .. self:Money(self.db.minimumPrice) .. ". Click Post 1 again within 10 seconds to confirm.")
            return
        end
    end
    self.lowPriceConfirmation = nil
    local bag, slot = self:FindItemInBags()
    local ok, message = pcall(function()
        AuctionFrameTab_OnClick(AuctionFrameTab3)
        C_Container.PickupContainerItem(bag, slot)
        ClickAuctionSellItemButton(AuctionsItemButton, "LeftButton", false)
        if select(10, GetAuctionSellItemInfo()) ~= self:SelectedItemID() then
            error("The native sell slot did not accept the selected item.")
        end
        AuctionsStackSizeEntry:SetNumber(1)
        AuctionsNumStacksEntry:SetNumber(1)
        MoneyInputFrame_SetCopper(StartPrice, price)
        MoneyInputFrame_SetCopper(BuyoutPrice, price)
        AuctionsFrameAuctions_ValidateAuction()
        self.prepared = { itemID = self:SelectedItemID(), price = price,
            duration = AuctionFrameAuctions and AuctionFrameAuctions.duration }
        local postProblem = self:PostProblem()
        if postProblem then error(postProblem) end
        local prepared = self.prepared
        self.prepared = nil
        AuctionsCreateAuctionButton:StartPost(prepared.price, prepared.price, prepared.duration, 1, 1, false)
    end)
    if ok then
        self:Notice("Posting 1 at " .. self:Money(price) .. ". Complete any Blizzard confirmation.")
    else
        self.prepared = nil
        -- Returning a cursor item is safer than leaving it attached to the mouse.
        if ClearCursor then ClearCursor() end
        self:Notice("Could not post: " .. tostring(message) .. ". Use Prepare 1 if needed.")
    end
    self:Refresh()
end

function F:PostProblem()
    if not self.open or InCombatLockdown() then return "Open the AH and leave combat to create an auction." end
    local prepared = self.prepared
    if not prepared then return "Click Prepare 1 before creating an auction." end
    if not (AuctionsCreateAuctionButton and type(AuctionsCreateAuctionButton.StartPost) == "function"
        and type(PostAuction) == "function" and MoneyInputFrame_GetCopper and GetAuctionSellItemInfo
        and AuctionFrameAuctions and AuctionsStackSizeEntry and AuctionsNumStacksEntry and StartPrice and BuyoutPrice) then
        return "Custom posting unavailable on this client. Use Blizzard's Create Auction button."
    end
    if not self.state.checked or GetTime() - self.state.checked > math.max(30, self.db.interval * 2) then
        return "Prices are stale. Refresh and Prepare 1 again."
    end
    if prepared.itemID ~= self:SelectedItemID() or select(10, GetAuctionSellItemInfo()) ~= prepared.itemID then
        return "The sell item changed. Place the configured item in the sell slot and Prepare 1 again."
    end
    if prepared.price ~= self.state.suggested or MoneyInputFrame_GetCopper(StartPrice) ~= prepared.price
        or MoneyInputFrame_GetCopper(BuyoutPrice) ~= prepared.price
        or AuctionsStackSizeEntry:GetNumber() ~= 1 or AuctionsNumStacksEntry:GetNumber() ~= 1 then
        return "Price or quantity changed. Review the suggestion and click Prepare 1 again."
    end
    if not prepared.duration or prepared.duration < 1 or prepared.duration > 3
        or prepared.duration ~= AuctionFrameAuctions.duration then
        return "Choose the duration in Blizzard's Auctions tab, then Prepare 1 again."
    end
    if not AuctionFrameAuctions:IsShown() or not AuctionsCreateAuctionButton:IsEnabled()
        or AuctionsCreateAuctionButton.pendingPost then
        return "Finish any Blizzard confirmation and check the native sell form before posting."
    end
end

function F:CreateAuction()
    -- Called ONLY by our button's OnClick. Never from a timer, scan or slash command.
    local problem = self:PostProblem()
    if problem then self:Notice(problem); return end
    local prepared = self.prepared
    self.prepared = nil -- A second click cannot submit this preparation twice.
    self:Refresh()
    -- Reuse Blizzard's verified method, not a synthetic button click. StartPost
    -- calls PostAuction(..., false) and caches any pending confirmation on the
    -- native button, which Blizzard's own confirmation dialog already uses.
    local ok = pcall(AuctionsCreateAuctionButton.StartPost, AuctionsCreateAuctionButton,
        prepared.price, prepared.price, prepared.duration, 1, 1, false)
    if ok then
        self:Notice("Posting requested. Complete any Blizzard confirmation and wait for the auction result.")
    else
        self:Notice("Client rejected custom posting. Review the native form and use Blizzard's Create Auction button.")
    end
end

function F:CreateUI()
    if self.panel then return end
    local panel = CreateFrame("Frame", "FlaskSellerPanel", UIParent, "BackdropTemplate")
    self.panel = panel
    panel:SetSize(310, 660)
    panel:SetPoint("TOPLEFT", AuctionFrame or UIParent, "TOPRIGHT", 8, -20)
    panel:SetClampedToScreen(true)
    panel:SetFrameStrata("DIALOG")
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(0.035, 0.043, 0.055, 0.98)
    panel:SetBackdropBorderColor(0.28, 0.25, 0.18, 1)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    local function label(parent, x, y, width, template)
        local text = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", x, y)
        text:SetWidth(width)
        text:SetJustifyH("LEFT")
        text:SetJustifyV("TOP")
        return text
    end
    local function fill(parent, x, y, width, height, r, g, b, alpha)
        local texture = parent:CreateTexture(nil, "BACKGROUND")
        texture:SetPoint("TOPLEFT", x, y)
        texture:SetSize(width, height)
        texture:SetColorTexture(r, g, b, alpha or 1)
        return texture
    end
    local function button(x, y, width, height, text, click, primary)
        local b = CreateFrame("Button", nil, panel, "BackdropTemplate")
        b:SetPoint("TOPLEFT", x, y)
        b:SetSize(width, height)
        b:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        b:SetBackdropColor(primary and 0.24 or 0.085, primary and 0.18 or 0.10, primary and 0.075 or 0.125, 1)
        b:SetBackdropBorderColor(primary and 0.65 or 0.22, primary and 0.48 or 0.25, primary and 0.20 or 0.29, 1)
        local caption = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        caption:SetPoint("CENTER")
        b:SetFontString(caption)
        b:SetNormalFontObject("GameFontHighlightSmall")
        b:SetHighlightFontObject("GameFontNormalSmall")
        b:SetDisabledFontObject("GameFontDisableSmall")
        b:SetText(text)
        local glow = b:CreateTexture(nil, "HIGHLIGHT")
        glow:SetAllPoints()
        glow:SetColorTexture(1, 0.85, 0.55, 0.09)
        b:SetHighlightTexture(glow)
        b:SetScript("OnClick", click)
        return b
    end
    fill(panel, 1, -1, 308, 2, 0.72, 0.54, 0.25)
    panel.title = label(panel, 16, -16, 180, "GameFontNormal")
    panel.title:SetText("FlaskSeller")
    panel.title:SetTextColor(0.90, 0.73, 0.43)
    panel.modeButton = button(190, -10, 104, 24, "Lowest page", function() F:ToggleScanMode() end)
    panel.itemSlot = CreateFrame("Button", nil, panel, "BackdropTemplate")
    panel.itemSlot:SetSize(278, 58)
    panel.itemSlot:SetPoint("TOPLEFT", 16, -47)
    panel.itemSlot:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})
    panel.itemSlot:SetBackdropColor(0.065, 0.077, 0.095, 1)
    panel.icon = panel.itemSlot:CreateTexture(nil, "ARTWORK")
    panel.icon:SetPoint("TOPLEFT", 8, -8)
    panel.icon:SetSize(42, 42)
    panel.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    panel.item = label(panel.itemSlot, 60, -8, 210, "GameFontHighlight")
    panel.item:SetHeight(29)
    local dropHint = label(panel.itemSlot, 60, -40, 210)
    dropHint:SetText("Drop item here to change")
    dropHint:SetTextColor(0.62, 0.65, 0.70)
    panel.itemSlot:SetScript("OnReceiveDrag", function() F:ReceiveItem() end)
    panel.itemSlot:SetScript("OnClick", function() F:ReceiveItem() end)
    dropHint:SetText("Drop an item here to add (up to 4)")
    panel.rows = {}
    for index = 1, 4 do
        local row = CreateFrame("Button", nil, panel, "BackdropTemplate")
        row:SetPoint("TOPLEFT", 16, -112 - (index - 1) * 38)
        row:SetSize(278, 36)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        row.name = label(row, 8, -4, 190, "GameFontHighlightSmall")
        row.status = label(row, 200, -4, 44, "GameFontHighlightSmall")
        row.details = label(row, 8, -19, 248, "GameFontHighlightSmall")
        row.details:SetTextColor(0.62, 0.65, 0.70)
        row.remove = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.remove:SetPoint("TOPRIGHT", -4, -8)
        row.remove:SetSize(18, 18)
        row.remove:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        row.remove:SetBackdropColor(0.25, 0.08, 0.08, 1)
        local removeText = row.remove:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        removeText:SetPoint("CENTER")
        row.remove:SetFontString(removeText)
        row.remove:SetText("x")
        row:SetScript("OnClick", function(self) if self.itemID then F:SelectWatchItem(self.itemID) end end)
        row.remove:SetScript("OnClick", function(self) if self.itemID then F:RemoveWatchItem(self.itemID) end end)
        panel.rows[index] = row
    end
    local yours = label(panel, 16, -280, 134)
    yours:SetText("YOUR LOWEST")
    yours:SetTextColor(0.56, 0.60, 0.66)
    local market = label(panel, 164, -280, 130)
    market:SetText("MARKET LOWEST")
    market:SetTextColor(0.56, 0.60, 0.66)
    panel.ownPrice = label(panel, 16, -299, 134, "GameFontHighlight")
    panel.marketPrice = label(panel, 164, -299, 130, "GameFontHighlight")
    fill(panel, 16, -326, 278, 1, 0.16, 0.18, 0.21)
    panel.indicator = fill(panel, 17, -343, 6, 6, 0.6, 0.6, 0.6)
    panel.status = label(panel, 32, -339, 262, "GameFontHighlightSmall")
    fill(panel, 16, -364, 278, 54, 0.10, 0.093, 0.075)
    local suggestionLabel = label(panel, 28, -373, 250)
    suggestionLabel:SetText("SUGGESTED BUYOUT / ITEM")
    suggestionLabel:SetTextColor(0.68, 0.62, 0.48)
    panel.suggested = label(panel, 28, -392, 250, "GameFontNormalLarge")
    panel.suggested:SetTextColor(1, 0.82, 0.44)
    panel.button = button(16, -427, 278, 32, "Post 1", function() F:PostOne() end, true)
    panel.meta = label(panel, 16, -467, 278)
    panel.meta:SetTextColor(0.56, 0.60, 0.66)
    panel.refreshButton = button(16, -488, 135, 28, "Refresh now", function() F:ManualRefresh() end)
    panel.scanButton = button(159, -488, 135, 28, "Auto: On", function() F:ToggleScanning() end)
    panel.recentButton = button(16, -525, 135, 24, "Next recent", function() F:UseNextRecentItem() end)
    panel.quietButton = button(159, -525, 135, 24, "Quiet: On", function()
        F.db.quietMode = not F.db.quietMode
        F:Refresh()
    end)
    panel.history = label(panel, 16, -560, 278)
    panel.history:SetTextColor(0.56, 0.60, 0.66)
    panel.note = label(panel, 16, -583, 278)
    panel.note:SetHeight(50)
    panel.note:SetTextColor(0.64, 0.68, 0.74)
    self:Refresh()
end

function F:UpdateUI()
    local p, s = self.panel, self.state
    if not p then return end
    p.item:SetText(self.itemName or ("Item " .. self:SelectedItemID()))
    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(self:SelectedItemID())
    p.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    for index, row in ipairs(p.rows or {}) do
        local itemID = (self.db.watchItems or {})[index]
        if itemID then
            local itemState = self:StateFor(itemID)
            local name = getInfo and getInfo(itemID) or ("Item " .. itemID)
            local selected = itemID == self:SelectedItemID()
            local state = itemState.checked and itemState.status or "WAITING"
            row.itemID, row.remove.itemID = itemID, itemID
            row.name:SetText((selected and "> " or "  ") .. name)
            local shortStatus = { COMPETITIVE = "OK", UNDERCUT = "LOW", NO_AUCTION = "NONE", POSSIBLY_SOLD = "SOLD", WAITING = "..." }
            row.status:SetText(shortStatus[state] or state)
            local statusColor = colors[itemState.status] or colors.NO_AUCTION
            row.status:SetTextColor(unpack(statusColor))
            row.details:SetText("Y " .. self:Money(itemState.own) .. "   M " .. self:Money(itemState.market)
                .. "   P " .. self:Money(itemState.suggested))
            row:SetBackdropColor(selected and 0.14 or 0.055, selected and 0.11 or 0.064, selected and 0.065 or 0.078, 1)
            row:SetBackdropBorderColor(selected and 0.72 or 0.18, selected and 0.54 or 0.20, selected and 0.25 or 0.24, 1)
            row.remove:SetEnabled(#(self.db.watchItems or {}) > 1)
        else
            row.itemID, row.remove.itemID = nil, nil
            row.name:SetText("+ Empty watch slot")
            row.status:SetText("")
            row.details:SetText("Drop a flask above to add it")
            row:SetBackdropColor(0.045, 0.052, 0.064, 1)
            row:SetBackdropBorderColor(0.12, 0.14, 0.17, 1)
            row.remove:SetEnabled(false)
        end
        row:Show()
    end
    p.ownPrice:SetText(self:Money(s.own))
    p.marketPrice:SetText(self:Money(s.market))
    p.status:SetText("Status: " .. (s.checked and s.status or (self.paused and not self.manualRequested and "PAUSED" or "WAITING")))
    local color = colors[s.checked and s.status or "NO_AUCTION"]
    p.status:SetTextColor(unpack(color))
    p.indicator:SetColorTexture(color[1], color[2], color[3], 1)
    p.suggested:SetText(self:Money(s.suggested))
    local checked = s.checked and math.max(0, math.floor(GetTime() - s.checked)) or nil
    p.meta:SetText("Watching " .. #(self.db.watchItems or {}) .. "/4 | In bags: " .. self:CountItemsInBags() .. "   |   Last check: "
        .. (checked and (checked .. "s ago") or "not yet"))
    p.history:SetText("Recent: " .. ((s.history and #s.history > 0) and table.concat(s.history, " -> ") or "-"))
    p.note:SetText(s.note or "")
    p.button:SetEnabled(self:PostOneProblem() == nil)
    if s.status == "COMPETITIVE" then p.button:SetText("All good — no action needed")
    elseif s.checked then p.button:SetText("Post 1 at " .. self:Money(s.suggested))
    else p.button:SetText("Waiting for market check") end
    if self.paused then
        p.scanButton:SetText("Auto: Off")
    elseif self.scan then
        p.scanButton:SetText(self.manualRequested and "Auto: manual" or "Auto: checking")
    elseif self.nextScan and self.nextScan > GetTime() then
        p.scanButton:SetText("Auto: On (" .. math.ceil(self.nextScan - GetTime()) .. "s)")
    else
        p.scanButton:SetText("Auto: waiting")
    end
    p.refreshButton:SetEnabled(self.scan == nil and not self.manualRequested)
    p.refreshButton:SetText((self.scan or self.manualRequested) and "Checking..." or "Refresh now")
    p.modeButton:SetText(self.db.lowestPageOnly and "Lowest page" or "All pages")
    p.quietButton:SetText(self.db.quietMode and "Quiet: On" or "Quiet: Off")
    p.recentButton:SetEnabled(self.db.recentItems and #self.db.recentItems > 1)
end
