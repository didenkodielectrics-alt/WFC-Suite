local _, ns = ...
local WFC = WFC
local Tips = ns.Tips

-- InventoryValue: Calculates total inventory value across bags.
-- By default calculates "junk" (items autosold by Scrap or grey quality).
-- Configurable popup panel allows enabling Crafting Materials, Gear, and Consumables.
-- Adds a launcher button next to WFC_ProfessionsLauncher in the top-left.

local InventoryValue = {}
ns.InventoryValue = InventoryValue

local totals = {
    junk = 0,
    crafting = 0,
    gear = 0,
    consumables = 0,
    active = 0,
}
InventoryValue.totals = totals

local launcher
local popup
local debounceTimer = nil
local pendingLoads = false
local profHooked = false

---------------------------------------------------------------------------
-- Pricing & Item Classification
---------------------------------------------------------------------------
local function formatCoins(copper)
    if WFC.Compat and WFC.Compat.FormatMoney then
        return WFC.Compat.FormatMoney(copper)
    end
    copper = math.floor((copper or 0) + 0.5)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then
        return string.format("|cffffd700%dg|r |cffc7c7cf%02ds|r |cffeda55f%02dc|r", g, s, c)
    elseif s > 0 then
        return string.format("|cffc7c7cf%ds|r |cffeda55f%02dc|r", s, c)
    else
        return string.format("|cffeda55f%dc|r", c)
    end
end

local function getItemUnitPrice(itemId, sellPrice)
    local ahPrice = nil
    local vendorPrice = nil

    -- 1. Check WFC.DB:GetPrice
    if WFC.DB and WFC.DB.GetPrice then
        local ok, ah, v = pcall(WFC.DB.GetPrice, WFC.DB, itemId)
        if ok then
            if type(ah) == "number" and ah > 0 then ahPrice = ah end
            if type(v) == "number" and v > 0 then vendorPrice = v end
        end
    end

    -- 2. Direct Auctionator API fallback
    if (not ahPrice or ahPrice <= 0) and _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1 and _G.Auctionator.API.v1.GetAuctionPriceByItemID then
        local ok, p = pcall(_G.Auctionator.API.v1.GetAuctionPriceByItemID, "WFC", itemId)
        if ok and type(p) == "number" and p > 0 then
            ahPrice = p
        end
    end

    -- 3. Direct WFC DB Vendor price fallback
    if (not vendorPrice or vendorPrice <= 0) and WFC.DB and WFC.DB.Prices and WFC.DB.Prices.Vendor then
        local ok, vp = pcall(WFC.DB.Prices.Vendor, WFC.DB.Prices, itemId)
        if ok and type(vp) == "number" and vp > 0 then
            vendorPrice = vp
        end
    end

    -- 4. Return AH price > vendorPrice > sellPrice
    if ahPrice and ahPrice > 0 then
        return ahPrice
    elseif vendorPrice and vendorPrice > 0 then
        return vendorPrice
    elseif sellPrice and sellPrice > 0 then
        return sellPrice
    end
    return 0
end

local function safeGetItemInfo(item)
    if not item then return end
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo or (WFC.Compat and WFC.Compat.GetItemInfo)
    if fn then
        local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q = pcall(fn, item)
        if ok and a then
            return a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q
        end
    end
end

-- Profession tools kept in bags: used kit, never counted as gear value.
local TOOLS = {
    [2901] = true, [7005] = true, [5956] = true, [6256] = true, [6219] = true, [6218] = true,
    [6339] = true, [11130] = true, [11145] = true, [16207] = true, [10498] = true,
}

