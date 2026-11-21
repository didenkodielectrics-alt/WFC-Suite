local _, ns = ...
local WFC = WFC

-- Style packs (7.0): whole-UI looks that sit next to the race-themed "Original+" skin.
--   original      Blizzard's own look (skinning off)
--   originalplus  the 6.0 stone-and-gold skin, accented by race (Skin.lua's built-in look)
--   modern        StyleModern.lua
--   futuristic    StyleFuturistic.lua
-- A pack is data (StyleX.lua) driven by the generic painter below: shadow, glow, fill, shade,
-- background art, title band, divider, light rails, border(s), corner art, emblem, shimmer,
-- buttons, tabs, tooltip quality mark and the quest/gossip reading panel. Same safety rules as
-- Skin.lua: our own frames and textures only; Blizzard regions are only faded.

local Styles = { packs = {} }
ns.Styles = Styles

Styles.ORDER = { "original", "originalplus", "modern", "futuristic", "nightdrive", "wildwood", "frostbound", "panelka" }
Styles.INFO = {
    original     = { name = "Original", desc = "Blizzard's own windows, fonts and colours." },
    originalplus = { name = "Original+", desc = "Stone panels and gold trim in your race's colours." },
    modern       = { name = "Modern", desc = "Graphite glass, rounded cards, clean type, indigo glow." },
    futuristic   = { name = "Futuristic", desc = "Amber holo-city: art-deco gold, halos, scanlines." },
    nightdrive   = { name = "Nightdrive", desc = "Synthwave: neon tubes, sunset grid, palms, stars." },
    wildwood     = { name = "Wildwood", desc = "Glowing forest: vines, bark-gold, fireflies." },
    frostbound   = { name = "Frostbound", desc = "Glacial citadel: ice shards, aurora, falling snow." },
    panelka      = { name = "Panelka", desc = "Zone survival: rusted steel, field scanner, hazard amber." },
}

---------------------------------------------------------------------------
-- Drawing helpers (shared with ThemeButton.lua / Chrome.lua)
---------------------------------------------------------------------------
local function unpackColor(c, alphaMul)
    return c[1], c[2], c[3], (c[4] or 1) * (alphaMul or 1)
end
Styles.Color = unpackColor

--- Nine textures cut from one square texture (k = corner share), corners drawn `size` px and
--- pushed `out` px outside `anchor` (default: the parent). center = also draw the middle.
function Styles.Slice(parent, layer, sub, file, k, size, out, center, blend, anchor)
    local s = {}
    out = out or 0
    anchor = anchor or parent
    local function piece(l, r, t, b)
        local tex = parent:CreateTexture(nil, layer, nil, sub)
        tex:SetTexture(file)
        tex:SetTexCoord(l, r, t, b)
        if blend then tex:SetBlendMode(blend) end
        s[#s + 1] = tex
        return tex
    end
    local tl = piece(0, k, 0, k); tl:SetSize(size, size); tl:SetPoint("TOPLEFT", anchor, "TOPLEFT", -out, out)
    local tr = piece(1 - k, 1, 0, k); tr:SetSize(size, size); tr:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", out, out)
    local bl = piece(0, k, 1 - k, 1); bl:SetSize(size, size); bl:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -out, -out)
    local br = piece(1 - k, 1, 1 - k, 1); br:SetSize(size, size); br:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out, -out)
    local top = piece(k, 1 - k, 0, k)
    top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    local bottom = piece(k, 1 - k, 1 - k, 1)
    bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    local left = piece(0, k, k, 1 - k)
    left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    local right = piece(1 - k, 1, k, 1 - k)
    right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    if center then
        local c = piece(k, 1 - k, k, 1 - k)
        c:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); c:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
        s.center = c
    end
    return s
end

function Styles.SliceColor(s, c, alphaMul)
    if not (s and c) then return end
    local r, g, b, a = unpackColor(c, alphaMul)
    for _, t in ipairs(s) do t:SetVertexColor(r, g, b, a) end
end

function Styles.SliceShown(s, shown)
    if not s then return end
    for _, t in ipairs(s) do if shown then t:Show() else t:Hide() end end
end

