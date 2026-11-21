local _, ns = ...
local WFC = WFC
local Overlay = ns.Overlay

-- Easter Egg: "Glock Fire Blast" (WFC_OverlayRevamp)
-- When enabled in Settings (or via `/wfcui glock`), casting Fire Blast makes your character
-- draw and hold a Glock 19 (scaled to your camera zoom, with outstretched arm/sleeve and
-- fingers gripping the handle & trigger), aimed directly at your target with blowback slide
-- recoil, muzzle flip, ejected spinning 9mm brass casing, a high-velocity bullet with a
-- billowing smoke trail, and a smoky impact explosion on the target!

if ns.Glock then return end
local Glock = {}
ns.Glock = Glock

local FIRE_BLAST_IDS = {
    [2136]  = true, -- Rank 1
    [2137]  = true, -- Rank 2
    [2138]  = true, -- Rank 3
    [8412]  = true, -- Rank 4
    [8413]  = true, -- Rank 5
    [10197] = true, -- Rank 6
    [10199] = true, -- Rank 7
}

local CIRCLE_TEX = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local STAR_TEX   = "Interface\\Cooldown\\star4"
local WHITE_TEX  = "Interface\\Buttons\\WHITE8X8"

-- WoW built-in CASC FileDataIDs (PlaySoundFile requires numeric FileDataIDs in modern clients)
local SOUND_GUNFIRE   = { 567718, 567719, 567720 } -- Sound/Item/Weapons/Gun/GunFire01..03.ogg
local SOUND_SLIDERACK = 567721                     -- Sound/Item/Weapons/Gun/GunLoad01.ogg
local SOUND_SHELLCLINK = 567428                    -- Sound/Interface/LootCoinSmall.ogg (brass clatter)
local SOUND_EXPLOSION = 566982                     -- Sound/Doodad/Hellfire_Raid_FX_Explosion05.ogg

local function playSoundId(fileDataId, fallbackKitId)
    if PlaySoundFile and fileDataId then
        local ok, willPlay = pcall(PlaySoundFile, fileDataId, "Master")
        if ok and willPlay then return end
    end
    if PlaySound and fallbackKitId then
        pcall(PlaySound, fallbackKitId, "Master")
    end
end

-- Use LOW strata so the Glock and effects sit in the world layer behind UI panels/actionbars
local canvas = CreateFrame("Frame", "WFC_GlockCanvas", UIParent)
canvas:SetAllPoints(UIParent)
canvas:SetFrameStrata("LOW")
canvas:SetFrameLevel(20)

local particlePool = {}
local activeParticles = {}
local activeShots = {}

local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if _G.atan2 then return _G.atan2(y, x) end
    if x > 0 then return math.atan(y / x)
    elseif x < 0 and y >= 0 then return math.atan(y / x) + math.pi
    elseif x < 0 and y < 0 then return math.atan(y / x) - math.pi
    elseif x == 0 and y > 0 then return math.pi * 0.5
    elseif x == 0 and y < 0 then return -math.pi * 0.5
    else return 0 end
end

---------------------------------------------------------------------------
-- Particle System (Smoke Trail Puffs, Sparks, Muzzle Flash, Smoke Cloud)
---------------------------------------------------------------------------
local function acquireParticle()
    local p = table.remove(particlePool)
    if not p then
        p = canvas:CreateTexture(nil, "OVERLAY", nil, 5)
    end
    p:Show()
    return p
end