local function classifyItem(itemId, itemLink, bag, slot, fallbackQuality)
    itemId = tonumber(itemId) or itemId
    -- 1. Check Scrap / Junk
    local isJunk = false
    if _G.Scrap and _G.Scrap.IsJunk then
        local ok, res = pcall(_G.Scrap.IsJunk, _G.Scrap, itemId, bag, slot)
        if ok and res then
            isJunk = true
        end
    end

    local itemName, _, quality, _, _, itemType, subType, _, equipLoc, _, sellPrice, classID, subClassID, _, _, _, isCraftingReagent = safeGetItemInfo(itemLink or itemId)

    -- If classID or equipLoc not available via GetItemInfo, check GetItemInfoInstant
    if not classID and C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, eq, _, cId, scId = pcall(C_Item.GetItemInfoInstant, itemId)
        if ok then
            if cId ~= nil then classID = cId end
            if scId ~= nil then subClassID = scId end
            if eq and eq ~= "" then equipLoc = equipLoc or eq end
        end
    end

    quality = quality or fallbackQuality

    if not itemName and quality == nil then
        return nil -- Data not in cache yet
    end

    sellPrice = sellPrice or 0

    -- Quality 0 (Poor / Grey) or Scrap flagged = Junk
    if isJunk or quality == 0 then
        return "junk", sellPrice
    end

    -- 2. Crafting Materials (Trade goods / Reagents / Recipes)
    -- classID 7 = Tradeskill / Trade Goods, 5 = Reagents, 9 = Recipes
    local isCrafting = false
    if classID == 7 or classID == 5 or classID == 9 or isCraftingReagent == true then
        isCrafting = true
    elseif itemType == "Trade Goods" or itemType == "Tradeskill" or itemType == "Reagent" or itemType == "Recipe" then
        isCrafting = true
    elseif subType == "Cloth" or subType == "Leather" or subType == "Metal & Stone" or subType == "Herb"
        or subType == "Meat" or subType == "Elemental" or subType == "Enchanting" or subType == "Jewelcrafting"
        or subType == "Parts" or subType == "Explosives" or subType == "Devices" then
        isCrafting = true
    end
    if isCrafting then
        return "crafting", sellPrice
    end

    -- 3. Gear (Weapons & Armor)
    -- classID 2 = Weapon, 4 = Armor
    local isGear = false
    if classID == 2 or classID == 4 then
        isGear = true
    elseif itemType == "Weapon" or itemType == "Armor" then
        isGear = true
    elseif equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG" and equipLoc ~= "INVTYPE_TABARD" and equipLoc ~= "INVTYPE_BODY" and equipLoc ~= "INVTYPE_NON_EQUIP" then
        isGear = true
    end
    if isGear then
        -- Gear you use (profession tools, fishing poles) is "equipped" kit, not sellable stock.
        if TOOLS[itemId] or (classID == 2 and subClassID == 20) then return "other", sellPrice end
        return "gear", sellPrice
    end

    -- 4. Consumables
    -- classID 0 = Consumable
    local isCon = false
    if classID == 0 or itemType == "Consumable" then
        isCon = true
    elseif subType == "Potion" or subType == "Potions" or subType == "Elixir" or subType == "Elixirs"
        or subType == "Flask" or subType == "Flasks" or subType == "Food & Drink" or subType == "Bandage"
        or subType == "Scroll" or subType == "Scrolls" or subType == "Item Enhancement" then
        isCon = true
    end
    if isCon then
        return "consumables", sellPrice
    end

    return "other", sellPrice
end

