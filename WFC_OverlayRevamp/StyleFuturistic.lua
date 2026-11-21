local _, ns = ...

-- FUTURISTIC: an amber holo-city at dusk (inspired by the mood of a golden art-deco metropolis).
-- Warm-black glass with an amber sky haze, a faint skyline and halo watermark (Gemini art),
-- circuit traces, drifting scanlines, chamfered double-line gold edges with an amber glow,
-- art-deco corner brackets, a turning halo emblem on the top edge, light rails up the sides and
-- a light that sweeps along the top every few seconds. Teko headers, amber text.

local F = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Futuristic\\"
local SHADOW = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Modern\\round_shadow"

local GOLD = { 0.95, 0.74, 0.36, 1 }
local BRIGHT = { 1.00, 0.87, 0.56, 1 }

ns.Styles.NewPack({
    id = "futuristic",

    tokens = {
        bg = "0D0905", surface = "1A120A", accent = "E9B44C", text = "FFF3DE", textMuted = "BFA57A",
        border = "6B4A1C", buttonSurface = "2A1C0C", buttonBorder = "8A6428",
        -- Michroma (wide sci-fi display) for window titles, Chakra Petch (chamfered, like the
        -- frames) for headings and body text. OFL; Media/Fonts. Teko/Barlow if not installed.
        titleFont = "Michroma-Regular", titleSize = 13,
        headerFont = "ChakraPetch-SemiBold", bodyFont = "ChakraPetch-Medium",
        headerSize = 17, bodySize = 13, headerScale = 1.08, bodyScale = 1.04,
        fontColors = {
            GameFontNormal = { 1.00, 0.80, 0.42 }, GameFontNormalSmall = { 1.00, 0.78, 0.40 },
            GameFontNormalLarge = { 1.00, 0.85, 0.52 }, GameFontNormalHuge = { 1.00, 0.85, 0.52 },
            GameFontNormalMed3 = { 1.00, 0.80, 0.42 }, GameFontHighlight = { 1.00, 0.96, 0.88 },
            GameFontHighlightSmall = { 1.00, 0.94, 0.84 }, GameFontDisable = { 0.52, 0.43, 0.30 },
            GameFontDisableSmall = { 0.52, 0.43, 0.30 }, GameTooltipHeaderText = { 1.00, 0.86, 0.55 },
        },
        parchment = { bg = "120D07", border = "6B4A1C", header = "FFD27A", text = "F3E7CF", muted = "BFA57A",
            headerShadow = { 0, 0, 0, 0.9 }, bodyShadow = { 0, 0, 0, 0.6 } },
        swatch = { 0.95, 0.74, 0.36 },
    },

    window = {
        shadow = { file = SHADOW, k = 0.5, size = 40, out = 24, color = { 0, 0, 0, 0.8 } },
        glow = { file = F .. "chamfer_glow", k = 0.5, size = 40, out = 22, color = { 0.95, 0.58, 0.18, 0.32 } },
        fill = { file = F .. "chamfer_fill", k = 0.28, size = 14, color = { 0.058, 0.040, 0.022, 0.94 } },
        shade = { top = { 0.60, 0.36, 0.10, 0.30 }, bottom = { 0, 0, 0, 0 } },
        art = {
            -- warm city glow rising from the bottom edge
            { file = F .. "mote", anchor = "bottom", inset = 6, y = 4, h = 130, coords = { 0, 1, 0, 0.5 },
                color = { 1, 0.62, 0.22, 0.20 }, blend = "ADD" },
            { file = F .. "fx_circuit", tile = { 256, 256 }, anchor = "fill", inset = 4, color = { 1, 0.75, 0.35, 0.05 }, blend = "ADD" },
            { file = F .. "fx_emblem", anchor = "BOTTOMRIGHT", x = -18, y = 26, w = 170, h = 170, color = { 1, 0.80, 0.42, 0.06 }, blend = "ADD" },
            { file = F .. "fx_skyline", anchor = "bottom", inset = 12, y = 3, h = 110, color = { 1, 0.72, 0.30, 0.14 }, blend = "ADD" },
            { file = F .. "scan", tile = { 8, 4 }, anchor = "fill", inset = 3, scroll = 6, color = { 1, 0.85, 0.6, 0.035 }, blend = "ADD" },
        },
        title = { height = 32, top = { 0.95, 0.62, 0.20, 0.24 }, bottom = { 0.95, 0.62, 0.20, 0 } },
        divider = { y = 31, inset = 18, gap = 9, color = { 0.95, 0.74, 0.36, 0.85 },
            node = { file = F .. "node", size = 14, color = BRIGHT } },
        rails = { width = 1, inset = 5, top = 40, bottom = 16, color = { 1, 0.75, 0.35, 0.32 } },
        border = { file = F .. "chamfer_edge", k = 0.28, size = 14, out = 1, color = GOLD },
        corners = { file = F .. "fx_corner", size = 74, out = 8, color = { 1, 0.87, 0.56, 1 }, blend = "ADD",
            which = { "TOPLEFT", "BOTTOMLEFT", "BOTTOMRIGHT" } },
        nodes = { file = F .. "node", size = 12, color = { 1, 0.87, 0.56, 0.9 },
            at = { { "LEFT", -1, 0 }, { "RIGHT", 1, 0 }, { "BOTTOM", 0, -1 } } },
        emblem = { y = 20, layers = {
            { file = F .. "fx_ring", size = 58, color = { 0.95, 0.74, 0.36, 0.55 }, spin = 0.22 },
            { file = F .. "fx_emblem", size = 44, color = { 1, 0.87, 0.56, 0.95 } },
            { file = F .. "mote", size = 26, color = { 1, 0.80, 0.40, 0.55 } },
        } },
        shimmer = { file = F .. "streak", w = 140, h = 14, every = 7, time = 1.4, y = -1, color = { 1, 0.85, 0.5, 0.9 } },
        quality = { mode = "top", size = 2, inset = 3, pad = 14 },
    },

    tooltip = {
        shadow = { file = SHADOW, k = 0.5, size = 24, out = 12, color = { 0, 0, 0, 0.7 } },
        glow = { file = F .. "chamfer_glow", k = 0.5, size = 26, out = 14, color = { 0.95, 0.58, 0.18, 0.22 } },
        fill = { file = F .. "chamfer_fill", k = 0.28, size = 9, color = { 0.05, 0.035, 0.02, 0.96 } },
        shade = { top = { 0.55, 0.32, 0.08, 0.16 }, bottom = { 0, 0, 0, 0 } },
        art = {
            { file = F .. "fx_circuit", tile = { 256, 256 }, anchor = "fill", inset = 3, color = { 1, 0.75, 0.35, 0.035 }, blend = "ADD" },
            { file = F .. "scan", tile = { 8, 4 }, anchor = "fill", inset = 2, scroll = 6, color = { 1, 0.85, 0.6, 0.03 }, blend = "ADD" },
        },
        border = { file = F .. "chamfer_edge", k = 0.28, size = 9, out = 1, color = GOLD },
        quality = { mode = "top", size = 2, inset = 3, pad = 10 },
    },

    button = {
        fill = { file = F .. "chip_fill", k = 0.25, size = 6 },
        edge = { file = F .. "chip_edge", k = 0.25, size = 6 },
        sheenInset = 2,
        underline = { inset = 6, y = 2, height = 1 },
        normal   = { fill = { 0.11, 0.075, 0.035, 0.96 }, edge = { 0.95, 0.72, 0.33, 0.55 }, sheen = { 1, 0.80, 0.40, 0.08 } },
        hover    = { fill = { 0.42, 0.27, 0.07, 1 }, edge = { 1, 0.88, 0.58, 1 }, sheen = { 1, 0.90, 0.60, 0.25 },
            line = { 1, 0.85, 0.5, 1 } },
        disabled = { fill = { 0.07, 0.05, 0.03, 0.7 }, edge = { 0.6, 0.45, 0.2, 0.25 }, sheen = { 1, 0.8, 0.4, 0.02 } },
    },

    tab = {
        fill = { file = F .. "chip_fill", k = 0.25, size = 6 },
        edge = { file = F .. "chip_edge", k = 0.25, size = 6 },
        normal   = { fill = { 0.07, 0.05, 0.03, 0.85 }, edge = { 0.95, 0.72, 0.33, 0.30 } },
        selected = { fill = { 0.28, 0.18, 0.05, 1 }, edge = { 1, 0.85, 0.5, 1 } },
        lineHeight = 2, lineInset = 8, lineY = 2,
        lineLeft = { 0.95, 0.60, 0.20, 0.35 }, lineRight = { 1, 0.90, 0.60, 1 },
        marker = { file = F .. "node", size = 12, color = BRIGHT },
    },

    reading = {
        fill = { file = F .. "chamfer_fill", k = 0.28, size = 10, color = { 0.06, 0.042, 0.022, 0.97 } },
        edge = { file = F .. "chamfer_edge", k = 0.28, size = 10, color = { 0.95, 0.72, 0.33, 0.7 } },
        art = {
            { file = F .. "grid", tile = { 64, 64 }, inset = 3, color = { 1, 0.75, 0.35, 0.07 }, blend = "ADD" },
            { file = F .. "scan", tile = { 8, 4 }, inset = 3, scroll = 5, color = { 1, 0.85, 0.6, 0.03 }, blend = "ADD" },
        },
        rule = { 1, 0.80, 0.40, 0.6 },
    },

    chrome = {
        minimap = {
            { file = SHADOW, scale = 1.6, color = { 0, 0, 0, 0.45 }, back = true },
            { file = F .. "fx_minimap", scale = 1.55, color = { 1, 0.80, 0.42, 0.85 }, blend = "ADD" },
            { file = F .. "fx_ring", scale = 1.5, color = { 1, 0.72, 0.30, 0.30 }, blend = "ADD", spin = -0.06 },
        },
        caps = { file = F .. "fx_pylon", ratio = 0.5, scale = 1.15, color = { 1, 0.80, 0.42, 0.9 },
            glow = { file = F .. "mote", size = 0.45, y = 0.23, color = { 1, 0.75, 0.35, 0.7 } } },
        -- hotbar: chamfered gold rim with an amber glow that flares on hover
        buttons = {
            edge = { file = F .. "chip_edge", k = 0.25, size = 6, out = 1, color = { 0.95, 0.74, 0.36, 0.85 } },
            hoverEdge = { 1, 0.92, 0.65, 1 },
            glow = { file = F .. "chamfer_glow", k = 0.5, size = 12, out = 7, color = { 0.95, 0.58, 0.18, 0.22 } },
        },
        ambience = {
            edges = {
                TOP = { 0.22, { 0.95, 0.58, 0.18, 0.12 }, { 0.95, 0.58, 0.18, 0 } },
                BOTTOM = { 0.14, { 0.9, 0.5, 0.15, 0 }, { 0.9, 0.5, 0.15, 0.09 } },
                LEFT = { 0.06, { 0.10, 0.05, 0.01, 0.30 }, { 0.10, 0.05, 0.01, 0 } },
                RIGHT = { 0.06, { 0.10, 0.05, 0.01, 0 }, { 0.10, 0.05, 0.01, 0.30 } },
            },
            motes = { file = F .. "mote", count = 18, color = { 1, 0.78, 0.38 }, alpha = 0.38,
                size = { 4, 13 }, vy = { 8, 24 }, sway = 14, life = { 7, 15 } },
        },
    },

    mini = {
        fill = 6, border = 6,
        art = { { file = F .. "fx_skyline", anchor = "BOTTOM", x = 0, y = 2, w = 66, h = 24, color = { 1, 0.72, 0.30, 0.45 }, blend = "ADD" } },
        emblem = { file = F .. "fx_emblem", size = 18, y = 1, color = BRIGHT },
        text = { 1, 0.84, 0.50, 1 }, muted = { 1, 0.80, 0.50, 0.45 },
    },
})
