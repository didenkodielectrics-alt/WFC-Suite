local _, ns = ...
local WFC = ns.WFC

-- Native Settings panel helpers (design.md §4.6): one "WFC" root category with a
-- subcategory per addon, built only from standard Blizzard controls.
-- Everything is pcall-guarded: the panel is a convenience, the /wfc commands
-- always work, and a Settings API difference on Forever must never break loading.

WFC.UI = WFC.UI or {}
local UI = WFC.UI

local root

local function api()
    return Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting
        and Settings.CreateCheckbox and Settings.RegisterAddOnCategory
end

local function rootCategory()
    if root then return root end
    root = Settings.RegisterVerticalLayoutCategory("WFC")
    Settings.RegisterAddOnCategory(root)
    return root
end

UI.settingsObjects = UI.settingsObjects or {}

--- Builds an addon's settings page. `controls` is a list of
---   { key, label, tooltip, kind = "checkbox" | "slider", min, max, step, format }
--- bound directly to `store[key]` (the addon's SavedVariables settings table).
--- onChange(key, value) runs after the user changes a value. Returns the category or nil.
function UI:AddSettingsPage(name, store, defaults, controls, onChange)
    if not api() then
        WFC:Log("WARN", "settings", "Settings API missing; use /wfc commands for " .. name)
        return nil
    end
    local ok, result = pcall(function()
        local parent = rootCategory()
        local category = Settings.RegisterVerticalLayoutSubcategory
            and Settings.RegisterVerticalLayoutSubcategory(parent, name)
            or Settings.RegisterVerticalLayoutCategory("WFC " .. name)
        for _, c in ipairs(controls) do
            local varType = c.kind == "slider" and Settings.VarType.Number or Settings.VarType.Boolean
            local varName = "WFC_" .. name .. "_" .. c.key
            local setting = Settings.RegisterAddOnSetting(category, varName, c.key,
                store, varType, c.label, defaults[c.key])
            UI.settingsObjects[varName] = setting
            if setting.SetValueChangedCallback then
                setting:SetValueChangedCallback(function(_, value)
                    if UI.OnSettingChanged then UI:OnSettingChanged(name, c.key, value) end
                    if onChange then onChange(c.key, value) end
                end)
            end
            if c.kind == "slider" then
                local options = Settings.CreateSliderOptions(c.min, c.max, c.step)
                if c.format and MinimalSliderWithSteppersMixin then
                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, c.format)
                end
                Settings.CreateSlider(category, setting, options, c.tooltip)
            else
                Settings.CreateCheckbox(category, setting, c.tooltip)
            end
        end
        if not Settings.RegisterVerticalLayoutSubcategory then Settings.RegisterAddOnCategory(category) end
        return category
    end)
    if not ok then
        WFC:Log("WARN", "settings", name .. " settings page failed: " .. tostring(result))
        return nil
    end
    return result
end

--- Updates a setting both in `store` and in the registered Blizzard Settings object (if any).
function UI:SetSettingValue(name, key, value, store)
    if store then store[key] = value end
    local varName = "WFC_" .. tostring(name) .. "_" .. tostring(key)
    local setting = (self.settingsObjects and self.settingsObjects[varName])
        or (Settings and Settings.GetSetting and Settings.GetSetting(varName))
    if setting and setting.SetValue then
        pcall(setting.SetValue, setting, value)
    end
end

function UI:OpenSettings(category)
    if category and Settings and Settings.OpenToCategory and category.GetID then
        Settings.OpenToCategory(category:GetID())
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Map Header Buttons (Travel, Quests, etc.)
---------------------------------------------------------------------------
local mapButtons = {}
local mapButtonsList = {}
local mapHooked = false

local function layoutMapButtons()
    if not WorldMapFrame or #mapButtonsList == 0 then return end
    local parent = (WorldMapFrame.BorderFrame) or WorldMapFrame
    for i, btn in ipairs(mapButtonsList) do
        btn:ClearAllPoints()
        btn:SetParent(parent)
        btn:SetFrameStrata("HIGH")
        btn:SetFrameLevel(500)
        -- Place in the title bar gap right after the zone dropdowns (around x = 270)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 270 + (i - 1) * 58, -4)
        btn:Show()
    end
end

function UI:AddMapHeaderButton(id, config)
    if mapButtons[id] then return mapButtons[id] end
    local parent = (WorldMapFrame and WorldMapFrame.BorderFrame) or WorldMapFrame or UIParent
    local btn = CreateFrame("Button", "WFC_MapBtn_" .. id, parent, "UIPanelButtonTemplate")
    btn:SetSize(config.width or 54, 20)
    btn:SetText(config.text or id)
    local f = WFC.Fonts and WFC.Fonts:Get("small")
    if f then btn:SetNormalFontObject(f) end

    btn:SetScript("OnClick", function(self)
        if config.onClick then config.onClick(self) end
    end)
    btn:SetScript("OnEnter", function(self)
        if not (config.tooltipTitle or config.tooltipText) then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if config.tooltipTitle then GameTooltip:AddLine(config.tooltipTitle, 1, 1, 1) end
        if config.tooltipText then
            local text = type(config.tooltipText) == "function" and config.tooltipText() or config.tooltipText
            GameTooltip:AddLine(text, 0.75, 0.75, 0.75)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    mapButtons[id] = btn
    mapButtonsList[#mapButtonsList + 1] = btn

    if not mapHooked and WorldMapFrame then
        mapHooked = true
        if WorldMapFrame.HookScript then
            pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnShow", layoutMapButtons)
            pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnSizeChanged", layoutMapButtons)
        end
        local maxMin = (WorldMapFrame.BorderFrame and WorldMapFrame.BorderFrame.MaximizeMinimizeFrame)
            or WorldMapFrame.MaximizeMinimizeFrame
        if maxMin then
            for _, sub in ipairs({ maxMin.MaximizeButton, maxMin.MinimizeButton }) do
                if sub and sub.HookScript then
                    pcall(sub.HookScript, sub, "OnClick", function() C_Timer.After(0.01, layoutMapButtons) end)
                end
            end
        end
    end
    layoutMapButtons()
    return btn
end

WFC:RegisterEvent("PLAYER_LOGIN", layoutMapButtons)
WFC:RegisterEvent("ADDON_LOADED", function(_, name)
    if name == "Blizzard_WorldMap" then layoutMapButtons() end
end)
