local _, ns = ...

-- WILDWOOD: a bioluminescent forest at night. Deep moss-green glass framed in carved bark-gold
-- with an inner leaf-green line, glowing vine-and-bud corners (Gemini art), a fern-and-mushroom
-- silhouette and a teal mist rising at the bottom of every window, soft canopy light from
-- above. The minimap sits in a living wreath, glowing trees of life replace the gryphons,
-- hotbar buttons get a bark rim that blooms green on hover, and fireflies wander the screen.
-- Marcellus SC (carved serif) titles, lime-gold labels.

local WW = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Wildwood\\"
local M = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Modern\\"
local F = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Futuristic\\"

local BARK = { 0.80, 0.68, 0.42, 1 }
local LEAF = { 0.55, 0.92, 0.48, 1 }
local MOSS = { 0.035, 0.060, 0.040, 0.94 }

ns.Styles.NewPack({
    id = "wildwood",

    tokens = {
        bg = "0A140C", surface = "142318", accent = "7FE08A", text = "F1F6E6", textMuted = "A9BC9A",
        border = "3C5A34", buttonSurface = "1C3120", buttonBorder = "8C7A4C",
        titleFont = "MarcellusSC-Regular", titleSize = 17,
        headerFont = "MarcellusSC-Regular", bodyFont = "BarlowSemiCondensed-Medium",
        headerSize = 17, bodySize = 13, headerScale = 1.04, bodyScale = 1.05,
        fontColors = {
            GameFontNormal = { 0.82, 0.95, 0.56 }, GameFontNormalSmall = { 0.80, 0.94, 0.55 },
            GameFontNormalLarge = { 0.96, 0.88, 0.60 }, GameFontNormalHuge = { 0.96, 0.88, 0.60 },
            GameFontNormalMed3 = { 0.82, 0.95, 0.56 }, GameFontHighlight = { 0.96, 0.98, 0.90 },
            GameFontHighlightSmall = { 0.94, 0.97, 0.88 }, GameFontDisable = { 0.40, 0.48, 0.38 },
            GameFontDisableSmall = { 0.40, 0.48, 0.38 }, GameTooltipHeaderText = { 0.86, 1.00, 0.70 },
        },
        parchment = { bg = "0F1C12", border = "3C5A34", header = "C9F2A0", text = "EEF4E2", muted = "A9BC9A",
            headerShadow = { 0, 0, 0, 0.85 }, bodyShadow = { 0, 0, 0, 0.55 } },
        swatch = { 0.45, 0.85, 0.45 },
    },

    window = {
        shadow = { file = M .. "round_shadow", k = 0.5, size = 44, out = 26, color = { 0, 0, 0, 0.8 } },
        glow = { file = M .. "round_shadow", k = 0.5, size = 36, out = 20, color = { 0.2, 0.9, 0.6, 0.20 } },
        fill = { file = M .. "round_fill", k = 0.25, size = 14, color = MOSS },
        shade = { top = { 0.18, 0.40, 0.16, 0.20 }, bottom = { 0, 0, 0, 0 } },
        art = {
            { file = F .. "mote", anchor = "bottom", inset = 6, y = 4, h = 120, coords = { 0, 1, 0, 0.5 },
                color = { 0.25, 1, 0.7, 0.16 }, blend = "ADD" },
            { file = WW .. "ww_canopy", anchor = "bottom", inset = 10, y = 4, h = 110, color = { 0.45, 0.95, 0.6, 0.17 }, blend = "ADD" },
            { file = M .. "noise", tile = { 128, 128 }, anchor = "fill", inset = 4, color = { 0.8, 1, 0.8, 0.035 } },
        },
        title = { height = 32, top = { 0.5, 0.85, 0.4, 0.18 }, bottom = { 0.5, 0.85, 0.4, 0 } },
        divider = { y = 31, inset = 22, gap = 10, color = { 0.80, 0.68, 0.42, 0.8 },
            node = { file = F .. "node", size = 13, color = LEAF } },
        border = { file = M .. "round_edge", k = 0.25, size = 14, out = 1, color = BARK },
        border2 = { file = M .. "round_edge", k = 0.25, size = 12, out = -4, color = { 0.55, 0.92, 0.48, 0.32 } },
        corners = { file = WW .. "ww_corner", size = 92, out = 11, color = { 0.62, 1, 0.58, 0.95 }, blend = "ADD",
            which = { "TOPLEFT", "BOTTOMLEFT", "BOTTOMRIGHT" } },
        nodes = { file = F .. "mote", size = 10, color = { 0.7, 1, 0.5, 0.85 },
            at = { { "LEFT", 1, 0 }, { "RIGHT", -1, 0 } } },
        quality = { mode = "top", size = 2, inset = 3, pad = 16 },
    },

    tooltip = {
        shadow = { file = M .. "round_shadow", k = 0.5, size = 26, out = 14, color = { 0, 0, 0, 0.7 } },
        glow = { file = M .. "round_shadow", k = 0.5, size = 22, out = 12, color = { 0.2, 0.9, 0.6, 0.16 } },
        fill = { file = M .. "round_fill", k = 0.25, size = 9, color = { 0.04, 0.068, 0.045, 0.96 } },
        shade = { top = { 0.18, 0.40, 0.16, 0.16 }, bottom = { 0, 0, 0, 0 } },
        art = { { file = M .. "noise", tile = { 128, 128 }, anchor = "fill", inset = 3, color = { 0.8, 1, 0.8, 0.03 } } },
        border = { file = M .. "round_edge", k = 0.25, size = 9, out = 1, color = BARK },
        border2 = { file = M .. "round_edge", k = 0.25, size = 8, out = -3, color = { 0.55, 0.92, 0.48, 0.28 } },
        quality = { mode = "top", size = 2, inset = 3, pad = 12 },
    },

    button = {
        fill = { file = M .. "pill_fill", k = 0.25, size = 8 },
        edge = { file = M .. "pill_edge", k = 0.25, size = 8 },
        sheenInset = 2,
        underline = { inset = 10, y = 2, height = 1 },
        normal   = { fill = { 0.08, 0.14, 0.08, 0.95 }, edge = { 0.80, 0.68, 0.42, 0.65 }, sheen = { 0.8, 1, 0.7, 0.06 } },
        hover    = { fill = { 0.20, 0.42, 0.18, 1 }, edge = { 0.78, 1, 0.62, 1 }, sheen = { 0.8, 1, 0.7, 0.22 },
            line = { 0.4, 1, 0.75, 1 } },
        disabled = { fill = { 0.06, 0.09, 0.06, 0.7 }, edge = { 0.5, 0.45, 0.3, 0.25 }, sheen = { 0.8, 1, 0.7, 0.02 } },
    },

    tab = {
        fill = { file = M .. "pill_fill", k = 0.25, size = 8 },
        edge = { file = M .. "pill_edge", k = 0.25, size = 8 },
        normal   = { fill = { 0.07, 0.11, 0.07, 0.85 }, edge = { 0.80, 0.68, 0.42, 0.30 } },
        selected = { fill = { 0.16, 0.30, 0.15, 1 }, edge = { 0.85, 0.74, 0.46, 1 } },
        lineHeight = 2, lineInset = 10, lineY = 3,
        lineLeft = { 0.4, 0.9, 0.5, 0.3 }, lineRight = { 0.85, 1, 0.6, 1 },
        marker = { file = F .. "mote", size = 12, color = LEAF },
    },

    reading = {
        fill = { file = M .. "round_fill", k = 0.25, size = 12, color = { 0.055, 0.095, 0.06, 0.97 } },
        edge = { file = M .. "round_edge", k = 0.25, size = 12, color = { 0.80, 0.68, 0.42, 0.5 } },
        art = { { file = M .. "noise", tile = { 128, 128 }, inset = 3, color = { 0.8, 1, 0.8, 0.03 } } },
        rule = { 0.55, 0.92, 0.48, 0.6 },
    },

    chrome = {
        minimap = {
            { file = M .. "ring_shadow", scale = 1.3, color = { 0, 0, 0, 0.8 }, back = true },
            { file = M .. "ring_shadow", scale = 1.24, color = { 0.2, 0.9, 0.6, 0.35 }, blend = "ADD" },
            { file = WW .. "ww_wreath", scale = 1.42, color = { 0.62, 0.98, 0.52, 0.9 }, blend = "ADD" },
        },
        caps = { file = WW .. "ww_tree", ratio = 0.5, scale = 1.2, color = { 0.55, 0.95, 0.6, 0.9 },
            glow = { file = F .. "mote", size = 0.55, y = 0.22, color = { 0.3, 1, 0.7, 0.55 } } },
        buttons = {
            edge = { file = M .. "pill_edge", k = 0.25, size = 7, out = 1, color = { 0.80, 0.68, 0.42, 0.85 } },
            hoverEdge = { 0.70, 1, 0.55, 1 },
            glow = { file = M .. "round_shadow", k = 0.5, size = 12, out = 7, color = { 0.2, 0.9, 0.6, 0.18 } },
        },
        ambience = {
            edges = {
                TOP = { 0.20, { 0.02, 0.07, 0.03, 0.32 }, { 0.02, 0.07, 0.03, 0 } },
                BOTTOM = { 0.14, { 0.10, 0.40, 0.22, 0 }, { 0.10, 0.40, 0.22, 0.12 } },
                LEFT = { 0.07, { 0.02, 0.06, 0.02, 0.28 }, { 0.02, 0.06, 0.02, 0 } },
                RIGHT = { 0.07, { 0.02, 0.06, 0.02, 0 }, { 0.02, 0.06, 0.02, 0.28 } },
            },
            -- fireflies: slow, wandering, pulsing
            motes = { file = F .. "mote", count = 24, color = { 0.82, 1, 0.42 }, alpha = 0.6, twinkle = 2.2,
                size = { 3, 9 }, vy = { -6, 9 }, sway = 26, life = { 6, 13 } },
        },
    },

    mini = {
        fill = 7, border = 6,
        art = { { file = WW .. "ww_canopy", anchor = "BOTTOM", x = 0, y = 2, w = 72, h = 22, color = { 0.45, 0.95, 0.6, 0.5 }, blend = "ADD" },
            { file = WW .. "ww_corner", anchor = "TOPLEFT", x = -2, y = 2, w = 24, h = 24, color = { 0.62, 1, 0.58, 0.9 }, blend = "ADD" } },
        text = { 0.96, 0.88, 0.60, 1 }, muted = { 0.82, 0.95, 0.56, 0.55 },
    },
})
