local _, ns = ...
local WFC = WFC

-- What gets restyled (design.md §7.5), the conflict guard, tooltips, and start-up.
-- Frames that don't exist on a client (Forever vs Classic Era names differ) are skipped.
-- Not touched: unit frames, action bars, nameplates, Edit Mode positions, the cooldown
-- manager, the damage meter, and the world map (taint-sensitive; its border stays Blizzard's).

local Overlay, Skin, Fonts = ns.Overlay, ns.Skin, ns.Fonts
local Themes = ns.Themes
local RGB = Themes.RGB
local Compat = WFC.Compat

---------------------------------------------------------------------------
-- Registry
---------------------------------------------------------------------------
local CORE = {
    "CharacterFrame", "SpellBookFrame", "QuestLogFrame", "MerchantFrame", "MailFrame", "OpenMailFrame",
    "GossipFrame", "QuestFrame", "FriendsFrame", "PVEFrame", "LFGParentFrame", "GameMenuFrame", "SettingsPanel",
    "DressUpFrame", "LootFrame", "ItemTextFrame", "TabardFrame", "PetStableFrame", "TaxiFrame",
    "ContainerFrameCombinedBags", "ContainerFrame1", "ContainerFrame2", "ContainerFrame3", "ContainerFrame4",
    "ContainerFrame5", "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4",
}
local ECONOMY = { "BankFrame", "TradeFrame" }
local LOAD_ON_DEMAND = {
    { "PlayerSpellsFrame", "core", "Blizzard_PlayerSpells" },
    { "CommunitiesFrame", "core", "Blizzard_Communities" },
    { "ProfessionsFrame", "economy", "Blizzard_Professions" },
    { "TradeSkillFrame", "economy", "Blizzard_TradeSkillUI" },
    { "ClassTrainerFrame", "economy", "Blizzard_TrainerUI" },
    { "AuctionHouseFrame", "economy", "Blizzard_AuctionHouseUI" },
    { "AuctionFrame", "economy", "Blizzard_AuctionUI" },
    -- The map and quest log window. Its frame art lives on WorldMapFrame.BorderFrame (Skin.lua
    -- fades it there); the map canvas is a ScrollFrame, which the deep fade never enters.
    { "WorldMapFrame", "core", "Blizzard_WorldMap" },
}
-- WFC windows: our own frames, skinned by the same functions. Their fonts stay WFC's
-- unless "Use theme header fonts in WFC windows" is on.
local WFC_FRAMES = {
    WFC_QuestPanel = {}, WFC_QuestRewards = {}, WFC_DungeonMap = {}, WFC_TextBox = {}, WFC_DevWindow = {},
    WFC_TravelBox = { noTitleBand = true, noTopLeft = true }, WFC_DungeonLegend = { noTitleBand = true, noTopLeft = true },
    WFC_QuestMenu = { noTitleBand = true, noTopLeft = true, noBand = true, buttons = false },
}
local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "EmbeddedItemTooltip" }
local TOOLTIP_OPTS = { alpha = 0.95, noTitleBand = true, noOrnaments = true, noTopLeft = true, noBand = true,
    buttons = false, keepFonts = true, tooltip = true }

-- Windows whose pages are printed in dark ink: the Modern / Futuristic deep fade keeps their
-- parchment (only frame chrome goes) so the text stays readable.
local INK_PAGES = { SpellBookFrame = true, PlayerSpellsFrame = true, OpenMailFrame = true }

for _, name in ipairs(CORE) do
    local opts = { noTopLeft = true }
    if name == "QuestFrame" or name == "GossipFrame" or name == "ItemTextFrame" then
        opts.parchment = true
    elseif name == "QuestLogFrame" then
        opts.questLogParchment = true
    end
    if INK_PAGES[name] then opts.deep = "border" end
    Skin:Register(name, "core", opts)
end
for _, name in ipairs(ECONOMY) do Skin:Register(name, "economy", { noTopLeft = true }) end
for _, f in ipairs(LOAD_ON_DEMAND) do
    Skin:Register(f[1], f[2], { noTopLeft = true, deep = INK_PAGES[f[1]] and "border" or nil }, f[3])
end