---------------------------------------------------------------------------
-- Bag Scanner
---------------------------------------------------------------------------
function InventoryValue:Scan()
    local junkSum = 0
    local craftSum = 0
    local gearSum = 0
    local conSum = 0
    pendingLoads = false

    local minBag = 0
    local maxBag = NUM_BAG_SLOTS or 4

    for bag = minBag, maxBag do
        local numSlots = 0
        if C_Container and C_Container.GetContainerNumSlots then
            local ok, count = pcall(C_Container.GetContainerNumSlots, bag)
            if ok and count then numSlots = count end
        elseif GetContainerNumSlots then
            local ok, count = pcall(GetContainerNumSlots, bag)
            if ok and count then numSlots = count end
        end

        for slot = 1, numSlots do
            local itemID, itemLink, stackCount, itemQuality

            if C_Container and C_Container.GetContainerItemInfo then
                local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                if ok and info then
                    itemID = info.itemID
                    itemLink = info.hyperlink
                    stackCount = info.stackCount or 1
                    itemQuality = info.quality
                end
            end

            if not itemID and C_Container and C_Container.GetContainerItemID then
                local ok, id = pcall(C_Container.GetContainerItemID, bag, slot)
                if ok and id then itemID = id end
                if C_Container.GetContainerItemLink then
                    local ok2, link = pcall(C_Container.GetContainerItemLink, bag, slot)
                    if ok2 and link then itemLink = link end
                end
            end

            if not itemID and GetContainerItemInfo then
                local ok, _, count, _, quality, _, _, link, _, _, id = pcall(GetContainerItemInfo, bag, slot)
                if ok and id then
                    itemID = id
                    itemLink = link
                    stackCount = count or 1
                    itemQuality = quality
                end
            end

            if itemID then
                stackCount = stackCount or 1
                local cat, sellPrice = classifyItem(itemID, itemLink, bag, slot, itemQuality)
                if not cat then
                    -- Item info not in client cache yet; request load
                    pendingLoads = true
                    if C_Item and C_Item.RequestLoadItemDataByID then
                        pcall(C_Item.RequestLoadItemDataByID, itemID)
                    end
                else
                    if cat == "junk" then
                        local unitPrice = (sellPrice and sellPrice > 0) and sellPrice or 0
                        if unitPrice == 0 and WFC.DB and WFC.DB.Prices and WFC.DB.Prices.Vendor then
                            local ok, vp = pcall(WFC.DB.Prices.Vendor, WFC.DB.Prices, itemID)
                            if ok and type(vp) == "number" and vp > 0 then unitPrice = vp end
                        end
                        junkSum = junkSum + (unitPrice * stackCount)
                    elseif cat == "crafting" then
                        local unitPrice = getItemUnitPrice(itemID, sellPrice)
                        craftSum = craftSum + (unitPrice * stackCount)
                    elseif cat == "gear" then
                        local unitPrice = getItemUnitPrice(itemID, sellPrice)
                        gearSum = gearSum + (unitPrice * stackCount)
                    elseif cat == "consumables" then
                        local unitPrice = getItemUnitPrice(itemID, sellPrice)
                        conSum = conSum + (unitPrice * stackCount)
                    end
                end
            end
        end
    end

    totals.junk = junkSum
    totals.crafting = craftSum
    totals.gear = gearSum
    totals.consumables = conSum

    local s = Tips.settings or Tips.DEFAULTS
    local activeSum = 0
    if s.valueJunk ~= false then activeSum = activeSum + totals.junk end
    if s.valueCrafting == true then activeSum = activeSum + totals.crafting end
    if s.valueGear == true then activeSum = activeSum + totals.gear end
    if s.valueConsumables == true then activeSum = activeSum + totals.consumables end
    totals.active = activeSum

    if pendingLoads and C_Timer and C_Timer.After then
        C_Timer.After(0.4, function()
            if pendingLoads then InventoryValue:Scan() end
        end)
    end

    self:UpdateUI()
end

function InventoryValue:RequestScan()
    if debounceTimer then return end
    if C_Timer and C_Timer.After then
        debounceTimer = C_Timer.After(0.1, function()
            debounceTimer = nil
            InventoryValue:Scan()
        end)
    else
        InventoryValue:Scan()
    end
end

