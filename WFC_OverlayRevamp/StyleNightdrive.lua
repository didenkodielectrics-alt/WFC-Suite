local _, ns = ...

-- NIGHTDRIVE: retro-80s synthwave. Purple-black glass lit by neon tubes (a hot-pink outer tube
-- and a cyan inner one, both glowing), a striped sunset sun (Gemini art) sinking into a neon
-- perspective grid at the bottom of every window, magenta horizon haze, CRT scanlines, chrome
-- pink-to-cyan accents. Neon palms replace the gryphons, the minimap gets a double neon ring,
-- hotbar buttons glow pink and flash cyan on hover, and faint stars twinkle over the screen.
-- Teko (tall condensed retro type) for titles and headings, cyan labels.

local ND = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Nightdrive\\"
local M = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Modern\\"
local F = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Futuristic\\"

local PINK = { 1.00, 0.28, 0.78, 1 }
local CYAN = { 0.22, 0.90, 1.00, 1 }
local NIGHT = { 0.055, 0.020, 0.095, 0.94 }

ns.Styles.NewPack({
    id = "nightdrive",

    tokens = {
        bg = "10051A", surface = "1C0B2B", accent = "FF48C8", text = "FBE9FF", textMuted = "B9A1CC",
        border = "4A1F66", buttonSurface = "2A1240", buttonBorder = "B23F9A",
        titleFont = "Teko-SemiBold", titleSize = 23,
        headerFont = "Teko-SemiBold", bodyFont = "BarlowSemiCondensed-Medium",
        headerSize = 22, bodySize = 13, headerScale = 1.28, bodyScale = 1.05,
        fontColors = {
            GameFontNormal = { 0.42, 0.92, 1.00 }, GameFontNormalSmall = { 0.42, 0.92, 1.00 },
            GameFontNormalLarge = { 1.00, 0.50, 0.86 }, GameFontNormalHuge = { 1.00, 0.50, 0.86 },
            GameFontNormalMed3 = { 0.42, 0.92, 1.00 }, GameFontHighlight = { 1.00, 0.94, 1.00 },
            GameFontHighlightSmall = { 0.98, 0.90, 1.00 }, GameFontDisable = { 0.45, 0.38, 0.55 },
            GameFontDisableSmall = { 0.45, 0.38, 0.55 }, GameTooltipHeaderText = { 1.00, 0.56, 0.90 },
        },
        parchment = { bg = "140821", border = "4A1F66", header = "FF6AD5", text = "F4E6FF", muted = "B9A1CC",
            headerShadow = { 0, 0, 0, 0.9 }, bodyShadow = { 0, 0, 0, 0.6 } },
        swatch = { 1.00, 0.28, 0.78 },
    },

    window = {
        shadow = { file = M .. "round_shadow", k = 0.5, size = 44, out = 26, color = { 0, 0, 0, 0.8 } },
        glow = { file = M .. "round_shadow", k = 0.5, size = 34, out = 18, color = { 1, 0.2, 0.7, 0.42 } },
        fill = { file = M .. "round_fill", k = 0.25, size = 10, color = NIGHT },
        shade = { top = { 0.30, 0.05, 0.45, 0.0 }, bottom = { 0.60, 0.10, 0.45, 0.32 } },
        art = {
            -- sunset: the sun's top three quarters stand on the grid horizon
            { file = ND .. "nd_sun", anchor = "BOTTOM", x = 0, y = 88, w = 200, h = 150, coords = { 0, 1, 0, 0.75 },
                color = { 1, 1, 1, 0.48 }, blend = "ADD" },
            { file = ND .. "nd_grid", anchor = "bottom", inset = 6, y = 4, h = 96, color = { 1, 0.32, 0.86, 0.40 }, blend = "ADD" },
            { file = F .. "mote", anchor = "bottom", inset = 6, y = 70, h = 60, coords = { 0, 1, 0.25, 0.75 },
                color = { 1, 0.3, 0.75, 0.22 }, blend = "ADD" },
            { file = F .. "scan", tile = { 8, 4 }, anchor = "fill", inset = 3, scroll = 10, color = { 1, 0.8, 1, 0.05 }, blend = "ADD" },
        },
        title = { height = 30, top = { 1, 0.25, 0.75, 0.22 }, bottom = { 1, 0.25, 0.75, 0 } },
        divider = { y = 30, inset = 14, color = { 0.22, 0.90, 1.00, 0.85 } },
        border = { file = ND .. "tube", k = 0.25, size = 10, out = 0, color = PINK, blend = "ADD" },
        border2 = { file = ND .. "tube", k = 0.25, size = 9, out = -4, color = { 0.22, 0.90, 1.00, 0.55 }, blend = "ADD" },
        topline = { inset = 14, y = 1, height = 2, left = PINK, right = CYAN },
        shimmer = { file = F .. "streak", w = 120, h = 12, every = 5, time = 1.0, y = -1, color = { 0.5, 0.95, 1, 0.9 } },
        quality = { mode = "left", size = 3, inset = 5, pad = 9 },
    },

    tooltip = {
        shadow = { file = M .. "round_shadow", k = 0.5, size = 26, out = 14, color = { 0, 0, 0, 0.75 } },
        glow = { file = M .. "round_shadow", k = 0.5, size = 22, out = 12, color = { 1, 0.2, 0.7, 0.28 } },
        fill = { file = M .. "round_fill", k = 0.25, size = 8, color = { 0.07, 0.025, 0.11, 0.96 } },
        shade = { top = { 0.3, 0.05, 0.45, 0 }, bottom = { 0.5, 0.10, 0.45, 0.26 } },
        art = {
            { file = F .. "scan", tile = { 8, 4 }, anchor = "fill", inset = 2, scroll = 10, color = { 1, 0.8, 1, 0.04 }, blend = "ADD" },
        },
        border = { file = ND .. "tube", k = 0.25, size = 8, out = 0, color = PINK, blend = "ADD" },
        border2 = { file = ND .. "tube", k = 0.25, size = 7, out = -3, color = { 0.22, 0.90, 1.00, 0.45 }, blend = "ADD" },
        quality = { mode = "left", size = 3, inset = 4, pad = 7 },
    },

    button = {
        fill = { file = M .. "pill_fill", k = 0.25, size = 7 },
        edge = { file = M .. "pill_edge", k = 0.25, size = 7 },
        sheenInset = 2,
        underline = { inset = 8, y = 2, height = 1 },
        normal   = { fill = { 0.12, 0.04, 0.18, 0.95 }, edge = { 1, 0.35, 0.80, 0.85 }, sheen = { 1, 0.6, 1, 0.07 } },
        hover    = { fill = { 0.85, 0.15, 0.60, 1 }, edge = { 0.55, 0.95, 1, 1 }, sheen = { 1, 0.8, 1, 0.28 },
            line = CYAN },
        disabled = { fill = { 0.08, 0.03, 0.11, 0.7 }, edge = { 0.6, 0.3, 0.6, 0.25 }, sheen = { 1, 0.6, 1, 0.02 } },
    },

    tab = {
        fill = { file = M .. "pill_fill", k = 0.25, size = 7 },
        edge = { file = M .. "pill_edge", k = 0.25, size = 7 },
        normal   = { fill = { 0.10, 0.04, 0.15, 0.85 }, edge = { 1, 0.35, 0.80, 0.30 } },
        selected = { fill = { 0.30, 0.06, 0.32, 1 }, edge = { 1, 0.45, 0.85, 1 } },
        lineHeight = 2, lineInset = 10, lineY = 3, lineLeft = PINK, lineRight = CYAN,
    },

    reading = {
        fill = { file = M .. "round_fill", k = 0.25, size = 10, color = { 0.08, 0.03, 0.12, 0.97 } },
        edge = { file = ND .. "tube", k = 0.25, size = 10, color = { 0.22, 0.90, 1.00, 0.45 } },
        art = {
            { file = F .. "grid", tile = { 64, 64 }, inset = 3, color = { 1, 0.3, 0.85, 0.06 }, blend = "ADD" },
            { file = F .. "scan", tile = { 8, 4 }, inset = 3, scroll = 8, color = { 1, 0.8, 1, 0.03 }, blend = "ADD" },
        },
        rule = { 0.22, 0.90, 1.00, 0.7 },
    },

    chrome = {
        minimap = {
            { file = M .. "ring_shadow", scale = 1.3, color = { 0, 0, 0, 0.8 }, back = true },
            { file = M .. "ring_shadow", scale = 1.22, color = { 1, 0.2, 0.7, 0.55 }, blend = "ADD" },
            { file = M .. "ring", scale = 1.04, color = PINK, blend = "ADD" },
            { file = M .. "ring", scale = 1.11, color = { 0.22, 0.90, 1.00, 0.75 }, blend = "ADD" },
        },
        caps = { file = ND .. "nd_palm", ratio = 0.5, scale = 1.25, color = { 1, 0.35, 0.80, 0.95 }, mirror = true,
            glow = { file = F .. "mote", size = 0.6, y = 0.95, color = { 1, 0.3, 0.75, 0.45 } } },
        buttons = {
            edge = { file = ND .. "tube", k = 0.25, size = 7, out = 1, color = { 1, 0.35, 0.80, 0.9 }, blend = "ADD" },
            hoverEdge = { 0.45, 0.95, 1, 1 },
            glow = { file = M .. "round_shadow", k = 0.5, size = 12, out = 7, color = { 1, 0.2, 0.7, 0.30 } },
        },
        ambience = {
            edges = {
                TOP = { 0.18, { 0.25, 0.04, 0.40, 0.20 }, { 0.25, 0.04, 0.40, 0 } },
                BOTTOM = { 0.20, { 1, 0.2, 0.7, 0 }, { 1, 0.2, 0.7, 0.13 } },
                LEFT = { 0.06, { 0.12, 0.02, 0.20, 0.25 }, { 0.12, 0.02, 0.20, 0 } },
                RIGHT = { 0.06, { 0.12, 0.02, 0.20, 0 }, { 0.12, 0.02, 0.20, 0.25 } },
            },
            -- twinkling stars in the upper screen
            motes = { file = F .. "mote", count = 22, color = { 0.55, 0.92, 1 }, alpha = 0.45, twinkle = 3,
                size = { 2, 6 }, vy = { -0.5, 0.5 }, sway = 0, life = { 6, 14 } },
        },
    },

    mini = {
        fill = 6, border = 6,
        art = {
            { file = ND .. "nd_sun", anchor = "BOTTOM", x = 0, y = 14, w = 34, h = 26, color = { 1, 1, 1, 0.85 }, blend = "ADD" },
            { file = ND .. "nd_grid", anchor = "BOTTOM", x = 0, y = 2, w = 74, h = 16, color = { 1, 0.32, 0.86, 0.7 }, blend = "ADD" },
        },
        text = { 1, 0.5, 0.86, 1 }, muted = { 0.42, 0.92, 1, 0.55 },
    },
})