---------------------------------------------------------------------------
-- Bagnon (BagBrother): its inventory / bank windows replace Blizzard's bags. They're unnamed,
-- so they're attached when Bagnon shows them.
---------------------------------------------------------------------------
local function hookBagnon()
    local B = _G.Bagnon
    if Overlay.bagnonHooked or not (B and B.Frames and B.Frames.Show and hooksecurefunc) then return end
    Overlay.bagnonHooked = true
    local function attach(id)
        local ok, f = pcall(B.Frames.Get, B.Frames, id)
        if ok and type(f) == "table" and f[0] and f.GetObjectType then
            Skin:Attach(f, "economy", { noTopLeft = true, noBand = true })
        end
    end
    hooksecurefunc(B.Frames, "Show", function(_, id) attach(id) end)
    for _, id in ipairs({ "inventory", "bank", "guild", "vault" }) do attach(id) end
end
for name, opts in pairs(WFC_FRAMES) do Skin:Register(name, "wfc", opts) end
for _, name in ipairs(TOOLTIPS) do Skin:Register(name, "tooltips", TOOLTIP_OPTS) end

---------------------------------------------------------------------------
-- Every other Blizzard window (Legacy Points and whatever Forever adds): picked up from the
-- UI panel table, the Escape-closable list and every ShowUIPanel call. Only frames whose global
-- was created by Blizzard's own (secure) code, never another addon's, and only ones that look
-- like a window (frame art, a title bar, a portrait or a close button).
---------------------------------------------------------------------------
local NOT_WINDOWS = { CinematicFrame = true, MovieFrame = true, SubtitlesFrame = true, BarberShopFrame = true,
    CharacterCreateFrame = true, StoreFrame = true, LossOfControlFrame = true }

local function isForbiddenFrame(f)
    local ok, forbidden = pcall(function() return f.IsForbidden and f:IsForbidden() end)
    return not ok or forbidden == true
end

local function looksLikeWindow(f)
    return f.NineSlice or f.Bg or f.TitleContainer or f.PortraitContainer or f.CloseButton or f.Inset or f.BorderFrame
end

local function autoRegister(name)
    if type(name) ~= "string" or Skin.registry[name] or NOT_WINDOWS[name] or name:find("^WFC_") then return end
    local f = _G[name]
    if type(f) ~= "table" or not f.GetObjectType or isForbiddenFrame(f) then return end
    if not issecurevariable then return end
    local ok, secure = pcall(issecurevariable, name)
    if not (ok and secure) then return end
    local okT, kind = pcall(f.GetObjectType, f)
    if not (okT and kind == "Frame") or not looksLikeWindow(f) then return end
    Skin:Register(name, "core", { noTopLeft = true, auto = true })
    Skin:Watch(name)
end

local function sweepWindows()
    for name in pairs(_G.UIPanelWindows or {}) do autoRegister(name) end
    for _, name in ipairs(_G.UISpecialFrames or {}) do autoRegister(name) end
end

local function hookShowUIPanel()
    if Overlay.panelHooked or not (hooksecurefunc and _G.ShowUIPanel) then return end
    Overlay.panelHooked = true
    hooksecurefunc("ShowUIPanel", function(frame)
        if type(frame) ~= "table" or isForbiddenFrame(frame) then return end
        local ok, name = pcall(function() return frame.GetName and frame:GetName() end)
        if ok then autoRegister(name) end
    end)
end

---------------------------------------------------------------------------
-- Conflict guard (design §7.6): other skin addons own their frames.
---------------------------------------------------------------------------
local CONFLICTS = {
    { "ElvUI", { fonts = true, tooltips = true, core = true, economy = true } },
    { "Aurora", { fonts = true, tooltips = true, core = true, economy = true } },
    { "ForeverUI", { core = true, economy = true } },
    { "ForeverClassicUI", { core = true } },
}

function Overlay:CheckConflicts()
    self.blocked, self.blockedBy = nil, nil
    for _, c in ipairs(CONFLICTS) do
        if Compat.IsAddOnLoaded(c[1]) then
            self.blocked = self.blocked or {}
            for module in pairs(c[2]) do self.blocked[module] = true end
            self.blockedBy = self.blockedBy and (self.blockedBy .. ", " .. c[1]) or c[1]
        end
    end
    if self.blockedBy and not self.warned then
        self.warned = true
        WFC:Print(("OverlayRevamp leaves %s's windows alone (it skins them already)."):format(self.blockedBy))
    end