--- Two-colour gradient. VERTICAL: (top, bottom); HORIZONTAL: (left, right).
function Styles.Gradient(tex, dir, c1, c2)
    tex:SetColorTexture(1, 1, 1, 1)
    local minC, maxC = c2, c1
    if dir == "HORIZONTAL" then minC, maxC = c1, c2 end
    if CreateColor and tex.SetGradient
        and pcall(tex.SetGradient, tex, dir, CreateColor(unpackColor(minC)), CreateColor(unpackColor(maxC))) then
        return
    end
    if tex.SetGradientAlpha and pcall(tex.SetGradientAlpha, tex, dir, minC[1], minC[2], minC[3], minC[4] or 1,
        maxC[1], maxC[2], maxC[3], maxC[4] or 1) then
        return
    end
    tex:SetColorTexture((c1[1] + c2[1]) / 2, (c1[2] + c2[2]) / 2, (c1[3] + c2[3]) / 2, ((c1[4] or 1) + (c2[4] or 1)) / 2)
end
local Gradient, Slice, SliceColor, SliceShown = Styles.Gradient, Styles.Slice, Styles.SliceColor, Styles.SliceShown

--- A texture that repeats every w x h pixels (texcoords follow its size; see retile).
local function tile(tex, file, w, h)
    tex:SetTexture(file, "REPEAT", "REPEAT")
    tex.tileW, tex.tileH = w, h
end
local function retile(tex)
    local W, H = tex:GetWidth(), tex:GetHeight()
    if not W or W <= 0 or not H or H <= 0 then return end
    local u, v = (tex.offX or 0) / tex.tileW, (tex.offY or 0) / tex.tileH
    tex:SetTexCoord(u, u + W / tex.tileW, v, v + H / tex.tileH)
end
Styles.Tile, Styles.Retile = tile, retile

local function ornamentAlpha()
    local s = ns.Overlay and ns.Overlay.settings
    local level = s and s.ornaments or 0.55
    return math.min(1, level / 0.55)
end

---------------------------------------------------------------------------
-- Pack
---------------------------------------------------------------------------
local Pack = {}
Pack.__index = Pack

function Styles.NewPack(spec)
    local p = setmetatable({ id = spec.id, spec = spec }, Pack)
    Styles.packs[spec.id] = p
    return p
end

local function layerOf(rec, id)
    rec.packs = rec.packs or {}
    local L = rec.packs[id]
    if not L then
        L = { buttons = {}, tabs = {} }
        rec.packs[id] = L
    end
    return L
end

-- Places one art texture (inside the panel) from its spec.
local function placeArt(t, o)
    local i = o.inset or 0
    if o.anchor == "fill" then
        t:SetPoint("TOPLEFT", i, -i); t:SetPoint("BOTTOMRIGHT", -i, i)
    elseif o.anchor == "bottom" then
        t:SetPoint("BOTTOMLEFT", i, o.y or i); t:SetPoint("BOTTOMRIGHT", -i, o.y or i); t:SetHeight(o.h)
    elseif o.anchor == "top" then
        t:SetPoint("TOPLEFT", i, -(o.y or i)); t:SetPoint("TOPRIGHT", -i, -(o.y or i)); t:SetHeight(o.h)
    else
        t:SetPoint(o.anchor, o.x or 0, o.y or 0); t:SetSize(o.w, o.h)
    end
end

