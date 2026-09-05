local _, F = ...

local SALE_SOUND_FILE = "Interface\\AddOns\\FlaskSeller\\ffnice.ogg"
local defaults = { itemID = 22851, interval = 10, undercut = 1,
    fallback = 250000, lastPostedPrice = 0, undercutSound = true }
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

function F:Suggested(market)
    if market then return math.max(1, math.floor(market - self.db.undercut)) end
    return self.db.lastPostedPrice > 0 and self.db.lastPostedPrice or self.db.fallback
end

function F:CommitScan(own, market, count)
    local previousStatus = self.state and self.state.status
    local previousChecked = self.state and self.state.checked
    -- Two complete snapshots must agree that our auction count decreased.
    -- This is only a possible sale: cancellation/expiry/page movement also look like this.
    if self.previousCount and count < self.previousCount then
        self.missingScans = (self.missingScans or 0) + 1
        if self.missingScans >= 2 then
            self.possiblySold = true
            self.previousCount = count
        end
    else
        if self.previousCount and count > self.previousCount then self.possiblySold = false end
        self.previousCount, self.missingScans = count, 0
    end
    local status = "NO_AUCTION"
    if count > 0 then
        status = (not own or (market and own > market)) and "UNDERCUT" or "COMPETITIVE"
    end
    if self.possiblySold and status ~= "UNDERCUT" then status = "POSSIBLY_SOLD" end
    self.state = { own = own, market = market, count = count, status = status,
        suggested = self:Suggested(market), checked = GetTime(),
        note = self.possiblySold and "An auction disappeared; sale, expiry or cancellation. Check before replacing."
            or (status == "UNDERCUT" and "Post one at the suggested price; keep older auctions.")
            or (status == "COMPETITIVE" and "Your lowest auction is competitive.")
            or "No active auction found. Prepare one flask." }
    if market and market <= 1 then
        self.state.note = "Market is at 1 copper; a lower positive price is impossible."
    end
    -- Market scans can only estimate a sale. They never produce the happy sound;
    -- that belongs to Blizzard's authoritative owned-auction sold state below.
    local alert = not previousChecked or previousStatus ~= status
    local sound = status ~= "COMPETITIVE" and status ~= "POSSIBLY_SOLD"
        and SOUNDKIT and SOUNDKIT.RAID_WARNING
    if self.db.undercutSound and alert and sound and type(PlaySound) == "function" then
        PlaySound(sound)
    end
    self:Refresh()
end

function F:Reset()
    self.manualRequested = nil
    self.prepared = nil
    self.scan, self.previousCount, self.missingScans, self.possiblySold = nil, nil, nil, nil
    self.itemName = nil
    self.nextScan = GetTime() + 1
    self.state = { status = "NO_AUCTION", note = self.paused
        and "Automatic checks are off. Use Refresh now or turn Auto on." or "Waiting for a complete scan." }
    self:Refresh()
end

local function reply(text) print("|cffffd100FlaskSeller:|r " .. text) end
local limits = { item = {"itemID", 1, 2147483647}, interval = {"interval", 5, 3600},
    undercut = {"undercut", 1, 2147483647}, fallback = {"fallback", 1, 2147483647} }

function F:SetItem(itemID)
    if type(itemID) ~= "number" or itemID ~= math.floor(itemID)
        or itemID < 1 or itemID > 2147483647 then return false end
    if itemID ~= self.db.itemID then
        self.db.itemID = itemID
        self.db.lastPostedPrice = 0
        self.pendingPost = nil
        self.soldCount = nil
        self:Reset()
    end
    local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    self.itemName = getInfo and getInfo(itemID)
    self:Refresh()
    return true
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
    local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    local configuredName = self.itemName or (getInfo and getInfo(self.db.itemID))
    -- Custom yeehaw is reserved for the item FlaskSeller is currently watching.
    if itemName == configuredName and type(PlaySoundFile) == "function" then
        local played = PlaySoundFile(SALE_SOUND_FILE, "Master")
        if played then return end
    end
    if type(PlaySound) == "function" and SOUNDKIT and SOUNDKIT.LOOT_WINDOW_COIN_SOUND then
        PlaySound(SOUNDKIT.LOOT_WINDOW_COIN_SOUND)
    end
end

function F:Command(message)
    local command, arg = message:match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "" or command == "status" then
        reply(string.format("Item %d | %s%s | Yours %s | Market %s | Suggested %s",
            self.db.itemID, self.paused and "PAUSED" or self.state.status,
            self.state.checked and " (last complete scan)" or " (unverified)",
            self:Money(self.state.own), self:Money(self.state.market), self:Money(self.state.suggested)))
        reply(self.state.note)
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
        reply("/flask status | item [ID] | interval [seconds] | undercut [copper] | fallback [copper] | sound [on/off]")
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
            if type(n) ~= "number" or n ~= n or n < 0 or n > 2147483647 or n ~= math.floor(n) then
                F.db[key] = value
            end
        end
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
                F.db.lastPostedPrice = F.pendingPost
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
