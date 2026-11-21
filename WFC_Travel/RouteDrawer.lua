local _, ns = ...
local WFC = WFC

-- Draws the current route on the world map (plan.md §5.7, design.md §5.2, CoreRules R10):
-- pooled line textures on a click-through layer over the map canvas, constant on-screen
-- width, solid for walking and dashed for flights / boats / zeppelins / tram, plus the
-- target pin. One throttled OnUpdate driver, active only while the map is shown; it
-- redraws when the map, zoom or route changes.

local Travel = ns.Travel
local Compat = WFC.Compat
local P = WFC.Colors.palette

local Drawer = {}
ns.Drawer = Drawer

local THICKNESS, OUTLINE = 3, 2 -- screen pixels
local ALPHA = 0.85
local MAX_DASHES = 400

local function rgb(hex)
    local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
    return { r = r / 255, g = g / 255, b = b / 255, code = "|cff" .. hex }
end
Drawer.rgb = rgb

local BLUE, VIOLET = rgb("3d7dff"), rgb("a070ff")
local STYLE = {
    walk     = { color = P.TEXT },
    flight   = { color = P.NEW, dash = 8, gap = 6 },
    boat     = { color = BLUE, dash = 12, gap = 6 },
    zeppelin = { color = BLUE, dash = 12, gap = 6 },
    portal   = { color = BLUE, dash = 12, gap = 6 },
    tram     = { color = VIOLET, dash = 4, gap = 4 },
}
Drawer.STYLE = STYLE

local layer, canvas
local lines, used = {}, 0
local drawSafety -- defined below, after the projection helpers
local pin
local state = {}
Drawer.stats = { segments = 0, dashed = 0 }

local function scrollContainer()
    return WorldMapFrame and WorldMapFrame.ScrollContainer
end

local function line()
    used = used + 1
    local l = lines[used]
    if not l then
        l = layer:CreateLine(nil, "OVERLAY")
        lines[used] = l
    end
    l:Show()
    return l
end

local function canvasPoint(mx, my, w, h)
    return mx * w, -my * h
end

--- One straight piece in canvas units, outlined (dark under, colour on top).
local function piece(x1, y1, x2, y2, color, scale)
    local under = line()
    under:SetColorTexture(0, 0, 0, 0.6)
    under:SetThickness((THICKNESS + OUTLINE) / scale)
    under:SetStartPoint("TOPLEFT", canvas, x1, y1)
    under:SetEndPoint("TOPLEFT", canvas, x2, y2)
    local top = line()
    top:SetColorTexture(color.r, color.g, color.b, ALPHA)
    top:SetThickness(THICKNESS / scale)
    top:SetStartPoint("TOPLEFT", canvas, x1, y1)
    top:SetEndPoint("TOPLEFT", canvas, x2, y2)
end

local function segment(a, b, style, scale)
    Drawer.stats.segments = Drawer.stats.segments + 1
    if not style.dash then
        piece(a[1], a[2], b[1], b[2], style.color, scale)
        return
    end
    -- Dash lengths are in screen pixels so the pattern stays the same at any zoom.
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= 0 then return end
    local step = (style.dash + style.gap) / scale
    local n = math.min(MAX_DASHES, math.ceil(length / step))
    local dash = math.min(style.dash / scale, length)
    for i = 0, n - 1 do
        local s = i * step
        local e = math.min(s + dash, length)
        if e > s then
            piece(a[1] + dx * s / length, a[2] + dy * s / length, a[1] + dx * e / length, a[2] + dy * e / length, style.color, scale)
            Drawer.stats.dashed = Drawer.stats.dashed + 1
        end
    end
end

--- Map position of a route point on the displayed map, or nil when it can't be shown there.
local function project(p, mapId)
    if not p then return nil end
    if p.map == mapId and p.mx then return p.mx, p.my end
    if type(p.c) ~= "number" then return nil end -- island frame: only on its own map
    return Compat.WorldToMap(p.c, p.x, p.y, mapId)
end

local function toCanvas(p, mapId, w, h)
    local x, y = project(p, mapId)
    if x then return { canvasPoint(x, y, w, h) } end
end

-- Walking coloured by danger (Safe: green/yellow/orange/red per stretch), or white with
-- red ticks across the risky stretches (Deathrun). design §5.2.
local DANGER = { grey = P.EASY, green = P.EASY, yellow = P.FAIR, orange = P.DIFFICULT, red = P.IMPOSSIBLE }
local RISKY = { orange = true, red = true }
local TICK = 7 -- screen pixels, each side of the line
Drawer.stats.ticks = 0

