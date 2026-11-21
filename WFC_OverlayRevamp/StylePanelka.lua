local _, ns = ...

-- PANELKA: Zone survival. An original exclusion-zone look (rusted steel, a field scanner,
-- hazard markings, ruins), not taken from any game: rust-stained olive-brown steel panels in
-- corroded steel frames, riveted bracket corners, a hazard-stripe band under the title and a
-- worn hazard badge on the top edge, a dead industrial skyline (cooling tower, pylons, ruins)
-- with a faint anomaly glow at the bottom of every window, film grain. Buttons light up hazard
-- amber. The minimap sits in a rugged handheld scanner: a green screen with rolling scanlines,
-- the turning tuning dials and the radar sweep, LEDs on the scanner's buttons (a fast "geiger"
-- blink, a steady green, a slow amber) and a beacon on the antenna. A power-line pylon with a red
-- lamp replaces the gryphons, a sickly sky haze tops the screen and dust drifts by.
-- Teko titles, khaki labels, amber headings in dialogue. Theme music: see Media\Music.

local PK = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Panelka\\"
local M = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Modern\\"
local F = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Futuristic\\"

local AMBER = { 0.92, 0.66, 0.20, 1 }
local PDA = { 0.55, 0.88, 0.45, 1 }
local STEEL = { 0.58, 0.45, 0.32, 0.95 }
local KHAKI = { 0.92, 0.88, 0.74, 1 }
local OLIVE = { 0.068, 0.062, 0.045, 0.95 }

