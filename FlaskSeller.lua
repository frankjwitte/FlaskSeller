local _, F = ...

local SALE_SOUND_FILE = "Interface\\AddOns\\FlaskSeller\\ffnice.ogg"
local defaults = { itemID = 22851, interval = 10, undercut = 1,
    fallback = 250000, lastPostedPrice = 0, minimumPrice = 0,
    undercutSound = true, quietMode = true }
F.state = { status = "NO_AUCTION", note = "Open the Auction House to scan." }

function F:Money(copper)
    if not copper then return "--" end
    copper = math.floor(copper)
    return string.format("%dg %ds %dc", math.floor(copper / 10000),
        math.floor(copper / 100) % 100, copper % 100)
end

function F:Refresh()
    if self.UpdateUI then self:UpdateUI() end
end

function F:Notice(text)
    self.state.note = text
    self:Refresh()
end

function F:Suggested(market, state)
    state = state or self.state or {}
    if market then return math.max(1, math.floor(market - self.db.undercut)) end
    return state.lastPostedPrice and state.lastPostedPrice > 0 and state.lastPostedPrice or self.db.fallback
end

function F:AddHistory(status)
    self.history = self.history or {}
    if self.history[1] == status then return end
    table.insert(self.history, 1, status)
    while #self.history > 3 do table.remove(self.history) end
end

function F:CountItemsInBags()
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID) then return 0 end
    local count = 0
    for bag = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            if C_Container.GetContainerItemID(bag, slot) == self:SelectedItemID() then
                local info = C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
                count = count + (info and info.stackCount or 1)
            end
        end
    end
    return count
end

function F:SelectedItemID()
    return self.db.selectedItemID or self.db.itemID
end

function F:StateFor(itemID)
    self.db.itemStates = type(self.db.itemStates) == "table" and self.db.itemStates or {}
    local state = self.db.itemStates[itemID]
    if type(state) ~= "table" then
        state = { status = "NO_AUCTION", note = "Waiting for this item's first scan.", lastPostedPrice = 0 }
        self.db.itemStates[itemID] = state
    end
    return state
end

function F:CommitScan(itemID, own, market, count)
    local state = self:StateFor(itemID)
    local previousStatus, previousChecked = state.status, state.checked
    if state.saleBaseline and count < state.saleBaseline then
        state.missingScans = (state.missingScans or 0) + 1
        if state.missingScans >= 2 then state.possiblySold, state.saleBaseline = true, count end
    else
        if state.saleBaseline and count > state.saleBaseline then state.possiblySold = false end
        state.saleBaseline, state.missingScans = count, 0
    end
    local status = "NO_AUCTION"
    if count > 0 then status = (not own or (market and own > market)) and "UNDERCUT" or "COMPETITIVE" end
    if state.possiblySold and status ~= "UNDERCUT" then status = "POSSIBLY_SOLD" end
    state.own, state.market, state.count, state.status = own, market, count, status
    state.suggested, state.checked = self:Suggested(market, state), GetTime()
    state.note = state.possiblySold and "An auction disappeared; sale, expiry or cancellation. Check before replacing."
        or (status == "UNDERCUT" and "Post one at the suggested price; keep older auctions.")
        or (status == "COMPETITIVE" and "Your lowest auction is competitive.")
        or "No active auction found. Prepare one flask."
    if itemID == self:SelectedItemID() then self.lowPriceConfirmation = nil end
    state.history = state.history or {}
    if state.history[1] ~= status then
        table.insert(state.history, 1, status)
        while #state.history > 3 do table.remove(state.history) end
    end
    if market and market <= 1 then state.note = "Market is at 1 copper; a lower positive price is impossible." end
    local alert = not previousChecked or previousStatus ~= status
    local sound = status ~= "COMPETITIVE" and status ~= "POSSIBLY_SOLD" and SOUNDKIT and SOUNDKIT.RAID_WARNING
    if self.db.undercutSound and alert and sound and type(PlaySound) == "function" then PlaySound(sound) end
    self.state = self:StateFor(self:SelectedItemID())
    self:Refresh()
end

function F:Reset()
    self.manualRequested, self.prepared, self.scan, self.lowPriceConfirmation = nil, nil, nil, nil
    self.nextScan = GetTime() + 1
    self.state = self:StateFor(self:SelectedItemID())
    self.state.saleBaseline, self.state.missingScans, self.state.possiblySold = nil, nil, nil
    self:Refresh()
end

local function reply(text) print("|cffffd100FlaskSeller:|r " .. text) end
local limits = { item = {"itemID", 1, 2147483647}, interval = {"interval", 5, 3600},
    undercut = {"undercut", 1, 2147483647}, fallback = {"fallback", 1, 2147483647},
    minimum = {"minimumPrice", 0, 2147483647} }