function Pack:Build(L, frame, V)
    local under = CreateFrame("Frame", nil, frame)
    under:SetAllPoints(frame)
    under:SetFrameLevel(math.max(0, (frame:GetFrameLevel() or 1) - 1))
    if under.EnableMouse then under:EnableMouse(false) end
    local over = CreateFrame("Frame", nil, frame)
    over:SetAllPoints(frame)
    over:SetFrameLevel((frame:GetFrameLevel() or 1) + 1)
    if over.EnableMouse then over:EnableMouse(false) end
    L.under, L.over = under, over
    local p = { art = {}, tiles = {}, spin = {} }
    L.p = p

    if V.shadow then p.shadow = Slice(under, "BACKGROUND", -8, V.shadow.file, V.shadow.k, V.shadow.size, V.shadow.out, true) end
    if V.glow then p.glow = Slice(under, "BACKGROUND", -7, V.glow.file, V.glow.k, V.glow.size, V.glow.out, true, "ADD") end
    p.fill = Slice(under, "BACKGROUND", -6, V.fill.file, V.fill.k, V.fill.size, V.fill.out or 0, true)
    if V.shade then
        p.shade = under:CreateTexture(nil, "BACKGROUND", nil, -5)
        p.shade:SetPoint("TOPLEFT", 0, -V.fill.size)
        p.shade:SetPoint("BOTTOMRIGHT", 0, V.fill.size)
    end
    for i, o in ipairs(V.art or {}) do
        local t = under:CreateTexture(nil, "BACKGROUND", nil, math.min(7, -4 + i))
        if o.tile then
            tile(t, o.file, o.tile[1], o.tile[2])
            p.tiles[#p.tiles + 1] = t
        else
            t:SetTexture(o.file)
            if o.coords then t:SetTexCoord(unpack(o.coords)) end
        end
        if o.blend then t:SetBlendMode(o.blend) end
        placeArt(t, o)
        t.spec = o
        p.art[i] = t
    end
    if V.title then
        p.title = under:CreateTexture(nil, "BORDER", nil, -8)
        p.title:SetPoint("TOPLEFT", V.title.inset or 0, -(V.title.y or 0))
        p.title:SetPoint("TOPRIGHT", -(V.title.inset or 0), -(V.title.y or 0))
        p.title:SetHeight(V.title.height)
    end
    if V.divider then
        local D = V.divider
        p.divider = {}
        for i = 1, 2 do
            local d = under:CreateTexture(nil, "BORDER", nil, -7)
            d:SetHeight(D.thickness or 1)
            d:SetPoint("TOP", under, "TOP", 0, -D.y)
            if i == 1 then d:SetPoint("LEFT", under, "LEFT", D.inset, 0); d:SetPoint("RIGHT", under, "CENTER", -(D.gap or 0), 0)
            else d:SetPoint("LEFT", under, "CENTER", D.gap or 0, 0); d:SetPoint("RIGHT", under, "RIGHT", -D.inset, 0) end
            p.divider[i] = d
        end
        if D.node then
            p.divNode = under:CreateTexture(nil, "BORDER", nil, -6)
            p.divNode:SetTexture(D.node.file)
            p.divNode:SetSize(D.node.size, D.node.size)
            p.divNode:SetPoint("CENTER", under, "TOP", 0, -D.y)
            p.divNode:SetBlendMode("ADD")
        end
    end
    if V.rails then
        p.rails = {}
        for i, side in ipairs({ "LEFT", "RIGHT" }) do
            local r = under:CreateTexture(nil, "BORDER", nil, -7)
            r:SetWidth(V.rails.width or 1)
            r:SetPoint("TOP" .. side, under, "TOP" .. side, (side == "LEFT" and 1 or -1) * V.rails.inset, -V.rails.top)
            r:SetPoint("BOTTOM" .. side, under, "BOTTOM" .. side, (side == "LEFT" and 1 or -1) * V.rails.inset, V.rails.bottom)
            p.rails[i] = r
        end
    end

    -- Over the content: border(s), top accent line, corners, emblem, shimmer, quality mark.
    p.border = Slice(over, "OVERLAY", 0, V.border.file, V.border.k, V.border.size, V.border.out, false, V.border.blend)
    if V.border2 then
        p.border2 = Slice(over, "OVERLAY", -1, V.border2.file, V.border2.k, V.border2.size, V.border2.out, false, V.border2.blend)
    end
    if V.topline then
        local T = V.topline
        p.topline = over:CreateTexture(nil, "OVERLAY", nil, 1)
        p.topline:SetPoint("TOPLEFT", T.inset, -(T.y or 1))
        p.topline:SetPoint("TOPRIGHT", -T.inset, -(T.y or 1))
        p.topline:SetHeight(T.height or 2)
    end
    if V.corners then
        local C = V.corners
        p.corners = {}
        local spots = {
            TOPLEFT = { -1, 1, 0, 1, 0, 1 }, TOPRIGHT = { 1, 1, 1, 0, 0, 1 },
            BOTTOMLEFT = { -1, -1, 0, 1, 1, 0 }, BOTTOMRIGHT = { 1, -1, 1, 0, 1, 0 },
        }
        for _, where in ipairs(C.which) do
            local sp = spots[where]
            local t = over:CreateTexture(nil, "OVERLAY", nil, 2)
            t:SetTexture(C.file)
            t:SetSize(C.size, C.size)
            t:SetPoint(where, over, where, sp[1] * C.out, sp[2] * C.out)
            t:SetTexCoord(sp[3], sp[4], sp[5], sp[6])
            if C.blend then t:SetBlendMode(C.blend) end
            t.where = where
            p.corners[#p.corners + 1] = t
        end
    end
    if V.nodes then
        p.nodes = {}
        for _, n in ipairs(V.nodes.at) do
            local t = over:CreateTexture(nil, "OVERLAY", nil, 3)
            t:SetTexture(V.nodes.file)
            t:SetSize(V.nodes.size, V.nodes.size)
            t:SetPoint("CENTER", over, n[1], n[2], n[3])
            t:SetBlendMode("ADD")
            p.nodes[#p.nodes + 1] = t
        end
    end
    if V.emblem then
        p.emblem = {}
        for i, e in ipairs(V.emblem.layers) do
            local t = over:CreateTexture(nil, "OVERLAY", nil, 3 + i)
            t:SetTexture(e.file)
            t:SetSize(e.size, e.size)
            t:SetPoint("CENTER", over, "TOP", 0, V.emblem.y)
            t:SetBlendMode(e.blend or "ADD")
            t.spec = e
            if e.spin then p.spin[#p.spin + 1] = t end
            p.emblem[i] = t
        end
    end
    if V.shimmer then
        p.shimmer = over:CreateTexture(nil, "OVERLAY", nil, 5)
        p.shimmer:SetTexture(V.shimmer.file)
        p.shimmer:SetSize(V.shimmer.w, V.shimmer.h)
        p.shimmer:SetBlendMode("ADD")
        p.shimmer:Hide()
    end
    if V.quality then
        local Q = V.quality
        p.quality = over:CreateTexture(nil, "OVERLAY", nil, 6)
        if Q.mode == "left" then
            p.quality:SetPoint("TOPLEFT", Q.inset, -Q.pad)
            p.quality:SetPoint("BOTTOMLEFT", Q.inset, Q.pad)
            p.quality:SetWidth(Q.size)
        else
            p.quality:SetPoint("TOPLEFT", Q.pad, -Q.inset)
            p.quality:SetPoint("TOPRIGHT", -Q.pad, -Q.inset)
            p.quality:SetHeight(Q.size)
        end
        p.quality:Hide()
    end

    -- Animation: tiles follow the size, scanlines drift, halos turn, a light sweeps the top.
    local acc, lastW, lastH = 0, 0, 0
    local spec = V
    under:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        if acc < 0.033 then return end
        local dt = acc
        acc = 0
        local w, h = self:GetWidth(), self:GetHeight()
        if w ~= lastW or h ~= lastH then
            lastW, lastH = w, h
            -- Keep fixed-size art inside small windows (it would spill past the edges).
            for _, t in ipairs(p.art) do
                local o = t.spec
                if not o.tile then
                    if o.w then t:SetSize(math.max(1, math.min(o.w, w - 8)), math.max(1, math.min(o.h, h - 8)))
                    elseif o.anchor == "bottom" and o.h then t:SetHeight(math.max(1, math.min(o.h, h * 0.45))) end
                end
            end
        end
        for _, t in ipairs(p.tiles) do
            local o = t.spec
            if o.scroll then t.offY = ((t.offY or 0) - dt * o.scroll) % t.tileH end
            if o.jitter and math.random() < o.jitter then
                -- film grain: the tile jumps to a random spot a few times a second
                t.offX, t.offY = math.random() * t.tileW, math.random() * t.tileH
            end
            retile(t)
        end
        if self.animate then
            local now = GetTime()
            for _, t in ipairs(p.spin) do
                if t.SetRotation then t:SetRotation(now * t.spec.spin) end
            end
            local S = spec.shimmer
            if S and p.shimmer and self.shimmerOn then
                local phase = (now % S.every) / S.time
                if phase < 1 and w > 0 then
                    p.shimmer:ClearAllPoints()
                    p.shimmer:SetPoint("CENTER", L.over, "TOPLEFT", -S.w / 2 + (w + S.w) * phase, S.y or -1)
                    p.shimmer:SetAlpha(math.sin(math.pi * phase))
                    p.shimmer:Show()
                else
                    p.shimmer:Hide()
                end
            end
        end
    end)
end

function Pack:Paint(L, V, opts)
    local p = L.p
    local alpha = opts.alpha or 1
    local orn = ornamentAlpha()
    local fx = not opts.tooltip
    if p.shadow then SliceColor(p.shadow, V.shadow.color) end
    if p.glow then SliceColor(p.glow, V.glow.color) end
    SliceColor(p.fill, V.fill.color, alpha)
    if p.shade then Gradient(p.shade, "VERTICAL", V.shade.top, V.shade.bottom) end
    for _, t in ipairs(p.art) do
        t:SetVertexColor(unpackColor(t.spec.color))
        t:Show()
    end
    local showTitle = not opts.noTitleBand
    if p.title then
        Gradient(p.title, "VERTICAL", V.title.top, V.title.bottom)
        p.title:SetShown(showTitle)
    end
    if p.divider then
        local c, fade = V.divider.color, { V.divider.color[1], V.divider.color[2], V.divider.color[3], 0 }
        Gradient(p.divider[1], "HORIZONTAL", fade, c)
        Gradient(p.divider[2], "HORIZONTAL", c, fade)
        for _, d in ipairs(p.divider) do d:SetShown(showTitle) end
        if p.divNode then
            p.divNode:SetVertexColor(unpackColor(V.divider.node.color))
            p.divNode:SetShown(showTitle)
        end
    end
    if p.rails then
        for _, r in ipairs(p.rails) do
            local c = V.rails.color
            Gradient(r, "VERTICAL", { c[1], c[2], c[3], 0 }, c)
            r:Show()
        end
    end
    SliceColor(p.border, V.border.color)
    if p.border2 then SliceColor(p.border2, V.border2.color) end
    if p.topline then
        Gradient(p.topline, "HORIZONTAL", V.topline.left, V.topline.right)
        p.topline:Show()
    end
    local ornOn = fx and orn > 0 and not opts.noOrnaments
    for _, t in ipairs(p.corners or {}) do
        local skip = not ornOn or (t.where == "TOPLEFT" and opts.noTopLeft)
        if skip then t:Hide() else
            local r, g, b, a = unpackColor(V.corners.color)
            if ns.Skin and ns.Skin.debugZones then r, g, b, a = 1, 0, 1, 1 end
            t:SetVertexColor(r, g, b, a * orn)
            t:Show()
        end
    end
    for _, t in ipairs(p.nodes or {}) do
        t:SetVertexColor(unpackColor(V.nodes.color, orn))
        t:SetShown(ornOn)
    end
    local emblemOn = ornOn and not opts.noBand
    for _, t in ipairs(p.emblem or {}) do
        t:SetVertexColor(unpackColor(t.spec.color, orn))
        t:SetShown(emblemOn)
    end
    if p.shimmer then p.shimmer:SetVertexColor(unpackColor(V.shimmer.color)) end
    L.under.animate = (p.emblem and emblemOn) or (V.shimmer ~= nil)
    L.under.shimmerOn = V.shimmer ~= nil and (fx or V.shimmer.tooltip)
    if not L.under.shimmerOn and p.shimmer then p.shimmer:Hide() end
end

--- Quest / gossip / book reading area: the pack's own panel instead of parchment.
function Pack:Reading(L, frame, opts)
    local want = opts.parchment or opts.questLogParchment
    local R = L.reading
    if not want then
        if R then
            SliceShown(R.fill, false); SliceShown(R.edge, false)
            for _, t in ipairs(R.art) do t:Hide() end
            R.rule:Hide()
        end
        return
    end
    local S = self.spec.reading
    if not R then
        R = { art = {} }
        L.reading = R
        R.rect = L.under:CreateTexture(nil, "BACKGROUND", nil, -8)
        R.rect:SetColorTexture(0, 0, 0, 0)
        R.fill = Slice(L.under, "BORDER", -6, S.fill.file, S.fill.k, S.fill.size, 0, true, nil, R.rect)
        for i, o in ipairs(S.art or {}) do
            local t = L.under:CreateTexture(nil, "BORDER", nil, -6 + i)
            if o.tile then tile(t, o.file, o.tile[1], o.tile[2]); L.p.tiles[#L.p.tiles + 1] = t
            else t:SetTexture(o.file) end
            if o.blend then t:SetBlendMode(o.blend) end
            local inset = o.inset or 2
            t:SetPoint("TOPLEFT", R.rect, "TOPLEFT", inset, -inset)
            t:SetPoint("BOTTOMRIGHT", R.rect, "BOTTOMRIGHT", -inset, inset)
            t.spec = o
            R.art[i] = t
        end
        R.edge = Slice(L.under, "BORDER", -2, S.edge.file, S.edge.k, S.edge.size, 0, false, nil, R.rect)
        R.rule = L.under:CreateTexture(nil, "BORDER", nil, -1)
        R.rule:SetHeight(1)
        R.rule:SetPoint("TOPLEFT", R.rect, "TOPLEFT", 16, -26)
        R.rule:SetPoint("TOPRIGHT", R.rect, "TOPRIGHT", -16, -26)
    end
    R.rect:ClearAllPoints()
    if opts.questLogParchment and _G.QuestLogDetailScrollFrame then
        local ql = _G.QuestLogDetailScrollFrame
        R.rect:SetPoint("TOPLEFT", ql, "TOPLEFT", -8, 6)
        R.rect:SetPoint("BOTTOMRIGHT", ql, "BOTTOMRIGHT", 24, -6)
    else
        R.rect:SetPoint("TOPLEFT", L.under, "TOPLEFT", 14, -62)
        R.rect:SetPoint("BOTTOMRIGHT", L.under, "BOTTOMRIGHT", -14, 38)
    end
    SliceColor(R.fill, S.fill.color); SliceShown(R.fill, true)
    SliceColor(R.edge, S.edge.color); SliceShown(R.edge, true)
    for _, t in ipairs(R.art) do t:SetVertexColor(unpackColor(t.spec.color)); t:Show() end
    local rc = S.rule
    Gradient(R.rule, "HORIZONTAL", { rc[1], rc[2], rc[3], 0 }, rc)
    R.rule:Show()
end

function Pack:Window(rec, frame, opts, theme)
    local S = self.spec
    local V = opts.tooltip and S.tooltip or S.window
    local L = layerOf(rec, self.id)
    if not L.under then self:Build(L, frame, V) end
    self:Paint(L, V, opts)
    self:Reading(L, frame, opts)
    L.under:Show()
    L.over:Show()
    rec.quality = L.p.quality
    return L
end

--- Quality mark for item tooltips (top line or left bar, per pack).
function Pack:Quality(rec, r, g, b)
    local L = rec.packs and rec.packs[self.id]
    local q = L and L.p and L.p.quality
    if q then
        q:SetColorTexture(r, g, b, 0.95)
        q:Show()
    end
end

function Pack:ClearQuality(rec)
    local L = rec.packs and rec.packs[self.id]
    if L and L.p and L.p.quality then L.p.quality:Hide() end
end

---------------------------------------------------------------------------
-- Buttons and tabs
---------------------------------------------------------------------------
function Pack:Button(rec, b)
    local B = self.spec.button
    local L = layerOf(rec, self.id)
    local br = L.buttons[b]
    if not br then
        br = {}
        br.fill = Slice(b, "BACKGROUND", 1, B.fill.file, B.fill.k, B.fill.size, B.fill.out or 0, true)
        br.sheen = b:CreateTexture(nil, "BACKGROUND", nil, 2)
        br.sheen:SetPoint("TOPLEFT", B.sheenInset or 2, -(B.sheenInset or 2))
        br.sheen:SetPoint("TOPRIGHT", -(B.sheenInset or 2), -(B.sheenInset or 2))
        br.sheen:SetPoint("BOTTOM", b, "CENTER", 0, 0)
        br.edge = Slice(b, "BORDER", 0, B.edge.file, B.edge.k, B.edge.size, B.edge.out or 0, false)
        if B.underline then
            br.line = b:CreateTexture(nil, "BORDER", nil, 1)
            br.line:SetHeight(B.underline.height or 1)
            br.line:SetPoint("BOTTOMLEFT", B.underline.inset, B.underline.y or 2)
            br.line:SetPoint("BOTTOMRIGHT", -B.underline.inset, B.underline.y or 2)
        end
        L.buttons[b] = br
    end
    SliceShown(br.fill, true)
    SliceShown(br.edge, true)
    br.sheen:Show()
    self:PaintButton(rec, b, false)
end

function Pack:PaintButton(rec, b, hover)
    local L = rec.packs and rec.packs[self.id]
    local br = L and L.buttons[b]
    if not br then return end
    local B = self.spec.button
    local enabled = true
    if b.IsEnabled then
        local ok, v = pcall(b.IsEnabled, b)
        enabled = not ok or v ~= false
    end
    local st = (not enabled and B.disabled) or (hover and B.hover) or B.normal
    SliceColor(br.fill, st.fill)
    SliceColor(br.edge, st.edge)
    Gradient(br.sheen, "VERTICAL", st.sheen, { st.sheen[1], st.sheen[2], st.sheen[3], 0 })
    if br.line then
        if st.line then
            local c = st.line
            Gradient(br.line, "HORIZONTAL", { c[1], c[2], c[3], 0 }, c)
            -- symmetric: bright centre via a second half is overkill; a left-to-right fade-in reads as a light sweep
            br.line:Show()
        else
            br.line:Hide()
        end
    end
end

function Pack:Tabs(rec, frame, list)
    local T = self.spec.tab
    local L = layerOf(rec, self.id)
    for i, tab in ipairs(list) do
        local tr = L.tabs[tab]
        if not tr then
            tr = {}
            tr.rect = tab:CreateTexture(nil, "BACKGROUND", nil, 0)
            tr.rect:SetColorTexture(0, 0, 0, 0)
            tr.rect:SetPoint("TOPLEFT", 6, -3)
            tr.rect:SetPoint("BOTTOMRIGHT", -6, 2)
            tr.fill = Slice(tab, "BACKGROUND", 1, T.fill.file, T.fill.k, T.fill.size, 0, true, nil, tr.rect)
            tr.edge = Slice(tab, "BORDER", 0, T.edge.file, T.edge.k, T.edge.size, 0, false, nil, tr.rect)
            tr.line = tab:CreateTexture(nil, "OVERLAY")
            tr.line:SetHeight(T.lineHeight or 2)
            tr.line:SetPoint("BOTTOMLEFT", tr.rect, "BOTTOMLEFT", T.lineInset or 6, T.lineY or 2)
            tr.line:SetPoint("BOTTOMRIGHT", tr.rect, "BOTTOMRIGHT", -(T.lineInset or 6), T.lineY or 2)
            if T.marker then
                tr.marker = tab:CreateTexture(nil, "OVERLAY", nil, 1)
                tr.marker:SetTexture(T.marker.file)
                tr.marker:SetSize(T.marker.size, T.marker.size)
                tr.marker:SetPoint("CENTER", tr.rect, "BOTTOM", 0, T.lineY or 2)
                tr.marker:SetBlendMode("ADD")
            end
            L.tabs[tab] = tr
        end
        local selected = frame.selectedTab == i
        local st = selected and T.selected or T.normal
        SliceColor(tr.fill, st.fill); SliceShown(tr.fill, true)
        SliceColor(tr.edge, st.edge); SliceShown(tr.edge, true)
        if selected then
            Gradient(tr.line, "HORIZONTAL", T.lineLeft, T.lineRight)
            tr.line:Show()
            if tr.marker then tr.marker:SetVertexColor(unpackColor(T.marker.color)); tr.marker:Show() end
        else
            tr.line:Hide()
            if tr.marker then tr.marker:Hide() end
        end
    end
end

--- Hides everything this pack drew on a skinned frame (another look took over, or restore).
function Pack:Hide(rec)
    local L = rec.packs and rec.packs[self.id]
    if not L then return end
    if L.under then L.under:Hide(); L.over:Hide() end
    for _, br in pairs(L.buttons) do
        SliceShown(br.fill, false); SliceShown(br.edge, false)
        br.sheen:Hide()
        if br.line then br.line:Hide() end
    end
    for _, tr in pairs(L.tabs) do
        SliceShown(tr.fill, false); SliceShown(tr.edge, false)
        tr.line:Hide()
        if tr.marker then tr.marker:Hide() end
    end
end

function Styles.HideAll(rec, except)
    if not rec.packs then return end
    for id, pack in pairs(Styles.packs) do
        if id ~= except then pack:Hide(rec) end
    end
end

--- A small static preview of the pack (theme picker cards).
function Pack:Mini(parent)
    local V, M = self.spec.window, self.spec.mini or {}
    local f = CreateFrame("Frame", nil, parent)
    local fill = Slice(f, "BACKGROUND", -6, V.fill.file, V.fill.k, M.fill or 6, 0, true)
    SliceColor(fill, V.fill.color)
    if V.shade then
        local s = f:CreateTexture(nil, "BACKGROUND", nil, -5)
        s:SetPoint("TOPLEFT", 0, -3); s:SetPoint("BOTTOMRIGHT", 0, 3)
        Gradient(s, "VERTICAL", V.shade.top, V.shade.bottom)
    end
    for i, o in ipairs(M.art or {}) do
        local t = f:CreateTexture(nil, "BACKGROUND", nil, -4 + i)
        t:SetTexture(o.file)
        if o.blend then t:SetBlendMode(o.blend) end
        t:SetPoint(o.anchor, o.x or 0, o.y or 0)
        t:SetSize(o.w, o.h)
        t:SetVertexColor(unpackColor(o.color))
    end
    local edge = Slice(f, "OVERLAY", 0, V.border.file, V.border.k, M.border or 6, 0, false, V.border.blend)
    SliceColor(edge, V.border.color)
    if V.topline then
        local t = f:CreateTexture(nil, "OVERLAY", nil, 1)
        t:SetPoint("TOPLEFT", 5, -1); t:SetPoint("TOPRIGHT", -5, -1); t:SetHeight(1.5)
        Gradient(t, "HORIZONTAL", V.topline.left, V.topline.right)
    end
    if M.emblem then
        local e = f:CreateTexture(nil, "OVERLAY", nil, 2)
        e:SetTexture(M.emblem.file); e:SetSize(M.emblem.size, M.emblem.size)
        e:SetPoint("CENTER", f, "TOP", 0, M.emblem.y or 0)
        e:SetBlendMode("ADD"); e:SetVertexColor(unpackColor(M.emblem.color))
    end
    -- A fake title and two text lines, in the pack's colours.
    local bar = f:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", 8, -10); bar:SetSize(24, 3)
    bar:SetColorTexture(unpackColor(M.text or { 1, 1, 1, 0.9 }))
    for i = 1, 2 do
        local l = f:CreateTexture(nil, "ARTWORK")
        l:SetPoint("TOPLEFT", 8, -14 - i * 6); l:SetSize(i == 1 and 40 or 30, 2)
        l:SetColorTexture(unpackColor(M.muted or { 1, 1, 1, 0.4 }))
    end
    local anchorTex = f:CreateTexture(nil, "ARTWORK")
    anchorTex:SetColorTexture(0, 0, 0, 0)
    anchorTex:SetPoint("BOTTOMRIGHT", -6, 6); anchorTex:SetSize(22, 8)
    local pill = Slice(f, "ARTWORK", 2, self.spec.button.fill.file, self.spec.button.fill.k, 3, 0, true, nil, anchorTex)
    SliceColor(pill, self.spec.button.hover.fill)
    return f
end

---------------------------------------------------------------------------
-- Theme tokens (the GetTheme() table) for a pack
---------------------------------------------------------------------------
local tokenCache = {}
function Styles.Theme(id)
    local pack = Styles.packs[id]
    if not pack then return nil end
    local t = tokenCache[id]
    if not t then
        local Themes = ns.Themes
        t = {}
        for k, v in pairs(pack.spec.tokens) do t[k] = v end
        t.key, t.pack, t.style = id, pack, id
        t.name = Styles.INFO[id] and Styles.INFO[id].name or id
        t.border = t.border or "4D5460"
        t.buttonSurface = t.buttonSurface or Themes.Lighten(t.surface, 0.16)
        t.buttonBorder = t.buttonBorder or "6B7280"
        t.accentSoft = t.accent .. "33"
        t.titleBand = { from = Themes.Darken(t.accent, 0.75), to = t.bg }
        tokenCache[id] = t
    end
    return t
end

return Styles