end

---------------------------------------------------------------------------
-- Item tooltips: the item-quality colour as a 1 px top edge (design §7.4.7)
---------------------------------------------------------------------------
local function qualityEdge(tooltip, itemId)
    if not (Overlay:ModuleOn("tooltips") and itemId) then return end
    local quality = select(3, Compat.GetItemInfo(itemId))
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c then Skin:TopEdge(tooltip, c.r, c.g, c.b) end
end

---------------------------------------------------------------------------
-- Quest & Gossip text contrast (crisp typography tailored to the parchment inset)
---------------------------------------------------------------------------
local function getColors()
    local theme = Overlay:Theme()
    local p = theme and theme.parchment
    if p then
        local hr, hg, hb = RGB(p.header)
        local tr, tg, tb = RGB(p.text)
        local mr, mg, mb = RGB(p.muted)
        local ar, ag, ab = RGB(theme.accent)
        return hr, hg, hb, tr, tg, tb, mr, mg, mb, ar, ag, ab
    end
    return 0.38, 0.14, 0.03, 0.11, 0.08, 0.05, 0.28, 0.18, 0.10, 0.85, 0.55, 0.15
end

local function setParchmentText(fs, r, g, b, isHeader)
    if not fs then return end
    local theme = Overlay:Theme()
    local p = theme and theme.parchment
    local custom = p and (isHeader and p.headerShadow or (not isHeader and p.bodyShadow))
    if custom and fs.SetTextColor and not (fs.IsObjectType and fs:IsObjectType("SimpleHTML")) then
        -- Dark reading panels (Modern / Futuristic): light text with a dark drop shadow.
        pcall(fs.SetTextColor, fs, r, g, b, 1)
        if fs.SetShadowOffset then
            fs:SetShadowOffset(1, -1)
            fs:SetShadowColor(custom[1], custom[2], custom[3], custom[4] or 1)
        end
        return
    end
    if fs.IsObjectType and fs:IsObjectType("SimpleHTML") then
        if fs.SetTextColor then
            pcall(fs.SetTextColor, fs, "p", r, g, b)
            pcall(fs.SetTextColor, fs, "h1", r, g, b)
            pcall(fs.SetTextColor, fs, "h2", r, g, b)
        end
        return
    end
    if fs.SetTextColor then
        pcall(fs.SetTextColor, fs, r, g, b, 1)
        if fs.SetShadowOffset then
            if isHeader then
                fs:SetShadowOffset(1, -1)
                fs:SetShadowColor(1, 1, 1, 0.45)
            else
                fs:SetShadowOffset(0, 0)
            end
        end
    end
end

local function recolorQuestInfo()
    if not (Overlay:ModuleOn("core") and Overlay:Theme()) then return end
    local hr, hg, hb, tr, tg, tb, mr, mg, mb = getColors()

    -- Title & section headers (rich embossed mahogany/copper)
    setParchmentText(QuestInfoTitleHeader, hr, hg, hb, true)
    setParchmentText(QuestInfoDescriptionHeader, hr, hg, hb, true)
    setParchmentText(QuestInfoObjectivesHeader, hr, hg, hb, true)
    if QuestInfoRewardsFrame then setParchmentText(QuestInfoRewardsFrame.Header, hr, hg, hb, true) end

    -- Narrative & description (deep crisp dark ink)
    setParchmentText(QuestInfoDescriptionText, tr, tg, tb, false)
    setParchmentText(QuestInfoObjectivesText, tr, tg, tb, false)
    setParchmentText(QuestInfoGroupSize, mr, mg, mb, false)

    -- Rewards & completion details
    setParchmentText(QuestInfoRewardText, mr, mg, mb, false)
    setParchmentText(QuestInfoItemChooseText, hr, hg, hb, true)
    setParchmentText(QuestInfoItemReceiveText, hr, hg, hb, true)
    setParchmentText(QuestInfoSpellLearnText, hr, hg, hb, true)
    if QuestInfoXPFrame then setParchmentText(QuestInfoXPFrame.ReceiveText, mr, mg, mb, false) end
    if QuestRewardText then setParchmentText(QuestRewardText, tr, tg, tb, false) end

    local i = 1
    while _G["QuestInfoObjective" .. i] do
        setParchmentText(_G["QuestInfoObjective" .. i], tr, tg, tb, false)
        i = i + 1
    end