local function tick(a, b, scale)
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local len = math.sqrt(dx * dx + dy * dy)
    if len == 0 then return end
    local mx, my = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2
    local nx, ny = -dy / len * TICK / scale, dx / len * TICK / scale
    piece(mx - nx, my - ny, mx + nx, my + ny, P.IMPOSSIBLE, scale)
    Drawer.stats.ticks = Drawer.stats.ticks + 1
end

function drawSafety(leg, mapId, w, h, scale, deathrun)
    for _, part in ipairs(leg.safety) do
        local samples, cats = part.result.samples, part.result.categories
        local first = 1
        for i = 2, #samples do
            if i == #samples or cats[i] ~= cats[first] then
                local a, b = toCanvas(samples[first], mapId, w, h), toCanvas(samples[i], mapId, w, h)
                if a and b then
                    local cat = cats[first]
                    segment(a, b, { color = deathrun and P.TEXT or DANGER[cat] or P.TEXT }, scale)
                    if deathrun and RISKY[cat] then tick(a, b, scale) end
                end
                first = i
            end
        end
    end
end

local function clear()
    for i = 1, used do lines[i]:Hide() end
    used = 0
    if pin then pin:Hide() end
    Drawer.stats.segments, Drawer.stats.dashed, Drawer.stats.ticks = 0, 0, 0
end

function Drawer:Redraw()
    if not layer then return end
    clear()
    local route, legIndex = Travel:GetRoute()
    local target = Travel:GetTarget()
    local mapId = WorldMapFrame:GetMapID()
    if not (target and mapId) then return end
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local scale = scrollContainer().GetCanvasScale and scrollContainer():GetCanvasScale() or 1
    if not scale or scale <= 0 then scale = 1 end
    if route then
        local deathrun = Travel:GetMode() == "deathrun"
        for i = legIndex or 1, #route.legs do
            local leg = route.legs[i]
            local style = STYLE[leg.mode]
            if leg.mode == "walk" and leg.safety and #leg.safety > 0 then
                drawSafety(leg, mapId, w, h, scale, deathrun)
            elseif style then -- hearth legs have no line (design §5.2)
                local path = leg.path or { leg.from, leg.to }
                for p = 1, #path - 1 do
                    local a, b = toCanvas(path[p], mapId, w, h), toCanvas(path[p + 1], mapId, w, h)
                    if a and b then segment(a, b, style, scale) end
                end
            end
        end
    end
    local tx, ty = project(target, mapId)
    if tx and pin then
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", canvasPoint(tx, ty, w, h))
        pin:SetSize(18 / scale, 18 / scale)
        pin:Show()
    end
end

--- Throttled driver: redraw only when something visible changed.
local elapsedSince = 0
local function onUpdate(_, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < 0.1 then return end
    elapsedSince = 0
    local sc = scrollContainer()
    local now = {
        map = WorldMapFrame:GetMapID(),
        scale = sc.GetCanvasScale and sc:GetCanvasScale() or 1,
        w = canvas:GetWidth(), h = canvas:GetHeight(), version = Drawer.version,
    }
    for k, v in pairs(now) do
        if state[k] ~= v then
            state = now
            Drawer:Redraw()
            return
        end
    end
end

function Drawer:Init()
    local sc = scrollContainer()
    if layer or not (sc and sc.Child) then return end
    canvas = sc.Child
    layer = CreateFrame("Frame", nil, canvas)
    layer:SetAllPoints(canvas)
    layer:SetFrameLevel((canvas:GetFrameLevel() or 1) + 2) -- above Questie's lines, below its icons
    layer:EnableMouse(false) -- click-through
    -- Target pin: cyan ring with a dot (design §5.1).
    pin = CreateFrame("Frame", nil, layer)
    pin.ring = pin:CreateTexture(nil, "OVERLAY")
    pin.ring:SetAllPoints()
    pin.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    pin.ring:SetVertexColor(P.NEW.r, P.NEW.g, P.NEW.b, 1)
    pin.dot = pin:CreateTexture(nil, "OVERLAY")
    pin.dot:SetPoint("CENTER")
    pin.dot:SetSize(6, 6)
    pin.dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    pin.dot:SetVertexColor(P.NEW.r, P.NEW.g, P.NEW.b, 1)
    pin:Hide()
    -- The driver runs only while the map is open.
    local function start()
        state = {}
        layer:SetScript("OnUpdate", onUpdate)
    end
    WorldMapFrame:HookScript("OnShow", start)
    WorldMapFrame:HookScript("OnHide", function() layer:SetScript("OnUpdate", nil) end)
    if WorldMapFrame:IsShown() then start() end
    Drawer.layer = layer
    Drawer.version = 0
end

local function bump()
    Drawer.version = (Drawer.version or 0) + 1
    if layer and WorldMapFrame:IsShown() then Drawer:Redraw() end
end

WFC:On("WFC_TRAVEL_ROUTE", bump)
WFC:On("WFC_TRAVEL_TARGET", bump)
