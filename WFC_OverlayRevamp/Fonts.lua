local _, ns = ...
local WFC = WFC

-- Fonts (design.md §7.5): Blizzard's font objects re-pointed to the theme's header/body
-- families, keeping each object's size and outline. Chat, quest text, numbers, combat text
-- and nameplates are left alone. Latin clients only (our fonts have no other glyphs).
-- Originals are remembered so the Blizzard look can be restored live.

local Overlay = ns.Overlay

local Fonts = {}
ns.Fonts = Fonts

local DB_FONTS = "Interface\\AddOns\\WFC_Database\\Media\\Fonts\\"
local OUR_FONTS = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Fonts\\"
local DIRS = {
    ["Teko-SemiBold"] = DB_FONTS,
    ["Teko-Medium"] = DB_FONTS,
    ["BarlowSemiCondensed-Medium"] = DB_FONTS,
    ["BarlowSemiCondensed-SemiBold"] = DB_FONTS,
    ["MarcellusSC-Regular"] = OUR_FONTS,
    ["Michroma-Regular"] = OUR_FONTS,
    ["ChakraPetch-Medium"] = OUR_FONTS,
    ["ChakraPetch-SemiBold"] = OUR_FONTS,
    ["ChakraPetch-Bold"] = OUR_FONTS,
}
-- If a file isn't installed (or WoW hasn't been restarted since it was added): these instead.
local FALLBACK = {
    ["MarcellusSC-Regular"] = "Teko-SemiBold",
    ["Michroma-Regular"] = "Teko-SemiBold",
    ["ChakraPetch-SemiBold"] = "Teko-SemiBold",
    ["ChakraPetch-Bold"] = "Teko-SemiBold",
    ["ChakraPetch-Medium"] = "BarlowSemiCondensed-Medium",
}

Fonts.HEADERS = { "GameFontNormalLarge", "GameFontHighlightLarge", "GameFontNormalHuge", "GameFontHighlightHuge",
    "GameFontNormalLarge2", "SystemFont_Large", "SystemFont_Huge1", "GameTooltipHeaderText" }
Fonts.BODY = { "GameFontNormal", "GameFontHighlight", "GameFontDisable", "GameFontGreen", "GameFontRed",
    "GameFontNormalSmall", "GameFontHighlightSmall", "GameFontDisableSmall", "GameFontNormalMed3",
    "GameFontHighlightMedium", "GameTooltipText", "GameTooltipTextSmall", "SystemFont_Med1", "SystemFont_Med2",
    "SystemFont_Med3", "SystemFont_Small", "SystemFont_Shadow_Med1", "SystemFont_Shadow_Small" }

local NON_LATIN = { koKR = true, zhCN = true, zhTW = true, ruRU = true }
local originals = {}  -- [fontObject] = { path, size, flags }
local objects = {}    -- [true|false] = our header/body font object

local function setFont(font, family, size, flags)
    local path = DIRS[family] .. family .. ".ttf"
    if font:SetFont(path, size, flags) == false and FALLBACK[family] then
        local alt = FALLBACK[family]
        return font:SetFont(DIRS[alt] .. alt .. ".ttf", size, flags)
    end
    return true
end

--- Our own header/body font objects for skinned window titles and tabs.
function Fonts:Object(theme, header)
    local f = objects[header]
    if not f then
        f = CreateFont(header and "WFC_OverlayHeader" or "WFC_OverlayBody")
        objects[header] = f
    end
    if NON_LATIN[GetLocale()] then return nil end
    -- Window titles may use a display face (titleFont) different from the header objects.
    local family = header and (theme.titleFont or theme.headerFont) or (not header and theme.bodyFont)
    if not family then return nil end -- no body family: Blizzard's own font stays
    setFont(f, family, header and (theme.titleSize or theme.headerSize or 16) or (theme.bodySize or 12), "")
    if f.SetShadowOffset then
        f:SetShadowOffset(1, -1)
        f:SetShadowColor(0, 0, 0, 0.8)
    end
    if f.SetTextColor then
        local c = theme.fontColors and theme.fontColors[header and "GameFontNormalLarge" or "GameFontNormal"]
        if c then f:SetTextColor(c[1], c[2], c[3]) elseif f.wfcColored then f:SetTextColor(1, 1, 1) end
        f.wfcColored = c ~= nil
    end
    return f
end

local colorOriginals = {} -- [fontObject] = { r, g, b }

--- Style packs recolour Blizzard's text styles (gold labels -> cool white / amber).
local function applyColors(theme, on)
    local wanted = {}
    if on and theme then
        for k, v in pairs(theme.fontColors or {}) do wanted[k] = v end
        for k, v in pairs(Fonts.QuestColors and Fonts.QuestColors(theme) or {}) do wanted[k] = v end
    end
    for font, c in pairs(colorOriginals) do
        local name = font.GetName and font:GetName()
        if not (name and wanted[name]) then
            font:SetTextColor(c[1], c[2], c[3])
            colorOriginals[font] = nil
        end
    end
    for name, c in pairs(wanted) do
        local font = _G[name]
        if font and font.GetTextColor and font.SetTextColor then
            if not colorOriginals[font] then
                local r, g, b = font:GetTextColor()
                if r then colorOriginals[font] = { r, g, b } end
            end
            font:SetTextColor(c[1], c[2], c[3])
        end
    end
end

--- Re-points (theme) or restores (nil) Blizzard's font objects.
function Fonts:Apply(theme)
    local on = theme and Overlay:ModuleOn("fonts") and not NON_LATIN[GetLocale()]
    for header, names in pairs({ [true] = Fonts.HEADERS, [false] = Fonts.BODY }) do
        local scale = on and (header and theme.headerScale or (not header and theme.bodyScale)) or 1
        for _, name in ipairs(names) do
            local font = _G[name]
            local family = on and (header and theme.headerFont or (not header and theme.bodyFont)) or nil
            if font and font.GetFont then
                if family then
                    if not originals[font] then
                        local path, size, flags = font:GetFont()
                        if path then originals[font] = { path, size, flags } end
                    end
                    local o = originals[font]
                    if o then setFont(font, family, math.floor(o[2] * scale + 0.5), o[3]) end
                elseif originals[font] then
                    local o = originals[font]
                    font:SetFont(o[1], o[2], o[3])
                    originals[font] = nil
                end
            end
        end
    end
    applyColors(theme, on and Overlay:Style() ~= "originalplus")
end

-- Quest / dialogue text styles print dark ink for parchment. Style packs draw dark reading
-- panels, so these take the pack's reading colours (light text, header colour for titles).
local QUEST_FONTS = { QuestFont = "text", QuestFontNormalSmall = "text", QuestFontLeft = "text",
    QuestFont_Large = "text", QuestFontHighlight = "text", QuestTitleFont = "header",
    QuestTitleFontBlackShadow = "header", QuestFont_Huge = "header" }

function Fonts.QuestColors(theme)
    local p = theme and theme.pack and theme.parchment
    if not p then return nil end
    local Themes = ns.Themes
    local out = {}
    for name, kind in pairs(QUEST_FONTS) do
        local r, g, b = Themes.RGB(kind == "header" and p.header or p.text)
        out[name] = { r, g, b }
    end
    return out
end

function Fonts:IsApplied(name)
    return _G[name] ~= nil and originals[_G[name]] ~= nil
end