end

local function recolorQuestProgress()
    if not (Overlay:ModuleOn("core") and Overlay:Theme()) then return end
    local hr, hg, hb, tr, tg, tb, mr, mg, mb = getColors()

    setParchmentText(QuestProgressTitleText, hr, hg, hb, true)
    setParchmentText(QuestProgressText, tr, tg, tb, false)
    setParchmentText(QuestProgressRequiredItemsText, hr, hg, hb, true)
    setParchmentText(QuestProgressRequiredMoneyText, mr, mg, mb, false)
end

local function recolorQuestGreeting()
    if not (Overlay:ModuleOn("core") and Overlay:Theme()) then return end
    local hr, hg, hb, tr, tg, tb, mr, mg, mb, ar, ag, ab = getColors()

    setParchmentText(GreetingText, tr, tg, tb, false)
    setParchmentText(QuestGreetingDescriptionText, tr, tg, tb, false)
    setParchmentText(CurrentQuestsText, hr, hg, hb, true)
    setParchmentText(AvailableQuestsText, hr, hg, hb, true)

    for i = 1, 32 do
        local b = _G["QuestTitleButton" .. i]
        if b then
            local fs = b:GetFontString()
            if fs then setParchmentText(fs, hr, hg, hb, false) end
            if not b._wfcHoverHooked then
                b._wfcHoverHooked = true
                b:HookScript("OnEnter", function()
                    local hhr, hhg, hhb, _, _, _, _, _, _, har, hag, hab = getColors()
                    setParchmentText(b:GetFontString(), har, hag, hab, false)
                end)
                b:HookScript("OnLeave", function()
                    local hhr, hhg, hhb = getColors()
                    setParchmentText(b:GetFontString(), hhr, hhg, hhb, false)
                end)
            end
        end
    end
end

local function recolorGossip()
    if not (Overlay:ModuleOn("core") and Overlay:Theme()) then return end
    local hr, hg, hb, tr, tg, tb, mr, mg, mb, ar, ag, ab = getColors()

    setParchmentText(GossipGreetingText, tr, tg, tb, false)

    for i = 1, 32 do
        local b = _G["GossipTitleButton" .. i]
        if b then
            local fs = b:GetFontString()
            if fs then setParchmentText(fs, hr, hg, hb, false) end
            if not b._wfcHoverHooked then
                b._wfcHoverHooked = true
                b:HookScript("OnEnter", function()
                    local hhr, hhg, hhb, _, _, _, _, _, _, har, hag, hab = getColors()
                    setParchmentText(b:GetFontString(), har, hag, hab, false)
                end)
                b:HookScript("OnLeave", function()
                    local hhr, hhg, hhb = getColors()
                    setParchmentText(b:GetFontString(), hhr, hhg, hhb, false)
                end)
            end
        end
    end
end

-- Forever's (mainline) dialogue lists are ScrollBoxes: the greeting and each option are pooled
-- element frames, not GossipGreetingText / GossipTitleButtonN. Recolour whatever is showing:
-- text lines in the reading colour, options in the header colour, lit on hover.
local hoverHooked = setmetatable({}, { __mode = "k" })

local function hoverColor()
    local theme = Overlay:Theme()
    local c = theme and theme.fontColors and theme.fontColors.GameFontNormal
    if c then return c[1], c[2], c[3] end
    local _, _, _, _, _, _, _, _, _, ar, ag, ab = getColors()
    return ar, ag, ab
end

