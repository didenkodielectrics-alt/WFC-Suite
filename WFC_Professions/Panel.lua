local _, ns = ...
local WFC = WFC

-- Panel: Standalone window (/wfc prof or /wfcprof) for WFC_Professions.
-- Four tabs:
--   1. Materials (cross-character crafting materials + mail hints)
--   2. Scrolls   (scroll/pattern/plan recipes only: learned vs unlearned + owned scrolls)
--   3. Gear      (equippable items for your current character's level, with Have Mats & Unlearned checkboxes)
--   4. Skill-Up  ("Next best character to level" + step-by-step skill-ups with materials on hand)

local Professions = ns.Professions
local Inventory   = ns.Inventory
local Engine      = ns.Engine
local Colors      = WFC.Colors
local P           = Colors.palette
local Compat      = WFC.Compat

local Panel = {}
ns.Panel = Panel
Professions.Panel = Panel

local NAME = "WFC_ProfessionsFrame"
local WIDTH, HEIGHT = 650, 530
local PAD, ROW_GAP, LINE = 10, 4, 13
local BAR_H = 30
local STAR_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"

local TABS = {
    { key = "materials", label = "Materials" },
    { key = "scrolls",   label = "Scrolls" },
    { key = "gear",      label = "Craftable Gear" },
    { key = "skillup",   label = "Skill-Up" },
}

local frame, scroll, content, status, toolbar
local scrollTop = 32
local rows = {}
local tab = "materials"
local searchQuery = ""
local menuFrame
local GEAR_STAT_LABELS -- assigned in the toolbar section; declared here so buildGearRows sees the local

local function font(fs, key)
    local f = WFC.Fonts and WFC.Fonts:Get(key)
    if f then fs:SetFontObject(f) end
end

local function isCollapsed(key)
    local s = Professions.settings
    return s and s.collapsed and s.collapsed[key] == true
end

local function toggleCollapsed(key)
    local s = Professions.settings
    if not s then return end
    s.collapsed = s.collapsed or {}
    s.collapsed[key] = not s.collapsed[key] or nil
    Panel:Refresh()
end

---------------------------------------------------------------------------
-- Compact Dropdown Menu (taint-free)
---------------------------------------------------------------------------
local function showDropdown(owner, items)
    if not menuFrame then
        menuFrame = CreateFrame("Frame", "WFC_ProfessionsMenu", UIParent, "BackdropTemplate")
        if menuFrame.SetBackdrop then
            menuFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            menuFrame:SetBackdropColor(0.06, 0.065, 0.075, 0.97)
            menuFrame:SetBackdropBorderColor(0.30, 0.32, 0.36, 1)
        end
        menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        menuFrame:SetClampedToScreen(true)
        menuFrame:EnableMouse(true)
        menuFrame:Hide()
        menuFrame.buttons = {}
        tinsert(UISpecialFrames, "WFC_ProfessionsMenu")
        pcall(menuFrame.RegisterEvent, menuFrame, "GLOBAL_MOUSE_DOWN")
        menuFrame:SetScript("OnEvent", function(self)
            if self:IsShown() and not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
                self:Hide()
            end
        end)
    end

    if menuFrame:IsShown() and menuFrame.owner == owner then
        menuFrame:Hide()
        return
    end
    menuFrame.owner = owner

    local rowH = 18
    local maxW = 140
    for i, item in ipairs(items) do
        local b = menuFrame.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, menuFrame)
            b:SetHeight(rowH)
            b.text = b:CreateFontString(nil, "OVERLAY")
            font(b.text, "small")
            b.text:SetPoint("LEFT", 8, 0)
            b.text:SetJustifyH("LEFT")
            b.hl = b:CreateTexture(nil, "BACKGROUND")
            b.hl:SetAllPoints()
            b.hl:SetColorTexture(1, 1, 1, 0.10)
            b.hl:Hide()
            b:SetScript("OnEnter", function(self) self.hl:Show() end)
            b:SetScript("OnLeave", function(self) self.hl:Hide() end)
            menuFrame.buttons[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 2, -4 - (i - 1) * rowH)
        local label = item.selected and ("|cff4dd9ff• " .. item.text .. "|r") or item.text
        b.text:SetText(label)
        local w = (b.text.GetUnboundedStringWidth and b.text:GetUnboundedStringWidth() or b.text:GetStringWidth() or 100) + 20
        if w > maxW then maxW = w end
        b:SetScript("OnClick", function()
            menuFrame:Hide()
            if item.fn then item.fn() end
        end)
        b:Show()
    end
    for i = #items + 1, #menuFrame.buttons do menuFrame.buttons[i]:Hide() end

    for i = 1, #items do menuFrame.buttons[i]:SetWidth(maxW - 4) end
    menuFrame:SetSize(maxW, #items * rowH + 8)
    menuFrame:ClearAllPoints()
    menuFrame:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    menuFrame:Show()
end

---------------------------------------------------------------------------
-- Top Skill-Up Recommendation Banner Row
---------------------------------------------------------------------------
local function skillUpBannerRow()
    local s = Professions.settings
    if not s or not s.showSkillUpBanner then return nil end
    -- "Next best character" = biggest gain across every character, whatever the Skill-Up tab filter is
    local plans = Engine:GetSkillUpPlan({ onlyHaveMats = true, targetChar = "all", sortBy = "gain" })
    local best = plans[1]
    if not best or best.estGain <= 0 then return nil end

    local charColored = Inventory.ColorizeName(best.char.name, best.char.class)
    local topStep = best.steps[1]
    local sub = {
        Colors.Wrap(("%s can gain ~%d %s skill (%d/%d) using materials you already own"):format(
            charColored, best.estGain, best.profName, best.rank, best.max), P.EASY),
    }
    if topStep then
        local mailExtra = topStep.mailFrom and (" · mail mats from " .. topStep.mailFrom) or " · mats on character"
        sub[2] = Colors.Wrap(("Next: %dx %s (%s%s)"):format(
            topStep.crafts, topStep.name, topStep.diff, mailExtra), P.TEXT_MUTED)
    end
    return {
        kind = "banner",
        icon = STAR_ICON,
        title = Colors.Wrap(("★ Next Best Skill-Up: %s · %s"):format(best.char.shortName or best.char.name, best.profName), P.NEW),
        right = Colors.Wrap(("~+%d skill"):format(best.estGain), P.EASY),
        sub = sub,
        onClick = function() Panel:ShowTab("skillup") end,
    }
end

---------------------------------------------------------------------------
-- Build Display Rows per Tab
---------------------------------------------------------------------------
local function buildMaterialRows()
    local s = Professions.settings
    local mats = Engine:GetMaterials({
        profFilter = s.matProfFilter or 0,
        inStockOnly = s.matInStockOnly ~= false,
        search = searchQuery,
    })
    local out = {}
    local banner = skillUpBannerRow()
    if banner then out[#out + 1] = banner end

    local totalStacks = 0
    for _, m in ipairs(mats) do
        totalStacks = totalStacks + m.total
        local sub = {
            Colors.Wrap(m.holderText, P.TEXT_MUTED),
            Colors.Wrap(m.usedByText, P.TEXT_MUTED),
        }
        if m.mailHint then
            sub[#sub + 1] = "|cffffd100→ " .. m.mailHint .. "|r"
        end
        local countColor = m.total > 0 and P.EASY or P.TRIVIAL
        out[#out + 1] = {
            kind = "material",
            itemId = m.itemId,
            icon = m.icon,
            title = m.coloredName,
            right = Colors.Wrap("x" .. tostring(m.total), countColor),
            sub = sub,
        }
    end
    return out, ("%d crafting materials (%d total items)"):format(#mats, totalStacks)
end

local function buildScrollRows()
    local s = Professions.settings
    local state = s.scrollStateFilter or "all"
    local owned, toLearn = Engine:GetScrollTab({
        profFilter = s.scrollProfFilter or -1,
        search = searchQuery,
        window = 25,
    })
    local out = {}
    local who = function(c) return c and Inventory.ColorizeName(c.shortName or c.name, c.class) or "?" end

    -- 1. Scrolls you own: what each one is for, and what to do with it.
    if state ~= "unlearned" then
        local key = "scrolls_owned"
        local collapsed = isCollapsed(key)
        local nowCount = 0
        for _, e in ipairs(owned) do if e.verdict == "now" then nowCount = nowCount + 1 end end
        out[#out + 1] = { kind = "header", group = key, collapsed = collapsed,
            icon = "Interface\\Icons\\INV_Scroll_03",
            title = Colors.Wrap("Scrolls you own", P.NEW),
            right = Colors.Wrap(("%d owned%s"):format(#owned, nowCount > 0 and (" · " .. nowCount .. " to learn now") or ""), nowCount > 0 and P.EASY or P.TEXT_MUTED),
            sub = {} }
        if not collapsed then
            if #owned == 0 then
                out[#out + 1] = { kind = "step", icon = "Interface\\Icons\\INV_Misc_QuestionMark",
                    title = Colors.Wrap("No patterns, plans, formulas or recipes on any character.", P.TEXT_MUTED), sub = {} }
            end
            for _, e in ipairs(owned) do
                local right, line
                if e.verdict == "now" then
                    right = Colors.Wrap("Learn now", P.EASY)
                    line = ("%s can learn it (%s %d, needs %s%d)"):format(who(e.who), e.profName, e.whoRank, e.est and "~" or "", e.learn)
                elseif e.verdict == "later" then
                    right = Colors.Wrap(("At skill %s%d"):format(e.est and "~" or "", e.learn), P.FAIR)
                    line = ("%s has %s %d · %s%d more points, then learn it"):format(who(e.who), e.profName, e.whoRank, e.est and "~" or "", e.learn - e.whoRank)
                elseif e.verdict == "known" then
                    right = Colors.Wrap("Already known · sell", P.TRIVIAL)
                    line = "Every character with " .. (e.profName or "the profession") .. " already knows it"
                elseif e.verdict == "nobody" then
                    right = Colors.Wrap("Nobody can use · sell", P.TRIVIAL)
                    line = "No character has " .. (e.profName or "this profession")
                else
                    right = Colors.Wrap("Recipe not matched", P.TEXT_MUTED)
                    line = "Couldn't match this to a recipe in the data"
                end
                out[#out + 1] = { kind = "scroll", itemId = e.itemId, spellId = e.spellId, icon = e.icon,
                    title = ("%s%s"):format(e.name, e.count > 1 and (" x" .. e.count) or ""),
                    right = right,
                    sub = { Colors.Wrap(line .. " · held by " .. e.holders, P.TEXT_MUTED) },
                    alpha = (e.verdict == "known" or e.verdict == "nobody") and 0.75 or 1 }
            end
        end
    end

    -- 2. Still to learn: per character and profession, current skill up to +25.
    local nowTotal = 0
    if state ~= "owned" then
        for _, g in ipairs(toLearn) do
            local key = ("tolearn_%s_%d"):format(g.char.key or g.char.name or "?", g.profId)
            local collapsed = isCollapsed(key)
            local nowN = 0
            for _, r in ipairs(g.list) do if r.now then nowN = nowN + 1 end end
            nowTotal = nowTotal + nowN
            out[#out + 1] = { kind = "header", group = key, collapsed = collapsed,
                icon = Engine.ProfIcon(g.profId),
                title = ("%s %s · %s"):format(Colors.Wrap("Still to learn:", P.NEW), who(g.char), Colors.Wrap(("%s %d/%d"):format(g.profName, g.rank, g.max), P.TEXT)),
                right = Colors.Wrap(nowN > 0 and (nowN .. " learnable now") or ("next at " .. g.list[1].learn), nowN > 0 and P.EASY or P.TEXT_MUTED),
                sub = {} }
            if not collapsed then
                for _, r in ipairs(g.list) do
                    out[#out + 1] = { kind = "scroll", spellId = r.spellId, icon = Engine.ProfIcon(g.profId),
                        title = ("%s |cffaaaaaa[%s%d]|r"):format(Colors.Wrap(r.name, Colors.ForSkill(r.color)), r.est and "~" or "", r.learn),
                        right = r.now and Colors.Wrap("Learn now", P.EASY) or Colors.Wrap(("At %s%d"):format(r.est and "~" or "", r.learn), P.FAIR),
                        sub = { Colors.Wrap(r.where, P.TEXT_MUTED) } }
                end
            end
        end
    end

    local summary = ("%d scrolls owned · %d recipes learnable now · showing up to 25 skill ahead"):format(#owned, nowTotal)
    return out, summary
end

---------------------------------------------------------------------------
-- Gear tab: character slot view ("paper doll") + upgrades per slot
---------------------------------------------------------------------------
-- Inventory slot ids, slot names (for GetInventorySlotInfo's empty-slot art) and the
-- equip locations a craftable item can have to fit there.
local GEAR_SLOTS = {
    { id = 1,  name = "HeadSlot",          label = "Head",      locs = { INVTYPE_HEAD = true } },
    { id = 2,  name = "NeckSlot",          label = "Neck",      locs = { INVTYPE_NECK = true } },
    { id = 3,  name = "ShoulderSlot",      label = "Shoulder",  locs = { INVTYPE_SHOULDER = true } },
    { id = 15, name = "BackSlot",          label = "Back",      locs = { INVTYPE_CLOAK = true } },
    { id = 5,  name = "ChestSlot",         label = "Chest",     locs = { INVTYPE_CHEST = true, INVTYPE_ROBE = true } },
    { id = 9,  name = "WristSlot",         label = "Wrist",     locs = { INVTYPE_WRIST = true } },
    { id = 10, name = "HandsSlot",         label = "Hands",     locs = { INVTYPE_HAND = true } },
    { id = 6,  name = "WaistSlot",         label = "Waist",     locs = { INVTYPE_WAIST = true } },
    { id = 7,  name = "LegsSlot",          label = "Legs",      locs = { INVTYPE_LEGS = true } },
    { id = 8,  name = "FeetSlot",          label = "Feet",      locs = { INVTYPE_FEET = true } },
    { id = 11, name = "Finger0Slot",       label = "Finger",    locs = { INVTYPE_FINGER = true } },
    { id = 12, name = "Finger1Slot",       label = "Finger",    locs = { INVTYPE_FINGER = true } },
    { id = 13, name = "Trinket0Slot",      label = "Trinket",   locs = { INVTYPE_TRINKET = true } },
    { id = 14, name = "Trinket1Slot",      label = "Trinket",   locs = { INVTYPE_TRINKET = true } },
    { id = 16, name = "MainHandSlot",      label = "Main Hand", locs = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true } },
    { id = 17, name = "SecondaryHandSlot", label = "Off Hand",  locs = { INVTYPE_WEAPON = true, INVTYPE_SHIELD = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_HOLDABLE = true } },
    { id = 18, name = "RangedSlot",        label = "Ranged",    locs = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true } },
}
local GEAR_SLOT_BY_ID = {}
for _, sl in ipairs(GEAR_SLOTS) do GEAR_SLOT_BY_ID[sl.id] = sl end

local gearView = { selected = nil, equipped = {}, upgrades = {}, who = nil } -- filled by buildGearRows
local gearCard

local function itemIlvl(itemId, link)
    if link and C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok, il = pcall(C_Item.GetDetailedItemLevelInfo, link)
        if ok and type(il) == "number" and il > 0 then return il end
    end
    local client = itemId and WFC.DB and WFC.DB:GetItemClient(itemId)
    if client and client.ilvl then return client.ilvl end
    local card = itemId and WFC.DB and WFC.DB:GetItem(itemId)
    return card and card.ilvl or 0
end

--- { [slotId] = { itemId, link, ilvl } } for the viewed character: live for the logged-in one,
--- Bagnon's saved copy (BrotherBags ... .equip[slot]) for an alt.
local function equippedFor(char)
    local out = {}
    if not char or char.isCurrent then
        for _, sl in ipairs(GEAR_SLOTS) do
            local id = GetInventoryItemID("player", sl.id)
            if id then
                local link = GetInventoryItemLink("player", sl.id)
                out[sl.id] = { itemId = id, link = link, ilvl = itemIlvl(id, link) }
            end
        end
        return out
    end
    if type(BrotherBags) ~= "table" then return out end
    for realmKey, realm in pairs(BrotherBags) do
        local d = realmKey ~= "account" and type(realm) == "table" and (realm[char.name] or realm[char.shortName or ""])
        if not d and type(realm) == "table" then
            for owner, data in pairs(realm) do
                if type(owner) == "string" and owner:match("^(%S+)") == char.shortName and type(data) == "table" and data.equip then d = data end
            end
        end
        if type(d) == "table" and type(d.equip) == "table" then
            for slot, str in pairs(d.equip) do
                local id = type(slot) == "number" and tonumber(tostring(str):match("^(%d+)"))
                if id then out[slot] = { itemId = id, ilvl = itemIlvl(id) } end
            end
            return out
        end
    end
    return out
end

local function createGearCard(parent)
    if gearCard then return gearCard end
    gearCard = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    gearCard:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    gearCard:SetBackdropColor(0.08, 0.09, 0.12, 0.95)
    gearCard:SetBackdropBorderColor(0.25, 0.29, 0.36, 1)
    gearCard.title = gearCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    font(gearCard.title, "subheader")
    gearCard.title:SetPoint("TOPLEFT", 8, -6)
    gearCard.hint = gearCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    font(gearCard.hint, "small")
    gearCard.hint:SetPoint("TOPRIGHT", -8, -8)
    gearCard.buttons = {}
    local SIZE, GAP, PER_ROW = 34, 4, 9
    for i, sl in ipairs(GEAR_SLOTS) do
        local b = CreateFrame("Button", nil, gearCard, "BackdropTemplate")
        b:SetSize(SIZE, SIZE)
        local row, col = math.floor((i - 1) / PER_ROW), (i - 1) % PER_ROW
        b:SetPoint("TOPLEFT", 8 + col * (SIZE + GAP), -26 - row * (SIZE + GAP + 2))
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        b:SetBackdropColor(0, 0, 0, 0.9)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        local okSlot, _, emptyTex = pcall(GetInventorySlotInfo, sl.name)
        b.emptyTex = okSlot and emptyTex or "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
        b.badge = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        font(b.badge, "small")
        b.badge:SetPoint("BOTTOMRIGHT", -1, 1)
        b.badge:SetTextColor(0.25, 1, 0.25)
        b.badge:SetShadowOffset(1, -1)
        b.slot = sl
        b:RegisterForClicks("LeftButtonUp")
        b:SetScript("OnClick", function(self)
            gearView.selected = (gearView.selected == self.slot.id) and nil or self.slot.id
            Panel:Refresh()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local eq = gearView.equipped[self.slot.id]
            if eq and gearView.who and gearView.who.isCurrent then
                GameTooltip:SetInventoryItem("player", self.slot.id)
            elseif eq then
                pcall(GameTooltip.SetItemByID, GameTooltip, eq.itemId)
            else
                GameTooltip:AddLine(self.slot.label .. " (empty)", 1, 1, 1)
            end
            local n = #(gearView.upgrades[self.slot.id] or {})
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(n > 0 and ("%d craftable upgrade%s · click to see"):format(n, n == 1 and "" or "s")
                or "No craftable upgrade for this slot", n > 0 and 0.25 or 0.6, n > 0 and 1 or 0.6, n > 0 and 0.25 or 0.6)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        gearCard.buttons[i] = b
    end
    gearCard:SetHeight(26 + 2 * (SIZE + GAP + 2) + 4)
    return gearCard
end

local function updateGearCard(width)
    if not gearCard and content then createGearCard(content) end
    if not gearCard then return 0 end
    gearCard:ClearAllPoints()
    gearCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    gearCard:SetWidth(width)
    local who = gearView.who
    gearCard.title:SetText(Colors.Wrap("Gear · ", P.NEW) .. (who and Inventory.ColorizeName(who.shortName or who.name, who.class) or "?")
        .. Colors.Wrap(who and (" (level " .. (who.level or "?") .. ")") or "", P.TEXT_MUTED))
    local sel = gearView.selected and GEAR_SLOT_BY_ID[gearView.selected]
    gearCard.hint:SetText(Colors.Wrap(sel and ("Showing: " .. sel.label .. " · click it again for all slots") or "Click a slot to see craftable upgrades for it", P.TEXT_MUTED))
    for _, b in ipairs(gearCard.buttons) do
        local eq = gearView.equipped[b.slot.id]
        if eq then
            b.icon:SetTexture(C_Item.GetItemIconByID(eq.itemId) or "Interface\\Icons\\INV_Misc_QuestionMark")
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b.icon:SetDesaturated(false)
        else
            b.icon:SetTexture(b.emptyTex)
            b.icon:SetTexCoord(0, 1, 0, 1)
            b.icon:SetDesaturated(true)
        end
        local n = #(gearView.upgrades[b.slot.id] or {})
        b.badge:SetText(n > 0 and ("+" .. n) or "")
        if gearView.selected == b.slot.id then
            b:SetBackdropBorderColor(P.NEW.r, P.NEW.g, P.NEW.b, 1)
        else
            local q = eq and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(eq.itemId)
            local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
            if c then b:SetBackdropBorderColor(c.r, c.g, c.b, 0.9) else b:SetBackdropBorderColor(0.25, 0.27, 0.30, 1) end
        end
    end
    gearCard:Show()
    return gearCard:GetHeight()
end

local function buildGearRows()
    local s = Professions.settings
    local tc = s.gearTargetChar or "player"
    local gear = Engine:GetCraftableGear({
        onlyHaveMats = s.gearOnlyHaveMats == true,
        includeUnlearned = s.gearIncludeUnlearned ~= false,
        statFilter = s.gearStatFilter or "all",
        targetChar = tc,
        levelSpan = s.gearLevelSpan or 12,
        search = searchQuery,
    })

    local out = {}
    local tName = UnitName("player") or "Player"
    local tClass = (WFC.Player and WFC.Player.classFile) or select(2, UnitClass("player")) or ""
    local tLevel = (WFC.Player and WFC.Player.level) or UnitLevel("player") or 1

    if tc == "all" then
        tName = "All Characters"
        tClass = "ALL"
        tLevel = 0
    elseif tc ~= "player" then
        local chars = Inventory:GetCharacters()
        for _, ch in ipairs(chars) do
            if ch.key == tc or ch.name == tc or ch.shortName == tc then
                tName = ch.shortName or ch.name
                tClass = ch.class or ""
                tLevel = ch.level or 1
                break
            end
        end
    end

    -- Character being viewed: the one picked in the toolbar, else the logged-in one.
    local viewed
    for _, ch in ipairs(Inventory:GetCharacters()) do
        if (tc == "player" or tc == "all") and ch.isCurrent then viewed = ch end
        if tc ~= "player" and tc ~= "all" and (ch.key == tc or ch.name == tc or ch.shortName == tc) then viewed = ch end
    end
    gearView.who = viewed or { isCurrent = true, shortName = tName, class = tClass, level = tLevel }
    gearView.equipped = equippedFor(gearView.who)
    gearView.upgrades = {}

    -- Upgrades per slot: craftable items that fit the slot with a higher item level than equipped.
    for _, g in ipairs(gear) do
        for _, sl in ipairs(GEAR_SLOTS) do
            if g.equipLoc and sl.locs[g.equipLoc] then
                local eq = gearView.equipped[sl.id]
                if not eq or (g.ilvl or 0) > (eq.ilvl or 0) then
                    local list = gearView.upgrades[sl.id] or {}
                    gearView.upgrades[sl.id] = list
                    list[#list + 1] = g
                end
            end
        end
    end
    for _, list in pairs(gearView.upgrades) do
        table.sort(list, function(a, b)
            local ak, bk = a.state == "known", b.state == "known"
            if ak ~= bk then return ak end
            if (a.ilvl or 0) ~= (b.ilvl or 0) then return (a.ilvl or 0) > (b.ilvl or 0) end
            return (a.name or "") < (b.name or "")
        end)
    end

    local readyCount = 0
    local rowsByGear = {}
    for _, g in ipairs(gear) do
        if g.maxCrafts >= 1 then readyCount = readyCount + 1 end
        local badge
        if g.state == "known" then
            if g.maxCrafts >= 1 then
                badge = ("|cff40ff40Craftable x%d|r"):format(g.maxCrafts)
            else
                badge = "|cffff8040Known (Need Mats)|r"
            end
        elseif g.state == "known_low_skill" then
            badge = ("|cffffd100Known (Needs %d %s)|r"):format(g.learnRank, g.profName)
        elseif g.state == "unlearned_have_scroll" then
            badge = "|cff4dd9ffHave Scroll!|r"
        elseif g.state == "unlearned_scroll" then
            badge = ("|cffaaaaaaNeeds Scroll (%d)|r"):format(g.learnRank)
        else
            badge = ("|cffaaaaaaTrainer (%d %s)|r"):format(g.learnRank, g.profName)
        end

        if g.bop then
            badge = "|cffff6060BoP · crafter only|r · " .. badge
        end
        local crafterName = Inventory.ColorizeName(g.crafter.char.shortName or g.crafter.char.name, g.crafter.char.class)
        local statBadge = (g.statSummary and g.statSummary ~= "") and (" · " .. g.statSummary) or ""
        local sub = {
            Colors.Wrap(("%s · Req Lvl %d (iLvl %d)"):format(g.slotLabel, g.reqLevel, g.ilvl), P.TEXT_MUTED)
                .. statBadge
                .. Colors.Wrap((" · Crafter: %s (%s %d/%d)"):format(crafterName, g.profName, g.crafter.rank, g.crafter.max), P.TEXT_MUTED),
            Colors.Wrap("Mats: ", P.TEXT_MUTED) .. g.reagentText,
        }

        rowsByGear[g] = {
            kind = "gear",
            itemId = g.productId,
            spellId = g.spellId,
            icon = g.icon,
            title = g.coloredName,
            right = badge,
            sub = sub,
        }
    end

    -- List: the selected slot's upgrades, or every slot with upgrades (grouped, foldable).
    local function slotHeader(sl)
        local eq = gearView.equipped[sl.id]
        local eqName = eq and (select(1, Engine.ItemDisplay(eq.itemId)) or "?") or "empty"
        local n = #(gearView.upgrades[sl.id] or {})
        return {
            kind = "header", group = "gearslot_" .. sl.id, collapsed = gearView.selected == nil and isCollapsed("gearslot_" .. sl.id),
            icon = eq and C_Item.GetItemIconByID(eq.itemId) or nil,
            title = Colors.Wrap(sl.label, P.NEW) .. Colors.Wrap(("  ·  equipped: %s%s"):format(eqName, eq and (" (iLvl " .. (eq.ilvl or 0) .. ")") or ""), P.TEXT_MUTED),
            right = Colors.Wrap(("%d upgrade%s"):format(n, n == 1 and "" or "s"), n > 0 and P.EASY or P.TEXT_MUTED),
            sub = {},
        }
    end
    if gearView.selected then
        local sl = GEAR_SLOT_BY_ID[gearView.selected]
        out[#out + 1] = slotHeader(sl)
        local list = gearView.upgrades[sl.id] or {}
        if #list == 0 then
            out[#out + 1] = { kind = "step", icon = "Interface\\Icons\\INV_Misc_QuestionMark",
                title = Colors.Wrap("Nothing craftable on your account beats what's equipped here.", P.TEXT_MUTED),
                sub = { Colors.Wrap("Try 'include unlearned recipes', a wider level window, or another stat filter.", P.TEXT_MUTED) } }
        end
        for _, g in ipairs(list) do out[#out + 1] = rowsByGear[g] end
    else
        local shown = {}
        for _, sl in ipairs(GEAR_SLOTS) do
            local list = gearView.upgrades[sl.id]
            -- the second ring/trinket slot repeats the first one's list: show it once
            local dupKey = sl.label .. ":" .. #(list or {})
            if list and #list > 0 and not shown[dupKey] then
                shown[dupKey] = true
                local h = slotHeader(sl)
                out[#out + 1] = h
                if not h.collapsed then
                    for _, g in ipairs(list) do out[#out + 1] = rowsByGear[g] end
                end
            end
        end
        if #out == 0 then
            out[#out + 1] = { kind = "step", icon = "Interface\\Icons\\INV_Misc_QuestionMark",
                title = Colors.Wrap("No craftable upgrades for this character right now.", P.TEXT_MUTED),
                sub = { Colors.Wrap("Try 'include unlearned recipes' or a wider level window.", P.TEXT_MUTED) } }
        end
    end

    local filterSuffix = ""
    local curFilter = s.gearStatFilter or "all"
    if curFilter ~= "all" and GEAR_STAT_LABELS and GEAR_STAT_LABELS[curFilter] then
        filterSuffix = " · " .. GEAR_STAT_LABELS[curFilter]
    end

    local forStr
    if tc == "all" then
        forStr = "|cffffffffFor: All Characters|r"
    else
        forStr = ("For %s (Lvl %d %s)"):format(Inventory.ColorizeName(tName, tClass), tLevel, tClass:lower())
    end

    local summary = ("%s: %d items (%d with mats ready)%s"):format(
        forStr, #gear, readyCount, filterSuffix)
    return out, summary
end

local function buildSkillUpRows()
    local s = Professions.settings or Professions.DEFAULTS
    local onlyHave = s.skillUpOnlyHaveMats ~= false
    local chars = Inventory:GetCharacters()
    local plans = Engine:GetSkillUpPlan({
        onlyHaveMats = onlyHave,
        targetChar = s.skillUpCharFilter or "all",
        sortBy = s.skillUpSort or "current",
    })
    local out = {}

    -- Section header for the recommendations (character roster is in its dedicated box above)
    local subtitle = onlyHave and ("%d ready with materials"):format(#plans) or ("%d character professions"):format(#plans)
    out[#out + 1] = {
        kind = "header",
        icon = "Interface\\Icons\\Trade_Engineering",
        title = Colors.Wrap("Skill-Up Plans" .. (onlyHave and " (Materials On Hand)" or " (All Leveling)"), P.NEW),
        right = Colors.Wrap(subtitle, P.TEXT_MUTED),
        sub = {},
    }

    if #plans == 0 then
        local filterChar = s.skillUpCharFilter
        local msg = (filterChar and filterChar ~= "all")
            and "No recipes with materials ready for this character."
            or "No professions have materials ready right now."
        out[#out + 1] = {
            kind = "step",
            icon = "Interface\\Icons\\INV_Misc_QuestionMark",
            title = Colors.Wrap(msg, P.TEXT_MUTED),
            right = onlyHave and Colors.Wrap("[Show All Recipes]", P.EASY) or "",
            sub = { Colors.Wrap("Click here or uncheck 'Have Materials' above to see the full leveling roadmap.", P.TEXT_MUTED) },
            onClick = function()
                s.skillUpOnlyHaveMats = false
                if s.skillUpCharFilter ~= "all" then s.skillUpCharFilter = "all" end
                Panel:Refresh()
            end,
        }
    else
        -- Skill-up recommendations per character & profession
        for idx, plan in ipairs(plans) do
            local groupKey = ("skillup_%s_%d"):format(plan.char.key, plan.profId)
            local collapsed = isCollapsed(groupKey)
            local charColored = Inventory.ColorizeName(plan.char.name, plan.char.class)
            local gainStr
            if plan.estGain > 0 then
                gainStr = Colors.Wrap(("~+%d skill ready"):format(plan.estGain), P.EASY)
            elseif plan.totalPossibleGain and plan.totalPossibleGain > 0 then
                gainStr = Colors.Wrap(("~+%d skill roadmap"):format(plan.totalPossibleGain), P.TEXT_MUTED)
            else
                gainStr = Colors.Wrap("Need Materials", P.TRIVIAL)
            end

            out[#out + 1] = {
                kind = "header",
                group = groupKey,
                collapsed = collapsed,
                icon = plan.profIcon,
                title = ("#%d %s · %s (%d/%d)"):format(idx, charColored, plan.profName, plan.rank, plan.max),
                right = gainStr,
                sub = {},
            }
            if not collapsed then
                if #plan.steps == 0 then
                    out[#out + 1] = {
                        kind = "step",
                        icon = plan.profIcon,
                        title = Colors.Wrap(onlyHave and "Need materials for next skill-up recipes."
                            or ("No known %s recipe still gives skill at %d: learn new ones."):format(plan.profName, plan.rank), P.TEXT_MUTED),
                        right = onlyHave and Colors.Wrap("[See Roadmap]", P.EASY) or Colors.Wrap("[Still to learn]", P.EASY),
                        sub = onlyHave and { Colors.Wrap("Click here or uncheck 'Have Materials' to view the full leveling shopping list.", P.TEXT_MUTED) }
                            or { Colors.Wrap(("Visit a %s trainer, or click here for the Scrolls tab's 'Still to learn' list with where to get each recipe."):format(plan.profName), P.TEXT_MUTED) },
                        onClick = onlyHave and function()
                            s.skillUpOnlyHaveMats = false
                            Panel:Refresh()
                        end or function()
                            s.scrollStateFilter = "unlearned"
                            Panel:ShowTab("scrolls")
                        end,
                    }
                else
                    -- Total Materials needed across entire skill-up
                    if plan.totalReagentsSummary and plan.totalReagentsSummary ~= "" then
                        local totalCostStr = (plan.totalCost and plan.totalCost > 0)
                            and WFC.Compat.FormatMoney(plan.totalCost) or nil
                        local rightLabel = plan.allMatsReady
                            and Colors.Wrap("All Materials Ready", P.EASY)
                            or Colors.Wrap(totalCostStr or "Shopping List", P.TRIVIAL)

                        out[#out + 1] = {
                            kind = "step",
                            icon = "Interface\\Icons\\INV_Misc_Bag_08",
                            title = Colors.Wrap(("Total Materials (%d \226\134\146 %d):"):format(plan.rank, plan.targetSkill or plan.max), P.NEW),
                            right = rightLabel,
                            sub = {
                                plan.totalReagentsSummary,
                            },
                        }
                    end

                    -- Compact Step rows (1 line title + 1 line detail)
                    for sIdx, step in ipairs(plan.steps) do
                        local dCol = Colors.ForSkill(step.diff)
                        local costStr = (step.totalCost and step.totalCost > 0)
                            and WFC.Compat.FormatMoney(step.totalCost) or nil
                        local perPtStr = (step.costPerPoint and step.costPerPoint > 0)
                            and (WFC.Compat.FormatMoney(step.costPerPoint) .. "/pt") or nil

                        local rightText
                        if step.readyCrafts and step.readyCrafts < step.crafts then
                            if step.readyCrafts > 0 then
                                rightText = Colors.Wrap(("~+%d pts (have %d/%d)"):format(
                                    math.floor(step.estGain + 0.5), step.readyCrafts, step.crafts), P.TRIVIAL)
                            else
                                rightText = Colors.Wrap(("~+%d pts (need mats)"):format(
                                    math.floor(step.estGain + 0.5)), P.TRIVIAL)
                            end
                        else
                            rightText = Colors.Wrap(("~+%d pts (%s)"):format(
                                math.floor(step.estGain + 0.5), step.diff), dCol)
                        end
                        if costStr then
                            rightText = rightText .. " · " .. costStr
                        end

                        local learnPrefix = not step.knows and "|cffffd100[Learn]|r " or ""
                        local greenInfo = (step.greenRank and step.greenRank > 0)
                            and (" · green at " .. step.greenRank) or ""
                        local bracket = (" |cff7f8c8d(%d\226\134\146%d%s)|r"):format(step.startRank, step.endRank, greenInfo)

                        local lineParts = {}
                        lineParts[#lineParts + 1] = "Mats: " .. step.reagentSummary
                        if not step.knows and step.learnSource then
                            lineParts[#lineParts + 1] = "|cffffd100" .. step.learnSource .. "|r"
                        end
                        if step.mailFrom then
                            lineParts[#lineParts + 1] = "|cffffd100Mail: " .. step.mailFrom .. "|r"
                        end
                        if perPtStr then
                            lineParts[#lineParts + 1] = Colors.Wrap(perPtStr, P.TEXT_MUTED)
                        end

                        out[#out + 1] = {
                            kind = "step",
                            spellId = step.spellId,
                            itemId = (step.recipe.product and step.recipe.product.id) or step.learnItem,
                            icon = step.icon,
                            title = ("%d. %sCraft |cffffffff%dx|r %s%s"):format(
                                sIdx, learnPrefix, step.crafts, Colors.Wrap(step.name, dCol), bracket
                            ),
                            right = rightText,
                            sub = {
                                table.concat(lineParts, " · "),
                            },
                        }
                    end
                end
            end
        end
    end

    local summary = onlyHave
        and ("%d professions with materials ready across %d characters"):format(#plans, #chars)
        or ("%d crafting professions analyzed across %d characters"):format(#plans, #chars)
    return out, summary
end

function Panel:DisplayRows()
    if tab == "scrolls" then return buildScrollRows() end
    if tab == "gear" then return buildGearRows() end
    if tab == "skillup" then return buildSkillUpRows() end
    return buildMaterialRows()
end

---------------------------------------------------------------------------
-- Row Creation & Interaction
---------------------------------------------------------------------------
local function newRow(i)
    local row = CreateFrame("Button", nil, content)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("TOPLEFT", 2, -2)
    row.title = row:CreateFontString(nil, "OVERLAY")
    font(row.title, "body")
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 5, 1)
    row.title:SetJustifyH("LEFT")
    row.right = row:CreateFontString(nil, "OVERLAY")
    font(row.right, "small")
    row.right:SetPoint("TOPRIGHT", -2, -1)
    row.right:SetJustifyH("RIGHT")
    row.title:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.sub = row:CreateFontString(nil, "OVERLAY")
    font(row.sub, "small")
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("RIGHT", -2, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetJustifyV("TOP")
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.08)
    row.hover:Hide()

    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        local it = self.item
        if not it then return end
        if it.itemId then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(it.itemId)
            GameTooltip:Show()
        elseif it.spellId and GameTooltip.SetSpellByID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetSpellByID, GameTooltip, it.spellId)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
        local it = self.item
        if not it then return end
        if IsModifiedClick and IsModifiedClick("CHATLINK") and it.itemId then
            local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo or (Compat and Compat.GetItemInfo)
            local link = nil
            if fn then
                local ok, _, l = pcall(fn, it.itemId)
                if ok then link = l end
            end
            if link and ChatEdit_InsertLink then
                ChatEdit_InsertLink(link)
                return
            end
        end
        if it.kind == "header" and it.group then
            toggleCollapsed(it.group)
        elseif it.onClick then
            it.onClick()
        end
    end)

    rows[i] = row
    return row
end

local function contentWidth()
    local s = Professions.settings
    local w = (s and s.window and s.window.w) or (frame and frame:GetWidth()) or WIDTH
    return w - 2 * PAD - 26
end

---------------------------------------------------------------------------
-- Toolbar Controls Updating
---------------------------------------------------------------------------
GEAR_STAT_LABELS = {
    all      = "Stat: All",
    agi      = "Stat: Agility",
    str      = "Stat: Strength",
    sta      = "Stat: Stamina",
    int      = "Stat: Intellect",
    spi      = "Stat: Spirit",
    sp       = "Stat: Spell Power",
    ap       = "Stat: Attack Power",
    crit_hit = "Stat: Crit / Hit",
    def      = "Stat: Defense",
    mp5      = "Stat: MP5",
    res      = "Stat: Resistance",
}

local LEGEND_PROFS = {
    { id = 0,   name = "All Materials",  icon = "Interface\\Icons\\INV_Misc_Bag_08", label = "All", w = 46 },
    { id = 197, name = "Tailoring",      icon = "Interface\\Icons\\Trade_Tailoring", label = "Tailor", w = 56 },
    { id = 165, name = "Leatherworking", icon = "Interface\\Icons\\Trade_LeatherWorking", label = "Leather", w = 62 },
    { id = 164, name = "Blacksmithing",  icon = "Interface\\Icons\\Trade_BlackSmithing", label = "Smith", w = 56 },
    { id = 202, name = "Engineering",    icon = "Interface\\Icons\\Trade_Engineering", label = "Eng", w = 50 },
    { id = 333, name = "Enchanting",     icon = "Interface\\Icons\\Trade_Engraving", label = "Ench", w = 52 },
    { id = 171, name = "Alchemy",        icon = "Interface\\Icons\\Trade_Alchemy", label = "Alch", w = 50 },
    { id = 185, name = "Cooking",        icon = "Interface\\Icons\\INV_Misc_Food_15", label = "Cook", w = 50 },
    { id = 129, name = "First Aid",      icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", label = "Aid", w = 48 },
    { id = 186, name = "Mining",         icon = "Interface\\Icons\\Trade_Mining", label = "Mining", w = 56 },
}

local legendBar
local legendButtons = {}

local function createLegendBar(parent)
    if legendBar then return legendBar end
    legendBar = CreateFrame("Frame", NAME .. "LegendBar", parent)
    legendBar:SetHeight(24)
    legendBar:SetPoint("TOPLEFT", PAD, -(scrollTop + BAR_H + 2))
    legendBar:SetPoint("RIGHT", -PAD, -(scrollTop + BAR_H + 2))

    local prevBtn = nil
    for i, def in ipairs(LEGEND_PROFS) do
        local btn = CreateFrame("Button", nil, legendBar, "BackdropTemplate")
        btn:SetSize(def.w, 22)
        if btn.SetBackdrop then
            btn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            btn:SetBackdropColor(0.10, 0.11, 0.13, 0.95)
            btn:SetBackdropBorderColor(0.25, 0.27, 0.30, 1)
        end
        if not prevBtn then
            btn:SetPoint("LEFT", 0, 0)
        else
            btn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
        end

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(14, 14)
        btn.icon:SetPoint("LEFT", 4, 0)
        btn.icon:SetTexture(def.icon)
        btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        btn.label = btn:CreateFontString(nil, "OVERLAY")
        font(btn.label, "small")
        btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 3, 0)
        btn.label:SetPoint("RIGHT", -2, 0)
        btn.label:SetJustifyH("LEFT")
        btn.label:SetText(def.label)

        btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.hl:SetAllPoints()
        btn.hl:SetColorTexture(1, 1, 1, 0.12)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(def.name, 1, 1, 1)
            local tip = def.id == 0 and "Click to show all crafting materials."
                or ("Click to filter materials for " .. def.name .. ".")
            GameTooltip:AddLine(tip, P.TEXT_MUTED.r, P.TEXT_MUTED.g, P.TEXT_MUTED.b, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        btn:SetScript("OnClick", function()
            local s = Professions.settings
            if s.matProfFilter == def.id then
                s.matProfFilter = 0
            else
                s.matProfFilter = def.id
            end
            Panel:Refresh()
        end)

        legendButtons[i] = btn
        prevBtn = btn
    end

    return legendBar
end

local function updateLegendBar()
    if not legendBar then return end
    local isMatTab = (tab == "materials")
    legendBar:SetShown(isMatTab)
    if not isMatTab then return end

    local s = Professions.settings
    local activeFilter = s and s.matProfFilter or 0

    for i, def in ipairs(LEGEND_PROFS) do
        local btn = legendButtons[i]
        local isSelected = (activeFilter == def.id)
        if btn and btn.SetBackdropColor then
            if isSelected then
                btn:SetBackdropColor(0.12, 0.24, 0.36, 0.98)
                btn:SetBackdropBorderColor(P.NEW.r, P.NEW.g, P.NEW.b, 1)
                btn.label:SetTextColor(P.NEW.r, P.NEW.g, P.NEW.b)
            else
                btn:SetBackdropColor(0.10, 0.11, 0.13, 0.95)
                btn:SetBackdropBorderColor(0.25, 0.27, 0.30, 1)
                btn.label:SetTextColor(0.85, 0.85, 0.85)
            end
        end
    end
end

local function profFilterLabel(val, myLabel, allLabel)
    if val == -1 then return myLabel or "My Alts' Profs" end
    if not val or val == 0 then return allLabel or "All Professions" end
    return WFC.DB.Recipes.PROFESSION_NAMES[val] or ("Prof " .. val)
end

local function updateToolbar()
    if not toolbar then return end
    local s = Professions.settings or Professions.DEFAULTS

    toolbar.matProfBtn:SetShown(tab == "materials")
    toolbar.matStockCheck:SetShown(tab == "materials")
    toolbar.scrollProfBtn:SetShown(tab == "scrolls")
    toolbar.scrollStateBtn:SetShown(tab == "scrolls")
    toolbar.scrollAtLevelBtn:SetShown(tab == "scrolls")
    toolbar.gearHaveMatsCheck:SetShown(tab == "gear")
    toolbar.gearUnlearnedCheck:SetShown(tab == "gear")
    toolbar.gearCharBtn:SetShown(tab == "gear")
    toolbar.gearStatBtn:SetShown(tab == "gear")
    toolbar.skillUpHaveMatsCheck:SetShown(tab == "skillup")
    toolbar.skillUpCharBtn:SetShown(tab == "skillup")
    toolbar.searchBox:SetShown(tab ~= "skillup")

    if tab == "materials" then
        toolbar.matProfBtn:SetText(profFilterLabel(s.matProfFilter, "My Alts' Profs", "All Mats"))
        toolbar.matStockCheck:SetChecked(s.matInStockOnly ~= false)
    elseif tab == "scrolls" then
        toolbar.scrollProfBtn:SetText(profFilterLabel(s.scrollProfFilter, "My Alts' Profs", "All Profs"))
        local st = s.scrollStateFilter or "all"
        local stLabel = st == "unlearned" and "Show: Unlearned"
            or st == "learned" and "Show: Learned"
            or st == "owned" and "Show: Scroll Owned"
            or "Show: All"
        toolbar.scrollStateBtn:SetText(stLabel)
        toolbar.scrollAtLevelBtn:SetText(s.scrollAtLearnedLevel and "|cffffd100At Learned Level|r" or "All Skill Levels")
    elseif tab == "gear" then
        toolbar.gearHaveMatsCheck:SetChecked(s.gearOnlyHaveMats == true)
        toolbar.gearUnlearnedCheck:SetChecked(s.gearIncludeUnlearned ~= false)
        local tc = s.gearTargetChar or "player"
        local tcLabel
        if tc == "player" then
            local pName = (WFC.Player and WFC.Player.name) or UnitName("player") or "Current"
            tcLabel = "For: " .. pName
        elseif tc == "all" then
            tcLabel = "For: All Alts"
        else
            local chars = Inventory:GetCharacters()
            for _, ch in ipairs(chars) do
                if ch.key == tc or ch.name == tc or ch.shortName == tc then
                    tcLabel = "For: " .. (ch.shortName or ch.name)
                    break
                end
            end
            if not tcLabel then tcLabel = "For: Alt" end
        end
        toolbar.gearCharBtn:SetText(tcLabel)
        local sf = s.gearStatFilter or "all"
        toolbar.gearStatBtn:SetText(GEAR_STAT_LABELS[sf] or "Stat: All")
    elseif tab == "skillup" then
        toolbar.skillUpHaveMatsCheck:SetChecked(s.skillUpOnlyHaveMats ~= false)
        local sFilter = s.skillUpCharFilter or "all"
        local sSort = s.skillUpSort or "current"
        local charLabel
        if sFilter == "player" then
            charLabel = "Char: Current Only"
        elseif sFilter ~= "all" then
            local chName = sFilter:match("^([^%-]+)") or sFilter
            charLabel = "Char: " .. chName
        elseif sSort == "gain" then
            charLabel = "Sort: Most Gain"
        elseif sSort == "name" then
            charLabel = "Sort: Name (A-Z)"
        else
            charLabel = "Sort: Current First"
        end
        toolbar.skillUpCharBtn:SetText(charLabel)
    end
end

---------------------------------------------------------------------------
-- Dedicated "Your Characters" Box Card (Skill-Up Tab)
---------------------------------------------------------------------------
local rosterCard
local function createRosterCard(parent)
    if rosterCard then return rosterCard end
    parent = parent or content
    if not parent then return nil end

    rosterCard = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if rosterCard.SetBackdrop then
        rosterCard:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        rosterCard:SetBackdropColor(0.08, 0.09, 0.12, 0.95)
        rosterCard:SetBackdropBorderColor(0.25, 0.29, 0.36, 1)
    end

    -- Header button of the box
    local header = CreateFrame("Button", nil, rosterCard)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(24)

    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints()
    headerBg:SetColorTexture(0.12, 0.14, 0.19, 0.95)
    header.bg = headerBg

    local hover = header:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.08)

    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexture("Interface\\Icons\\Achievement_Character_Orc_Male")
    header.icon = icon

    local title = header:CreateFontString(nil, "OVERLAY")
    font(title, "subheader")
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    header.title = title

    local toggle = header:CreateFontString(nil, "OVERLAY")
    font(toggle, "small")
    toggle:SetPoint("RIGHT", -8, 0)
    header.toggle = toggle

    header:SetScript("OnClick", function()
        toggleCollapsed("skillup_roster")
        Panel:Refresh()
    end)
    rosterCard.header = header

    -- Body container
    local body = CreateFrame("Frame", nil, rosterCard)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", rosterCard, "BOTTOMRIGHT", -1, 1)
    rosterCard.body = body

    rosterCard.charRows = {}
    return rosterCard
end

local function updateRosterCard(width)
    if not rosterCard and content then
        createRosterCard(content)
    end
    if not rosterCard then return 0 end

    local chars = Inventory:GetCharacters()
    local collapsed = isCollapsed("skillup_roster")

    rosterCard:ClearAllPoints()
    rosterCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    rosterCard:SetWidth(width)

    rosterCard.header.title:SetText(Colors.Wrap(("Your Characters (%d)"):format(#chars), P.NEW))

    if collapsed then
        rosterCard.header.toggle:SetText(Colors.Wrap("[+] Expand", P.TEXT_MUTED))
        rosterCard.body:Hide()
        rosterCard:SetHeight(26)
        return 26
    end

    rosterCard.header.toggle:SetText(Colors.Wrap("[-] Collapse", P.TEXT_MUTED))
    rosterCard.body:Show()

    local rowH = 30
    local innerY = 4
    for i, c in ipairs(chars) do
        local cr = rosterCard.charRows[i]
        if not cr then
            cr = CreateFrame("Frame", nil, rosterCard.body)
            cr.name = cr:CreateFontString(nil, "OVERLAY")
            font(cr.name, "body")
            cr.name:SetPoint("TOPLEFT", 8, 0)

            cr.active = cr:CreateFontString(nil, "OVERLAY")
            font(cr.active, "small")
            cr.active:SetPoint("TOPRIGHT", -8, 0)

            cr.profs = cr:CreateFontString(nil, "OVERLAY")
            font(cr.profs, "small")
            cr.profs:SetPoint("TOPLEFT", cr.name, "BOTTOMLEFT", 0, -2)
            cr.profs:SetPoint("RIGHT", -8, 0)
            cr.profs:SetJustifyH("LEFT")

            cr.divider = cr:CreateTexture(nil, "BACKGROUND")
            cr.divider:SetHeight(1)
            cr.divider:SetColorTexture(1, 1, 1, 0.06)
            cr.divider:SetPoint("BOTTOMLEFT", 4, 0)
            cr.divider:SetPoint("BOTTOMRIGHT", -4, 0)

            rosterCard.charRows[i] = cr
        end

        local profParts = {}
        for pId, pInfo in pairs(c.professions or {}) do
            profParts[#profParts + 1] = ("%s |cffffffff%d/%d|r"):format(
                pInfo.name or WFC.DB.Recipes.PROFESSION_NAMES[pId] or "Prof",
                pInfo.rank or 0, pInfo.max or 75)
        end
        table.sort(profParts)
        local profStr = #profParts > 0 and table.concat(profParts, " · ") or "No professions recorded yet (log in on this alt)"

        local classDisplay = (c.class and c.class:lower()) or "adventurer"
        cr.name:SetText(("%s |cffaaaaaa(Lvl %d %s)|r"):format(
            Inventory.ColorizeName(c.name, c.class), c.level or 1, classDisplay))
        cr.active:SetText(c.isCurrent and "|cff40ff40Active|r" or "")
        cr.profs:SetText(Colors.Wrap(profStr, P.TEXT_MUTED))
        cr.divider:SetShown(i < #chars)

        local profLines = math.max(1, math.ceil(#profParts / 3))
        local thisRowH = 18 + 12 * profLines
        cr:ClearAllPoints()
        cr:SetPoint("TOPLEFT", rosterCard.body, "TOPLEFT", 0, -innerY)
        cr:SetPoint("RIGHT", rosterCard.body, "RIGHT", 0, 0)
        cr:SetHeight(thisRowH)
        cr:Show()

        innerY = innerY + thisRowH + 2
    end

    for i = #chars + 1, #rosterCard.charRows do
        rosterCard.charRows[i]:Hide()
    end

    local totalH = 26 + innerY + 4
    rosterCard:SetHeight(totalH)
    return totalH
end

local function render()
    if not frame or not frame:IsShown() then return end
    updateToolbar()
    updateLegendBar()

    if scroll then
        local topOffset = scrollTop + BAR_H + 4
        if tab == "materials" then
            topOffset = topOffset + 26
        end
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", PAD, -topOffset)
        scroll:SetPoint("BOTTOMRIGHT", -PAD - 22, 32)
    end

    -- A failing tab builder must not leave the window blank or stale: show the error in the
    -- status line and report it once to BugSack.
    local ok, items, summary = pcall(Panel.DisplayRows, Panel)
    if not ok then
        local err = items
        if Panel.lastError ~= err then
            Panel.lastError = err
            geterrorhandler()(err)
        end
        items, summary = {}, "|cffff6060Error building this tab — see BugSack. Try /reload.|r"
    end
    local width = contentWidth()
    local y = 0

    if tab == "skillup" then
        local rosterH = updateRosterCard(width)
        if rosterCard then rosterCard:Show() end
        y = rosterH + 10
    elseif rosterCard then
        rosterCard:Hide()
    end
    if tab == "gear" then
        local ok2, h = pcall(updateGearCard, width)
        if ok2 then y = y + (h or 0) + 10 else geterrorhandler()(h) end
    elseif gearCard then
        gearCard:Hide()
    end

    for i, item in ipairs(items) do
        local row = rows[i] or newRow(i)
        local header = item.kind == "header"
        row.item = item
        row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        font(row.title, header and "subheader" or "body")
        row.title:SetText(header and ((item.collapsed and "+ " or "- ") .. item.title) or item.title)
        row.right:SetText(item.right or "")
        local sub = item.sub or {}
        local subText = table.concat(sub, "\n")
        row.sub:SetText(subText)
        local height
        if header then
            height = 22
        elseif subText ~= "" then
            row.sub:SetWidth(width - 24)
            local subH = row.sub:GetStringHeight() or 0
            height = 19 + math.max(LINE * #sub, subH + 2)
        else
            height = 19
        end
        row:SetSize(width, height)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row:SetAlpha(item.alpha or 1)
        row:Show()
        y = y + height + ROW_GAP
    end
    for i = #items + 1, #rows do rows[i]:Hide() end
    content:SetSize(width, math.max(y, 1))
    status:SetText(Colors.Wrap(summary or "", P.TEXT_MUTED))
end

function Panel:Refresh()
    WFC:RunOutOfCombat("professions:panel", render)
end

local function selectTab(key)
    tab = key
    if Professions.settings then
        Professions.settings.lastTab = key
    end
    if frame and frame.tabButtons then
        for i, t in ipairs(TABS) do
            local button = frame.tabButtons[i]
            if PanelTemplates_SetTab and frame.numTabs then
                if t.key == key then PanelTemplates_SetTab(frame, i) end
                if PanelTemplates_TabResize then PanelTemplates_TabResize(button, 0) end
            elseif t.key == key then
                button:LockHighlight()
            else
                button:UnlockHighlight()
            end
        end
    end
    Panel:Refresh()
end

---------------------------------------------------------------------------
-- Window Construction
---------------------------------------------------------------------------
local function createTabs()
    frame.tabButtons = {}
    local ok = PanelTemplates_SetNumTabs ~= nil
    for i, t in ipairs(TABS) do
        local button
        if ok then
            local okCreate, b = pcall(CreateFrame, "Button", NAME .. "Tab" .. i, frame, "PanelTabButtonTemplate")
            if okCreate then button = b else ok = false end
        end
        if not button then
            button = CreateFrame("Button", NAME .. "Tab" .. i, frame, "UIPanelButtonTemplate")
            button:SetSize(110, 20)
        end
        button:SetText(t.label)
        button:SetID(i)
        button:SetScript("OnClick", function() selectTab(t.key) end)
        frame.tabButtons[i] = button
    end
    if ok then
        frame.Tabs = frame.tabButtons
        PanelTemplates_SetNumTabs(frame, #TABS)
        frame.tabButtons[1]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
        for i = 2, #TABS do frame.tabButtons[i]:SetPoint("LEFT", frame.tabButtons[i - 1], "RIGHT", -14, 0) end
        for i = 1, #TABS do
            if PanelTemplates_TabResize then
                PanelTemplates_TabResize(frame.tabButtons[i], 0)
            end
        end
    else
        frame.numTabs = nil
        frame.tabButtons[1]:SetPoint("TOPLEFT", PAD, -28)
        for i = 2, #TABS do frame.tabButtons[i]:SetPoint("LEFT", frame.tabButtons[i - 1], "RIGHT", 4, 0) end
    end
    return ok
end

local function makeCheckbox(parent, labelText, tooltipText, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    local text = cb.text or cb.Text or cb:CreateFontString(nil, "OVERLAY")
    font(text, "small")
    text:ClearAllPoints()
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    text:SetText(labelText)
    cb.label = text
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() == true) end)
    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(labelText, 1, 1, 1)
        GameTooltip:AddLine(tooltipText, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return cb
end

local function buildProfMenuItems(currentVal, setter, includeAllLabel)
    local acctProfs = Engine:GetAccountProfessions()
    local items = {
        { text = "My Alts' Professions", selected = (currentVal == -1), fn = function() setter(-1) end },
        { text = includeAllLabel or "All Professions", selected = (currentVal == 0), fn = function() setter(0) end },
    }
    for _, p in ipairs(Engine.CRAFTING_PROFS) do
        local hasAlt = acctProfs[p.id] ~= nil
        local suffix = hasAlt and (" (" .. (acctProfs[p.id][1].char.shortName or "") .. ")") or ""
        items[#items + 1] = {
            text = p.name .. suffix,
            selected = (currentVal == p.id),
            fn = function() setter(p.id) end,
        }
    end
    return items
end

local function savePosition()
    if not Professions.settings then return end
    local point, _, _, x, y = frame:GetPoint(1)
    local w = Professions.settings.window
    w.point, w.x, w.y = point, x, y
    w.w, w.h = frame:GetSize()
end

local function create()
    local ok
    ok, frame = pcall(CreateFrame, "Frame", NAME, UIParent, "ButtonFrameTemplate")
    if not ok then
        frame = CreateFrame("Frame", NAME, UIParent, "BackdropTemplate")
        if frame.SetBackdrop then
            frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            frame:SetBackdropColor(0.086, 0.094, 0.11, 0.95)
            frame:SetBackdropBorderColor(0.23, 0.25, 0.28, 1)
        end
    elseif ButtonFrameTemplate_HidePortrait then
        ButtonFrameTemplate_HidePortrait(frame)
    end
    frame:Hide()
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(540, 380) elseif frame.SetMinResize then frame:SetMinResize(540, 380) end
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    tinsert(UISpecialFrames, NAME)

    local title = "WFC Professions"
    if frame.SetTitle then
        frame:SetTitle(title)
    elseif not frame.TitleText then
        frame.TitleText = frame:CreateFontString(nil, "OVERLAY")
        frame.TitleText:SetPoint("TOP", 0, -6)
        frame.TitleText:SetText(title)
    else
        frame.TitleText:SetText(title)
    end
    if frame.TitleText then font(frame.TitleText, "header") end

    local tabsBelow = createTabs()
    scrollTop = tabsBelow and 30 or 52

    -- Toolbar
    toolbar = CreateFrame("Frame", nil, frame)
    toolbar:SetPoint("TOPLEFT", PAD, -scrollTop)
    toolbar:SetPoint("RIGHT", -PAD, 0)
    toolbar:SetHeight(BAR_H)

    -- Materials controls
    toolbar.matProfBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    toolbar.matProfBtn:SetSize(130, 22)
    toolbar.matProfBtn:SetPoint("LEFT", 0, 0)
    toolbar.matProfBtn:SetScript("OnClick", function(self)
        local s = Professions.settings
        showDropdown(self, buildProfMenuItems(s.matProfFilter or 0, function(val)
            s.matProfFilter = val
            Panel:Refresh()
        end, "All Mats"))
    end)

    toolbar.matStockCheck = makeCheckbox(toolbar, "In Stock Only",
        "Only show crafting materials that at least one of your characters currently owns.",
        function(checked)
            Professions.settings.matInStockOnly = checked
            Panel:Refresh()
        end)
    toolbar.matStockCheck:SetPoint("LEFT", toolbar.matProfBtn, "RIGHT", 6, 0)

    -- Scrolls controls
    toolbar.scrollProfBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    toolbar.scrollProfBtn:SetSize(130, 22)
    toolbar.scrollProfBtn:SetPoint("LEFT", 0, 0)
    toolbar.scrollProfBtn:SetScript("OnClick", function(self)
        local s = Professions.settings
        showDropdown(self, buildProfMenuItems(s.scrollProfFilter or -1, function(val)
            s.scrollProfFilter = val
            Panel:Refresh()
        end, "All Professions"))
    end)

    toolbar.scrollStateBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    toolbar.scrollStateBtn:SetSize(136, 22)
    toolbar.scrollStateBtn:SetPoint("LEFT", toolbar.scrollProfBtn, "RIGHT", 6, 0)
    toolbar.scrollStateBtn:SetScript("OnClick", function(self)
        local s = Professions.settings
        local cur = s.scrollStateFilter or "all"
        showDropdown(self, {
            { text = "All Scroll Recipes", selected = (cur == "all"), fn = function() s.scrollStateFilter = "all"; Panel:Refresh() end },
            { text = "Unlearned Only",     selected = (cur == "unlearned"), fn = function() s.scrollStateFilter = "unlearned"; Panel:Refresh() end },
            { text = "Learned Only",       selected = (cur == "learned"), fn = function() s.scrollStateFilter = "learned"; Panel:Refresh() end },
            { text = "Scroll Owned Now",   selected = (cur == "owned"), fn = function() s.scrollStateFilter = "owned"; Panel:Refresh() end },
        })
    end)

    toolbar.scrollAtLevelBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    toolbar.scrollAtLevelBtn:SetSize(130, 22)
    toolbar.scrollAtLevelBtn:SetPoint("LEFT", toolbar.scrollStateBtn, "RIGHT", 6, 0)
    toolbar.scrollAtLevelBtn:SetScript("OnClick", function(self)
        local s = Professions.settings
        s.scrollAtLearnedLevel = not s.scrollAtLearnedLevel
        Panel:Refresh()
    end)
    toolbar.scrollAtLevelBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("At Learned Level", 1, 1, 1)
        GameTooltip:AddLine("Only show scroll recipes that your characters meet the required skill level to learn right now.", P.TEXT_MUTED.r, P.TEXT_MUTED.g, P.TEXT_MUTED.b, true)
        GameTooltip:Show()
    end)
    toolbar.scrollAtLevelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Craftable Gear controls (the 2 checkboxes + stat filter button)
    toolbar.gearHaveMatsCheck = makeCheckbox(toolbar, "Have Materials",
        "Only show equippable items that you have required crafting materials for (excluding vendor-bought items like thread/vials).",
        function(checked)
            Professions.settings.gearOnlyHaveMats = checked
            Panel:Refresh()
        end)
    toolbar.gearHaveMatsCheck:SetPoint("LEFT", 0, 0)

    toolbar.gearUnlearnedCheck = makeCheckbox(toolbar, "Include Unlearned",
        "Also include equippable items from recipes your alts haven't learned yet (marked as Needs Scroll or Trainer).",
        function(checked)
            Professions.settings.gearIncludeUnlearned = checked
            Panel:Refresh()
        end)
    toolbar.gearUnlearnedCheck:SetPoint("LEFT", toolbar.gearHaveMatsCheck.label, "RIGHT", 14, 0)

    toolbar.gearCharBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    toolbar.gearCharBtn:SetSize(115, 22)
    toolbar.gearCharBtn:SetPoint("LEFT", toolbar.gearUnlearnedCheck.label, "RIGHT", 14, 0)
    toolbar.gearCharBtn:SetScript("OnClick", function(self)
        local s = Professions.settings
        local cur = s.gearTargetChar or "player"
        local pName = (WFC.Player and WFC.Player.name) or UnitName("player") or "Current"
        local pClass = (WFC.Player and WFC.Player.classFile) or select(2, UnitClass("player")) or "WARRIOR"
        local pLvl = (WFC.Player and WFC.Player.level) or UnitLevel("player") or 1
        local pColorName = Inventory.ColorizeName(pName, pClass)

        local items = {
            {
                text = ("Current: %s (Lv %d)"):format(pColorName, pLvl),
                selected = (cur == "player"),
                fn = function() s.gearTargetChar = "player"; Panel:Refresh() end,
            },
            {
                text = "All Characters",
                selected = (cur == "all"),
                fn = function() s.gearTargetChar = "all"; Panel:Refresh() end,
            },
        }

        local chars = Inventory:GetCharacters()
        local curKey = (WFC.Player and WFC.Player.key) or (pName .. " - " .. (GetRealmName() or ""))
        for _, ch in ipairs(chars) do
            if ch.key ~= curKey then
                local cName = Inventory.ColorizeName(ch.shortName or ch.name, ch.class)
                local key = ch.key
                items[#items + 1] = {
                    text = ("%s (Lv %d %s)"):format(cName, ch.level or 1, ch.className or ch.class or ""),
                    selected = (cur == key),
                    fn = function() s.gearTargetChar = key; Panel:Refresh() end,
                }
            end
        end

        showDropdown(self, items)
    end)

    toolbar.gearStatBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    toolbar.gearStatBtn:SetSize(104, 22)
    toolbar.gearStatBtn:SetPoint("LEFT", toolbar.gearCharBtn, "RIGHT", 8, 0)
    toolbar.gearStatBtn:SetScript("OnClick", function(self)
        local s = Professions.settings
        local cur = s.gearStatFilter or "all"
        showDropdown(self, {
            { text = "All Stats",             selected = (cur == "all"),      fn = function() s.gearStatFilter = "all"; Panel:Refresh() end },
            { text = "Agility (Agi)",         selected = (cur == "agi"),      fn = function() s.gearStatFilter = "agi"; Panel:Refresh() end },
            { text = "Strength (Str)",        selected = (cur == "str"),      fn = function() s.gearStatFilter = "str"; Panel:Refresh() end },
            { text = "Stamina (Sta)",         selected = (cur == "sta"),      fn = function() s.gearStatFilter = "sta"; Panel:Refresh() end },
            { text = "Intellect (Int)",       selected = (cur == "int"),      fn = function() s.gearStatFilter = "int"; Panel:Refresh() end },
            { text = "Spirit (Spi)",          selected = (cur == "spi"),      fn = function() s.gearStatFilter = "spi"; Panel:Refresh() end },
            { text = "Spell Power / Healing", selected = (cur == "sp"),       fn = function() s.gearStatFilter = "sp"; Panel:Refresh() end },
            { text = "Attack Power",          selected = (cur == "ap"),       fn = function() s.gearStatFilter = "ap"; Panel:Refresh() end },
            { text = "Crit / Hit",            selected = (cur == "crit_hit"), fn = function() s.gearStatFilter = "crit_hit"; Panel:Refresh() end },
            { text = "Defense / Tank",        selected = (cur == "def"),      fn = function() s.gearStatFilter = "def"; Panel:Refresh() end },
            { text = "MP5 (Mana Regen)",      selected = (cur == "mp5"),      fn = function() s.gearStatFilter = "mp5"; Panel:Refresh() end },
            { text = "Resistance",            selected = (cur == "res"),      fn = function() s.gearStatFilter = "res"; Panel:Refresh() end },
        })
    end)

    -- Skill-Up controls
    toolbar.skillUpHaveMatsCheck = makeCheckbox(toolbar, "Have Materials",
        "Only show professions and recipes that you have crafting materials for right now across your characters.",
        function(checked)
            Professions.settings.skillUpOnlyHaveMats = checked
            Panel:Refresh()
        end)
    toolbar.skillUpHaveMatsCheck:SetPoint("LEFT", 0, 0)

    toolbar.skillUpCharBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    toolbar.skillUpCharBtn:SetSize(140, 22)
    toolbar.skillUpCharBtn:SetPoint("LEFT", toolbar.skillUpHaveMatsCheck.label, "RIGHT", 14, 0)
    toolbar.skillUpCharBtn:SetScript("OnClick", function(self)
        local s = Professions.settings
        local curSort = s.skillUpSort or "current"
        local curFilter = s.skillUpCharFilter or "all"
        local pName = (WFC.Player and WFC.Player.name) or UnitName("player") or "Current"
        local pClass = (WFC.Player and WFC.Player.classFile) or select(2, UnitClass("player")) or "WARRIOR"
        local pColorName = Inventory.ColorizeName(pName, pClass)

        local items = {
            {
                text = "Current Character First (Default)",
                selected = (curSort == "current" and curFilter == "all"),
                fn = function() s.skillUpSort = "current"; s.skillUpCharFilter = "all"; Panel:Refresh() end,
            },
            {
                text = "Most Skill Ready (All)",
                selected = (curSort == "gain" and curFilter == "all"),
                fn = function() s.skillUpSort = "gain"; s.skillUpCharFilter = "all"; Panel:Refresh() end,
            },
            {
                text = ("Only Current: %s"):format(pColorName),
                selected = (curFilter == "player"),
                fn = function() s.skillUpCharFilter = "player"; Panel:Refresh() end,
            },
            {
                text = "All Characters (A-Z)",
                selected = (curSort == "name" and curFilter == "all"),
                fn = function() s.skillUpSort = "name"; s.skillUpCharFilter = "all"; Panel:Refresh() end,
            },
        }

        local chars = Inventory:GetCharacters()
        local curKey = (WFC.Player and WFC.Player.key) or (pName .. " - " .. (GetRealmName() or ""))
        for _, ch in ipairs(chars) do
            if ch.key ~= curKey then
                local cName = Inventory.ColorizeName(ch.shortName or ch.name, ch.class)
                local key = ch.key
                items[#items + 1] = {
                    text = ("Only: %s"):format(cName),
                    selected = (curFilter == key),
                    fn = function() s.skillUpCharFilter = key; Panel:Refresh() end,
                }
            end
        end

        showDropdown(self, items)
    end)

    -- Search box on the right of the toolbar
    local searchBox = CreateFrame("EditBox", NAME .. "Search", toolbar, "InputBoxTemplate")
    searchBox:SetSize(116, 20)
    searchBox:SetPoint("RIGHT", -4, 0)
    searchBox:SetAutoFocus(false)
    searchBox.placeholder = searchBox:CreateFontString(nil, "OVERLAY")
    font(searchBox.placeholder, "small")
    searchBox.placeholder:SetPoint("LEFT", 6, 0)
    searchBox.placeholder:SetText(Colors.Wrap("Search...", P.TEXT_MUTED))
    searchBox:SetScript("OnTextChanged", function(self)
        local txt = self:GetText() or ""
        self.placeholder:SetShown(txt == "")
        searchQuery = txt
        Panel:Refresh()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    toolbar.searchBox = searchBox

    -- Scroll Frame
    scroll = CreateFrame("ScrollFrame", NAME .. "Scroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", PAD, -(scrollTop + BAR_H + 4))
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 22, 32)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(contentWidth(), 1)
    scroll:SetScrollChild(content)

    -- Materials Legend Bar (clickable row to easily switch between professions)
    createLegendBar(frame)

    -- Resize grip in bottom-right corner
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        savePosition()
        Panel:Refresh()
    end)

    status = frame:CreateFontString(nil, "OVERLAY")
    font(status, "small")
    status:SetPoint("BOTTOMLEFT", PAD + 2, 10)

    Panel:RestorePosition()
end

function Panel:RestorePosition()
    if not frame then return end
    local w = Professions.settings and Professions.settings.window or {}
    local curW = w.w
    if not curW or curW < WIDTH then
        curW = WIDTH
        w.w = WIDTH
    end
    local curH = w.h
    if not curH or curH < HEIGHT then
        curH = HEIGHT
        w.h = HEIGHT
    end
    frame:SetSize(curW, curH)
    frame:ClearAllPoints()
    if w.point and w.x and w.y then
        frame:SetPoint(w.point, UIParent, w.point, w.x, w.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
end

function Panel:ResetPosition()
    if not frame then return end
    self:RestorePosition()
    self:Refresh()
end

function Panel:Show()
    if not frame then create() end
    self:CreateLauncher()
    if ns.Inventory then
        ns.Inventory:Invalidate()
    end
    local initialTab = (Professions.settings and Professions.settings.lastTab) or "materials"
    frame:Show()
    selectTab(initialTab)
end

function Panel:ShowTab(key)
    if not frame then create() end
    if ns.Inventory then
        ns.Inventory:Invalidate()
    end
    frame:Show()
    selectTab(key)
end

function Panel:Hide()
    if frame then frame:Hide() end
end

function Panel:Toggle()
    if frame and frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

---------------------------------------------------------------------------
-- Quick Button on Profession Window & Item Load Refresh
---------------------------------------------------------------------------
local tradeBtn
local function attachTradeSkillButton()
    if tradeBtn then return end
    local parent = ProfessionsFrame or TradeSkillFrame
    if not parent then return end
    tradeBtn = CreateFrame("Button", "WFC_ProfessionsTradeButton", parent, "UIPanelButtonTemplate")
    tradeBtn:SetSize(84, 20)
    tradeBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -42, -2)
    tradeBtn:SetFrameLevel((parent:GetFrameLevel() or 1) + 10)
    tradeBtn:SetText("WFC Prof")
    tradeBtn:SetScript("OnClick", function() Panel:Toggle() end)
    tradeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("WFC Professions (/wfc prof)", 1, 1, 1)
        GameTooltip:AddLine("Open cross-character materials, scroll recipes, craftable gear & skill-up planner.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    tradeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

WFC:RegisterEvent("TRADE_SKILL_SHOW", attachTradeSkillButton)

local itemLoadTimer
WFC:On("WFC_ITEM_LOADED", function()
    if not frame or not frame:IsShown() then return end
    if itemLoadTimer then return end
    itemLoadTimer = C_Timer.NewTimer(0.25, function()
        itemLoadTimer = nil
        Panel:Refresh()
    end)
end)

---------------------------------------------------------------------------
-- Top-Left Screen Quick Launcher Button
---------------------------------------------------------------------------
local launcher

function Panel:CreateLauncher()
    if launcher then return launcher end
    local s = Professions.settings or Professions.DEFAULTS

    launcher = CreateFrame("Button", "WFC_ProfessionsLauncher", UIParent, "BackdropTemplate")
    launcher:SetSize(28, 28)
    launcher:SetFrameStrata("HIGH")
    launcher:SetClampedToScreen(true)
    launcher:SetMovable(true)
    launcher:EnableMouse(true)
    launcher:RegisterForClicks("LeftButtonUp")
    launcher:RegisterForDrag("LeftButton", "RightButton")

    if launcher.SetBackdrop then
        launcher:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        launcher:SetBackdropColor(0.08, 0.09, 0.12, 0.95)
        launcher:SetBackdropBorderColor(0.30, 0.75, 0.95, 0.85)
    end

    local pos = (s and s.launcherPos) or { point = "TOPLEFT", x = 14, y = -60 }
    launcher:ClearAllPoints()
    launcher:SetPoint(pos.point or "TOPLEFT", UIParent, pos.point or "TOPLEFT", pos.x or 14, pos.y or -60)

    launcher:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    launcher:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        if Professions.settings then
            Professions.settings.launcherPos = { point = point, x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
        end
    end)

    local icon = launcher:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture("Interface\\Icons\\Trade_Engraving")
    launcher.icon = icon

    local hover = launcher:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.18)

    launcher:SetScript("OnClick", function()
        Panel:Toggle()
    end)

    launcher:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("WFC Professions", 0.3, 0.85, 1)
        GameTooltip:AddLine("Click to open professions & material manager (/wfc prof)", 1, 1, 1, true)
        GameTooltip:AddLine("Drag with mouse to reposition anywhere on screen.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    launcher:SetScript("OnLeave", function() GameTooltip:Hide() end)

    launcher:SetShown(s.showLauncher ~= false)
    return launcher
end

function Panel:UpdateLauncher()
    if not launcher then
        self:CreateLauncher()
        return
    end
    local s = Professions.settings or Professions.DEFAULTS
    launcher:SetShown(s.showLauncher ~= false)
end

WFC:RegisterEvent("PLAYER_LOGIN", function()
    Panel:CreateLauncher()
end)

-- Gear tab: keep the slot view current when equipment changes while the window is open.
WFC:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function()
    if frame and frame:IsShown() and tab == "gear" then Panel:Refresh() end
end)
