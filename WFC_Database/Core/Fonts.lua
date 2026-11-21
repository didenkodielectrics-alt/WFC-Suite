local _, ns = ...
local WFC = ns.WFC

-- The suite's font objects (design.md §2.2). Each starts as a copy of a Blizzard
-- font, then switches to our TTF from Media\Fonts when the file loads. A missing
-- file (fonts not shipped yet) or a non-Latin client keeps the Blizzard font, so
-- text never disappears. WFC_FontTooltip etc. are globals so XML/other addons can use them.

local Fonts = {}
WFC.Fonts = Fonts

Fonts.DIR = "Interface\\AddOns\\WFC_Database\\Media\\Fonts\\"

-- key = { global name, file, size, flags, Blizzard fallback, shadow alpha }
local SPECS = {
    header      = { "WFC_FontHeader", "Teko-SemiBold.ttf", 17, "", "GameFontNormalLarge", 0.8 },
    subheader   = { "WFC_FontSubheader", "Teko-Medium.ttf", 14, "", "GameFontNormal", 0.8 },
    body        = { "WFC_FontBody", "BarlowSemiCondensed-Medium.ttf", 12, "", "GameFontHighlight", 0.8 },
    small       = { "WFC_FontSmall", "BarlowSemiCondensed-Medium.ttf", 11, "", "GameFontHighlightSmall", 0.8 },
    tooltip     = { "WFC_FontTooltip", "AlegreyaSans-MediumItalic.ttf", 12, "", "GameTooltipText", 0.9 },
    tooltipHead = { "WFC_FontTooltipHead", "AlegreyaSans-BoldItalic.ttf", 13, "", "GameTooltipText", 0.9 },
    mapLabel    = { "WFC_FontMapLabel", "BarlowSemiCondensed-SemiBold.ttf", 11, "OUTLINE", "GameFontNormalSmall", 0 },
}

-- Our fonts cover Latin only; these locales keep Blizzard's fonts.
local NON_LATIN = { koKR = true, zhCN = true, zhTW = true, ruRU = true }

local objects = {}
Fonts.custom = {} -- [key] = true when our TTF loaded

local function apply(key, scale)
    local spec = SPECS[key]
    local font = objects[key]
    local fallback = _G[spec[5]]
    if fallback and font.CopyFontObject then font:CopyFontObject(fallback) end
    Fonts.custom[key] = false
    if not NON_LATIN[GetLocale()] then
        local ok = font:SetFont(Fonts.DIR .. spec[2], spec[3] * scale, spec[4])
        local path = font.GetFont and font:GetFont()
        if ok ~= false and path then
            Fonts.custom[key] = true
        elseif fallback and font.CopyFontObject then
            font:CopyFontObject(fallback)
        end
    end
    if spec[6] > 0 then
        font:SetShadowOffset(1, -1)
        font:SetShadowColor(0, 0, 0, spec[6])
    end
end

for key, spec in pairs(SPECS) do
    objects[key] = _G[spec[1]] or CreateFont(spec[1])
    apply(key, 1)
end

--- Font object by key ("tooltip", "tooltipHead", "header", ...).
function Fonts:Get(key)
    return objects[key]
end

--- Re-applies every font at the saved scale (settings.fontScale, 0.8-1.3).
function Fonts:Apply()
    local s = WFC_DB_Global and WFC_DB_Global.settings
    local scale = math.max(0.8, math.min(1.3, s and s.fontScale or 1))
    for key in pairs(SPECS) do apply(key, scale) end
end

WFC:On("WFC_STORE_READY", function() Fonts:Apply() end)