local function recolorElement(el, hr, hg, hb, tr, tg, tb)
    local okB, isButton = pcall(function() return el:IsObjectType("Button") end)
    if okB and isButton then
        local fs = el.GetFontString and el:GetFontString()
        if fs then setParchmentText(fs, hr, hg, hb, false) end
        if not hoverHooked[el] and el.HookScript then
            hoverHooked[el] = true
            el:HookScript("OnEnter", function(self)
                if not Overlay:Theme() then return end
                local r, g, b = hoverColor()
                setParchmentText(self:GetFontString(), r, g, b, false)
            end)
            el:HookScript("OnLeave", function(self)
                if not Overlay:Theme() then return end
                local r, g, b = getColors()
                setParchmentText(self:GetFontString(), r, g, b, false)
            end)
        end
        return
    end
    local okR, regions = pcall(function() return { el:GetRegions() } end)
    for _, r in ipairs(okR and regions or {}) do
        local okF, isFS = pcall(function() return r:IsObjectType("FontString") end)
        if okF and isFS then setParchmentText(r, tr, tg, tb, false) end
    end
end

local function recolorBox(box)
    if not (box and box.ForEachFrame) then return end
    if not (Overlay:ModuleOn("core") and Overlay:Theme()) then return end
    local hr, hg, hb, tr, tg, tb = getColors()
    pcall(box.ForEachFrame, box, function(el) recolorElement(el, hr, hg, hb, tr, tg, tb) end)
end

local function dialogueBoxes()
    return {
        GossipFrame and GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.ScrollBox,
        QuestFrame and QuestFrame.GreetingPanel and QuestFrame.GreetingPanel.ScrollBox,
        QuestFrameGreetingPanel and QuestFrameGreetingPanel.ScrollBox,
    }
end

local boxPending
local function recolorDialogue()
    if boxPending then return end
    boxPending = true
    C_Timer.After(0, function()
        boxPending = false
        for _, box in pairs(dialogueBoxes()) do recolorBox(box) end
    end)
end

local function recolorQuestLog()
    if not (Overlay:ModuleOn("core") and Overlay:Theme()) then return end
    local hr, hg, hb, tr, tg, tb, mr, mg, mb = getColors()

    setParchmentText(QuestLogQuestTitle, hr, hg, hb, true)
    setParchmentText(QuestLogDescriptionTitle, hr, hg, hb, true)
    setParchmentText(QuestLogQuestDescription, tr, tg, tb, false)
    setParchmentText(QuestLogObjectivesText, tr, tg, tb, false)
    setParchmentText(QuestLogRewardTitleText, hr, hg, hb, true)
    setParchmentText(QuestLogItemChooseText, mr, mg, mb, false)
    setParchmentText(QuestLogItemReceiveText, mr, mg, mb, false)
    setParchmentText(QuestLogTimerText, hr, hg, hb, true)

    local i = 1
    while _G["QuestLogObjective" .. i] do
        setParchmentText(_G["QuestLogObjective" .. i], tr, tg, tb, false)
        i = i + 1
    end
end

-- Each hook is installed once (this runs again on every ADDON_LOADED for late frames).
local hooksDone = {}
local function once(key, target, fn)
    if hooksDone[key] or not target then return end
    hooksDone[key] = true
    fn()
end