local function releaseParticle(p)
    p:Hide()
    p:ClearAllPoints()
    if p.SetRotation then pcall(p.SetRotation, p, 0) end
    particlePool[#particlePool + 1] = p
end

local function spawnParticle(spec)
    local p = acquireParticle()
    p:SetTexture(spec.tex or CIRCLE_TEX)
    p:SetBlendMode(spec.blend or "BLEND")
    p:SetVertexColor(spec.r or 1, spec.g or 1, spec.b or 1, spec.a or 1)
    p:SetSize(spec.size0 or 12, (spec.size0 or 12) * (spec.aspect or 1))
    if spec.rot0 and p.SetRotation then pcall(p.SetRotation, p, spec.rot0) end
    p:SetPoint("CENTER", UIParent, "BOTTOMLEFT", spec.x, spec.y)

    activeParticles[#activeParticles + 1] = {
        tex = p,
        x = spec.x,
        y = spec.y,
        vx = spec.vx or 0,
        vy = spec.vy or 0,
        gravity = spec.gravity or 0,
        drag = spec.drag or 0,
        floorY = spec.floorY,
        bounces = 0,
        maxBounces = spec.maxBounces or 0,
        onBounce = spec.onBounce,
        size0 = spec.size0 or 12,
        size1 = spec.size1 or spec.size0 or 12,
        r0 = spec.r or 1, g0 = spec.g or 1, b0 = spec.b or 1,
        r1 = spec.r1 or spec.r or 1, g1 = spec.g1 or spec.g or 1, b1 = spec.b1 or spec.b or 1,
        a0 = spec.a or 1,
        a1 = spec.a1 or 0,
        rot = spec.rot0 or 0,
        vrot = spec.vrot or 0,
        aspect = spec.aspect or 1,
        age = 0,
        life = spec.life or 0.4,
    }
end

---------------------------------------------------------------------------
-- Rotatable Multi-Part Glock 19 + Character Arm & Gripping Hand
---------------------------------------------------------------------------
-- Every part is defined in local coordinates (cx, cy) relative to the character's
-- hand grip pivot (0, 0), facing right (+X) with +Y up. On each frame we rotate
-- and scale all parts around the character's hand so the character aims directly
-- at the target and the gun kicks upward with recoil!
local gunRig

local function addPart(parts, layer, sublevel, w, h, cx, cy, r, g, b, a, group)
    local t = canvas:CreateTexture(nil, layer, nil, sublevel or 0)
    t:SetTexture(WHITE_TEX)
    t:SetVertexColor(r, g, b, a or 1)
    t:Hide()
    local part = {
        tex = t,
        w = w, h = h,
        cx = cx, cy = cy,
        r = r, g = g, b = b, a = a or 1,
        group = group or "frame", -- "frame", "slide", "trigger", "hand"
    }
    parts[#parts + 1] = part
    return part
end

local function ensureGunRig()
    if gunRig then return gunRig end

    local parts = {}

    -- Arm / Sleeve segments (stretched dynamically between shoulder and wrist)
    local armShadow = canvas:CreateTexture(nil, "ARTWORK", nil, -2)
    armShadow:SetTexture(WHITE_TEX)
    armShadow:SetVertexColor(0.06, 0.07, 0.10, 0.95)
    armShadow:Hide()

    local armMain = canvas:CreateTexture(nil, "ARTWORK", nil, -1)
    armMain:SetTexture(WHITE_TEX)
    armMain:SetVertexColor(0.16, 0.22, 0.36, 1.0) -- caster robe sleeve
    armMain:Hide()

    local armCuff = canvas:CreateTexture(nil, "ARTWORK", nil, 0)
    armCuff:SetTexture(WHITE_TEX)
    armCuff:SetVertexColor(0.82, 0.66, 0.24, 1.0) -- gold caster cuff trim
    armCuff:Hide()

    -- 1. Back of palm / wrist behind grip
    addPart(parts, "ARTWORK", 0, 10, 12, -5, -2, 0.88, 0.70, 0.56, 1, "hand") -- wrist/palm skin

    -- 2. Glock 19 Polymer Grip & Frame (origin 0,0 is center of grip)
    addPart(parts, "ARTWORK", 1, 13, 8,  -4, -14, 0.09, 0.10, 0.12, 1, "frame") -- flared mag baseplate
    addPart(parts, "ARTWORK", 1, 11, 10, -2, -8,  0.12, 0.13, 0.16, 1, "frame") -- lower grip
    addPart(parts, "ARTWORK", 1, 11, 10,  0, -1,  0.12, 0.13, 0.16, 1, "frame") -- mid grip
    addPart(parts, "ARTWORK", 1, 12, 9,   2,  5,  0.12, 0.13, 0.16, 1, "frame") -- upper grip & beavertail
    addPart(parts, "ARTWORK", 2, 6,  14, -1, -4,  0.07, 0.08, 0.09, 1, "frame") -- grip stippling panel

    -- 3. Polymer Receiver / Dust Cover / Picatinny Rail
    addPart(parts, "ARTWORK", 2, 40, 6,  18,  9,  0.13, 0.15, 0.18, 1, "frame") -- receiver body
    addPart(parts, "ARTWORK", 3, 12, 2,  30,  7,  0.07, 0.08, 0.10, 1, "frame") -- under-barrel rail slot

    -- 4. Trigger Guard & Moving Trigger
    addPart(parts, "ARTWORK", 2, 14, 2,  13,  0,  0.11, 0.12, 0.14, 1, "frame") -- bottom of trigger guard
    addPart(parts, "ARTWORK", 2, 2,  8,  19,  3,  0.11, 0.12, 0.14, 1, "frame") -- front of trigger guard
    addPart(parts, "ARTWORK", 2, 3,  6,  11,  4,  0.06, 0.06, 0.07, 1, "trigger") -- trigger shoe

    -- 5. Character's Fingers & Thumb Wrapped Around the Grip & Trigger!
    addPart(parts, "ARTWORK", 4, 9,  4,   2,  6,  0.90, 0.72, 0.58, 1, "hand")    -- thumb along frame
    addPart(parts, "ARTWORK", 4, 8,  3.5, 9,  4,  0.92, 0.74, 0.60, 1, "trigger") -- index finger on trigger!
    addPart(parts, "ARTWORK", 4, 8,  3.8, 3, -3,  0.90, 0.72, 0.58, 1, "hand")    -- middle finger wrapped on grip
    addPart(parts, "ARTWORK", 4, 7.5,3.6, 1, -7,  0.86, 0.68, 0.54, 1, "hand")    -- ring finger wrapped on grip
    addPart(parts, "ARTWORK", 4, 6.5,3.2,-1, -11, 0.82, 0.64, 0.50, 1, "hand")    -- pinky finger on lower grip

    -- 6. Inner Steel Barrel & Guide Rod (revealed when the slide kicks back!)
    addPart(parts, "ARTWORK", 2, 44, 5,  19, 15,  0.26, 0.28, 0.32, 1, "frame")   -- inner barrel
    addPart(parts, "ARTWORK", 2, 38, 2.5,18, 12,  0.18, 0.20, 0.22, 1, "frame")   -- recoil spring guide rod

    -- 7. Recoiling Matte-Steel Slide (kicks backward along -X when fired!)
    addPart(parts, "OVERLAY", 1, 45, 10, 16, 15,  0.20, 0.22, 0.26, 1, "slide")   -- main slide body
    addPart(parts, "OVERLAY", 2, 45, 2.5,16, 19,  0.35, 0.38, 0.44, 1, "slide")   -- top metallic bevel highlight
    addPart(parts, "OVERLAY", 2, 11, 5,  17, 16,  0.08, 0.09, 0.11, 1, "slide")   -- 9mm ejection port cutout

    -- Rear Glock slide serrations
    for i = 0, 4 do
        addPart(parts, "OVERLAY", 3, 1.4, 6.5, -2 + i * 2.5, 14.5, 0.10, 0.11, 0.13, 1, "slide")
    end

    -- White Glock iron sights (rear U-notch + front white dot)
    addPart(parts, "OVERLAY", 3, 3.5, 2.5, -4, 21, 0.94, 0.96, 1.00, 1, "slide")
    addPart(parts, "OVERLAY", 3, 2.8, 2.5, 36, 21, 0.96, 0.96, 1.00, 1, "slide")

    gunRig = {
        parts = parts,
        armShadow = armShadow,
        armMain = armMain,
        armCuff = armCuff,
    }
    return gunRig
end

local function hideGunRig()
    if not gunRig then return end
    gunRig.armShadow:Hide()
    gunRig.armMain:Hide()
    gunRig.armCuff:Hide()
    for i = 1, #gunRig.parts do
        gunRig.parts[i].tex:Hide()
    end
end

-- Positions and rotates the character's outstretched arm, gripping hand, and Glock 19
local function renderGunRig(shoulderX, shoulderY, handX, handY, aimAngle, scale, dirY, slideKick, triggerPull, alpha)
    local rig = ensureGunRig()
    local cosA = math.cos(aimAngle)
    local sinA = math.sin(aimAngle)

    -- 1. Render outstretched arm / sleeve from character's shoulder to the hand grip
    local armDx = handX - shoulderX
    local armDy = handY - shoulderY
    local armLen = math.max(8, math.sqrt(armDx * armDx + armDy * armDy))
    local armAngle = atan2(armDy, armDx)
    local armMidX = (shoulderX + handX) * 0.5
    local armMidY = (shoulderY + handY) * 0.5
    local sleeveThick = 13 * scale

    -- Classic dark caster robe sleeve
    local sr, sg, sb = 0.18, 0.22, 0.34
    local theme = Overlay and Overlay:Theme()
    if theme and type(theme.accent) == "table" and type(theme.accent[1]) == "number" then
        sr = 0.12 + theme.accent[1] * 0.22
        sg = 0.14 + theme.accent[2] * 0.22
        sb = 0.18 + theme.accent[3] * 0.22
    end

    rig.armShadow:SetSize(armLen + 4 * scale, sleeveThick + 3 * scale)
    rig.armShadow:ClearAllPoints()
    rig.armShadow:SetPoint("CENTER", UIParent, "BOTTOMLEFT", armMidX, armMidY)
    rig.armShadow:SetVertexColor(0.05, 0.06, 0.08, 0.90 * alpha)
    if rig.armShadow.SetRotation then pcall(rig.armShadow.SetRotation, rig.armShadow, armAngle) end
    rig.armShadow:Show()

    rig.armMain:SetSize(armLen, sleeveThick)
    rig.armMain:ClearAllPoints()
    rig.armMain:SetPoint("CENTER", UIParent, "BOTTOMLEFT", armMidX, armMidY)
    rig.armMain:SetVertexColor(sr, sg, sb, alpha)
    if rig.armMain.SetRotation then pcall(rig.armMain.SetRotation, rig.armMain, armAngle) end
    rig.armMain:Show()

    -- Gold cuff at the wrist end of the sleeve
    local cuffX = handX - math.cos(armAngle) * (5 * scale)
    local cuffY = handY - math.sin(armAngle) * (5 * scale)
    rig.armCuff:SetSize(4.5 * scale, sleeveThick + 1.5 * scale)
    rig.armCuff:ClearAllPoints()
    rig.armCuff:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cuffX, cuffY)
    rig.armCuff:SetVertexColor(0.85, 0.68, 0.24, alpha)
    if rig.armCuff.SetRotation then pcall(rig.armCuff.SetRotation, rig.armCuff, armAngle) end
    rig.armCuff:Show()

    -- 2. Render each rotated part of the Glock & gripping hand
    for i = 1, #rig.parts do
        local p = rig.parts[i]
        local lx = p.cx
        local ly = p.cy

        if p.group == "slide" then
            lx = lx - slideKick
        elseif p.group == "trigger" then
            lx = lx - triggerPull
        end

        -- Mirror vertically when aiming to the left so the gun is right-side up
        ly = ly * dirY

        local wx = handX + (lx * cosA - ly * sinA) * scale
        local wy = handY + (lx * sinA + ly * cosA) * scale

        local t = p.tex
        t:SetSize(p.w * scale, p.h * scale)
        t:ClearAllPoints()
        t:SetPoint("CENTER", UIParent, "BOTTOMLEFT", wx, wy)
        t:SetVertexColor(p.r, p.g, p.b, p.a * alpha)
        if t.SetRotation then pcall(t.SetRotation, t, aimAngle) end
        t:Show()
    end
end

---------------------------------------------------------------------------
-- Character Hand Anchor (Zoom-Aware) & Target Screen Position
---------------------------------------------------------------------------
local function getTargetScreenPos()
    local uiW, uiH = UIParent:GetWidth(), UIParent:GetHeight()
    local defaultX, defaultY = uiW * 0.53, uiH * 0.58

    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
        if WFC.Safe then plate = WFC.Safe(plate) end
        if ok and plate then
            local ok2, px, py = pcall(function()
                local x, y = plate:GetCenter()
                local s = plate:GetEffectiveScale() / UIParent:GetEffectiveScale()
                return x * s, y * s
            end)
            if WFC.Safe then px = WFC.Safe(px) end
            if WFC.Safe then py = WFC.Safe(py) end
            if ok2 and type(px) == "number" and type(py) == "number" then
                return px, py - 16
            end
        end
    end
    return defaultX, defaultY
end

local function getCharacterRigAnchor(targetX, targetY)
    local uiW, uiH = UIParent:GetWidth(), UIParent:GetHeight()

    -- Scale gun & arm offset based on camera zoom so it matches character model size!
    local zoom = 14
    if GetCameraZoom then
        local ok, z = pcall(GetCameraZoom)
        if WFC.Safe then z = WFC.Safe(z) end
        if ok and type(z) == "number" and z > 0.5 then
            zoom = z
        end
    end
    -- At normal zoom (~14 yds), scale is ~0.78; zoomed in close, up to 1.15; zoomed far out, down to 0.45
    local scale = math.max(0.45, math.min(1.15, 11.0 / math.max(5, zoom)))

    -- In WoW third-person camera, the character's upper torso/chest center is just below screen center
    local centerX = uiW * 0.50
    local torsoY  = uiH * 0.465

    -- Determine whether aiming right/forward or left
    local side = (targetX >= centerX - 10) and 1 or -1

    -- Character's casting shoulder & outstretched right hand holding the Glock
    local shoulderX = centerX + side * (11 * scale)
    local shoulderY = torsoY + (6 * scale)

    local aimDx = targetX - shoulderX
    local aimDy = targetY - shoulderY
    local aimDist = math.max(1, math.sqrt(aimDx * aimDx + aimDy * aimDy))
    local reach = 26 * scale

    local handX = shoulderX + (aimDx / aimDist) * reach
    local handY = shoulderY + (aimDy / aimDist) * (reach * 0.65)

    return shoulderX, shoulderY, handX, handY, scale, side
end

local function spawnSmokyExplosion(x, y)
    -- Play smoky impact explosion sound
    playSoundId(SOUND_EXPLOSION, 3134)

    -- 1. Bright core impact flash
    spawnParticle({
        tex = STAR_TEX, blend = "ADD",
        x = x, y = y,
        size0 = 18, size1 = 85,
        r = 1.0, g = 0.85, b = 0.35,
        r1 = 1.0, g1 = 0.35, b1 = 0.05,
        a = 1.0, a1 = 0,
        vrot = 6,
        life = 0.14,
    })
    spawnParticle({
        tex = CIRCLE_TEX, blend = "ADD",
        x = x, y = y,
        size0 = 14, size1 = 56,
        r = 1.0, g = 0.65, b = 0.20,
        r1 = 0.9, g1 = 0.20, b1 = 0.05,
        a = 0.9, a1 = 0,
        life = 0.18,
    })

    -- 2. Billowing smoky explosion cloud (12 layered smoke puffs)
    for i = 1, 12 do
        local ang = (i / 12) * math.pi * 2 + (math.random() - 0.5) * 0.4
        local spd = 25 + math.random() * 65
        local shade = 0.22 + math.random() * 0.28
        spawnParticle({
            tex = CIRCLE_TEX, blend = "BLEND",
            x = x + math.cos(ang) * 4,
            y = y + math.sin(ang) * 4,
            vx = math.cos(ang) * spd,
            vy = math.sin(ang) * spd + 28, -- smoke rises
            drag = 3.2,
            size0 = 18 + math.random() * 10,
            size1 = 48 + math.random() * 26,
            r = shade + 0.15, g = shade + 0.12, b = shade + 0.10,
            r1 = shade * 0.6, g1 = shade * 0.6, b1 = shade * 0.65,
            a = 0.82, a1 = 0,
            life = 0.45 + math.random() * 0.30,
        })
    end

    -- 3. Fiery ember sparks flying out of the explosion
    for i = 1, 8 do
        local ang = math.random() * math.pi * 2
        local spd = 90 + math.random() * 130
        spawnParticle({
            tex = STAR_TEX, blend = "ADD",
            x = x, y = y,
            vx = math.cos(ang) * spd,
            vy = math.sin(ang) * spd + 40,
            gravity = -260,
            size0 = 10, size1 = 3,
            r = 1.0, g = 0.90, b = 0.40,
            r1 = 1.0, g1 = 0.25, b1 = 0.05,
            a = 1.0, a1 = 0,
            life = 0.25 + math.random() * 0.18,
        })
    end
end

---------------------------------------------------------------------------
-- Fire Glock Shot!
---------------------------------------------------------------------------
function Glock:Fire()
    local targetX, targetY = getTargetScreenPos()
    local shoulderX, shoulderY, handX, handY, scale, side = getCharacterRigAnchor(targetX, targetY)

    -- 1. Play gunshot blast + metallic blowback slide rack sound
    local shotSound = SOUND_GUNFIRE[math.random(#SOUND_GUNFIRE)]
    playSoundId(shotSound, 1155)
    if C_Timer and C_Timer.After then
        C_Timer.After(0.04, function()
            playSoundId(SOUND_SLIDERACK, 1154)
        end)
    end

    local dx, dy = targetX - handX, targetY - handY
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 25 then
        targetX, targetY = handX + side * 120, handY + 55
        dx, dy = targetX - handX, targetY - handY
        dist = math.sqrt(dx * dx + dy * dy)
    end
    local aimAngle = atan2(dy, dx)
    local cosA, sinA = math.cos(aimAngle), math.sin(aimAngle)

    -- Compute exact muzzle tip & ejection port in screen coordinates
    local muzzleX = handX + (42 * cosA - (15 * side) * sinA) * scale
    local muzzleY = handY + (42 * sinA + (15 * side) * cosA) * scale
    local portX   = handX + (17 * cosA - (17 * side) * sinA) * scale
    local portY   = handY + (17 * sinA + (17 * side) * cosA) * scale

    -- Render initial frame of the Glock held in the character's hand
    renderGunRig(shoulderX, shoulderY, handX, handY, aimAngle, scale, side, 0, 2.5, 1)

    -- 1. Muzzle flash burst at barrel tip
    spawnParticle({
        tex = STAR_TEX, blend = "ADD",
        x = muzzleX + cosA * 4, y = muzzleY + sinA * 4,
        size0 = 38 * scale, size1 = 12 * scale,
        r = 1.0, g = 0.92, b = 0.45,
        r1 = 1.0, g1 = 0.45, b1 = 0.10,
        a = 1.0, a1 = 0,
        life = 0.08,
    })
    for i = 1, 4 do
        spawnParticle({
            tex = CIRCLE_TEX, blend = "BLEND",
            x = muzzleX, y = muzzleY,
            vx = cosA * (40 + i * 20) + (math.random() - 0.5) * 25,
            vy = sinA * (40 + i * 20) + 18 + math.random() * 20,
            drag = 4.0,
            size0 = 9 * scale, size1 = 24 * scale,
            r = 0.75, g = 0.75, b = 0.78,
            r1 = 0.40, g1 = 0.42, b1 = 0.45,
            a = 0.65, a1 = 0,
            life = 0.30,
        })
    end

    -- 2. Ejected spinning 9mm brass shell casing that arcs down, bounces on the ground, and clatters!
    spawnParticle({
        tex = WHITE_TEX, blend = "BLEND",
        x = portX, y = portY,
        vx = -side * (42 + math.random() * 28),
        vy = 135 + math.random() * 35,
        gravity = -680,
        floorY = portY - 62 * scale,
        maxBounces = 3,
        onBounce = function(p)
            -- Play metallic brass shell clatter on each ground bounce!
            playSoundId(SOUND_SHELLCLINK, 120)
            -- Tiny spark/glint when the brass casing strikes the ground
            spawnParticle({
                tex = STAR_TEX, blend = "ADD",
                x = p.x, y = p.y,
                size0 = 9 * scale, size1 = 2 * scale,
                r = 1.0, g = 0.90, b = 0.45,
                r1 = 1.0, g1 = 0.70, b1 = 0.20,
                a = 0.85, a1 = 0,
                life = 0.08,
            })
        end,
        size0 = 6.0 * scale, size1 = 6.0 * scale,
        aspect = 0.45,
        r = 0.96, g = 0.80, b = 0.24,
        r1 = 0.88, g1 = 0.68, b1 = 0.16,
        a = 1.0, a1 = 0.15,
        vrot = 20 * side,
        life = 0.92,
    })

    -- 3. High-velocity bullet projectile with continuous smoke trail
    local bullet = acquireParticle()
    bullet:SetTexture(WHITE_TEX)
    bullet:SetBlendMode("ADD")
    bullet:SetVertexColor(1.0, 0.88, 0.35, 1)
    bullet:SetSize(13 * scale, 3.5 * scale)
    if bullet.SetRotation then pcall(bullet.SetRotation, bullet, aimAngle) end
    bullet:SetPoint("CENTER", UIParent, "BOTTOMLEFT", muzzleX, muzzleY)

    activeShots[#activeShots + 1] = {
        bullet = bullet,
        startX = muzzleX, startY = muzzleY,
        targetX = targetX, targetY = targetY,
        lastSmokeX = muzzleX, lastSmokeY = muzzleY,
        age = 0,
        flightTime = math.max(0.10, math.min(0.22, dist / 1800)),
        gunAge = 0,
        gunDuration = 0.46,
        shoulderX = shoulderX, shoulderY = shoulderY,
        handX = handX, handY = handY,
        aimAngle = aimAngle,
        scale = scale,
        side = side,
        impacted = false,
    }
end

---------------------------------------------------------------------------
-- Master Animation Loop
---------------------------------------------------------------------------
canvas:SetScript("OnUpdate", function(_, elapsed)
    if #activeParticles == 0 and #activeShots == 0 then return end

    -- Update shots & character's Glock hand/recoil animation
    for i = #activeShots, 1, -1 do
        local s = activeShots[i]
        s.age = s.age + elapsed
        s.gunAge = s.gunAge + elapsed

        -- Animate the character holding, recoiling, and holstering the Glock
        if i == #activeShots then
            local gProgress = s.gunAge / s.gunDuration
            if gProgress < 1 then
                -- Sharp blowback & muzzle flip in the first 0.05s, then smooth recovery
                local kick = (s.gunAge < 0.05) and (s.gunAge / 0.05)
                    or math.max(0, 1 - (s.gunAge - 0.05) / 0.20)

                -- Holster lower animation in the last 25% of duration
                local holster = (gProgress > 0.72) and ((gProgress - 0.72) / 0.28) or 0
                local alpha = 1 - holster

                local cosA, sinA = math.cos(s.aimAngle), math.sin(s.aimAngle)
                -- Hand kicks back along barrel line and slightly up, then drops to hip on holster
                local curHandX = s.handX - cosA * (kick * 7 * s.scale) - (holster * 6 * s.scale * s.side)
                local curHandY = s.handY - sinA * (kick * 7 * s.scale) + (kick * 4 * s.scale) - (holster * 18 * s.scale)

                -- Muzzle flips upward on recoil, then tilts down toward hip on holster
                local curAngle = s.aimAngle + (kick * 0.28 * s.side) - (holster * 0.55 * s.side)
                local slideKick = kick * 9.5
                local triggerPull = (s.gunAge < 0.14) and 2.5 or 0

                renderGunRig(s.shoulderX, s.shoulderY, curHandX, curHandY,
                    curAngle, s.scale, s.side, slideKick, triggerPull, alpha)
            else
                hideGunRig()
            end
        end

        -- Animate bullet & spawn smoke trail puffs along the path
        if not s.impacted then
            local t = math.min(1, s.age / s.flightTime)
            local bx = s.startX + (s.targetX - s.startX) * t
            local by = s.startY + (s.targetY - s.startY) * t
            s.bullet:SetPoint("CENTER", UIParent, "BOTTOMLEFT", bx, by)

            -- Spawn dense smoke trail puffs every ~12px along the bullet path
            local sdx, sdy = bx - s.lastSmokeX, by - s.lastSmokeY
            local stepDist = math.sqrt(sdx * sdx + sdy * sdy)
            if stepDist >= 12 then
                local steps = math.min(6, math.floor(stepDist / 12))
                for k = 1, steps do
                    local f = k / steps
                    local px = s.lastSmokeX + sdx * f
                    local py = s.lastSmokeY + sdy * f
                    spawnParticle({
                        tex = CIRCLE_TEX, blend = "BLEND",
                        x = px + (math.random() - 0.5) * 3,
                        y = py + (math.random() - 0.5) * 3,
                        vx = (math.random() - 0.5) * 14,
                        vy = 14 + math.random() * 18,
                        size0 = 8, size1 = 24,
                        r = 0.78, g = 0.80, b = 0.84,
                        r1 = 0.38, g1 = 0.40, b1 = 0.44,
                        a = 0.60, a1 = 0,
                        life = 0.36,
                    })
                end
                s.lastSmokeX, s.lastSmokeY = bx, by
            end

            if t >= 1 then
                s.impacted = true
                releaseParticle(s.bullet)
                s.bullet = nil
                spawnSmokyExplosion(s.targetX, s.targetY)
            end
        end

        if s.impacted and s.gunAge >= s.gunDuration then
            table.remove(activeShots, i)
            if #activeShots == 0 then hideGunRig() end
        end
    end

    -- Update particles
    for i = #activeParticles, 1, -1 do
        local p = activeParticles[i]
        p.age = p.age + elapsed
        if p.age >= p.life then
            releaseParticle(p.tex)
            table.remove(activeParticles, i)
        else
            local t = p.age / p.life
            if p.drag > 0 then
                local damp = math.max(0, 1 - p.drag * elapsed)
                p.vx = p.vx * damp
                p.vy = p.vy * damp
            end
            p.vy = p.vy + p.gravity * elapsed
            p.x = p.x + p.vx * elapsed
            p.y = p.y + p.vy * elapsed

            -- Floor bounce physics (for ejected 9mm brass shell casing clatter!)
            if p.floorY and p.y <= p.floorY and p.vy < 0 then
                p.y = p.floorY
                if p.bounces < p.maxBounces then
                    p.bounces = p.bounces + 1
                    p.vy = -p.vy * 0.48
                    p.vx = p.vx * 0.68
                    p.vrot = p.vrot * 0.65
                    if p.onBounce then p.onBounce(p) end
                else
                    p.vy = 0
                    p.vx = p.vx * 0.85
                    p.vrot = 0
                end
            end

            local sz = p.size0 + (p.size1 - p.size0) * t
            p.tex:SetSize(sz, sz * (p.aspect or 1))
            local r = p.r0 + (p.r1 - p.r0) * t
            local g = p.g0 + (p.g1 - p.g0) * t
            local b = p.b0 + (p.b1 - p.b0) * t
            local a = p.a0 + (p.a1 - p.a0) * t
            p.tex:SetVertexColor(r, g, b, a)
            if p.vrot ~= 0 and p.tex.SetRotation then
                p.rot = p.rot + p.vrot * elapsed
                pcall(p.tex.SetRotation, p.tex, p.rot)
            end
            p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
        end
    end
end)

---------------------------------------------------------------------------
-- Spellcast Listener (Fire Blast)
---------------------------------------------------------------------------
WFC:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellId)
    local s = Overlay.settings
    if not s or not s.glockFireBlast then return end
    if WFC.Safe then unit = WFC.Safe(unit) end
    if unit ~= "player" then return end

    if WFC.Safe then spellId = WFC.Safe(spellId) end
    local isFireBlast = false
    if type(spellId) == "number" and FIRE_BLAST_IDS[spellId] then
        isFireBlast = true
    elseif spellId then
        local name = (GetSpellInfo and GetSpellInfo(spellId))
            or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellId))
        if WFC.Safe then name = WFC.Safe(name) end
        if name == "Fire Blast" then
            isFireBlast = true
        end
    end

    if isFireBlast then
        Glock:Fire()
    end
end)

local function handleGlockCmd(rest)
    local sub = (rest or ""):lower():match("^%s*(%S*)") or ""
    local s = Overlay.settings
    if sub == "on" or sub == "off" then
        if s then s.glockFireBlast = (sub == "on") end
        WFC:Print("Easter egg Glock 19 Fire Blast:", (sub == "on") and "ON" or "off")
    elseif sub == "toggle" then
        if s then s.glockFireBlast = not s.glockFireBlast end
        WFC:Print("Easter egg Glock 19 Fire Blast:", (s and s.glockFireBlast) and "ON" or "off")
    else
        Glock:Fire()
    end
end

WFC:AddCommand("glock", "[test|on|off|toggle] — Fire or toggle the Glock 19 Fire Blast easter egg", handleGlockCmd)
SLASH_WFCGLOCK1 = "/glock"
SlashCmdList.WFCGLOCK = handleGlockCmd
