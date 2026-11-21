local _, ns = ...

-- MODERN: graphite glass. Rounded cards with a big soft shadow, frosted noise, an aurora glow
-- (Gemini art) behind the title, a 2 px indigo-to-cyan accent line along the top, hairline
-- borders, pill buttons that light up indigo, segmented tabs, a left quality bar on tooltips.
-- Type: Barlow Semi Condensed everywhere, cool white instead of WoW gold.

local M = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Modern\\"

local INDIGO = { 0.42, 0.48, 1.00, 1 }
local CYAN = { 0.25, 0.84, 1.00, 1 }
local GLASS = { 0.070, 0.080, 0.105, 0.95 }

ns.Styles.NewPack({
    id = "modern",

    tokens = {
        bg = "12151B", surface = "1B1F28", accent = "7C8CFF", text = "F2F5FA", textMuted = "9AA3B5",
        border = "2A2F3A", buttonSurface = "232838", buttonBorder = "3A4150",
        headerFont = "BarlowSemiCondensed-SemiBold", bodyFont = "BarlowSemiCondensed-Medium",
        headerSize = 17, bodySize = 13, headerScale = 1.05, bodyScale = 1.06,
        -- Blizzard's gold labels become cool white; highlights stay pure white.
        fontColors = {
            GameFontNormal = { 0.90, 0.93, 1.00 }, GameFontNormalSmall = { 0.86, 0.89, 0.96 },
            GameFontNormalLarge = { 0.95, 0.97, 1.00 }, GameFontNormalHuge = { 0.95, 0.97, 1.00 },
            GameFontNormalMed3 = { 0.90, 0.93, 1.00 }, GameFontHighlight = { 1, 1, 1 },
            GameFontHighlightSmall = { 0.93, 0.95, 1.00 }, GameFontDisable = { 0.45, 0.48, 0.56 },
            GameFontDisableSmall = { 0.45, 0.48, 0.56 }, GameTooltipHeaderText = { 1, 1, 1 },
        },
        parchment = { bg = "1A1E27", border = "2C3240", header = "FFFFFF", text = "D5DBE7", muted = "8D96A8",
            headerShadow = { 0, 0, 0, 0.7 }, bodyShadow = { 0, 0, 0, 0.5 } },
        swatch = { 0.42, 0.48, 1.00 },
    },

    window = {
        shadow = { file = M .. "round_shadow", k = 0.5, size = 44, out = 26, color = { 0, 0, 0, 0.75 } },
        fill = { file = M .. "round_fill", k = 0.25, size = 12, color = GLASS },
        shade = { top = { 0.10, 0.12, 0.17, 0.0 }, bottom = { 0.02, 0.025, 0.035, 0.55 } },
        art = {
            { file = M .. "noise", tile = { 128, 128 }, anchor = "fill", inset = 3, color = { 1, 1, 1, 0.035 } },
            { file = M .. "md_aurora", anchor = "TOPLEFT", x = 2, y = -2, w = 320, h = 130, color = { 1, 1, 1, 0.30 }, blend = "ADD" },
            { file = M .. "md_aurora", anchor = "BOTTOMRIGHT", x = -2, y = 2, w = 240, h = 120, color = { 1, 1, 1, 0.11 }, blend = "ADD",
                coords = { 1, 0, 1, 0 } },
        },
        title = { height = 30, top = { 1, 1, 1, 0.035 }, bottom = { 1, 1, 1, 0 } },
        divider = { y = 30, inset = 14, color = { 1, 1, 1, 0.10 } },
        border = { file = M .. "round_edge", k = 0.25, size = 12, out = 0, color = { 1, 1, 1, 0.11 } },
        border2 = { file = M .. "round_edge", k = 0.25, size = 13, out = 1, color = { 0, 0, 0, 0.65 } },
        topline = { inset = 12, y = 1, height = 2, left = INDIGO, right = CYAN },
        quality = { mode = "left", size = 3, inset = 4, pad = 8 },
    },

    tooltip = {
        shadow = { file = M .. "round_shadow", k = 0.5, size = 26, out = 14, color = { 0, 0, 0, 0.6 } },
        fill = { file = M .. "round_fill", k = 0.25, size = 9, color = { 0.075, 0.085, 0.11, 0.97 } },
        shade = { top = { 0.12, 0.14, 0.20, 0.0 }, bottom = { 0.02, 0.025, 0.035, 0.45 } },
        art = {
            { file = M .. "md_aurora", anchor = "TOPRIGHT", x = -2, y = -2, w = 140, h = 60, color = { 1, 1, 1, 0.10 }, blend = "ADD" },
        },
        border = { file = M .. "round_edge", k = 0.25, size = 9, out = 0, color = { 1, 1, 1, 0.10 } },
        border2 = { file = M .. "round_edge", k = 0.25, size = 10, out = 1, color = { 0, 0, 0, 0.6 } },
        quality = { mode = "left", size = 3, inset = 4, pad = 7 },
    },

    button = {
        fill = { file = M .. "pill_fill", k = 0.25, size = 7 },
        edge = { file = M .. "pill_edge", k = 0.25, size = 7 },
        sheenInset = 2,
        normal   = { fill = { 0.14, 0.16, 0.22, 0.98 }, edge = { 1, 1, 1, 0.10 }, sheen = { 1, 1, 1, 0.06 } },
        hover    = { fill = { 0.34, 0.40, 0.98, 1 }, edge = { 0.70, 0.76, 1, 0.9 }, sheen = { 1, 1, 1, 0.18 } },
        disabled = { fill = { 0.11, 0.12, 0.15, 0.7 }, edge = { 1, 1, 1, 0.05 }, sheen = { 1, 1, 1, 0.02 } },
    },

    tab = {
        fill = { file = M .. "pill_fill", k = 0.25, size = 7 },
        edge = { file = M .. "pill_edge", k = 0.25, size = 7 },
        normal   = { fill = { 0.10, 0.115, 0.15, 0.85 }, edge = { 1, 1, 1, 0.05 } },
        selected = { fill = { 0.17, 0.19, 0.26, 1 }, edge = { 1, 1, 1, 0.14 } },
        lineHeight = 2, lineInset = 10, lineY = 3, lineLeft = INDIGO, lineRight = CYAN,
    },

    reading = {
        fill = { file = M .. "round_fill", k = 0.25, size = 10, color = { 0.10, 0.115, 0.15, 0.98 } },
        edge = { file = M .. "round_edge", k = 0.25, size = 10, color = { 1, 1, 1, 0.08 } },
        art = { { file = M .. "noise", tile = { 128, 128 }, inset = 3, color = { 1, 1, 1, 0.03 } } },
        rule = { 0.49, 0.55, 1.00, 0.55 },
    },

    chrome = {
        minimap = {
            { file = M .. "ring_shadow", scale = 1.29, color = { 0, 0, 0, 0.85 }, back = true },
            { file = M .. "ring", scale = 1.03, color = { 1, 1, 1, 0.28 } },
            { file = M .. "ring", scale = 1.08, color = { 0.45, 0.55, 1, 0.35 }, blend = "ADD" },
        },
        caps = "hide",
        -- hotbar: a crisp rounded hairline with a soft drop shadow; hover lights it indigo
        buttons = {
            edge = { file = M .. "pill_edge", k = 0.25, size = 6, out = 1, color = { 1, 1, 1, 0.22 } },
            hoverEdge = { 0.55, 0.65, 1, 1 },
            glow = { file = M .. "round_shadow", k = 0.5, size = 10, out = 5, color = { 0, 0, 0, 0.55 }, blend = "BLEND" },
        },
        ambience = {
            edges = {
                TOP = { 0.12, { 0, 0, 0, 0.28 }, { 0, 0, 0, 0 } },
                BOTTOM = { 0.12, { 0, 0, 0, 0 }, { 0, 0, 0, 0.30 } },
                LEFT = { 0.07, { 0.02, 0.02, 0.06, 0.22 }, { 0, 0, 0, 0 } },
                RIGHT = { 0.07, { 0, 0, 0, 0 }, { 0.02, 0.02, 0.06, 0.22 } },
            },
        },
    },

    mini = {
        fill = 6, border = 6,
        art = { { file = M .. "md_aurora", anchor = "TOPLEFT", x = 1, y = -1, w = 54, h = 26, color = { 1, 1, 1, 0.35 }, blend = "ADD" } },
        text = { 1, 1, 1, 0.95 }, muted = { 0.6, 0.65, 0.78, 0.6 },
    },
})
