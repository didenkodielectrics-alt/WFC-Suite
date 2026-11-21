local _, ns = ...
local WFC = WFC

-- Chrome: the parts of the screen outside windows. Each style pack describes its own in
-- spec.chrome (data, see StyleX.lua):
--   minimap   rings drawn around the minimap (Blizzard's border art faded), optionally turning
--   caps      what stands where the action-bar gryphons were ("hide", or an art sprite + glow)
--   buttons   a border / glow / hover light on every action button (Blizzard's frame art faded)
--   ambience  screen-edge gradients and drifting particles (motes, fireflies, stars, snow)
-- Same rules as Skin.lua: only SetAlpha on Blizzard regions (remembered and restored), our own
-- non-secure frames for everything else, built out of combat. Original / Original+ leave all of
-- it alone.

local Overlay = ns.Overlay
local Styles = ns.Styles
local Slice, SliceColor, SliceShown, Gradient = Styles.Slice, Styles.SliceColor, Styles.SliceShown, Styles.Gradient

local Chrome = {}
ns.Chrome = Chrome

local faded = {} -- [region] = original alpha

local function forbidden(o)
    local ok, f = pcall(function() return o.IsForbidden and o:IsForbidden() end)
    return not ok or f == true
end

local function fade(region)
    if not region or not region.SetAlpha or forbidden(region) then return end
    if faded[region] == nil then
        local ok, a = pcall(region.GetAlpha, region)
        faded[region] = ok and a or 1
    end
    pcall(region.SetAlpha, region, 0)
end

local function restoreFaded()
    for region, a in pairs(faded) do pcall(region.SetAlpha, region, a) end
    wipe(faded)
end

local function path(root, ...)
    local o = root
    for _, k in ipairs({ ... }) do
        if type(o) ~= "table" then return nil end
        o = o[k]
    end
    return o
end

local function color(t, c, mul)
    t:SetVertexColor(c[1], c[2], c[3], (c[4] or 1) * (mul or 1))
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------
local mm

local function minimapArt()
    return {
        _G.MinimapBorder, _G.MinimapBorderTop, _G.MinimapCompassTexture,
        path(_G.MinimapCluster, "BorderTop"), path(_G.Minimap, "Border"), path(_G.MinimapBackdrop, "Border"),
    }
end

local function buildMinimap()
    if mm or not _G.Minimap then return mm end
    local M = _G.Minimap
    mm = { layers = {} }
    -- Children of the minimap itself, so they share its scale (Edit Mode / cluster scaling) and
    -- its visibility; sized from GetWidth() in the minimap's own units.
    local function layer(levelOffset)
        local f = CreateFrame("Frame", nil, M)
        f:SetFrameStrata(M:GetFrameStrata())
        f:SetFrameLevel(math.max(0, M:GetFrameLevel() + levelOffset))
        f:SetPoint("CENTER", M, "CENTER")
        f:SetSize(1, 1)
        if f.EnableMouse then f:EnableMouse(false) end
        f:Hide()
        return f
    end
    mm.back = layer(1)
    mm.front = layer(3)
    -- Housing behind the map (layer field under = true): a lower strata always draws beneath it.
    mm.under = layer(0)
    mm.under:SetFrameStrata("BACKGROUND")
    local acc = 0
    mm.front:SetScript("OnUpdate", function(_, el)
        acc = acc + el
        if acc < 0.033 then return end
        local dt = acc
        acc = 0
        local now = GetTime()
        for _, t in ipairs(mm.layers) do
            if t:IsShown() then
                if t.spin and t.SetRotation then t:SetRotation(now * t.spin) end
                local P = t.pulse
                if P then -- blink / breathe: alpha between P.min and 1 of the layer's own alpha
                    local k = 0.5 + 0.5 * math.sin(now * P.speed + (P.phase or 0))
                    if P.hard then k = k > 0.5 and 1 or 0 end
                    t:SetAlpha(P.min + (1 - P.min) * k)
                end
                if t.scroll then -- rolling static (texture wraps vertically)
                    t.off = ((t.off or 0) + dt * t.scroll) % 1
                    t:SetTexCoord(0, 1, t.off, t.off + 1)
                end
            end
        end
    end)
    return mm
end

local function applyMinimap(C)
    if not _G.Minimap then return end
    local m = buildMinimap()
    for _, t in ipairs(m.layers) do t:Hide() end
    if not C then
        m.back:Hide(); m.front:Hide(); m.under:Hide()
        return
    end
    for _, r in ipairs(minimapArt()) do fade(r) end
    local d = _G.Minimap:GetWidth() or 140
    -- Layer fields: file, scale (of the minimap width), color, blend, and optionally
    -- under/back (draw beneath the map / just around it), x/y (offset in minimap widths),
    -- spin (rad/s), pulse { speed, min, phase, hard }, scroll (texture heights per second).
    for i, L in ipairs(C) do
        local t = m.layers[i]
        if not t then
            t = m.front:CreateTexture(nil, "ARTWORK", nil, math.min(7, i - 6))
            m.layers[i] = t
        end
        t:SetParent(L.under and m.under or L.back and m.back or m.front)
        t:ClearAllPoints()
        t:SetPoint("CENTER", _G.Minimap, "CENTER", (L.x or 0) * d, (L.y or 0) * d)
        if L.scroll then t:SetTexture(L.file, "REPEAT", "REPEAT") else t:SetTexture(L.file) end
        t:SetTexCoord(0, 1, 0, 1)
        t:SetSize(d * L.scale, d * L.scale)
        t:SetBlendMode(L.blend or "BLEND")
        color(t, L.color)
        t:SetAlpha(1)
        t.spin, t.pulse, t.scroll, t.off = L.spin, L.pulse, L.scroll, 0
        if not L.spin and t.SetRotation then t:SetRotation(0) end
        t:Show()
    end
    m.back:Show(); m.front:Show(); m.under:Show()
end

---------------------------------------------------------------------------
-- Action bar end caps (gryphons / wyverns)
---------------------------------------------------------------------------
local caps = {}

-- Found by their art: any texture under the action bars whose atlas or file names a gryphon,
-- wyvern or end cap (the frame names differ per client). Left/right by where it sits.
local function isCapArt(r)
    local okA, atlas = pcall(function() return r.GetAtlas and r:GetAtlas() end)
    local okT, tex = pcall(function() return r.GetTexture and r:GetTexture() end)
    local s = ((okA and type(atlas) == "string" and atlas or "") .. " " .. (okT and type(tex) == "string" and tex or "")):lower()
    return s:find("gryphon") or s:find("wyvern") or s:find("endcap")
end

local function scanCaps(frame, depth, out)
    if not frame or depth > 4 or forbidden(frame) then return end
    local okR, regions = pcall(function() return { frame:GetRegions() } end)
    for _, r in ipairs(okR and regions or {}) do
        local okT, isTex = pcall(function() return r:IsObjectType("Texture") end)
        if okT and isTex and isCapArt(r) then out[#out + 1] = r end
    end
    local okC, children = pcall(function() return { frame:GetChildren() } end)
    for _, c in ipairs(okC and children or {}) do scanCaps(c, depth + 1, out) end
end

local function endCaps()
    local left = _G.MainMenuBarLeftEndCap or path(_G.MainMenuBar, "EndCaps", "LeftEndCap")
        or path(_G.MainActionBar, "EndCaps", "LeftEndCap") or path(_G.MainMenuBarArtFrame, "LeftEndCap")
    local right = _G.MainMenuBarRightEndCap or path(_G.MainMenuBar, "EndCaps", "RightEndCap")
        or path(_G.MainActionBar, "EndCaps", "RightEndCap") or path(_G.MainMenuBarArtFrame, "RightEndCap")
    if left and right then return left, right end
    local found = {}
    for _, root in ipairs({ _G.MainActionBar, _G.MainMenuBar, _G.MainMenuBarArtFrame, _G.MultiBarBottomLeft }) do
        scanCaps(root, 1, found)
    end
    local mid = (UIParent:GetWidth() or 0) / 2
    for _, r in ipairs(found) do
        local okC, x = pcall(function() return (r:GetCenter()) end)
        if okC and type(x) == "number" then
            if x < mid then left = left or r else right = right or r end
        end
    end
    Chrome.found = found
    return left, right
end

local function applyCaps(C)
    local left, right = endCaps()
    for i, cap in ipairs({ left, right }) do
        if cap then
            if C then fade(cap) end
            local f = caps[i]
            if C and C ~= "hide" then
                if not f then
                    f = CreateFrame("Frame", nil, UIParent)
                    f:SetFrameStrata("MEDIUM")
                    if f.EnableMouse then f:EnableMouse(false) end
                    f.glow = f:CreateTexture(nil, "BACKGROUND")
                    f.tex = f:CreateTexture(nil, "ARTWORK")
                    f.tex:SetAllPoints()
                    caps[i] = f
                end
                local h = math.max(64, (cap.GetHeight and cap:GetHeight() or 100) * (C.scale or 1.15))
                f:SetSize(h * (C.ratio or 0.5), h)
                f:ClearAllPoints()
                f:SetPoint("BOTTOM", cap, "BOTTOM", 0, C.y or 2)
                f.tex:SetTexture(C.file)
                f.tex:SetBlendMode(C.blend or "ADD")
                -- mirror the right one when the art isn't symmetric
                if i == 2 and C.mirror then f.tex:SetTexCoord(1, 0, 0, 1) else f.tex:SetTexCoord(0, 1, 0, 1) end
                color(f.tex, C.color)
                if C.glow then
                    f.glow:SetTexture(C.glow.file)
                    f.glow:SetBlendMode("ADD")
                    f.glow:SetSize(h * C.glow.size, h * C.glow.size)
                    f.glow:ClearAllPoints()
                    f.glow:SetPoint("CENTER", f, "TOP", 0, -h * C.glow.y)
                    color(f.glow, C.glow.color)
                    f.glow:Show()
                else
                    f.glow:Hide()
                end
                local ok, shown = pcall(function() return cap:IsVisible() end)
                f:SetShown(ok and shown and true or false)
            elseif f then
                f:Hide()
            end
        end
    end
end

---------------------------------------------------------------------------
-- Action buttons
---------------------------------------------------------------------------
local BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button", "PetActionButton",
    "StanceButton", "PossessButton", "OverrideActionBarButton" }
local skins = {} -- [button] = our overlay
local buttonSpec

local function eachButton(fn)
    for _, prefix in ipairs(BARS) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            if b and not forbidden(b) then fn(b) end
        end
    end
end

-- Blizzard's frame art on a button (the icon, cooldown, count, hotkey and highlights stay).
local function buttonArt(b)
    local name = b.GetName and b:GetName()
    local nt = b.GetNormalTexture and select(2, pcall(b.GetNormalTexture, b))
    return { type(nt) == "table" and nt or nil, b.NormalTexture, b.SlotArt,
        name and _G[name .. "NormalTexture"], name and _G[name .. "NormalTexture2"], b.FloatingBG }
end

local function paintButton(o, hover)
    local B = buttonSpec
    if not (o and B) then return end
    SliceColor(o.edge, hover and B.hoverEdge or B.edge.color)
    if o.glow then SliceColor(o.glow, B.glow.color, hover and 1.8 or 1) end
end

local function skinButton(b)
    local B = buttonSpec
    for _, r in ipairs(buttonArt(b)) do fade(r) end
    local o = skins[b]
    if not o then
        o = CreateFrame("Frame", nil, b)
        o:SetAllPoints(b)
        o:SetFrameLevel(b:GetFrameLevel() + 4)
        if o.EnableMouse then o:EnableMouse(false) end
        skins[b] = o
        if b.HookScript then
            pcall(b.HookScript, b, "OnEnter", function() if o:IsShown() then paintButton(o, true) end end)
            pcall(b.HookScript, b, "OnLeave", function() if o:IsShown() then paintButton(o, false) end end)
        end
    end
    if o.style ~= B then
        -- rebuilt per style (different art and sizes)
        if o.edge then SliceShown(o.edge, false) end
        if o.glow then SliceShown(o.glow, false) end
        if o.inner then SliceShown(o.inner, false) end
        o.glow = B.glow and Slice(o, "BACKGROUND", 0, B.glow.file, B.glow.k, B.glow.size, B.glow.out, false, B.glow.blend or "ADD") or nil
        o.edge = Slice(o, "OVERLAY", 0, B.edge.file, B.edge.k, B.edge.size, B.edge.out or 0, false, B.edge.blend)
        o.inner = B.inner and Slice(o, "OVERLAY", -1, B.inner.file, B.inner.k, B.inner.size, B.inner.out or 0, false, B.inner.blend) or nil
        if o.inner then SliceColor(o.inner, B.inner.color) end
        o.style = B
    end
    SliceShown(o.edge, true)
    if o.glow then SliceShown(o.glow, true) end
    if o.inner then SliceShown(o.inner, true) end
    paintButton(o, false)
    o:Show()
end

local function applyButtons(B)
    buttonSpec = B
    if not B then
        for _, o in pairs(skins) do o:Hide() end
        return
    end
    eachButton(skinButton)
end

-- Blizzard re-sets button art when slots change or the grid shows: fade it again (SetAlpha on
-- textures is allowed in combat; our overlays already exist).
local function refade()
    if not buttonSpec then return end
    eachButton(function(b)
        if skins[b] then for _, r in ipairs(buttonArt(b)) do fade(r) end end
    end)
end
for _, e in ipairs({ "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_SHOWGRID", "ACTIONBAR_HIDEGRID", "UPDATE_BINDINGS",
    "ACTIONBAR_PAGE_CHANGED", "UPDATE_SHAPESHIFT_FORMS", "PET_BAR_UPDATE" }) do
    WFC:RegisterEvent(e, function() C_Timer.After(0, refade) end)
end

---------------------------------------------------------------------------
-- Ambience
---------------------------------------------------------------------------
local amb
local MAX_MOTES = 40

local function buildAmbience()
    if amb then return amb end
    amb = CreateFrame("Frame", "WFC_OverlayAmbience", UIParent)
    amb:SetFrameStrata("BACKGROUND")
    amb:SetFrameLevel(0)
    amb:SetAllPoints(UIParent)
    if amb.EnableMouse then amb:EnableMouse(false) end
    amb.edges = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = amb:CreateTexture(nil, "BACKGROUND")
        if i <= 2 then t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
        else t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side) end
        amb.edges[side] = t
    end
    amb.motes = {}
    for i = 1, MAX_MOTES do
        local t = amb:CreateTexture(nil, "ARTWORK")
        t:SetBlendMode("ADD")
        t.life = 0
        t:Hide()
        amb.motes[i] = t
    end
    local acc = 0
    amb:SetScript("OnUpdate", function(self, el)
        acc = acc + el
        if acc < 0.033 then return end
        local dt = acc
        acc = 0
        local P = self.motes.spec
        if not P then return end
        local W, H = self:GetWidth(), self:GetHeight()
        local now = GetTime()
        for i = 1, P.count do
            local m = self.motes[i]
            if m.life <= 0 then
                m.max = P.life[1] + math.random() * (P.life[2] - P.life[1])
                m.life = m.max * (m.fresh and 1 or math.random())
                m.fresh = true
                m.x = math.random() * W
                m.vy = P.vy[1] + math.random() * (P.vy[2] - P.vy[1])
                -- rising motes start low, falling ones high, still ones anywhere
                if m.vy > 1 then m.y = math.random() * H * 0.7
                elseif m.vy < -1 then m.y = H * (0.45 + math.random() * 0.6)
                else m.y = H * (0.35 + math.random() * 0.65) end
                m.phase = math.random() * 6.28
                local s = P.size[1] + math.random() * (P.size[2] - P.size[1])
                m:SetSize(s, s)
            end
            m.life = m.life - dt
            m.y = m.y + m.vy * dt
            local k = 1 - m.life / m.max
            local a = math.sin(math.pi * k) * P.alpha
            if P.twinkle then a = a * (0.55 + 0.45 * math.sin(now * P.twinkle + m.phase)) end
            m:ClearAllPoints()
            m:SetPoint("CENTER", self, "BOTTOMLEFT", m.x + math.sin(now * 0.6 + m.phase) * P.sway, m.y)
            m:SetVertexColor(P.color[1], P.color[2], P.color[3], math.max(0, a))
        end
    end)
    return amb
end

local function applyAmbience(A)
    if not A or Overlay.settings.ambience == false then
        if amb then amb:Hide() end
        return
    end
    local a = buildAmbience()
    local H, W = UIParent:GetHeight(), UIParent:GetWidth()
    for side, t in pairs(a.edges) do
        local E = A.edges and A.edges[side]
        if E then
            if side == "TOP" or side == "BOTTOM" then t:SetHeight(H * E[1]) else t:SetWidth(W * E[1]) end
            Gradient(t, (side == "TOP" or side == "BOTTOM") and "VERTICAL" or "HORIZONTAL", E[2], E[3])
            t:Show()
        else
            t:Hide()
        end
    end
    local P = A.motes
    a.motes.spec = P
    for i, m in ipairs(a.motes) do
        if P and i <= P.count then
            m:SetTexture(P.file)
            m.life, m.fresh = 0, false
            m:Show()
        else
            m:Hide()
        end
    end
    a:Show()
end

---------------------------------------------------------------------------
--- /wfcui debug chrome: what was found on this client.
function Chrome:Debug()
    local left, right = endCaps()
    local function desc(r)
        if not r then return "none" end
        local okA, atlas = pcall(function() return r:GetAtlas() end)
        local okN, name = pcall(function() return r:GetDebugName() end)
        return tostring(okN and name or "?") .. (okA and atlas and (" [" .. atlas .. "]") or "")
    end
    local nb = 0
    eachButton(function() nb = nb + 1 end)
    WFC:Print("Chrome · style", Overlay:Style(), "· module", Overlay:ModuleOn("chrome") and "on" or "off")
    WFC:Print("  end caps:", desc(left), "|", desc(right), "· art matches:", #(Chrome.found or {}))
    local n = 0
    for _, r in ipairs(minimapArt()) do if r then n = n + 1 end end
    WFC:Print("  minimap border pieces:", n, "· action buttons:", nb)
    WFC:Print("  music:", Chrome.MusicPlaying and Chrome.MusicPlaying() or "none", "· setting", Overlay.settings.music ~= false and "on" or "off")
end

---------------------------------------------------------------------------
-- Music: a shuffled playlist for packs that name one (spec.music = { file, name }). The songs
-- are the player's own copies in the same folder as `file` (Media\Music): `file` itself
-- (toska.mp3) plus track1 ... track20 (.mp3 or .ogg). WoW can't list a folder, so those are the
-- names it tries; missing ones are skipped instantly. New files need a full WoW restart.
--   * Each song plays on the Music channel (the music volume slider applies); when it ends the
--     next one starts. The order is reshuffled every round, never the same song twice in a row.
--   * While the playlist runs, a silent loop (Media\Music\silence.mp3) holds the zone-music
--     slot so Blizzard's music doesn't play underneath; StopMusic hands it back afterwards.
-- Setting "music" (/wfcui music on|off|next). Needs the game's Music sound channel on.
---------------------------------------------------------------------------
local MUSIC_EXT = { ".mp3", ".ogg" }
local MUSIC_TRACKS = 20
local FALLBACK_SECONDS = 240 -- clients without C_Sound.IsPlaying: move on after this long
local music = { key = nil, list = {}, order = {}, pos = 0, missing = {}, found = {}, history = {}, hpos = 0 }

local function musicCandidates(M)
    local list, seen = {}, {}
    local function add(f) if f and not seen[f] then seen[f] = true; list[#list + 1] = f end end
    add(M.file)
    local dir = M.dir or (M.file and M.file:match("^(.*\\)")) or ""
    for i = 1, M.count or MUSIC_TRACKS do
        for _, ext in ipairs(MUSIC_EXT) do add(dir .. "track" .. i .. ext) end
    end
    return list, dir
end

local function shortName(f) return f and (f:match("([^\\]+)$") or f) end

local function changed() WFC:Fire("WFC_MUSIC_CHANGED") end

-- The song handle is saved (SavedVariables): a sound started with PlaySoundFile keeps playing
-- through /reload, so the next UI session must stop it before starting its own.
local function saveHandle(h)
    if Overlay.settings then Overlay.settings.musicHandle = h end
end

local function stopTrack(fade)
    if music.handle then
        if StopSound then pcall(StopSound, music.handle, fade or 0) end
        saveHandle(nil) -- only our own song: a leftover from before /reload stays remembered
    end
    music.handle, music.track = nil, nil
end

--- Stops a song left playing by the previous UI session (before /reload).
local function stopLeftover()
    local h = Overlay.settings and Overlay.settings.musicHandle
    if h and StopSound then pcall(StopSound, h, 0) end
    saveHandle(nil)
end

-- Loading screens (hearth, portals, instances): the game can briefly report the song as
-- stopped. Don't advance until a few seconds after the world is back.
local loadingUntil = 0
local function loadingScreen() loadingUntil = GetTime() + 1e9 end
local function worldBack() loadingUntil = GetTime() + 4 end

local function reshuffle()
    local order = {}
    for _, f in ipairs(music.list) do if not music.missing[f] then order[#order + 1] = f end end
    for i = #order, 2, -1 do
        local j = math.random(i)
        order[i], order[j] = order[j], order[i]
    end
    -- never the same song twice in a row across rounds
    if #order > 1 and order[1] == music.last then order[1], order[2] = order[2], order[1] end
    music.order, music.pos = order, 0
end

local function playFile(file)
    local ok, willPlay, handle = pcall(PlaySoundFile, file, "Music")
    if ok and willPlay then
        music.handle, music.track, music.last, music.started = handle, file, file, GetTime()
        music.found[file] = true
        saveHandle(handle)
        return true
    end
    music.missing[file] = true
    return false
end

--- Starts the next song: forward through the history first (after going back), then a new
--- shuffled pick. false when the folder has no songs.
local function nextTrack()
    stopTrack()
    music.paused = false
    local H = music.history
    while music.hpos < #H do
        music.hpos = music.hpos + 1
        if playFile(H[music.hpos]) then changed() return true end
    end
    for _ = 1, #music.list + 1 do
        if music.pos >= #music.order then
            reshuffle()
            if #music.order == 0 then return false end
        end
        music.pos = music.pos + 1
        local file = music.order[music.pos]
        if playFile(file) then
            H[#H + 1] = file
            if #H > 50 then table.remove(H, 1) end
            music.hpos = #H
            changed()
            return true
        end
    end
    return false
end

--- Back to the song before (restarts the current one when there's no earlier song).
local function prevTrack()
    stopTrack()
    music.paused = false
    if music.hpos > 1 then music.hpos = music.hpos - 1 end
    local f = music.history[music.hpos]
    local ok = f ~= nil and playFile(f)
    changed()
    return ok
end

--- Pause stops the song (WoW can't resume a sound midway); play starts it again from the top.
--- The zone music stays quiet while paused.
local function pauseToggle()
    if music.paused then
        music.paused = false
        local f = music.history[music.hpos]
        if not (f and playFile(f)) then return nextTrack() end
        changed()
        return true
    end
    stopTrack(300)
    music.paused = true
    changed()
    return true
end

local musicFrame
local function stopMusic()
    stopTrack(1500)
    if music.silenced and StopMusic then pcall(StopMusic) end
    music.silenced, music.key, music.paused = false, nil, false
    if musicFrame then musicFrame:Hide() end
    changed()
end

local function startMusic(M)
    stopLeftover() -- a song still playing from before /reload
    music.list, music.dir = musicCandidates(M)
    music.missing, music.found, music.order, music.pos, music.last = {}, {}, {}, 0, nil
    music.history, music.hpos, music.paused = {}, 0, false
    music.name = M.name
    if not (PlaySoundFile and nextTrack()) then return false end
    -- hold the zone-music slot with silence while the playlist plays
    if PlayMusic and pcall(PlayMusic, music.dir .. "silence.mp3") then music.silenced = true end
    if not musicFrame then
        musicFrame = CreateFrame("Frame")
        local acc = 0
        musicFrame:SetScript("OnUpdate", function(_, el)
            acc = acc + el
            if acc < 1 then return end
            acc = 0
            if not music.key or music.paused or GetTime() < loadingUntil then return end
            local ended
            if music.handle and C_Sound and C_Sound.IsPlaying then
                local ok, isPlaying = pcall(C_Sound.IsPlaying, music.handle)
                -- two checks in a row: a single "not playing" can be a hiccup
                if ok and not isPlaying then
                    music.misses = (music.misses or 0) + 1
                else
                    music.misses = 0
                end
                ended = music.misses >= 2
            else
                ended = GetTime() - (music.started or 0) > FALLBACK_SECONDS
            end
            if ended then
                music.misses = 0
                if not nextTrack() then stopMusic() end
            end
        end)
    end
    musicFrame:Show()
    return true
end

local function applyMusic(theme)
    local M = theme and theme.pack and theme.pack.spec.music
    local key = M and Overlay.settings.music ~= false and (theme.pack.id .. ":" .. tostring(M.file)) or nil
    if key == music.key and (key == nil or music.track or music.paused) then return end
    stopMusic()
    if key and startMusic(M) then
        music.key = key
        changed()
    end
end

--- Skip to another song (/wfcui music next, the music bar).
function Chrome:MusicNext()
    if not music.key then return false end
    if not nextTrack() then stopMusic() return false end
    return true
end

--- Back to the previous song (/wfcui music prev, the music bar).
function Chrome:MusicPrev()
    if not music.key then return false end
    return prevTrack()
end

--- Pause / play (/wfcui music pause, the music bar).
function Chrome:MusicPause()
    if not music.key then return false end
    return pauseToggle()
end

--- Current song (file name, also while paused), songs found so far, names missing, active, paused.
function Chrome:MusicStatus()
    local found, missing = 0, 0
    for _ in pairs(music.found) do found = found + 1 end
    for _ in pairs(music.missing) do missing = missing + 1 end
    local current = music.track or (music.history and music.history[music.hpos or 0])
    return shortName(current), found, missing, music.key ~= nil, music.paused == true
end
Chrome.MusicPlaying = function() return shortName(music.track) end

function Chrome:Apply()
    local theme = Overlay:Theme()
    local C = theme and theme.pack and Overlay:ModuleOn("chrome") and theme.pack.spec.chrome or nil
    applyMusic(theme)
    applyAmbience(C and C.ambience)
    WFC:RunOutOfCombat("overlay:chrome", function()
        if not C then
            applyButtons(nil)
            applyMinimap(nil)
            applyCaps(nil)
            restoreFaded()
            return
        end
        restoreFaded() -- the next look fades what it needs
        applyMinimap(C.minimap)
        applyCaps(C.caps)
        applyButtons(C.buttons)
    end)
end

WFC:RegisterEvent("LOADING_SCREEN_ENABLED", loadingScreen)
WFC:RegisterEvent("LOADING_SCREEN_DISABLED", worldBack)
WFC:RegisterEvent("PLAYER_LEAVING_WORLD", loadingScreen)
WFC:RegisterEvent("PLAYER_ENTERING_WORLD", worldBack)

-- The action bar can be rebuilt (Edit Mode, bar settings): re-apply after it settles.
WFC:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if Overlay.started then C_Timer.After(1, function() Chrome:Apply() end) end
end)