ns.Styles.NewPack({
    id = "panelka",

    tokens = {
        bg = "100F0B", surface = "1C1A14", accent = "E0A030", text = "E8E4D2", textMuted = "A39E88",
        border = "5A4632", buttonSurface = "211E16", buttonBorder = "94704C",
        titleFont = "Teko-SemiBold", titleSize = 22,
        headerFont = "BarlowSemiCondensed-SemiBold", bodyFont = "BarlowSemiCondensed-Medium",
        headerSize = 17, bodySize = 13, headerScale = 1.04, bodyScale = 1.05,
        fontColors = {
            GameFontNormal = { 0.90, 0.80, 0.52 }, GameFontNormalSmall = { 0.88, 0.78, 0.50 },
            GameFontNormalLarge = { 0.95, 0.88, 0.66 }, GameFontNormalHuge = { 0.95, 0.88, 0.66 },
            GameFontNormalMed3 = { 0.90, 0.80, 0.52 }, GameFontHighlight = { 0.96, 0.95, 0.90 },
            GameFontHighlightSmall = { 0.94, 0.93, 0.88 }, GameFontDisable = { 0.45, 0.43, 0.36 },
            GameFontDisableSmall = { 0.45, 0.43, 0.36 }, GameTooltipHeaderText = { 0.95, 0.88, 0.66 },
        },
        -- dialogue: bright khaki text, hazard-amber options and headings
        parchment = { bg = "12110C", border = "5A4632", header = "F2B347", text = "EDE8D6", muted = "A39E88",
            headerShadow = { 0, 0, 0, 0.9 }, bodyShadow = { 0, 0, 0, 0.7 } },
        swatch = { 0.70, 0.50, 0.18 },
    },

    music = { file = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Music\\toska.mp3", name = "Toska" },

    window = {
        shadow = { file = M .. "round_shadow", k = 0.5, size = 44, out = 26, color = { 0, 0, 0, 0.85 } },
        fill = { file = PK .. "box_fill", k = 0.25, size = 6, color = OLIVE },
        shade = { top = { 0.32, 0.30, 0.14, 0.14 }, bottom = { 0, 0, 0, 0.35 } },
        art = {
            -- rust stains (darken) and rust highlights
            { file = PK .. "zn_rust", tile = { 256, 256 }, anchor = "fill", inset = 3, color = { 0.10, 0.055, 0.025, 0.55 } },
            { file = PK .. "zn_rust_hi", tile = { 256, 256 }, anchor = "fill", inset = 3, color = { 0.75, 0.42, 0.18, 0.07 }, blend = "ADD" },
            { file = PK .. "zn_hazard", anchor = "RIGHT", x = -16, y = -10, w = 150, h = 150, color = { 0.92, 0.66, 0.20, 0.05 }, blend = "ADD" },
            -- anomaly glow and the dead skyline at the bottom
            { file = F .. "mote", anchor = "bottom", inset = 6, y = 4, h = 120, coords = { 0, 1, 0, 0.5 }, color = { 0.55, 0.85, 0.30, 0.12 }, blend = "ADD" },
            { file = PK .. "zn_ruins", anchor = "bottom", inset = 8, y = 4, h = 130, color = { 0.80, 0.74, 0.56, 0.22 }, blend = "ADD" },
            -- hazard stripes under the title
            { file = PK .. "zn_stripes", tile = { 32, 32 }, anchor = "top", inset = 8, y = 6, h = 5, color = { 0.92, 0.66, 0.20, 0.55 } },
            { file = PK .. "grain", tile = { 128, 128 }, anchor = "fill", inset = 2, jitter = 0.5, color = { 1, 0.95, 0.8, 0.07 }, blend = "ADD" },
        },
        title = { height = 30, top = { 0.92, 0.66, 0.20, 0.10 }, bottom = { 0.92, 0.66, 0.20, 0 } },
        divider = { y = 30, inset = 12, color = { 0.86, 0.80, 0.62, 0.4 } },
        border = { file = PK .. "box_edge", k = 0.25, size = 8, out = 1, color = STEEL },
        border2 = { file = PK .. "box_edge", k = 0.25, size = 8, out = -4, color = { 1, 0.85, 0.6, 0.08 } },
        corners = { file = PK .. "zn_corner", size = 78, out = 7, color = { 0.62, 0.50, 0.38, 0.95 },
            which = { "TOPLEFT", "BOTTOMLEFT", "BOTTOMRIGHT" } },
        emblem = { y = 14, layers = {
            { file = PK .. "zn_hazard", size = 44, color = AMBER, blend = "BLEND" },
        } },
        quality = { mode = "left", size = 3, inset = 4, pad = 8 },
    },

    tooltip = {
        shadow = { file = M .. "round_shadow", k = 0.5, size = 24, out = 12, color = { 0, 0, 0, 0.8 } },
        fill = { file = PK .. "box_fill", k = 0.25, size = 6, color = { 0.072, 0.066, 0.048, 0.97 } },
        shade = { top = { 0.32, 0.30, 0.14, 0.10 }, bottom = { 0, 0, 0, 0.3 } },
        art = {
            { file = PK .. "zn_rust", tile = { 256, 256 }, anchor = "fill", inset = 2, color = { 0.10, 0.055, 0.025, 0.45 } },
            { file = PK .. "grain", tile = { 128, 128 }, anchor = "fill", inset = 2, jitter = 0.5, color = { 1, 0.95, 0.8, 0.06 }, blend = "ADD" },
        },
        border = { file = PK .. "box_edge", k = 0.25, size = 6, out = 1, color = STEEL },
        quality = { mode = "left", size = 3, inset = 4, pad = 6 },
    },

    button = {
        fill = { file = PK .. "box_fill", k = 0.25, size = 4 },
        edge = { file = PK .. "box_edge", k = 0.25, size = 4 },
        sheenInset = 2,
        underline = { inset = 6, y = 2, height = 1 },
        normal   = { fill = { 0.11, 0.10, 0.075, 0.96 }, edge = { 0.58, 0.45, 0.32, 0.75 }, sheen = { 1, 0.9, 0.7, 0.04 } },
        hover    = { fill = { 0.62, 0.42, 0.10, 1 }, edge = { 1, 0.86, 0.5, 1 }, sheen = { 1, 0.9, 0.6, 0.14 }, line = KHAKI },
        disabled = { fill = { 0.08, 0.075, 0.06, 0.7 }, edge = { 0.45, 0.4, 0.32, 0.25 }, sheen = { 1, 1, 1, 0.02 } },
    },

    tab = {
        fill = { file = PK .. "box_fill", k = 0.25, size = 4 },
        edge = { file = PK .. "box_edge", k = 0.25, size = 4 },
        normal   = { fill = { 0.09, 0.085, 0.065, 0.85 }, edge = { 0.58, 0.45, 0.32, 0.35 } },
        selected = { fill = { 0.18, 0.16, 0.11, 1 }, edge = { 0.92, 0.80, 0.55, 0.95 } },
        lineHeight = 3, lineInset = 6, lineY = 2, lineLeft = AMBER, lineRight = AMBER,
    },

    reading = {
        fill = { file = PK .. "box_fill", k = 0.25, size = 8, color = { 0.08, 0.075, 0.055, 0.97 } },
        edge = { file = PK .. "box_edge2", k = 0.25, size = 10, color = { 0.58, 0.45, 0.32, 0.65 } },
        art = {
            { file = PK .. "zn_rust", tile = { 256, 256 }, inset = 3, color = { 0.10, 0.055, 0.025, 0.35 } },
            { file = PK .. "grain", tile = { 128, 128 }, inset = 3, jitter = 0.5, color = { 1, 0.95, 0.8, 0.05 }, blend = "ADD" },
        },
        rule = { 0.92, 0.66, 0.20, 0.85 },
    },

    chrome = {
        -- The minimap in a rugged handheld scanner (Gemini art, under the map): a green screen
        -- with rolling scanlines behind the round map, the tuning dials and radar sweep in PDA
        -- green, LEDs on the scanner's buttons and a blinking beacon on its antenna.
        minimap = {
            { file = M .. "round_shadow", scale = 2.7, color = { 0, 0, 0, 0.7 }, under = true },
            { file = PK .. "zn_bezel", scale = 2.3, color = { 0.70, 0.60, 0.50, 1 }, under = true },
            { file = PK .. "box_fill", scale = 0.98, color = { 0.035, 0.065, 0.035, 1 }, under = true },
            { file = F .. "scan", scale = 0.98, color = { 0.55, 0.9, 0.45, 0.10 }, blend = "ADD", under = true, scroll = -0.6 },
            { file = F .. "grid", scale = 0.98, color = { 0.55, 0.9, 0.45, 0.10 }, blend = "ADD", under = true },
            -- around and over the map
            { file = M .. "ring_shadow", scale = 1.3, color = { 0, 0, 0, 0.8 }, back = true },
            { file = M .. "ring", scale = 1.03, color = { 0.55, 0.88, 0.45, 0.6 }, blend = "ADD" },
            { file = PK .. "pk_dial", scale = 1.3, color = { 0.80, 0.74, 0.58, 0.5 }, blend = "ADD", spin = 0.05 },
            { file = PK .. "pk_dial", scale = 1.14, color = { 0.55, 0.88, 0.45, 0.45 }, blend = "ADD", spin = -0.11 },
            { file = PK .. "mm_sweep", scale = 1.0, color = { 0.55, 0.95, 0.45, 0.5 }, blend = "ADD", spin = -1.1 },
            -- LEDs on the scanner's buttons: fast red "geiger" blink, steady green, slow amber
            { file = F .. "mote", scale = 0.1, x = -0.39, y = -0.72, color = { 1, 0.2, 0.12, 1 }, blend = "ADD",
                pulse = { speed = 9, min = 0.05, hard = true } },
            { file = F .. "mote", scale = 0.1, x = 0, y = -0.72, color = { 0.4, 1, 0.35, 1 }, blend = "ADD",
                pulse = { speed = 1.6, min = 0.45 } },
            { file = F .. "mote", scale = 0.1, x = 0.39, y = -0.72, color = { 1, 0.72, 0.2, 1 }, blend = "ADD",
                pulse = { speed = 1.3, min = 0.05, hard = true, phase = 1 } },
            -- beacon on the antenna tip
            { file = F .. "mote", scale = 0.16, x = 0.33, y = 1.07, color = { 1, 0.22, 0.15, 1 }, blend = "ADD",
                pulse = { speed = 2.4, min = 0.05, hard = true } },
        },
        -- a power-line pylon with a red warning lamp
        caps = { file = PK .. "zn_pylon", ratio = 0.5, scale = 1.5, color = { 0.78, 0.66, 0.50, 0.85 },
            glow = { file = F .. "mote", size = 0.14, y = 0.03, color = { 1, 0.2, 0.15, 0.95 } } },
        buttons = {
            edge = { file = PK .. "box_edge", k = 0.25, size = 4, out = 1, color = { 0.62, 0.48, 0.34, 0.85 } },
            hoverEdge = { 1, 0.75, 0.25, 1 },
            glow = { file = M .. "round_shadow", k = 0.5, size = 10, out = 5, color = { 0, 0, 0, 0.55 }, blend = "BLEND" },
        },
        ambience = {
            edges = {
                TOP = { 0.18, { 0.42, 0.40, 0.16, 0.16 }, { 0.42, 0.40, 0.16, 0 } },
                BOTTOM = { 0.16, { 0, 0, 0, 0 }, { 0, 0, 0, 0.45 } },
                LEFT = { 0.10, { 0.03, 0.025, 0.01, 0.38 }, { 0, 0, 0, 0 } },
                RIGHT = { 0.10, { 0, 0, 0, 0 }, { 0.03, 0.025, 0.01, 0.38 } },
            },
            -- dust drifting on the wind
            motes = { file = F .. "mote", count = 26, color = { 0.80, 0.68, 0.48 }, alpha = 0.32,
                size = { 2, 5 }, vy = { -4, 7 }, sway = 34, life = { 8, 15 } },
        },
    },

    mini = {
        fill = 4, border = 4,
        art = { { file = PK .. "zn_ruins", anchor = "BOTTOM", x = 0, y = 2, w = 72, h = 24, color = { 0.80, 0.74, 0.56, 0.7 }, blend = "ADD" } },
        emblem = { file = PK .. "zn_hazard", size = 14, y = 1, color = AMBER },
        text = { 0.95, 0.88, 0.66, 1 }, muted = { 0.62, 0.50, 0.38, 0.6 },
    },
})
