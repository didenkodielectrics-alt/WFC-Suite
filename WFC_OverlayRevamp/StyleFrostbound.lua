local _, ns = ...

-- FROSTBOUND: a glacial citadel under the northern lights. Deep blue-black frosted glass with
-- faceted (chamfered) ice edges and a cold glow, ice-crystal corners and a slowly turning
-- snowflake emblem (Gemini art), an aurora ribbon across the top and jagged glacier peaks at
-- the bottom of every window, frost grain, a light glinting along the top edge. The minimap
-- sits in a crown of ice shards, ice-crystal spires replace the gryphons, hotbar buttons get
-- faceted ice rims, and snow falls over the screen. Michroma titles, ice-blue labels.

local FB = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Frostbound\\"
local M = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Modern\\"
local F = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Futuristic\\"

local ICE = { 0.72, 0.93, 1.00, 1 }
local DEEP = { 0.030, 0.055, 0.095, 0.93 }

ns.Styles.NewPack({
    id = "frostbound",

    tokens = {
        bg = "08101A", surface = "102031", accent = "8FE3FF", text = "F2FAFF", textMuted = "9DB6C8",
        border = "2C4A63", buttonSurface = "15293D", buttonBorder = "6FA8C8",
        titleFont = "Michroma-Regular", titleSize = 12,
        headerFont = "BarlowSemiCondensed-SemiBold", bodyFont = "BarlowSemiCondensed-Medium",
        headerSize = 17, bodySize = 13, headerScale = 1.06, bodyScale = 1.05,
        fontColors = {
            GameFontNormal = { 0.70, 0.92, 1.00 }, GameFontNormalSmall = { 0.70, 0.92, 1.00 },
            GameFontNormalLarge = { 0.92, 0.98, 1.00 }, GameFontNormalHuge = { 0.92, 0.98, 1.00 },
            GameFontNormalMed3 = { 0.70, 0.92, 1.00 }, GameFontHighlight = { 1, 1, 1 },
            GameFontHighlightSmall = { 0.95, 0.98, 1.00 }, GameFontDisable = { 0.40, 0.50, 0.60 },
            GameFontDisableSmall = { 0.40, 0.50, 0.60 }, GameTooltipHeaderText = { 0.78, 0.96, 1.00 },
        },
        parchment = { bg = "0B1724", border = "2C4A63", header = "BFEFFF", text = "EAF6FF", muted = "9DB6C8",
            headerShadow = { 0, 0, 0, 0.85 }, bodyShadow = { 0, 0, 0, 0.55 } },
        swatch = { 0.56, 0.89, 1.00 },
    },

    window = {
        shadow = { file = M .. "round_shadow", k = 0.5, size = 44, out = 26, color = { 0, 0, 0, 0.8 } },
        glow = { file = F .. "chamfer_glow", k = 0.5, size = 40, out = 22, color = { 0.45, 0.80, 1, 0.26 } },
        fill = { file = F .. "chamfer_fill", k = 0.28, size = 12, color = DEEP },
        shade = { top = { 0.45, 0.75, 1.0, 0.14 }, bottom = { 0, 0, 0, 0 } },
        art = {
            { file = FB .. "fb_aurora", anchor = "top", inset = 6, y = 4, h = 100, color = { 1, 1, 1, 0.30 }, blend = "ADD" },
            { file = FB .. "fb_peaks", anchor = "bottom", inset = 10, y = 4, h = 100, color = { 0.70, 0.90, 1, 0.15 }, blend = "ADD" },
            { file = M .. "noise", tile = { 128, 128 }, anchor = "fill", inset = 4, color = { 0.85, 0.95, 1, 0.05 } },
        },
        title = { height = 30, top = { 0.6, 0.9, 1, 0.14 }, bottom = { 0.6, 0.9, 1, 0 } },
        divider = { y = 30, inset = 18, gap = 10, color = { 0.72, 0.93, 1.00, 0.8 },
            node = { file = FB .. "fb_flake", size = 16, color = ICE } },
        border = { file = F .. "chamfer_edge", k = 0.28, size = 12, out = 1, color = ICE },
        corners = { file = FB .. "fb_corner", size = 72, out = 9, color = { 0.85, 0.97, 1, 0.95 }, blend = "ADD",
            which = { "TOPLEFT", "BOTTOMLEFT", "BOTTOMRIGHT" } },
        emblem = { y = 18, layers = {
            { file = F .. "mote", size = 34, color = { 0.6, 0.9, 1, 0.5 } },
            { file = FB .. "fb_flake", size = 40, color = { 0.85, 0.97, 1, 0.95 }, spin = 0.12 },
        } },
        shimmer = { file = F .. "streak", w = 130, h = 12, every = 6, time = 1.3, y = -1, color = { 0.8, 0.95, 1, 0.9 } },
        quality = { mode = "top", size = 2, inset = 3, pad = 12 },
    },

    tooltip = {
        shadow = { file = M .. "round_shadow", k = 0.5, size = 24, out = 12, color = { 0, 0, 0, 0.7 } },
        glow = { file = F .. "chamfer_glow", k = 0.5, size = 26, out = 14, color = { 0.45, 0.80, 1, 0.18 } },
        fill = { file = F .. "chamfer_fill", k = 0.28, size = 8, color = { 0.035, 0.06, 0.10, 0.96 } },
        shade = { top = { 0.45, 0.75, 1.0, 0.12 }, bottom = { 0, 0, 0, 0 } },
        art = { { file = M .. "noise", tile = { 128, 128 }, anchor = "fill", inset = 3, color = { 0.85, 0.95, 1, 0.045 } } },
        border = { file = F .. "chamfer_edge", k = 0.28, size = 8, out = 1, color = ICE },
        quality = { mode = "top", size = 2, inset = 3, pad = 10 },
    },

    button = {
        fill = { file = F .. "chip_fill", k = 0.25, size = 6 },
        edge = { file = F .. "chip_edge", k = 0.25, size = 6 },
        sheenInset = 2,
        underline = { inset = 6, y = 2, height = 1 },
        normal   = { fill = { 0.06, 0.11, 0.17, 0.95 }, edge = { 0.72, 0.93, 1, 0.55 }, sheen = { 0.8, 0.95, 1, 0.08 } },
        hover    = { fill = { 0.18, 0.38, 0.55, 1 }, edge = { 0.92, 1, 1, 1 }, sheen = { 0.85, 0.97, 1, 0.26 },
            line = { 0.85, 0.97, 1, 1 } },
        disabled = { fill = { 0.05, 0.08, 0.12, 0.7 }, edge = { 0.5, 0.6, 0.7, 0.25 }, sheen = { 0.8, 0.95, 1, 0.02 } },
    },

    tab = {
        fill = { file = F .. "chip_fill", k = 0.25, size = 6 },
        edge = { file = F .. "chip_edge", k = 0.25, size = 6 },
        normal   = { fill = { 0.05, 0.09, 0.14, 0.85 }, edge = { 0.72, 0.93, 1, 0.30 } },
        selected = { fill = { 0.14, 0.28, 0.42, 1 }, edge = { 0.85, 0.97, 1, 1 } },
        lineHeight = 2, lineInset = 8, lineY = 2,
        lineLeft = { 0.5, 0.85, 1, 0.3 }, lineRight = { 0.9, 1, 1, 1 },
        marker = { file = FB .. "fb_flake", size = 13, color = ICE },
    },

    reading = {
        fill = { file = F .. "chamfer_fill", k = 0.28, size = 10, color = { 0.045, 0.08, 0.13, 0.97 } },
        edge = { file = F .. "chamfer_edge", k = 0.28, size = 10, color = { 0.72, 0.93, 1, 0.5 } },
        art = { { file = M .. "noise", tile = { 128, 128 }, inset = 3, color = { 0.85, 0.95, 1, 0.04 } } },
        rule = { 0.72, 0.93, 1, 0.6 },
    },

    chrome = {
        minimap = {
            { file = M .. "ring_shadow", scale = 1.3, color = { 0, 0, 0, 0.8 }, back = true },
            { file = M .. "ring_shadow", scale = 1.22, color = { 0.45, 0.8, 1, 0.30 }, blend = "ADD" },
            { file = FB .. "fb_ring", scale = 1.5, color = { 0.80, 0.95, 1, 0.85 }, blend = "ADD" },
            { file = F .. "fx_ring", scale = 1.62, color = { 0.6, 0.88, 1, 0.22 }, blend = "ADD", spin = 0.04 },
        },
        caps = { file = FB .. "fb_crystal", ratio = 0.5, scale = 1.15, color = { 0.80, 0.95, 1, 0.9 },
            glow = { file = F .. "mote", size = 0.5, y = 0.3, color = { 0.5, 0.85, 1, 0.5 } } },
        buttons = {
            edge = { file = F .. "chip_edge", k = 0.25, size = 6, out = 1, color = { 0.72, 0.93, 1, 0.85 } },
            hoverEdge = { 0.95, 1, 1, 1 },
            glow = { file = F .. "chamfer_glow", k = 0.5, size = 12, out = 7, color = { 0.45, 0.80, 1, 0.22 } },
        },
        ambience = {
            edges = {
                TOP = { 0.18, { 0.5, 0.8, 1, 0.11 }, { 0.5, 0.8, 1, 0 } },
                BOTTOM = { 0.12, { 0.7, 0.9, 1, 0 }, { 0.7, 0.9, 1, 0.08 } },
                LEFT = { 0.06, { 0.02, 0.05, 0.10, 0.26 }, { 0.02, 0.05, 0.10, 0 } },
                RIGHT = { 0.06, { 0.02, 0.05, 0.10, 0 }, { 0.02, 0.05, 0.10, 0.26 } },
            },
            -- snow: falling, drifting
            motes = { file = F .. "mote", count = 36, color = { 0.92, 0.97, 1 }, alpha = 0.5,
                size = { 2, 7 }, vy = { -34, -14 }, sway = 20, life = { 9, 16 } },
        },
    },

    mini = {
        fill = 6, border = 6,
        art = {
            { file = FB .. "fb_aurora", anchor = "TOP", x = 0, y = -2, w = 74, h = 22, color = { 1, 1, 1, 0.8 }, blend = "ADD" },
            { file = FB .. "fb_peaks", anchor = "BOTTOM", x = 0, y = 2, w = 72, h = 20, color = { 0.7, 0.9, 1, 0.5 }, blend = "ADD" },
        },
        emblem = { file = FB .. "fb_flake", size = 14, y = 1, color = ICE },
        text = { 0.92, 0.98, 1, 1 }, muted = { 0.70, 0.92, 1, 0.55 },
    },
})