---------------------------------------------------------------------------
-- Settings Popup Frame
---------------------------------------------------------------------------
local function makeCheckbox(parent, labelText, tooltipText, onClick)
    local ok, cb = pcall(CreateFrame, "CheckButton", nil, parent, "UICheckButtonTemplate")
    if not ok or not cb then
        cb = CreateFrame("CheckButton", nil, parent)
        cb:SetSize(20, 20)
        local bg = cb:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.15, 0.17, 0.22, 0.8)
        cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
        cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    end
    cb:SetSize(20, 20)

    local text = cb.text or cb.Text or cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:ClearAllPoints()
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(labelText)
    cb.label = text

    local valText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cb.valText = valText

    cb:RegisterForClicks("LeftButtonUp")
    cb:SetScript("OnClick", function(self)
        local isChecked = (self:GetChecked() == true) or (self:GetChecked() == 1)
        onClick(isChecked)
    end)
    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(labelText, 1, 1, 1)
        GameTooltip:AddLine(tooltipText, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return cb
end

function InventoryValue:CreatePopup()
    if popup then return popup end

    local ok, f = pcall(CreateFrame, "Frame", "WFC_ItemTipsValuePopup", UIParent, "BackdropTemplate")
    if not ok or not f then
        popup = CreateFrame("Frame", "WFC_ItemTipsValuePopup", UIParent)
    else
        popup = f
    end

    popup:SetSize(300, 210)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(100)
    popup:SetClampedToScreen(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function(self) self:StartMoving() end)
    popup:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    popup:Hide()

    if popup.SetBackdrop then
        popup:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        popup:SetBackdropColor(0.08, 0.09, 0.12, 0.98)
        popup:SetBackdropBorderColor(0.30, 0.75, 0.95, 0.85)
    else
        local bg = popup:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.08, 0.09, 0.12, 0.98)
    end

    tinsert(UISpecialFrames, "WFC_ItemTipsValuePopup")

    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("|TInterface\\Icons\\INV_Misc_Coin_02:14:14:0:0|t Inventory Valuation")

    -- Custom reliable Close Button
    local closeBtn = CreateFrame("Button", nil, popup)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    closeBtn:RegisterForClicks("LeftButtonUp")
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() popup:Hide() end)

    -- Active Total Header
    local totalText = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    totalText:SetPoint("TOPLEFT", 12, -32)
    totalText:SetText("Total Value: 0c")
    popup.totalText = totalText

    -- Divider
    local line = popup:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 10, -52)
    line:SetPoint("TOPRIGHT", -10, -52)
    line:SetColorTexture(0.30, 0.75, 0.95, 0.4)

    -- Checkboxes for valuation categories
    local function setupRow(cb, y)
        cb:SetPoint("TOPLEFT", 12, y)
        cb.valText:ClearAllPoints()
        cb.valText:SetPoint("RIGHT", popup, "RIGHT", -14, 0)
        cb.valText:SetPoint("TOP", cb, "TOP", 0, -2)
    end

    popup.cbJunk = makeCheckbox(popup, "Junk (Auto-sold)", "Include vendor trash and Scrap auto-sold items (calculated at vendor sell price).", function(val)
        if Tips.settings then Tips.settings.valueJunk = val end
        InventoryValue:Scan()
        InventoryValue:RefreshPopup()
    end)
    setupRow(popup.cbJunk, -62)

    popup.cbCraft = makeCheckbox(popup, "Crafting Materials", "Include trade goods, cloth, herbs, ores, leather, enchanting materials (market/vendor price).", function(val)
        if Tips.settings then Tips.settings.valueCrafting = val end
        InventoryValue:Scan()
        InventoryValue:RefreshPopup()
    end)
    setupRow(popup.cbCraft, -90)

    popup.cbGear = makeCheckbox(popup, "Gear (Weapons & Armor)", "Include equipable weapons and armor (market/vendor price).", function(val)
        if Tips.settings then Tips.settings.valueGear = val end
        InventoryValue:Scan()
        InventoryValue:RefreshPopup()
    end)
    setupRow(popup.cbGear, -118)

    popup.cbCon = makeCheckbox(popup, "Consumables", "Include potions, elixirs, flasks, food, drinks, bandages, scrolls (market/vendor price).", function(val)
        if Tips.settings then Tips.settings.valueConsumables = val end
        InventoryValue:Scan()
        InventoryValue:RefreshPopup()
    end)
    setupRow(popup.cbCon, -146)

    -- Footer note
    local footer = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", 12, 10)
    footer:SetText("Valuation: Scrap / Auctionator / Vendor")

    return popup
end

function InventoryValue:RefreshPopup()
    if not popup or not popup:IsShown() then return end
    local s = Tips.settings or Tips.DEFAULTS

    if popup.cbJunk then popup.cbJunk:SetChecked(s.valueJunk ~= false) end
    if popup.cbCraft then popup.cbCraft:SetChecked(s.valueCrafting == true) end
    if popup.cbGear then popup.cbGear:SetChecked(s.valueGear == true) end
    if popup.cbCon then popup.cbCon:SetChecked(s.valueConsumables == true) end

    if popup.cbJunk and popup.cbJunk.valText then popup.cbJunk.valText:SetText(formatCoins(totals.junk)) end
    if popup.cbCraft and popup.cbCraft.valText then popup.cbCraft.valText:SetText(formatCoins(totals.crafting)) end
    if popup.cbGear and popup.cbGear.valText then popup.cbGear.valText:SetText(formatCoins(totals.gear)) end
    if popup.cbCon and popup.cbCon.valText then popup.cbCon.valText:SetText(formatCoins(totals.consumables)) end

    if popup.totalText then
        popup.totalText:SetText("Total Value: " .. formatCoins(totals.active))
    end
