local _, ns = ...
local WFC = WFC

-- The skin engine (design.md §7.4/§7.6). Purely cosmetic:
--   * Blizzard's art regions are faded with SetAlpha(0) (never Hide() on protected children);
--   * our own backdrop child frame goes behind the content (flat fill, 1 px border, title band,
--     ornaments in the outer zone only);
--   * titles, tabs and panel buttons are re-fonted and flattened.
-- Never SetPoint/SetSize/Show/Hide on Blizzard frames, never replace scripts or write
-- attributes: only HookScript/hooksecurefunc. Each frame is skinned the first time it shows,
-- and only out of combat. Everything we touch is remembered (weak tables keyed by frame,
-- nothing written onto Blizzard frames), so the Blizzard look can be restored live.

local Overlay, Themes = ns.Overlay, ns.Themes

local Skin = {}
ns.Skin = Skin

-- 6.0 look: Forever's own language (dark stone panel, burnished gold trim, filigree corners)
-- with the race theme as the accent: title glow, gem in the crest, hairline, tabs, hovers.
-- Media/Frame/*.tga: corner + crest drawn with Gemini, border/shadow/stone procedural
-- (scratchpad tools/buildart.js).
local MEDIA = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Frame\\"
local TITLE_BAND = 30
local BORDER, BORDER_OUT = 6, 2         -- gold trim size and how far it sits outside the frame
local SHADOW, SHADOW_OUT = 18, 12
local CORNER, CORNER_OUT = 64, 7        -- filigree corner size, overhang
local CREST_W, CREST_H = 168, 42        -- the crest sits ON the top edge, above the title

Skin.registry = {}                                     -- [frameName] = { group, opts, addon }
local records = setmetatable({}, { __mode = "k" })    -- [frame] = { faded = {region = alpha}, bd, tabs, buttons }
local hooked = setmetatable({}, { __mode = "k" })
local pendingAddon = {}                                -- [addonName] = { frameNames }

local RGB = Themes.RGB
local EDGES = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }

---------------------------------------------------------------------------
-- Registry
---------------------------------------------------------------------------
--- name: global frame name; group: "core" | "economy" | "wfc"; opts: see Skin:Window;
--- addon: load-on-demand Blizzard addon that creates the frame.
function Skin:Register(name, group, opts, addon)
    self.registry[name] = { group = group, opts = opts or {}, addon = addon }
    if addon then
        pendingAddon[addon] = pendingAddon[addon] or {}
        table.insert(pendingAddon[addon], name)
    end
end

function Skin:Registered()
    local names = {}
    for name in pairs(self.registry) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function Skin:FindRegistered(lowerName)
    for name in pairs(self.registry) do
        if name:lower() == lowerName then return name end
    end
end

function Skin:IsSkinned(name)
    local f = _G[name]
    return f ~= nil and records[f] ~= nil and records[f].active == true
end

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------
local function isForbidden(obj)
    if not obj then return true end
    local ok, forbidden = pcall(function() return obj.IsForbidden and obj:IsForbidden() end)
    return not ok or forbidden == true
end

local function isObjectType(obj, kind)
    if isForbidden(obj) then return false end
    local ok, res = pcall(function() return obj.IsObjectType and obj:IsObjectType(kind) end)
    return ok and res == true
end

local function fade(rec, region)
    if not region or isForbidden(region) then return end
    if region.SetAlpha and rec.faded[region] == nil then
        local ok, alpha = pcall(function() return region.GetAlpha and region:GetAlpha() or 1 end)
        rec.faded[region] = (ok and alpha) or 1
        pcall(region.SetAlpha, region, 0)
    end
end

-- Our own frames (backdrops, overlays): never faded by the deep pass below.
local own = setmetatable({}, { __mode = "k" })
function Skin.MarkOwn(f) if f then own[f] = true end end

-- Deep fade (Modern / Futuristic): Forever's windows draw their panel art under many names, so
-- instead of a key list, every BACKGROUND/BORDER texture of the window and its plain panels is
-- faded. Interactive and content widgets (buttons, slots, edit boxes, scroll lists, models,
-- status bars, text frames) and their subtrees are left alone, as are ARTWORK/OVERLAY layers
-- (icons, portraits, text). mode "border": only BORDER layers (windows whose pages carry dark
-- ink, like the spellbook and letters, keep their parchment).
local SKIP_TYPES = { Button = true, CheckButton = true, EditBox = true, ScrollFrame = true, Slider = true,
    StatusBar = true, PlayerModel = true, DressUpModel = true, ModelScene = true, CinematicModel = true,
    Model = true, MessageFrame = true, ScrollingMessageFrame = true, SimpleHTML = true, Cooldown = true,
    ColorSelect = true, Minimap = true, GameTooltip = true }

-- Pictures that ARE the content (the flight map, a zone map) stay: anything whose name says map.
local function isMapArt(obj)
    local ok, name = pcall(function() return obj.GetDebugName and obj:GetDebugName() end)
    return ok and type(name) == "string" and name:lower():find("map") ~= nil
end

local function deepFade(rec, frame, depth, mode)
    if depth > 4 or isForbidden(frame) or own[frame] then return end
    if depth > 1 and isMapArt(frame) then return end
    rec.deep = rec.deep or {}
    local okR, regions = pcall(function() return { frame:GetRegions() } end)
    if okR then
        for _, r in ipairs(regions) do
            if not isForbidden(r) and r.GetDrawLayer and r.SetAlpha then
                local okL, layer = pcall(r.GetDrawLayer, r)
                local isTex = isObjectType(r, "Texture")
                if okL and isTex and (layer == "BORDER" or (layer == "BACKGROUND" and mode ~= "border"))
                    and rec.deep[r] == nil and rec.faded[r] == nil and not isMapArt(r) then
                    local okA, a = pcall(r.GetAlpha, r)
                    rec.deep[r] = okA and a or 1
                    pcall(r.SetAlpha, r, 0)
                end
            end
        end
    end
    local okC, children = pcall(function() return { frame:GetChildren() } end)
    if okC then
        for _, c in ipairs(children) do
            if not isForbidden(c) and not own[c] then
                local okT, kind = pcall(c.GetObjectType, c)
                if okT and not SKIP_TYPES[kind] then deepFade(rec, c, depth + 1, mode) end
            end
        end
    end
end

local function restoreDeep(rec)
    if not rec.deep then return end
    for r, a in pairs(rec.deep) do
        if not isForbidden(r) then pcall(r.SetAlpha, r, a) end
    end
    rec.deep = nil
end

--- Two-stop gradient with alpha. dir "VERTICAL": a1 = top, a2 = bottom;
--- "HORIZONTAL": a1 = left, a2 = right. Flat average when the client has neither API.
local function gradient(tex, dir, r, g, b, a1, a2)
    tex:SetColorTexture(1, 1, 1, 1)
    local minA, maxA = a2, a1                 -- vertical: min is the bottom
    if dir == "HORIZONTAL" then minA, maxA = a1, a2 end
    if CreateColor and tex.SetGradient
        and pcall(tex.SetGradient, tex, dir, CreateColor(r, g, b, minA), CreateColor(r, g, b, maxA)) then
        return
    end
    if tex.SetGradientAlpha and pcall(tex.SetGradientAlpha, tex, dir, r, g, b, minA, r, g, b, maxA) then return end
    tex:SetColorTexture(r, g, b, (a1 + a2) / 2)
end

--- Eight textures cut from one square 9-slice texture (k = corner share of the texture),
--- drawn `size` px thick and pushed `out` px outside the parent. No centre piece.
local function slice(parent, layer, sub, file, k, size, out)
    local s = {}
    local function piece(l, r, t, b)
        local tex = parent:CreateTexture(nil, layer, nil, sub)
        tex:SetTexture(file)
        tex:SetTexCoord(l, r, t, b)
        s[#s + 1] = tex
        return tex
    end
    local tl = piece(0, k, 0, k);       tl:SetSize(size, size); tl:SetPoint("TOPLEFT", -out, out)
    local tr = piece(1 - k, 1, 0, k);   tr:SetSize(size, size); tr:SetPoint("TOPRIGHT", out, out)
    local bl = piece(0, k, 1 - k, 1);   bl:SetSize(size, size); bl:SetPoint("BOTTOMLEFT", -out, -out)
    local br = piece(1 - k, 1, 1 - k, 1); br:SetSize(size, size); br:SetPoint("BOTTOMRIGHT", out, -out)
    local top = piece(0.49, 0.51, 0, k)
    top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    local bottom = piece(0.49, 0.51, 1 - k, 1)
    bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    local left = piece(0, k, 0.49, 0.51)
    left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    local right = piece(1 - k, 1, 0.49, 0.51)
    right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    s.top = top
    return s
end

local function sliceColor(s, r, g, b, a)
    for _, t in ipairs(s) do t:SetVertexColor(r, g, b, a or 1) end
end
local function sliceShown(s, shown)
    for _, t in ipairs(s) do if shown then t:Show() else t:Hide() end end
end

--- Gold filigree corners (top-left, bottom-left, bottom-right; never top-right, where close
--- buttons live) and the crest on the top edge, its gem in the race accent. Full-colour gold
--- art; the ornament setting scales its opacity (0.55 = full).
local CORNERS = {
    { "TOPLEFT", -1, 1, 0, 1, 0, 1 }, { "BOTTOMLEFT", -1, -1, 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, -1, 1, 0, 1, 0 },
}

local function ornaments(rec, over, theme)
    rec.ornaments = rec.ornaments or {}
    local level = Overlay.settings.ornaments or 0
    local alpha = math.min(1, level / 0.55)
    local wanted = alpha > 0 and not rec.opts.noOrnaments
    for i, spec in ipairs(CORNERS) do
        local t = rec.ornaments[i]
        if not t and wanted then
            t = over:CreateTexture(nil, "OVERLAY", nil, 2)
            t:SetTexture(MEDIA .. "corner")
            t:SetSize(CORNER, CORNER)
            t:SetPoint(spec[1], over, spec[1], spec[2] * CORNER_OUT, spec[3] * CORNER_OUT)
            -- The art is drawn for the top-left corner: mirror it into the others.
            t:SetTexCoord(spec[4], spec[5], spec[6], spec[7])
            rec.ornaments[i] = t
        end
        if t then
            local skip = not wanted or (spec[1] == "TOPLEFT" and rec.opts.noTopLeft)
            if skip then t:Hide() else
                if Skin.debugZones then t:SetVertexColor(1, 0, 1, 1) else t:SetVertexColor(1, 1, 1, alpha) end
                t:Show()
            end
        end
    end
    local crest = rec.crest
    if not crest and wanted then
        crest = {
            gold = over:CreateTexture(nil, "OVERLAY", nil, 3),
            gem = over:CreateTexture(nil, "OVERLAY", nil, 4),
        }
        for _, t in pairs(crest) do
            t:SetSize(CREST_W, CREST_H)
            -- Art band is the middle ~60%: this rests its lower edge on the gold trim, clear
            -- of the centred window title just below.
            t:SetPoint("BOTTOM", over, "TOP", 0, -CREST_H * 0.5 + 10)
        end
        crest.gold:SetTexture(MEDIA .. "crest")
        crest.gem:SetTexture(MEDIA .. "crest_gem")
        rec.crest = crest
    end
    if crest then
        if wanted and not rec.opts.noBand then
            local r, g, b = RGB(theme.accent)
            crest.gold:SetVertexColor(1, 1, 1, alpha)
            crest.gem:SetVertexColor(math.min(1, r * 1.5 + 0.15), math.min(1, g * 1.5 + 0.15), math.min(1, b * 1.5 + 0.15), alpha)
            crest.gold:Show(); crest.gem:Show()
        else
            crest.gold:Hide(); crest.gem:Hide()
        end
    end
end

--- Our window body, behind the content (bd, one level below the frame): drop shadow, stone
--- fill tinted with the theme colour, inner vignette, accent title glow with a gold divider.
--- The gold trim, accent hairline and ornaments sit on `over`, one level above the frame, so
--- inset art and scroll children can't cover them. Neither takes the mouse.
local function backdrop(rec, frame, theme)
    local bd = rec.bd
    local tooltip = rec.opts.tooltip
    if not bd then
        bd = CreateFrame("Frame", nil, frame)
        bd:SetAllPoints(frame)
        bd:SetFrameLevel(math.max(0, (frame:GetFrameLevel() or 1) - 1))
        bd.shadow = slice(bd, "BACKGROUND", -8, MEDIA .. "shadow", 0.25,
            tooltip and 12 or SHADOW, tooltip and 6 or SHADOW_OUT)
        bd.fill = bd:CreateTexture(nil, "BACKGROUND", nil, -8)
        bd.fill:SetAllPoints()
        bd.fill:SetTexture(MEDIA .. "stone", "REPEAT", "REPEAT")
        if bd.fill.SetHorizTile then bd.fill:SetHorizTile(true); bd.fill:SetVertTile(true) end
        bd.vignette = {}
        for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local v = bd:CreateTexture(nil, "BACKGROUND", nil, -7)
            if i <= 2 then
                v:SetPoint(side .. "LEFT"); v:SetPoint(side .. "RIGHT"); v:SetHeight(18)
                gradient(v, "VERTICAL", 0, 0, 0, i == 1 and 0.4 or 0, i == 1 and 0 or 0.4)
            else
                v:SetPoint("TOP" .. side); v:SetPoint("BOTTOM" .. side); v:SetWidth(18)
                gradient(v, "HORIZONTAL", 0, 0, 0, i == 3 and 0.4 or 0, i == 3 and 0 or 0.4)
            end
            bd.vignette[i] = v
        end
        bd.title = bd:CreateTexture(nil, "BACKGROUND", nil, -7)
        bd.title:SetPoint("TOPLEFT")
        bd.title:SetPoint("TOPRIGHT")
        bd.title:SetHeight(TITLE_BAND)
        -- Gold divider under the title, fading out at both ends, with an accent glow below it.
        bd.divider = {}
        for i = 1, 2 do
            local d = bd:CreateTexture(nil, "BORDER", nil, 1)
            d:SetHeight(1)
            d:SetPoint("TOP", bd, "TOP", 0, -TITLE_BAND)
            if i == 1 then d:SetPoint("LEFT", bd, "LEFT", 12, 0); d:SetPoint("RIGHT", bd, "CENTER")
            else d:SetPoint("LEFT", bd, "CENTER"); d:SetPoint("RIGHT", bd, "RIGHT", -12, 0) end
            bd.divider[i] = d
        end
        bd.glow = bd:CreateTexture(nil, "BORDER", nil, 0)
        bd.glow:SetHeight(6)
        bd.glow:SetPoint("TOPLEFT", bd, "TOPLEFT", 12, -TITLE_BAND - 1)
        bd.glow:SetPoint("TOPRIGHT", bd, "TOPRIGHT", -12, -TITLE_BAND - 1)

        local over = CreateFrame("Frame", nil, frame)
        over:SetAllPoints(frame)
        over:SetFrameLevel((frame:GetFrameLevel() or 1) + 1)
        bd.over = over
        bd.border = slice(over, "OVERLAY", 0, MEDIA .. "border", 0.125,
            tooltip and 4 or BORDER, tooltip and 1 or BORDER_OUT)
        bd.hair = {}
        for i, pts in ipairs(EDGES) do
            local e = over:CreateTexture(nil, "OVERLAY", nil, -1)
            local inset = BORDER - BORDER_OUT + 2
            local x1 = (pts[1]:find("LEFT") and inset or -inset)
            local y1 = (pts[1]:find("TOP") and -inset or inset)
            local x2 = (pts[2]:find("LEFT") and inset or -inset)
            local y2 = (pts[2]:find("TOP") and -inset or inset)
            e:SetPoint(pts[1], x1, y1)
            e:SetPoint(pts[2], x2, y2)
            if i <= 2 then e:SetHeight(1) else e:SetWidth(1) end
            bd.hair[i] = e
        end
        -- Item-quality line under the top trim (tooltips; see Skin:TopEdge).
        bd.quality = over:CreateTexture(nil, "OVERLAY", nil, 1)
        bd.quality:SetHeight(2)
        bd.quality:SetPoint("TOPLEFT", over, "TOPLEFT", 4, -3)
        bd.quality:SetPoint("TOPRIGHT", over, "TOPRIGHT", -4, -3)
        bd.quality:Hide()
        rec.bd = bd
    end
    local a = rec.opts.alpha or 1
    local r, g, b = RGB(theme.bg)
    bd.fill:SetVertexColor(math.min(1, r * 1.3), math.min(1, g * 1.3), math.min(1, b * 1.3), a)
    sliceColor(bd.shadow, 0, 0, 0, tooltip and 0.7 or 1)
    for _, v in ipairs(bd.vignette) do if tooltip then v:Hide() else v:Show() end end

    local ar, ag, ab = RGB(theme.accent)
    local showTitle = not rec.opts.noTitleBand
    if showTitle then
        gradient(bd.title, "VERTICAL", ar * 0.45, ag * 0.45, ab * 0.45, 0.9, 0)
        gradient(bd.divider[1], "HORIZONTAL", 0.85, 0.66, 0.29, 0, 0.95)
        gradient(bd.divider[2], "HORIZONTAL", 0.85, 0.66, 0.29, 0.95, 0)
        gradient(bd.glow, "VERTICAL", ar, ag, ab, 0.3, 0)
    end
    for _, t in ipairs({ bd.title, bd.divider[1], bd.divider[2], bd.glow }) do
        if showTitle then t:Show() else t:Hide() end
    end

    sliceColor(bd.border, 1, 1, 1, 1)
    for _, e in ipairs(bd.hair) do
        e:SetColorTexture(ar, ag, ab, tooltip and 0.18 or 0.28)
    end
    bd:Show()
    bd.over:Show()
    return bd
end

--- Detailed lighter parchment inset for quest and gossip reading areas.
--- Keeps the theme's background as a thick, race-flavoured border frame around it.
local function parchment(rec, bd, frame, theme)
    local p = rec.parchment
    local isParchment = rec.opts.parchment or rec.opts.questLogParchment
    if not isParchment then
        if p and p.fill then
            p.fill:Hide()
            if p.tex then p.tex:Hide() end
            if p.topShadow then p.topShadow:Hide() end
            if p.botShadow then p.botShadow:Hide() end
            for _, e in ipairs(p.edges or {}) do e:Hide() end
            for _, ie in ipairs(p.innerEdges or {}) do ie:Hide() end
            for _, c in ipairs(p.corners or {}) do c:Hide() end
            if p.divider then p.divider:Hide() end
        end
        return
    end

    if not p then
        p = {}
        rec.parchment = p

        -- Base warm parchment fill (sits on bd, behind all quest content)
        p.fill = bd:CreateTexture(nil, "BACKGROUND", nil, -6)

        -- Authentic paper grain overlay from Blizzard's achievement parchment
        p.tex = bd:CreateTexture(nil, "BACKGROUND", nil, -5)
        p.tex:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal")

        -- Subtle top & bottom depth shadows (recessed into the frame)
        p.topShadow = bd:CreateTexture(nil, "BACKGROUND", nil, -4)
        p.topShadow:SetHeight(28)

        p.botShadow = bd:CreateTexture(nil, "BACKGROUND", nil, -4)
        p.botShadow:SetHeight(28)

        -- Crisp outer border (1 px dark framing edge)
        p.edges = {}
        for i = 1, 4 do
            local e = bd:CreateTexture(nil, "BORDER", nil, -2)
            if i <= 2 then e:SetHeight(1) else e:SetWidth(1) end
            p.edges[i] = e
        end

        -- Detailed inner accent rule (inset by 2 px)
        p.innerEdges = {}
        for i = 1, 4 do
            local ie = bd:CreateTexture(nil, "BORDER", nil, -1)
            if i <= 2 then ie:SetHeight(1) else ie:SetWidth(1) end
            p.innerEdges[i] = ie
        end

        -- Detailed corner bracket studs
        p.corners = {}
        for i = 1, 4 do
            local c = bd:CreateTexture(nil, "BORDER", nil, 0)
            c:SetSize(7, 7)
            p.corners[i] = c
        end

        -- Subtle horizontal header rule
        p.divider = bd:CreateTexture(nil, "BORDER", nil, -1)
        p.divider:SetHeight(1)
    end

    p.fill:ClearAllPoints()
    if rec.opts.questLogParchment and _G.QuestLogDetailScrollFrame then
        local ql = _G.QuestLogDetailScrollFrame
        p.fill:SetPoint("TOPLEFT", ql, "TOPLEFT", -8, 6)
        p.fill:SetPoint("BOTTOMRIGHT", ql, "BOTTOMRIGHT", 24, -6)
    else
        -- Standard quest & gossip dialog: leaves top title area (62 px), bottom button bar (38 px),
        -- and 14 px left/right margins. The theme's rich color acts as the thick border frame.
        p.fill:SetPoint("TOPLEFT", bd, "TOPLEFT", 14, -62)
        p.fill:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -14, 38)
    end

    p.tex:ClearAllPoints()
    p.tex:SetAllPoints(p.fill)

    p.topShadow:ClearAllPoints()
    p.topShadow:SetPoint("TOPLEFT", p.fill, "TOPLEFT", 0, 0)
    p.topShadow:SetPoint("TOPRIGHT", p.fill, "TOPRIGHT", 0, 0)

    p.botShadow:ClearAllPoints()
    p.botShadow:SetPoint("BOTTOMLEFT", p.fill, "BOTTOMLEFT", 0, 0)
    p.botShadow:SetPoint("BOTTOMRIGHT", p.fill, "BOTTOMRIGHT", 0, 0)

    -- Outer border edges
    p.edges[1]:ClearAllPoints()
    p.edges[1]:SetPoint("TOPLEFT", p.fill, "TOPLEFT", 0, 0)
    p.edges[1]:SetPoint("TOPRIGHT", p.fill, "TOPRIGHT", 0, 0)

    p.edges[2]:ClearAllPoints()
    p.edges[2]:SetPoint("BOTTOMLEFT", p.fill, "BOTTOMLEFT", 0, 0)
    p.edges[2]:SetPoint("BOTTOMRIGHT", p.fill, "BOTTOMRIGHT", 0, 0)

    p.edges[3]:ClearAllPoints()
    p.edges[3]:SetPoint("TOPLEFT", p.fill, "TOPLEFT", 0, 0)
    p.edges[3]:SetPoint("BOTTOMLEFT", p.fill, "BOTTOMLEFT", 0, 0)

    p.edges[4]:ClearAllPoints()
    p.edges[4]:SetPoint("TOPRIGHT", p.fill, "TOPRIGHT", 0, 0)
    p.edges[4]:SetPoint("BOTTOMRIGHT", p.fill, "BOTTOMRIGHT", 0, 0)

    -- Inset inner decorative line (2 px inset)
    p.innerEdges[1]:ClearAllPoints()
    p.innerEdges[1]:SetPoint("TOPLEFT", p.fill, "TOPLEFT", 2, -2)
    p.innerEdges[1]:SetPoint("TOPRIGHT", p.fill, "TOPRIGHT", -2, -2)

    p.innerEdges[2]:ClearAllPoints()
    p.innerEdges[2]:SetPoint("BOTTOMLEFT", p.fill, "BOTTOMLEFT", 2, 2)
    p.innerEdges[2]:SetPoint("BOTTOMRIGHT", p.fill, "BOTTOMRIGHT", -2, 2)

    p.innerEdges[3]:ClearAllPoints()
    p.innerEdges[3]:SetPoint("TOPLEFT", p.fill, "TOPLEFT", 2, -2)
    p.innerEdges[3]:SetPoint("BOTTOMLEFT", p.fill, "BOTTOMLEFT", 2, 2)

    p.innerEdges[4]:ClearAllPoints()
    p.innerEdges[4]:SetPoint("TOPRIGHT", p.fill, "TOPRIGHT", -2, -2)
    p.innerEdges[4]:SetPoint("BOTTOMRIGHT", p.fill, "BOTTOMRIGHT", -2, 2)

    -- Corner bracket studs
    p.corners[1]:ClearAllPoints()
    p.corners[1]:SetPoint("TOPLEFT", p.fill, "TOPLEFT", 1, -1)

    p.corners[2]:ClearAllPoints()
    p.corners[2]:SetPoint("TOPRIGHT", p.fill, "TOPRIGHT", -1, -1)

    p.corners[3]:ClearAllPoints()
    p.corners[3]:SetPoint("BOTTOMLEFT", p.fill, "BOTTOMLEFT", 1, 1)

    p.corners[4]:ClearAllPoints()
    p.corners[4]:SetPoint("BOTTOMRIGHT", p.fill, "BOTTOMRIGHT", -1, 1)

    -- Header divider
    p.divider:ClearAllPoints()
    p.divider:SetPoint("TOPLEFT", p.fill, "TOPLEFT", 16, -26)
    p.divider:SetPoint("TOPRIGHT", p.fill, "TOPRIGHT", -16, -26)

    -- Apply theme parchment colors
    local pData = theme.parchment or { bg = "EDE2CB", border = "3E2E1C" }
    local r, g, b = RGB(pData.bg)
    p.fill:SetColorTexture(r, g, b, 0.98)
    p.fill:Show()

    p.tex:SetVertexColor(r, g, b, 0.52)
    p.tex:Show()

    gradient(p.topShadow, "VERTICAL", 0, 0, 0, 0.13, 0)
    p.topShadow:Show()
    gradient(p.botShadow, "VERTICAL", 0, 0, 0, 0, 0.09)
    p.botShadow:Show()

    local br, bg, bb = RGB(pData.border)
    for _, e in ipairs(p.edges) do
        e:SetColorTexture(br, bg, bb, 1)
        e:Show()
    end

    local ar, ag, ab = RGB(theme.accent)
    for _, ie in ipairs(p.innerEdges) do
        ie:SetColorTexture(ar, ag, ab, 0.35)
        ie:Show()
    end

    for _, c in ipairs(p.corners) do
        c:SetColorTexture(ar, ag, ab, 0.65)
        c:Show()
    end

    p.divider:SetColorTexture(ar, ag, ab, 0.28)
    p.divider:Show()
end

local function fontObject(theme, header)
    return ns.Fonts and ns.Fonts:Object(theme, header) or nil
end

local function hasButtonArt(b)
    if b.Left and b.Middle and b.Right then return true end
    if b.LeftTexture and b.MiddleTexture and b.RightTexture then return true end
    return false
end

local function fadeButtonArt(rec, b)
    fade(rec, b.Left)
    fade(rec, b.Middle)
    fade(rec, b.Right)
    fade(rec, b.LeftTexture)
    fade(rec, b.MiddleTexture)
    fade(rec, b.RightTexture)
end

-- Which skinned window a button belongs to (hover/enable hooks are set once per button and
-- dispatch to whichever look is active).
local buttonRec = setmetatable({}, { __mode = "k" })
local buttonHooked = setmetatable({}, { __mode = "k" })

local function hookButton(rec, b)
    buttonRec[b] = rec
    if buttonHooked[b] or not b.HookScript then return end
    buttonHooked[b] = true
    pcall(b.HookScript, b, "OnEnter", function() Skin:ButtonState(b, true) end)
    pcall(b.HookScript, b, "OnLeave", function() Skin:ButtonState(b, false) end)
    pcall(b.HookScript, b, "OnEnable", function() Skin:ButtonEnabled(b) end)
    pcall(b.HookScript, b, "OnDisable", function() Skin:ButtonEnabled(b) end)
end

--- Flat panel buttons (UIPanelButtonTemplate-style: Left/Middle/Right art).
local function button(rec, b, theme)
    if not isObjectType(b, "Button") then return end
    if not hasButtonArt(b) then return end
    fadeButtonArt(rec, b)
    hookButton(rec, b)
    if theme.pack then
        theme.pack:Button(rec, b)
        local fs = b.GetFontString and b:GetFontString()
        if fs and not isForbidden(fs) then
            fs:SetShadowOffset(1, -1)
            fs:SetShadowColor(0, 0, 0, 0.9)
            if not rec.opts.keepFonts and ns.Fonts then
                local f = ns.Fonts:Object(theme, false)
                if f then fs:SetFontObject(f) end
            end
        end
        return
    end
    local br = rec.buttons[b]
    if not br then
        br = { fill = b:CreateTexture(nil, "BACKGROUND", nil, 1) }
        br.fill:SetPoint("TOPLEFT", 1, -1)
        br.fill:SetPoint("BOTTOMRIGHT", -1, 1)
        br.shine = b:CreateTexture(nil, "BACKGROUND", nil, 2)
        br.shine:SetPoint("TOPLEFT", 2, -2)
        br.shine:SetPoint("TOPRIGHT", -2, -2)
        br.shine:SetHeight(1)
        br.edges = slice(b, "BORDER", 0, MEDIA .. "border", 0.125, 3, 0)
        rec.buttons[b] = br
    end
    br.theme = theme
    br.fill:Show()
    br.shine:Show()
    sliceShown(br.edges, true)
    Skin.PaintButton(br, b, false)

    local fs = b.GetFontString and b:GetFontString()
    if fs and not isForbidden(fs) then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
        if not rec.opts.keepFonts and ns.Fonts then
            local f = ns.Fonts:Object(theme, false)
            if f then fs:SetFontObject(f) end
        end
    end
end

function Skin:ButtonEnabled(b)
    if isForbidden(b) then return end
    local rec = buttonRec[b]
    if not (rec and rec.active) then return end
    local theme = Overlay:Theme()
    if theme and theme.pack then return theme.pack:PaintButton(rec, b, false) end
    local br = rec.buttons[b]
    if br and br.theme then
        local enabled = not b.IsEnabled or b:IsEnabled()
        local a = enabled and 1 or 0.45
        br.fill:SetAlpha(a)
        br.shine:SetAlpha(a)
        for _, e in ipairs(br.edges) do e:SetAlpha(a) end
    end
end

--- Dark lacquered button with a bronze rim; hover warms the fill with the race accent and
--- brightens the rim to full gold.
local function paintButton(br, b, hover)
            local enabled = not b.IsEnabled or b:IsEnabled()
            if hover and not enabled then return end
            local sr, sg, sb = RGB(br.theme.surface)
            local ar, ag, ab = RGB(br.theme.accent)
            local mix = hover and 0.38 or 0.14
            local function top(c, acc) return math.min(1, c * 1.6 + acc * mix) end
            br.fill:SetColorTexture(1, 1, 1, 1)
            local tr, tg, tb = top(sr, ar), top(sg, ag), top(sb, ab)
            if CreateColor and br.fill.SetGradient then
                pcall(br.fill.SetGradient, br.fill, "VERTICAL",
                    CreateColor(tr * 0.55, tg * 0.55, tb * 0.55, 1), CreateColor(tr, tg, tb, 1))
            else
                br.fill:SetColorTexture(tr * 0.8, tg * 0.8, tb * 0.8, 1)
            end
            br.shine:SetColorTexture(1, 0.9, 0.6, hover and 0.35 or 0.12)
            local rim = hover and 1 or 0.62
            sliceColor(br.edges, rim, rim, rim, 1)
            local a = enabled and 1 or 0.45
            br.fill:SetAlpha(a)
            br.shine:SetAlpha(a)
            for _, e in ipairs(br.edges) do e:SetAlpha(a) end
end
Skin.PaintButton = paintButton

function Skin:ButtonState(b, hover)
    if isForbidden(b) then return end
    local rec = buttonRec[b]
    if not (rec and rec.active) then return end
    local theme = Overlay:Theme()
    if theme and theme.pack then return theme.pack:PaintButton(rec, b, hover) end
    local br = rec.buttons[b]
    if br and br.theme then return paintButton(br, b, hover) end
end

local TAB_ART = { "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive",
    "LeftDisabled", "MiddleDisabled", "RightDisabled", "LeftHighlight", "MiddleHighlight", "RightHighlight" }

--- A window's tab buttons, with Blizzard's tab art faded.
local function listTabs(rec, frame)
    local list = {}
    if type(frame.Tabs) == "table" then
        for _, t in ipairs(frame.Tabs) do list[#list + 1] = t end
    elseif frame.numTabs and frame.GetName and frame:GetName() then
        for i = 1, frame.numTabs do list[#list + 1] = _G[frame:GetName() .. "Tab" .. i] end
    end
    local ok = {}
    for _, tab in ipairs(list) do
        if not isForbidden(tab) then
            for _, key in ipairs(TAB_ART) do fade(rec, tab[key]) end
            ok[#ok + 1] = tab
        end
    end
    return ok
end

--- Flat text tabs with a 2 px accent underline on the selected one (design §7.4.5).
local function tabs(rec, frame, theme)
    local list = listTabs(rec, frame)
    if theme.pack then
        theme.pack:Tabs(rec, frame, list)
        for _, tab in ipairs(list) do
            if tab.Text and not isForbidden(tab.Text) and not rec.opts.keepFonts then
                local f = fontObject(theme, false)
                if f then tab.Text:SetFontObject(f) end
            end
        end
        return
    end
    for i, tab in ipairs(list) do
        if not isForbidden(tab) then
            local tr = rec.tabs[tab]
            if not tr then
                tr = { line = tab:CreateTexture(nil, "OVERLAY"), index = i }
                tr.fill = tab:CreateTexture(nil, "BACKGROUND", nil, 1)
                tr.fill:SetPoint("TOPLEFT", 6, -3)
                tr.fill:SetPoint("BOTTOMRIGHT", -6, 2)
                tr.rim = slice(tab, "BORDER", 0, MEDIA .. "border", 0.125, 3, 0)
                for _, t in ipairs(tr.rim) do
                    t:ClearAllPoints()
                end
                -- re-anchor the rim to the fill rectangle rather than the whole tab
                local rim, s = tr.rim, 3
                rim[1]:SetPoint("TOPLEFT", tr.fill, "TOPLEFT"); rim[1]:SetSize(s, s)
                rim[2]:SetPoint("TOPRIGHT", tr.fill, "TOPRIGHT"); rim[2]:SetSize(s, s)
                rim[3]:SetPoint("BOTTOMLEFT", tr.fill, "BOTTOMLEFT"); rim[3]:SetSize(s, s)
                rim[4]:SetPoint("BOTTOMRIGHT", tr.fill, "BOTTOMRIGHT"); rim[4]:SetSize(s, s)
                rim[5]:SetPoint("TOPLEFT", rim[1], "TOPRIGHT"); rim[5]:SetPoint("BOTTOMRIGHT", rim[2], "BOTTOMLEFT")
                rim[6]:SetPoint("TOPLEFT", rim[3], "TOPRIGHT"); rim[6]:SetPoint("BOTTOMRIGHT", rim[4], "BOTTOMLEFT")
                rim[7]:SetPoint("TOPLEFT", rim[1], "BOTTOMLEFT"); rim[7]:SetPoint("BOTTOMRIGHT", rim[3], "TOPRIGHT")
                rim[8]:SetPoint("TOPLEFT", rim[2], "BOTTOMLEFT"); rim[8]:SetPoint("BOTTOMRIGHT", rim[4], "TOPRIGHT")
                tr.line:SetPoint("BOTTOMLEFT", tr.fill, "BOTTOMLEFT", 4, 3)
                tr.line:SetPoint("BOTTOMRIGHT", tr.fill, "BOTTOMRIGHT", -4, 3)
                tr.line:SetHeight(2)
                rec.tabs[tab] = tr
            end
            local selected = frame.selectedTab == i
            local ar, ag, ab = RGB(theme.accent)
            local sr, sg, sb = RGB(theme.surface)
            local k = selected and 1.9 or 1.15
            tr.fill:SetColorTexture(math.min(1, sr * k + ar * (selected and 0.18 or 0)),
                math.min(1, sg * k + ag * (selected and 0.12 or 0)), math.min(1, sb * k + ab * (selected and 0.12 or 0)), 0.96)
            tr.fill:Show()
            local rimA = selected and 1 or 0.5
            sliceColor(tr.rim, rimA, rimA, rimA, 1)
            sliceShown(tr.rim, true)
            tr.line:SetColorTexture(ar, ag, ab, 1)
            if selected then tr.line:Show() else tr.line:Hide() end
            if tab.Text and not isForbidden(tab.Text) and not rec.opts.keepFonts then
                local f = fontObject(theme, false)
                if f then tab.Text:SetFontObject(f) end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------
local ART_KEYS = { "NineSlice", "Bg", "Background", "TopTileStreaks", "PortraitContainer", "portrait",
    "PortraitFrame", "TitleBg", "TopBorder", "BottomBorder", "LeftBorder", "RightBorder" }

local function skinButtons(rec, parent, theme, depth)
    if not parent or isForbidden(parent) or not parent.GetChildren or (depth and depth > 4) then return end
    depth = depth or 1
    local ok, children = pcall(function() return { parent:GetChildren() } end)
    if not ok or not children then return end
    for _, child in ipairs(children) do
        if not isForbidden(child) then
            if isObjectType(child, "Button") then
                button(rec, child, theme)
            end
            if child.GetChildren and not isObjectType(child, "ScrollFrame") then
                skinButtons(rec, child, theme, depth + 1)
            end
        end
    end
end

--- Skins one window. opts: { title = key or region, keepFonts, noTopLeft, noBand, noTitleBand,
--- alpha, insets = { keys }, extraArt = { keys }, buttons = true }
function Skin:Window(frame, opts, theme)
    if not frame or isForbidden(frame) then return end
    opts = opts or {}
    local rec = records[frame]
    if not rec then
        rec = { faded = {}, buttons = {}, tabs = {}, opts = opts }
        records[frame] = rec
    end
    rec.opts = opts
    for _, key in ipairs(ART_KEYS) do fade(rec, frame[key]) end
    -- Some windows keep their frame art on a child (the world map's BorderFrame).
    local border = frame.BorderFrame
    if border and not isForbidden(border) then
        for _, key in ipairs(ART_KEYS) do fade(rec, border[key]) end
        if border.TitleContainer then fade(rec, border.TitleContainer.Bg) end
    end
    for _, key in ipairs(opts.extraArt or {}) do fade(rec, frame[key]) end
    -- Insets: fade their art; our backdrop shows through as the flat window colour.
    for _, key in ipairs(opts.insets or { "Inset" }) do
        local inset = frame[key]
        if inset and not isForbidden(inset) then
            fade(rec, inset.NineSlice)
            fade(rec, inset.Bg)
        end
    end
    local Styles = ns.Styles
    if theme.pack then
        -- A style pack owns this window: hide the Original+ pieces and the other packs.
        Skin.HideOriginal(rec)
        Styles.HideAll(rec, theme.pack.id)
        local L = theme.pack:Window(rec, frame, opts, theme)
        own[L.under] = true
        own[L.over] = true
        if not opts.tooltip and opts.deep ~= false then deepFade(rec, frame, 1, opts.deep) end
    else
        if Styles then Styles.HideAll(rec) end
        restoreDeep(rec)
        local bd = backdrop(rec, frame, theme)
        own[bd] = true
        if bd.over then own[bd.over] = true end
        ornaments(rec, bd.over, theme)
        parchment(rec, bd, frame, theme)
        rec.quality = bd.quality
    end
    local title = opts.title and (type(opts.title) == "string" and frame[opts.title] or opts.title)
        or frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText)
        or (border and (border.TitleText or (border.TitleContainer and border.TitleContainer.TitleText)))
    if title and not isForbidden(title) and title.SetFontObject and not opts.keepFonts then
        local f = fontObject(theme, true)
        if f then title:SetFontObject(f) end
    end
    tabs(rec, frame, theme)
    if opts.buttons ~= false and frame.GetChildren then
        skinButtons(rec, frame, theme, 1)
    end
    rec.active = true
    return rec
end

--- Hides the Original+ pieces on a frame (a style pack has taken it over).
function Skin.HideOriginal(rec)
    if rec.bd then
        rec.bd:Hide()
        if rec.bd.over then rec.bd.over:Hide() end
    end
    for _, br in pairs(rec.buttons) do
        br.fill:Hide()
        if br.shine then br.shine:Hide() end
        sliceShown(br.edges, false)
    end
    for _, tr in pairs(rec.tabs) do
        tr.line:Hide()
        if tr.fill then tr.fill:Hide() end
        if tr.rim then sliceShown(tr.rim, false) end
    end
end

--- Marks a skinned tooltip with the item's quality colour (top line or left bar, per look).
function Skin:TopEdge(frame, r, g, b)
    local rec = records[frame]
    if not (rec and rec.active) then return end
    local theme = Overlay:Theme()
    if theme and theme.pack then return theme.pack:Quality(rec, r, g, b) end
    if rec.bd then
        rec.bd.quality:SetColorTexture(r, g, b, 0.9)
        rec.bd.quality:Show()
    end
end

--- Hides the quality mark (a tooltip re-used for a non-item).
function Skin:ClearTopEdge(frame)
    local rec = records[frame]
    if not rec then return end
    if rec.bd then rec.bd.quality:Hide() end
    for _, pack in pairs(ns.Styles and ns.Styles.packs or {}) do pack:ClearQuality(rec) end
end

--- Undoes a skin: Blizzard's art back to its alpha, our pieces hidden.
function Skin:Restore(frame)
    local rec = records[frame]
    if not rec then return end
    for region, alpha in pairs(rec.faded) do
        if not isForbidden(region) and region.SetAlpha then
            pcall(region.SetAlpha, region, alpha)
        end
    end
    rec.faded = {}
    if rec.bd then
        rec.bd:Hide()
        if rec.bd.over then rec.bd.over:Hide() end
    end
    for _, br in pairs(rec.buttons) do
        br.fill:Hide()
        if br.shine then br.shine:Hide() end
        sliceShown(br.edges, false)
    end
    rec.buttons = {}
    for _, tr in pairs(rec.tabs) do
        tr.line:Hide()
        if tr.fill then tr.fill:Hide() end
        if tr.rim then sliceShown(tr.rim, false) end
    end
    rec.tabs = {}
    if ns.Styles then ns.Styles.HideAll(rec) end
    restoreDeep(rec)
    rec.active = false
end

---------------------------------------------------------------------------
-- Lazy application
---------------------------------------------------------------------------
local function wanted(name)
    local e = Skin.registry[name]
    return e and Overlay:ModuleOn(e.group) and not Overlay.settings.disabled[name]
end

--- Skins (or restores) one registered frame now, out of combat.
function Skin:Apply(name)
    local frame = _G[name]
    if not frame or isForbidden(frame) then return false end
    WFC:RunOutOfCombat("overlay:" .. name, function()
        local theme = Overlay:Theme()
        if theme and wanted(name) then
            local e = Skin.registry[name]
            local opts = e.opts
            if e.group == "wfc" and not Overlay.settings.wfcHeaderFonts then
                local copy = {}
                for k, v in pairs(opts) do copy[k] = v end
                copy.keepFonts = true
                opts = copy
            end
            Skin:Window(frame, opts, theme)
        else
            Skin:Restore(frame)
        end
    end)
    return true
end

--- Hooks a registered frame so it is skinned the first time it shows.
function Skin:Watch(name)
    local frame = _G[name]
    if not frame or isForbidden(frame) or hooked[frame] then return end
    hooked[frame] = true
    if frame.HookScript then
        pcall(frame.HookScript, frame, "OnShow", function()
            if not (records[frame] and records[frame].active) and wanted(name) then Skin:Apply(name) end
        end)
    end
    local ok, shown = pcall(function() return frame.IsShown and frame:IsShown() end)
    if ok and shown then Skin:Apply(name) end
end

function Skin:WatchAll()
    for name, e in pairs(self.registry) do
        if not e.addon or _G[name] then self:Watch(name) end
    end
end

--- Re-applies colours/ornaments to everything already skinned or open now, or restores the
--- Blizzard look.
function Skin:RestyleAll()
    for name in pairs(self.registry) do
        local frame = _G[name]
        if frame and not isForbidden(frame) then
            local ok, shown = pcall(function() return frame:IsShown() end)
            if records[frame] or (ok and shown) then self:Apply(name) end
        end
    end
    for frame in pairs(self.attached) do self:ApplyFrame(frame) end
end

---------------------------------------------------------------------------
-- Unnamed frames from other addons (Bagnon's bags): skinned on show like registered ones.
---------------------------------------------------------------------------
Skin.attached = setmetatable({}, { __mode = "k" }) -- [frame] = { group, opts }

function Skin:ApplyFrame(frame)
    local e = self.attached[frame]
    if not e or isForbidden(frame) then return end
    WFC:RunOutOfCombat(e, function()
        local theme = Overlay:Theme()
        if theme and Overlay:ModuleOn(e.group) then
            Skin:Window(frame, e.opts, theme)
        else
            Skin:Restore(frame)
        end
    end)
end

function Skin:Attach(frame, group, opts)
    if not frame or isForbidden(frame) then return end
    if not self.attached[frame] then
        self.attached[frame] = { group = group, opts = opts or {} }
        if frame.HookScript and not hooked[frame] then
            hooked[frame] = true
            pcall(frame.HookScript, frame, "OnShow", function() Skin:ApplyFrame(frame) end)
        end
    end
    local ok, shown = pcall(function() return frame:IsShown() end)
    if ok and shown then self:ApplyFrame(frame) end
end

-- Selected tab underline follows Blizzard's tab selection (a post-hook: no taint).
local function tabChanged(frame)
    local rec = records[frame]
    if rec and rec.active then
        local theme = Overlay:Theme()
        if theme then tabs(rec, frame, theme) end
    end
end

function Skin:HookTabs()
    if self.tabsHooked or not hooksecurefunc then return end
    self.tabsHooked = true
    if PanelTemplates_SetTab then hooksecurefunc("PanelTemplates_SetTab", tabChanged) end
end

-- Shared helpers for the other files (theme picker, chrome).
Skin.util = { fade = fade, isForbidden = isForbidden, slice = slice, gradient = gradient, MEDIA = MEDIA }

--- The skin record of a frame (theme picker previews read it).
function Skin:Record(frame) return records[frame] end

WFC:RegisterEvent("ADDON_LOADED", function(_, addon)
    local names = pendingAddon[addon]
    if names then
        for _, name in ipairs(names) do Skin:Watch(name) end
    end
end)