local function hookQuestText()
    if hooksecurefunc then
        once("QuestInfo_Display", QuestInfo_Display, function() pcall(hooksecurefunc, "QuestInfo_Display", recolorQuestInfo) end)
        once("QuestLog_Update", QuestLog_Update, function() pcall(hooksecurefunc, "QuestLog_Update", recolorQuestLog) end)
        once("GossipFrameUpdate", GossipFrameUpdate, function() pcall(hooksecurefunc, "GossipFrameUpdate", recolorGossip) end)
        once("GossipFrame.Update", GossipFrame and GossipFrame.Update, function()
            pcall(hooksecurefunc, GossipFrame, "Update", function() recolorGossip(); recolorDialogue() end)
        end)

        -- SetText hooks ensure dynamic text is restyled immediately upon change
        local function onSetText(key, fs, fn)
            once(key, fs and fs.SetText, function() pcall(hooksecurefunc, fs, "SetText", fn) end)
        end
        onSetText("GossipGreetingText", GossipGreetingText, recolorGossip)
        onSetText("GreetingText", GreetingText, recolorQuestGreeting)
        onSetText("QuestInfoDescriptionText", QuestInfoDescriptionText, recolorQuestInfo)
        onSetText("QuestProgressText", QuestProgressText, recolorQuestProgress)
        onSetText("QuestRewardText", QuestRewardText, recolorQuestInfo)
        onSetText("QuestLogQuestDescription", QuestLogQuestDescription, recolorQuestLog)
    end
    local function onShow(key, frame, fn)
        once(key, frame and frame.HookScript and frame, function() frame:HookScript("OnShow", fn) end)
    end
    onShow("QuestFrameProgressPanel", QuestFrameProgressPanel, recolorQuestProgress)
    onShow("QuestFrameRewardPanel", QuestFrameRewardPanel, recolorQuestInfo)
    onShow("QuestFrameDetailPanel", QuestFrameDetailPanel, recolorQuestInfo)
    onShow("QuestFrameGreetingPanel", QuestFrameGreetingPanel, function() recolorQuestGreeting(); recolorDialogue() end)
    onShow("QuestFrame", QuestFrame, function()
        recolorQuestInfo()
        recolorQuestProgress()
        recolorQuestGreeting()
        recolorDialogue()
    end)
    onShow("GossipFrame", GossipFrame, function() recolorGossip(); recolorDialogue() end)
    onShow("QuestLogFrame", QuestLogFrame, recolorQuestLog)
    -- Options scrolled into view are freshly acquired frames: recolour them too.
    if ScrollUtil and ScrollUtil.AddAcquiredFrameCallback then
        for i, box in pairs(dialogueBoxes()) do
            once("box" .. i, box, function()
                pcall(ScrollUtil.AddAcquiredFrameCallback, box, function() recolorDialogue() end, Overlay, false)
            end)
        end
    end
    if ItemTextFrame and ItemTextFrame.HookScript then
        ItemTextFrame:HookScript("OnShow", function()
            local _, _, _, tr, tg, tb = getColors()
            setParchmentText(ItemTextPageText, tr, tg, tb, false)
        end)
    end
end

---------------------------------------------------------------------------
-- Start-up and live changes
---------------------------------------------------------------------------
--- Applies the current settings everywhere: fonts, already-skinned frames, ornaments.
function Overlay:Restyle()
    if not self.started then return end
    WFC:RunOutOfCombat("overlay:restyle", function()
        local theme = self:Theme()
        Fonts:Apply(theme)
        Skin:RestyleAll()
        Skin:WatchAll()
        if ns.Chrome then ns.Chrome:Apply() end
        if ns.ThemeButton then ns.ThemeButton:Refresh() end
        recolorQuestInfo()
        recolorQuestProgress()
        recolorQuestGreeting()
        recolorGossip()
        recolorQuestLog()
        recolorDialogue()
    end)
end

WFC:RegisterEvent("PLAYER_LOGIN", function()
    Overlay:CheckConflicts()
    Overlay.started = true
    WFC:RunOutOfCombat("overlay:start", function()
        Fonts:Apply(Overlay:Theme())
        Skin:HookTabs()
        Skin:WatchAll()
        if ns.Chrome then ns.Chrome:Apply() end
        if ns.ThemeButton then ns.ThemeButton:Refresh() end
        hookBagnon()
        hookShowUIPanel()
        sweepWindows()
        hookQuestText()
        local frames = {}
        for _, name in ipairs(TOOLTIPS) do frames[#frames + 1] = _G[name] end
        Compat.HookItemTooltips(qualityEdge, frames)
        -- The quality line belongs to the item: clear it when the tooltip is reused.
        for _, tt in ipairs(frames) do
            if tt.HookScript then
                pcall(tt.HookScript, tt, "OnTooltipCleared", function(self) Skin:ClearTopEdge(self) end)
            end
        end
    end)
end)

WFC:RegisterEvent("ADDON_LOADED", function()
    if Overlay.started then
        hookQuestText()
        hookBagnon()
        sweepWindows()
    end
end)

WFC:RegisterEvent("GOSSIP_SHOW", recolorGossip)
WFC:RegisterEvent("QUEST_GREETING", recolorQuestGreeting)
WFC:RegisterEvent("QUEST_DETAIL", recolorQuestInfo)
WFC:RegisterEvent("QUEST_PROGRESS", recolorQuestProgress)
WFC:RegisterEvent("QUEST_COMPLETE", recolorQuestInfo)

-- WFC windows are created at PLAYER_LOGIN by the other WFC addons; watch them once they exist.
WFC:On("WFC_DB_READY", function() Skin:WatchAll() end)