function F:RememberItem(itemID)
    local recent = self.db.recentItems
    if type(recent) ~= "table" then recent = {}; self.db.recentItems = recent end
    for index = #recent, 1, -1 do if recent[index] == itemID then table.remove(recent, index) end end
    table.insert(recent, 1, itemID)
    while #recent > 5 do table.remove(recent) end
end

function F:UseNextRecentItem()
    local recent = self.db.recentItems or {}
    if #recent < 2 then self:Notice("Drag another flask here first to build your recent list."); return end
    local current = 1
    for index, itemID in ipairs(recent) do if itemID == self.db.itemID then current = index; break end end
    local itemID = recent[current % #recent + 1]
    self:SetItem(itemID)
    self:Notice("Watching recent item " .. (self.itemName or ("item " .. itemID)) .. ".")
end

function F:AddWatchItem(itemID)
        if type(itemID) ~= "number" or itemID ~= math.floor(itemID) or itemID < 1 or itemID > 2147483647 then return false end
local list = self.db.watchItems or {}
    self.db.watchItems = list
    for _, id in ipairs(list) do if id == itemID then return true end end
    if #list >= 4 then return false end
    table.insert(list, itemID)
    self:StateFor(itemID)
    return true
end

function F:SelectWatchItem(itemID)
    if not self:AddWatchItem(itemID) then return false end
    self.db.selectedItemID, self.db.itemID = itemID, itemID -- itemID remains a legacy saved-variable alias.
    local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    self.itemName = getInfo and getInfo(itemID)
    self.state = self:StateFor(itemID)
    self.db.lastPostedPrice = self.state.lastPostedPrice or 0
    self:Refresh()
    return true
end

function F:AdvanceWatchItem()
    local list = self.db.watchItems or {}
    if #list > 0 then self.scanCursor = (self.scanCursor or 1) % #list + 1 end
end

function F:SetItem(itemID)
    if type(itemID) ~= "number" or itemID ~= math.floor(itemID) or itemID < 1 or itemID > 2147483647 then return false end
    if not self:AddWatchItem(itemID) then return false end
    self.pendingPost, self.soldCount = nil, nil
    self:RememberItem(itemID)
    return self:SelectWatchItem(itemID)
end

function F:RemoveWatchItem(itemID)
    local list = self.db.watchItems or {}
    if #list <= 1 then return false end
    for index, id in ipairs(list) do
        if id == itemID then
            table.remove(list, index)
            self.db.itemStates[itemID] = nil
            if self:SelectedItemID() == itemID then self:SelectWatchItem(list[math.min(index, #list)]) end
            if self.scanCursor and self.scanCursor > #list then self.scanCursor = 1 end
            self:Refresh()
            return true
        end
    end
    return false
end

function F:GetAuctionSoldMessageItem(message)
    if type(message) ~= "string" or type(ERR_AUCTION_SOLD_S) ~= "string" then return end
    -- Build a Lua pattern from Blizzard's localized format string. The item
    -- name is the sole %s argument, so this works in every client locale.
    local before, after = ERR_AUCTION_SOLD_S:match("^(.-)%%s(.-)$")
    if not before then return end
    local function escape(value) return (value:gsub("([^%w])", "%%%1")) end
    return message:match("^" .. escape(before) .. "(.+)" .. escape(after) .. "$")
end

function F:PlaySaleSound(itemName)
    if not self.db.undercutSound then return end
    -- Use one distinct sale sound for every confirmed Blizzard sale notice.
    -- It works with the AH panel closed and avoids the common coin sound.
    if type(PlaySoundFile) == "function" then
        PlaySoundFile(SALE_SOUND_FILE, "Master")
    end
end

function F:ShowPanel()
    if not self.open then
        self:Notice("Open the Auction House to show FlaskSeller.")
        return false
    end
    self:CreateUI()
    self.panel:Show()
    self:Refresh()
    return true
end
function F:Command(message)
    local command, arg = message:match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "show" then self:ShowPanel(); return end
    if command == "" or command == "status" then
        reply(string.format("Item %d | %s%s | Yours %s | Market %s | Suggested %s",
            self.db.itemID, self.paused and "PAUSED" or self.state.status,
            self.state.checked and " (last complete scan)" or " (unverified)",
            self:Money(self.state.own), self:Money(self.state.market), self:Money(self.state.suggested)))
        reply(self.state.note)
        return
    end
    if command == "quiet" then
        local value = arg:lower()
        if value == "" then reply("quiet mode = " .. (self.db.quietMode and "on" or "off")); return end
        if value ~= "on" and value ~= "off" then reply("Use /flask quiet on or /flask quiet off."); return end
        self.db.quietMode = value == "on"
        reply("Quiet mode " .. value .. ".")
        self:Refresh()
        return
    end
    if command == "sound" then
        local value = arg:lower()
        if value == "" then reply("sound = " .. (self.db.undercutSound and "on" or "off")); return end
        if value ~= "on" and value ~= "off" then reply("Use /flask sound on or /flask sound off."); return end
        self.db.undercutSound = value == "on"
        reply("Undercut alert sound " .. value .. ".")
        return
    end
    local rule = limits[command]
    if not rule then
        reply("/flask show | status | item [ID] | interval [seconds] | undercut [copper] | fallback [copper] | minimum [copper] | sound [on/off] | quiet [on/off]")
        return
    end
    if arg == "" then reply(command .. " = " .. self.db[rule[1]]); return end
    local value = tonumber(arg)
    if not value or value ~= math.floor(value) or value < rule[2] or value > rule[3] then
        reply("Use a whole number from " .. rule[2] .. " to " .. rule[3] .. "."); return
    end
    if command == "item" then
        self:SetItem(value)
    else
        self.db[rule[1]] = value
        self:Reset()
    end
    reply(command .. " = " .. value)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
events:RegisterEvent("AUCTION_OWNED_LIST_UPDATE")
events:RegisterEvent("CHAT_MSG_SYSTEM")
events:RegisterEvent("AUCTION_MULTISELL_UPDATE")
events:RegisterEvent("AUCTION_MULTISELL_FAILURE")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= "FlaskSeller" then return end
        FlaskSellerDB = type(FlaskSellerDB) == "table" and FlaskSellerDB or {}
        F.db = FlaskSellerDB
        if type(F.db.lowestPageOnly) ~= "boolean" then F.db.lowestPageOnly = true end
        for key, value in pairs(defaults) do
            local n = F.db[key]
            if type(value) == "number" and (type(n) ~= "number" or n ~= n or n < 0 or n > 2147483647 or n ~= math.floor(n)) then
                F.db[key] = value
            elseif type(value) == "boolean" and type(n) ~= "boolean" then F.db[key] = value end
        end
        if type(F.db.recentItems) ~= "table" then F.db.recentItems = {} end
        local savedWatch = type(F.db.watchItems) == "table" and F.db.watchItems or { F.db.itemID }
        F.db.watchItems, F.db.itemStates = {}, type(F.db.itemStates) == "table" and F.db.itemStates or {}
        for _, itemID in ipairs(savedWatch) do F:AddWatchItem(itemID) end
        F.db.selectedItemID = F.db.selectedItemID or F.db.itemID
        if not F:AddWatchItem(F.db.selectedItemID) then F.db.selectedItemID = F.db.watchItems[1] or defaults.itemID; F:AddWatchItem(F.db.selectedItemID) end
        F:StateFor(F.db.selectedItemID).lastPostedPrice = F.db.lastPostedPrice or F:StateFor(F.db.selectedItemID).lastPostedPrice or 0
        F.scanCursor = 1
        F:SelectWatchItem(F.db.selectedItemID)
        for _, rule in pairs(limits) do
            if F.db[rule[1]] < rule[2] or F.db[rule[1]] > rule[3] then
                F.db[rule[1]] = defaults[rule[1]]
            end
        end
        SLASH_FLASKSELLER1 = "/flask"
        SlashCmdList.FLASKSELLER = function(msg) F:Command(msg) end
        F:InstallHooks()
    elseif F.db then
        if event == "AUCTION_HOUSE_SHOW" then
            F.open = true
            F.ownersReady = false
            F:Reset()
            F:CreateUI()
            F.panel:Show()
        elseif event == "AUCTION_HOUSE_CLOSED" then
            F.open, F.scan, F.pendingPost = false, nil, nil
            F.ownersReady = false
            F.prepared = nil
            F.manualRequested = nil
            if F.panel then F.panel:Hide() end
        elseif event == "AUCTION_OWNED_LIST_UPDATE" and F.open then
            F.ownersReady = true
        elseif event == "CHAT_MSG_SYSTEM" then
            local itemName = F:GetAuctionSoldMessageItem(...)
            if not itemName then return end
            -- This is Blizzard's yellow global sale notification. It is sent
            -- while logged in even if the Auction House panel is closed.
            F:PlaySaleSound(itemName)
        elseif event == "AUCTION_ITEM_LIST_UPDATE" and F.scan and F.scan.waiting then
            F.scan.received = true
            F.scan.readAt = GetTime() + 0.3
        elseif event == "AUCTION_MULTISELL_FAILURE" then
            F.pendingPost = nil
        elseif event == "AUCTION_MULTISELL_UPDATE" then
            local created = ...
            if F.pendingPost and created and created > 0 then
                local posted = F:StateFor(F.pendingPost.itemID)
                posted.lastPostedPrice = F.pendingPost.price
                if F.pendingPost.itemID == F:SelectedItemID() then F.db.lastPostedPrice = posted.lastPostedPrice end
                F.pendingPost = nil
                F:Reset()
            end
        end
    end
end)
local elapsed = 0
events:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.25 then return end
    elapsed = 0
    if F.open and F.db then
        F:Tick()
        -- Keep the auto-check countdown and native action readiness current.
        F:Refresh()
    end
end)