end

function InventoryValue:TogglePopup()
    local p = self:CreatePopup()
    if not p then return end

    if p:IsShown() then
        p:Hide()
    else
        p:ClearAllPoints()
        if launcher and launcher:IsShown() then
            p:SetPoint("TOPLEFT", launcher, "BOTTOMLEFT", 0, -4)
        else
            p:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 46, -92)
        end
        self:Scan()
        p:Show()
        self:RefreshPopup()
    end
end

---------------------------------------------------------------------------
-- Launcher Button (Anchored next to WFC_ProfessionsLauncher)
---------------------------------------------------------------------------
local function updateLauncherPosition()
    if not launcher then return end
    local s = Tips.settings or Tips.DEFAULTS

    local prof = _G.WFC_ProfessionsLauncher
    if prof and not profHooked and prof.HookScript then
        profHooked = true
        pcall(prof.HookScript, prof, "OnDragStop", function() updateLauncherPosition() end)
        pcall(prof.HookScript, prof, "OnShow", function() updateLauncherPosition() end)
        pcall(prof.HookScript, prof, "OnHide", function() updateLauncherPosition() end)
    end

    if s.valueLauncherPos then
        local p = s.valueLauncherPos
        launcher:ClearAllPoints()
        launcher:SetPoint(p.point or "TOPLEFT", UIParent, p.point or "TOPLEFT", p.x or 46, p.y or -60)
        return
    end

    if prof and prof:IsShown() then
        launcher:ClearAllPoints()
        launcher:SetPoint("LEFT", prof, "RIGHT", 4, 0)
    else
        launcher:ClearAllPoints()
        launcher:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 46, -60)
    end
end
InventoryValue.UpdateLauncherPosition = updateLauncherPosition

