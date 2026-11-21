local _, ns = ...

-- PANELKA: Soviet post-punk / coldwave (in the mood of Molchat Doma). Cold black-and-white:
-- hard square concrete frames with a faint inner line, poured-concrete texture, flickering film
-- grain and a VHS tracking band rolling down, a row of grey panel apartment blocks with a few
-- lit windows at the bottom of every window (Gemini art), constructivist bars in the corners and
-- a single faded-red constructivist emblem on the top edge, a red poster stripe under the title.
-- Buttons light up signal red. A panel tower with a red aircraft light replaces the gryphons, a
-- radio tuning dial turns around the minimap, heavy cold vignette, slow grey snow. Optional
-- music: the player's own copy of a track at Media\Music\toska.mp3 (see README there).
-- Teko poster titles, paper-white labels, red headings in dialogue.

local PK = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Panelka\\"
local M = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Modern\\"
local F = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Futuristic\\"

local RED = { 0.78, 0.24, 0.20, 1 }
local PAPER = { 0.91, 0.90, 0.87, 1 }
local GREY = { 0.70, 0.71, 0.73, 1 }
local CONCRETE = { 0.055, 0.056, 0.060, 0.95 }

ns.Styles.NewPack({
    id = "panelka",

    tokens = {
        bg = "0E0E10", surface = "1A1A1D", accent = "C73E33", text = "ECEAE5", textMuted = "9A9CA1",
        border = "3A3A3F", buttonSurface = "202024", buttonBorder = "77787C",
        titleFont = "Teko-SemiBold", titleSize = 22,
        headerFont = "BarlowSemiCondensed-SemiBold", bodyFont = "BarlowSemiCondensed-Medium",
        headerSize = 17, bodySize = 13, headerScale = 1.04, bodyScale = 1.05,
        fontColors = {
            GameFontNormal = { 0.88, 0.87, 0.83 }, GameFontNormalSmall = { 0.86, 0.85, 0.81 },
            GameFontNormalLarge = { 0.95, 0.94, 0.90 }, GameFontNormalHuge = { 0.95, 0.94, 0.90 },
            GameFontNormalMed3 = { 0.88, 0.87, 0.83 }, GameFontHighlight = { 1, 1, 1 },
            GameFontHighlightSmall = { 0.96, 0.96, 0.94 }, GameFontDisable = { 0.42, 0.42, 0.45 },
            GameFontDisableSmall = { 0.42, 0.42, 0.45 }, GameTooltipHeaderText = { 0.95, 0.94, 0.90 },
        },
        -- dialogue: bright paper text, signal-red options and headings
        parchment = { bg = "0F0F11", border = "3A3A3F", header = "F06A5C", text = "EFEDE8", muted = "A3A5AA",
            headerShadow = { 0, 0, 0, 0.9 }, bodyShadow = { 0, 0, 0, 0.7 } },
        swatch = { 0.78, 0.24, 0.20 },
    },

    music = { file = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Music\\toska.mp3", name = "Toska" },

    window = {
        shadow = { file = M .. "round_shadow", k = 0.5, size = 44, out = 26, color = { 0, 0, 0, 0.85 } },
        fill = { file = PK .. "box_fill", k = 0.25, size = 8, color = CONCRETE },
        shade = { top = { 0.20, 0.21, 0.23, 0.10 }, bottom = { 0, 0, 0, 0.35 } },
        art = {
            { file = PK .. "concrete", tile = { 256, 256 }, anchor = "fill", inset = 3, color = { 1, 1, 1, 0.05 } },
            { file = PK .. "pk_emblem", anchor = "RIGHT", x = -16, y = -10, w = 150, h = 150, color = { 0.78, 0.24, 0.20, 0.06 }, blend = "ADD" },
            { file = PK .. "pk_blocks", anchor = "bottom", inset = 8, y = 4, h = 135, color = { 0.85, 0.87, 0.90, 0.27 }, blend = "ADD" },
            { file = PK .. "grain", tile = { 128, 128 }, anchor = "fill", inset = 2, jitter = 0.5, color = { 1, 1, 1, 0.08 }, blend = "ADD" },
            { file = PK .. "vhs", tile = { 64, 256 }, anchor = "fill", inset = 2, scroll = -22, color = { 1, 1, 1, 0.05 }, blend = "ADD" },
        },
        title = { height = 30, top = { 1, 1, 1, 0.05 }, bottom = { 1, 1, 1, 0 } },
        divider = { y = 30, inset = 12, color = { 0.70, 0.71, 0.73, 0.5 } },
        border = { file = PK .. "box_edge", k = 0.25, size = 8, out = 1, color = { 0.70, 0.71, 0.73, 0.9 } },
        border2 = { file = PK .. "box_edge", k = 0.25, size = 8, out = -4, color = { 1, 1, 1, 0.10 } },
        -- a red poster stripe under the top edge, fading to the right
        topline = { inset = 6, y = 4, height = 3, left = RED, right = { 0.78, 0.24, 0.20, 0 } },
        corners = { file = PK .. "pk_corner", size = 80, out = 7, color = { 0.91, 0.90, 0.87, 0.7 }, blend = "ADD",
            which = { "TOPLEFT", "BOTTOMRIGHT" } },
        emblem = { y = 14, layers = {
            { file = PK .. "pk_emblem", size = 46, color = RED, blend = "BLEND" },
        } },
        quality = { mode = "left", size = 3, inset = 4, pad = 8 },
    },

    tooltip = {
        shadow = { file = M .. "round_shadow", k = 0.5, size = 24, out = 12, color = { 0, 0, 0, 0.8 } },
        fill = { file = PK .. "box_fill", k = 0.25, size = 6, color = { 0.06, 0.06, 0.065, 0.97 } },
        shade = { top = { 0.2, 0.21, 0.23, 0.08 }, bottom = { 0, 0, 0, 0.3 } },
        art = {
            { file = PK .. "grain", tile = { 128, 128 }, anchor = "fill", inset = 2, jitter = 0.5, color = { 1, 1, 1, 0.07 }, blend = "ADD" },
            { file = PK .. "vhs", tile = { 64, 256 }, anchor = "fill", inset = 2, scroll = -22, color = { 1, 1, 1, 0.04 }, blend = "ADD" },
        },
        border = { file = PK .. "box_edge", k = 0.25, size = 6, out = 1, color = { 0.70, 0.71, 0.73, 0.9 } },
        quality = { mode = "left", size = 3, inset = 4, pad = 6 },
    },

    button = {
        fill = { file = PK .. "box_fill", k = 0.25, size = 4 },
        edge = { file = PK .. "box_edge", k = 0.25, size = 4 },
        sheenInset = 2,
        underline = { inset = 6, y = 2, height = 1 },
        normal   = { fill = { 0.10, 0.10, 0.11, 0.96 }, edge = { 0.70, 0.71, 0.73, 0.6 }, sheen = { 1, 1, 1, 0.04 } },
        hover    = { fill = { 0.70, 0.20, 0.17, 1 }, edge = PAPER, sheen = { 1, 1, 1, 0.12 }, line = PAPER },
        disabled = { fill = { 0.07, 0.07, 0.08, 0.7 }, edge = { 0.5, 0.5, 0.5, 0.25 }, sheen = { 1, 1, 1, 0.02 } },
    },

    tab = {
        fill = { file = PK .. "box_fill", k = 0.25, size = 4 },
        edge = { file = PK .. "box_edge", k = 0.25, size = 4 },
        normal   = { fill = { 0.08, 0.08, 0.09, 0.85 }, edge = { 0.70, 0.71, 0.73, 0.30 } },
        selected = { fill = { 0.16, 0.16, 0.17, 1 }, edge = { 0.91, 0.90, 0.87, 0.9 } },
        lineHeight = 3, lineInset = 6, lineY = 2, lineLeft = RED, lineRight = RED,
    },

    reading = {
        fill = { file = PK .. "box_fill", k = 0.25, size = 8, color = { 0.075, 0.075, 0.08, 0.97 } },
        edge = { file = PK .. "box_edge2", k = 0.25, size = 10, color = { 0.70, 0.71, 0.73, 0.55 } },
        art = {
            { file = PK .. "concrete", tile = { 256, 256 }, inset = 3, color = { 1, 1, 1, 0.04 } },
            { file = PK .. "grain", tile = { 128, 128 }, inset = 3, jitter = 0.5, color = { 1, 1, 1, 0.05 }, blend = "ADD" },
        },
        rule = { 0.78, 0.24, 0.20, 0.85 },
    },

    chrome = {
        minimap = {
            { file = M .. "ring_shadow", scale = 1.3, color = { 0, 0, 0, 0.8 }, back = true },
            { file = M .. "ring", scale = 1.04, color = { 0.85, 0.86, 0.88, 0.55 } },
            { file = PK .. "pk_dial", scale = 1.42, color = { 0.85, 0.86, 0.88, 0.55 }, blend = "ADD", spin = 0.02 },
        },
        -- a panel tower with a red aircraft-warning light on its antenna
        caps = { file = PK .. "pk_tower", ratio = 0.5, scale = 1.5, color = { 0.82, 0.84, 0.88, 0.85 },
            glow = { file = F .. "mote", size = 0.14, y = 0.03, color = { 1, 0.2, 0.15, 0.95 } } },
        buttons = {
            edge = { file = PK .. "box_edge", k = 0.25, size = 4, out = 1, color = { 0.75, 0.76, 0.78, 0.8 } },
            hoverEdge = { 0.95, 0.35, 0.30, 1 },
            glow = { file = M .. "round_shadow", k = 0.5, size = 10, out = 5, color = { 0, 0, 0, 0.55 }, blend = "BLEND" },
        },
        ambience = {
            edges = {
                TOP = { 0.16, { 0, 0, 0, 0.40 }, { 0, 0, 0, 0 } },
                BOTTOM = { 0.16, { 0, 0, 0, 0 }, { 0, 0, 0, 0.45 } },
                LEFT = { 0.10, { 0, 0, 0, 0.35 }, { 0, 0, 0, 0 } },
                RIGHT = { 0.10, { 0, 0, 0, 0 }, { 0, 0, 0, 0.35 } },
            },
            -- slow grey snow
            motes = { file = F .. "mote", count = 30, color = { 0.85, 0.87, 0.90 }, alpha = 0.40,
                size = { 2, 5 }, vy = { -20, -8 }, sway = 10, life = { 10, 18 } },
        },
    },

    mini = {
        fill = 4, border = 4,
        art = { { file = PK .. "pk_blocks", anchor = "BOTTOM", x = 0, y = 2, w = 72, h = 24, color = { 0.85, 0.87, 0.9, 0.6 }, blend = "ADD" } },
        emblem = { file = PK .. "pk_emblem", size = 14, y = 1, color = RED },
        text = { 0.95, 0.94, 0.90, 1 }, muted = { 0.70, 0.71, 0.73, 0.55 },
    },
})