function InventoryValue:CreateLauncher()
    if launcher then return launcher end
    local s = Tips.settings or Tips.DEFAULTS

    local ok, b = pcall(CreateFrame, "Button", "WFC_ItemTipsValueLauncher", UIParent, "BackdropTemplate")
    if not ok or not b then
        launcher = CreateFrame("Button", "WFC_ItemTipsValueLauncher", UIParent)
    else
        launcher = b
    end

    launcher:SetSize(28, 28)
    launcher:SetFrameStrata("HIGH")
    launcher:SetClampedToScreen(true)
    launcher:SetMovable(true)
    launcher:EnableMouse(true)
    launcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    if launcher.SetBackdrop then
        launcher:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        launcher:SetBackdropColor(0.08, 0.09, 0.12, 0.95)
        launcher:SetBackdropBorderColor(0.95, 0.75, 0.20, 0.85) -- Gold accent border
    end

    local icon = launcher:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    launcher.icon = icon

    local hover = launcher:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.18)

    local isDragging = false
    launcher:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and IsShiftKeyDown() then
            isDragging = true
            self:StartMoving()
        end
    end)

    launcher:SetScript("OnMouseUp", function(self, btn)
        if isDragging then
            isDragging = false
            self:StopMovingOrSizing()
            local point, _, _, x, y = self:GetPoint(1)
            if Tips.settings then
                Tips.settings.valueLauncherPos = { point = point or "TOPLEFT", x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
            end
            self._justDragged = true
        end
    end)

    launcher:SetScript("OnClick", function(self, btn)
        if self._justDragged then
            self._justDragged = nil
            return
        end

        if btn == "RightButton" and not IsShiftKeyDown() then
            -- Snap back next to WFC Professions
            if Tips.settings then Tips.settings.valueLauncherPos = nil end
            updateLauncherPosition()
            return
        end

        -- Left-Click: Toggle Popup
        InventoryValue:TogglePopup()
    end)

    function launcher:RefreshTooltip()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("Inventory Valuation", 1, 0.82, 0)
        GameTooltip:AddLine("Calculated value of your bags:", 0.8, 0.8, 0.8)
        GameTooltip:AddLine(" ")

        local cfg = Tips.settings or Tips.DEFAULTS
        local function tag(active)
            return active and "|cff00ff00[Active]|r" or "|cff888888[Off]|r"
        end

        GameTooltip:AddDoubleLine("Junk (Auto-sold):", formatCoins(totals.junk) .. " " .. tag(cfg.valueJunk ~= false), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Crafting Materials:", formatCoins(totals.crafting) .. " " .. tag(cfg.valueCrafting == true), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Gear (Weapons & Armor):", formatCoins(totals.gear) .. " " .. tag(cfg.valueGear == true), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Consumables:", formatCoins(totals.consumables) .. " " .. tag(cfg.valueConsumables == true), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Total Inventory Value:", formatCoins(totals.active), 0.3, 0.85, 1, 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click: Configure categories popup (/wfcinv)", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-Click: Snap next to WFC Professions", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("Shift-Drag: Move button anywhere on screen", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end

    launcher:SetScript("OnEnter", function(self)
        self:RefreshTooltip()
    end)
    launcher:SetScript("OnLeave", function() GameTooltip:Hide() end)

    updateLauncherPosition()
    launcher:SetShown(s.showValueLauncher ~= false)
    return launcher
end

function InventoryValue:UpdateUI()
    if popup and popup:IsShown() then
        self:RefreshPopup()
    end
    if launcher and launcher:IsShown() and launcher.IsMouseOver and launcher:IsMouseOver() then
        launcher:RefreshTooltip()
    end
end

function InventoryValue:OnSettingsChanged()
    local s = Tips.settings or Tips.DEFAULTS
    if launcher then
        launcher:SetShown(s.showValueLauncher ~= false)
        updateLauncherPosition()
    end
    self:Scan()
end

---------------------------------------------------------------------------
-- Slash Commands
---------------------------------------------------------------------------
SLASH_WFC_INVENTORY_VALUE1 = "/wfcinv"
SLASH_WFC_INVENTORY_VALUE2 = "/wfcvalue"
SlashCmdList["WFC_INVENTORY_VALUE"] = function()
    InventoryValue:TogglePopup()
end

---------------------------------------------------------------------------
-- Initialization & Events
---------------------------------------------------------------------------
function InventoryValue:Init()
    local s = Tips.settings
    if not s then
        s = Tips.DEFAULTS
        Tips.settings = s
    end
    if s.valueJunk == nil then s.valueJunk = true end
    if s.valueCrafting == nil then s.valueCrafting = false end
    if s.valueGear == nil then s.valueGear = false end
    if s.valueConsumables == nil then s.valueConsumables = false end
    if s.showValueLauncher == nil then s.showValueLauncher = true end

    self:CreateLauncher()

    -- Hook MainMenuBarBackpackButton for bag value display
    if MainMenuBarBackpackButton and MainMenuBarBackpackButton.HookScript then
        MainMenuBarBackpackButton:HookScript("OnEnter", function()
            if GameTooltip:IsShown() then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine("Bag Value:", formatCoins(totals.active), 0.3, 0.85, 1, 1, 0.82, 0)
                GameTooltip:Show()
            end
        end)
    end

    self:RequestScan()
end

WFC:RegisterEvent("PLAYER_LOGIN", function()
    InventoryValue:Init()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            updateLauncherPosition()
            InventoryValue:Scan()
        end)
        C_Timer.After(2.0, function()
            updateLauncherPosition()
            InventoryValue:Scan()
        end)
    end
end)

WFC:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    updateLauncherPosition()
    InventoryValue:RequestScan()
end)

WFC:RegisterEvent("BAG_UPDATE_DELAYED", function()
    InventoryValue:RequestScan()
end)

WFC:RegisterEvent("BAG_UPDATE", function()
    InventoryValue:RequestScan()
end)

WFC:RegisterEvent("PLAYER_MONEY", function()
    InventoryValue:RequestScan()
end)

WFC:RegisterEvent("ITEM_DATA_LOAD_RESULT", function()
    InventoryValue:RequestScan()
end)

WFC:On("WFC_ITEM_LOADED", function()
    InventoryValue:RequestScan()
end)

WFC:On("WFC_PRICES_UPDATED", function()
    InventoryValue:RequestScan()
end)

WFC:On("WFC_DB_READY", function()
    updateLauncherPosition()
    InventoryValue:RequestScan()
end)
