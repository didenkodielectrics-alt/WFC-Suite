local _, ns = ...
local WFC = WFC

-- Tooltip glue (plan.md §3.2, design.md §3): one post-call hook, our lines appended
-- after Blizzard's (and Questie's), fonts set only on OUR lines and restored on
-- OnTooltipCleared, nothing at all in combat, and never a protected call.

local Tips, Format = ns.Tips, ns.Format
local Compat = WFC.Compat

local FRAME_NAMES = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }

local allowed = {}                                       -- [tooltip] = true
local augmented = setmetatable({}, { __mode = "k" })     -- [tooltip] = itemId we added lines for
local current = setmetatable({}, { __mode = "k" })       -- [tooltip] = itemId last shown (even if skipped)
local restore = setmetatable({}, { __mode = "k" })       -- [tooltip] = { [fontString] = original font object }
local separators = setmetatable({}, { __mode = "k" })    -- [tooltip] = our 1px rule texture

---------------------------------------------------------------------------
-- Temporary Weapon Enchant Clarification (Rockbiter, Windfury, Oils, Stones)
---------------------------------------------------------------------------
local ROCKBITER = { [1]=54, [2]=104, [3]=154, [4]=211, [5]=284, [6]=377, [7]=500 }
local WINDFURY = { [1]=119, [2]=166, [3]=229, [4]=333, [5]=448 }
local FLAMETONGUE = { [1]="10.5-32.5", [2]="18-55.5", [3]="26-80.5", [4]="35-108.5", [5]="45-139.5", [6]="56-173.5" }
local FROSTBRAND = { [1]="66", [2]="110", [3]="154", [4]="210", [5]="287" }

local STONES = {
    ["Rough Sharpening Stone"] = "+2 Weapon Damage",
    ["Coarse Sharpening Stone"] = "+3 Weapon Damage",
    ["Heavy Sharpening Stone"] = "+4 Weapon Damage",
    ["Solid Sharpening Stone"] = "+6 Weapon Damage",
    ["Dense Sharpening Stone"] = "+8 Weapon Damage",
    ["Elemental Sharpening Stone"] = "+2% Crit Chance",
    ["Rough Weightstone"] = "+2 Blunt Damage",
    ["Coarse Weightstone"] = "+3 Blunt Damage",
    ["Heavy Weightstone"] = "+4 Blunt Damage",
    ["Solid Weightstone"] = "+6 Blunt Damage",
    ["Dense Weightstone"] = "+8 Blunt Damage",
}

local OILS = {
    ["Minor Wizard Oil"] = "+4 Spell Damage",
    ["Lesser Wizard Oil"] = "+16 Spell Damage",
    ["Wizard Oil"] = "+24 Spell Damage",
    ["Brilliant Wizard Oil"] = "+36 Spell Damage, +14 Spell Crit",
    ["Minor Mana Oil"] = "+4 Mana/5s",
    ["Lesser Mana Oil"] = "+8 Mana/5s",
    ["Brilliant Mana Oil"] = "+12 Mana/5s, +25 Healing",
}

local function transformEnchantText(text)
    if not text or type(text) ~= "string" then return text end

    -- Avoid double-tagging
    if text:find("Attack Power", 1, true)
        or text:find("Weapon Damage", 1, true)
        or text:find("Blunt Damage", 1, true)
        or text:find("Spell Damage", 1, true)
        or text:find("Mana/5s", 1, true)
        or text:find("Fire dmg", 1, true)
        or text:find("Frost & slow", 1, true)
        or text:find("extra attacks", 1, true)
    then
        return text
    end

    -- Rockbiter: e.g. "Rockbiter 1 (60 min)" or "|cff00ff00Rockbiter 1 (60 min)|r"
    local rbRank = text:match("Rockbiter.-(%d+)")
    if rbRank then
        local ap = ROCKBITER[tonumber(rbRank)]
        if ap then
            return text:gsub("Rockbiter.-" .. rbRank, "Rockbiter " .. rbRank .. " (+" .. ap .. " Attack Power)", 1)
        end
    end

    -- Windfury: e.g. "Windfury 1"
    local wfRank = text:match("Windfury.-(%d+)")
    if wfRank then
        local ap = WINDFURY[tonumber(wfRank)]
        if ap then
            return text:gsub("Windfury.-" .. wfRank, "Windfury " .. wfRank .. " (20% proc: +" .. ap .. " AP)", 1)
        end
    end

    -- Flametongue
    local ftRank = text:match("Flametongue.-(%d+)")
    if ftRank then
        local dmg = FLAMETONGUE[tonumber(ftRank)]
        if dmg then
            return text:gsub("Flametongue.-" .. ftRank, "Flametongue " .. ftRank .. " (Fire dmg " .. dmg .. ")", 1)
        end
    end

    -- Frostbrand
    local fbRank = text:match("Frostbrand.-(%d+)")
    if fbRank then
        local dmg = FROSTBRAND[tonumber(fbRank)]
        if dmg then
            return text:gsub("Frostbrand.-" .. fbRank, "Frostbrand " .. fbRank .. " (" .. dmg .. " Frost & slow)", 1)
        end
    end

    -- Sharpening Stones & Weightstones
    for stoneName, effect in pairs(STONES) do
        if text:find(stoneName, 1, true) then
            return text:gsub(stoneName, stoneName .. " (" .. effect .. ")", 1)
        end
    end

    -- Oils
    for oilName, effect in pairs(OILS) do
        if text:find(oilName, 1, true) then
            return text:gsub(oilName, oilName .. " (" .. effect .. ")", 1)
        end
    end

    return text
end

local fontStringAt = function(tooltip, side, i)
    local name = tooltip:GetName()
    return name and _G[name .. "Text" .. side .. i]
end

-- Tooltip text on this client is a "secret string" (unreadable by addons), so we can't
-- rewrite Blizzard's "Rockbiter 1 (55 min)" line. Instead we read the enchant from
-- GetWeaponEnchantInfo() and append our own explanation line under the item.
local ENCHANT_IDS = {
    -- Rockbiter Weapon
    [29] = { "Rockbiter", 1 }, [6] = { "Rockbiter", 2 }, [1] = { "Rockbiter", 3 },
    [503] = { "Rockbiter", 4 }, [1663] = { "Rockbiter", 5 }, [683] = { "Rockbiter", 6 },
    [1664] = { "Rockbiter", 7 },
    -- Flametongue Weapon
    [5] = { "Flametongue", 1 }, [4] = { "Flametongue", 2 }, [3] = { "Flametongue", 3 },
    [523] = { "Flametongue", 4 }, [1665] = { "Flametongue", 5 }, [1666] = { "Flametongue", 6 },
    -- Frostbrand Weapon
    [2] = { "Frostbrand", 1 }, [12] = { "Frostbrand", 2 }, [524] = { "Frostbrand", 3 },
    [1667] = { "Frostbrand", 4 }, [1668] = { "Frostbrand", 5 },
    -- Windfury Weapon
    [283] = { "Windfury", 1 }, [284] = { "Windfury", 2 }, [525] = { "Windfury", 3 },
    [1669] = { "Windfury", 4 },
}
local ROCKBITER_SPELLS = { 8017, 8018, 8019, 10399, 16314, 16315, 16316 }

local function describeImbue(kind, rank)
    if kind == "Rockbiter" and ROCKBITER[rank] then
        return string.format("Rockbiter %d: +%d Attack Power", rank, ROCKBITER[rank])
    elseif kind == "Windfury" and WINDFURY[rank] then
        return string.format("Windfury %d: 20%% chance for 2 extra attacks (+%d AP)", rank, WINDFURY[rank])
    elseif kind == "Flametongue" and FLAMETONGUE[rank] then
        return string.format("Flametongue %d: %s Fire damage per hit", rank, FLAMETONGUE[rank])
    elseif kind == "Frostbrand" and FROSTBRAND[rank] then
        return string.format("Frostbrand %d: chance for %s Frost damage + slow", rank, FROSTBRAND[rank])
    end
end

--- Highest Rockbiter rank the player knows (fallback when the enchant ID is unmapped).
local function knownRockbiterRank()
    if not IsSpellKnown then return nil end
    for r = #ROCKBITER_SPELLS, 1, -1 do
        local ok, known = pcall(IsSpellKnown, ROCKBITER_SPELLS[r])
        if ok and known then return r end
    end
end

local function addEnchantLine(tooltip, itemId)
    if not (Tips.settings and Tips.settings.weaponEnchants) then return end
    if not tooltip or tooltip._wfcEnchantAdded or type(itemId) ~= "number" then return end
    if not GetWeaponEnchantInfo or not GetInventoryItemID then return end
    local hasMH, _, _, mhId, hasOH, _, _, ohId = GetWeaponEnchantInfo()
    local enchantId
    if hasMH and GetInventoryItemID("player", 16) == itemId then
        enchantId = mhId
    elseif hasOH and GetInventoryItemID("player", 17) == itemId then
        enchantId = ohId
    else
        return
    end
    local text
    local info = enchantId and ENCHANT_IDS[enchantId]
    if info then
        text = describeImbue(info[1], info[2])
    else
        local rb = knownRockbiterRank()
        if rb and UnitClassBase and UnitClassBase("player") == "SHAMAN" then
            text = describeImbue("Rockbiter", rb)
        end
        WFC:Debug("Unmapped temp enchant id", tostring(enchantId))
    end
    if not text then return end
    tooltip._wfcEnchantAdded = true
    tooltip:AddLine(text, 0.55, 1.0, 0.55, true)
    tooltip:Show()
end

local function annotateFontStrings() end -- legacy no-op (text is secret on this client)


---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Gathering Indicators (Skinning, Mining, Herbalism)
---------------------------------------------------------------------------
local function getPlayerProfSkill(skillLineId, profName)
    -- 1. Live player professions table in WFC.Player (kept current via SKILL_LINES_CHANGED)
    if WFC and WFC.Player and WFC.Player.professions then
        local p = WFC.Player.professions[skillLineId]
        if p and p.rank and p.rank > 0 then
            return p.rank, false
        end
    end
    -- 2. Fallback live API check only before WFC.Player is initialized
    if not (WFC and WFC.Player and WFC.Player.charKey) then
        if GetProfessions and GetProfessionInfo then
            local profs = { GetProfessions() }
            for i = 1, #profs do
                local idx = profs[i]
                if idx then
                    local name, _, rank, _, _, _, skillLine = GetProfessionInfo(idx)
                    if skillLine == skillLineId or (name and name:find(profName)) then
                        return rank or 0, false
                    end
                end
            end
        elseif GetNumSkillLines and GetSkillLineInfo then
            for i = 1, GetNumSkillLines() do
                local name, isHeader, _, rank = GetSkillLineInfo(i)
                if not isHeader and name and (name == profName or name:find(profName)) then
                    return rank or 0, false
                end
            end
        end
    end
    -- Current character only: alts' skill is deliberately not used (a gather tooltip
    -- answers "can I gather this, here, now").
    return nil, false
end

-- The client colours its own gather line ("Requires Mining", "Skinnable", a node's
-- "Herbalism 50" line) with the same difficulty colours as recipes. That colour is the
-- authority: it knows Forever's exact bands. Our bands below are only the fallback.
local GAME_BANDS = {
    { "Too Low", 1.00, 0.10, 0.10 },  -- RED_FONT_COLOR
    { "Optimal", 1.00, 0.50, 0.25 },  -- TradeSkillTypeColor.optimal
    { "Medium",  1.00, 1.00, 0.00 },  -- .medium
    { "Low",     0.25, 0.75, 0.25 },  -- .easy
    { "Trivial", 0.50, 0.50, 0.50 },  -- .trivial
}
local function safeNum(v)
    if Compat.IsSecret(v) then return nil end
    return type(v) == "number" and v or nil
end

--- Nearest difficulty band for a colour, or nil when it isn't one (white / gold / unreadable).
local function bandForColor(r, g, b)
    r, g, b = safeNum(r), safeNum(g), safeNum(b)
    if not (r and g and b) then return nil end
    local best, bestD
    for _, band in ipairs(GAME_BANDS) do
        local d = (r - band[2]) ^ 2 + (g - band[3]) ^ 2 + (b - band[4]) ^ 2
        if not bestD or d < bestD then best, bestD = band, d end
    end
    if bestD and bestD <= 0.06 then return best end
    return nil
end

--- Game difficulty band read from the tooltip line whose text satisfies match(lowerText).
--- Must run BEFORE we recolour anything.
local function gameGatherBand(tooltip, match)
    local name = tooltip and tooltip.GetName and tooltip:GetName()
    if not name then return nil end
    for i = 2, (tooltip:NumLines() or 0) do
        local fs = _G[name .. "TextLeft" .. i]
        local t = fs and fs:GetText()
        if type(t) == "string" and not Compat.IsSecret(t) then
            local clean = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
            if match(clean) then
                local inline = t:match("|c%x%x(%x%x%x%x%x%x)")
                if inline then
                    local band = bandForColor(tonumber(inline:sub(1, 2), 16) / 255,
                        tonumber(inline:sub(3, 4), 16) / 255, tonumber(inline:sub(5, 6), 16) / 255)
                    if band then return band end
                end
                local ok, r, g, b = pcall(fs.GetTextColor, fs)
                if ok then return bandForColor(r, g, b) end
                return nil
            end
        end
    end
    return nil
end

--- "Requires 1 · You: 45 (Optimal)" — always the current character's skill.
--- gameBand (from gameGatherBand) overrides the calculated colour when present.
local function getGatherTagAndColor(reqSkill, playerSkill, gameBand)
    if not playerSkill then
        -- Current character doesn't have this profession
        return string.format("Requires %d · You: not learned", reqSkill), 0.75, 0.75, 0.75
    end
    local who = "You"
    local label, r, g, b
    if type(gameBand) == "table" then
        label, r, g, b = gameBand[1], gameBand[2], gameBand[3], gameBand[4]
    elseif playerSkill < reqSkill then
        label, r, g, b = "Too Low", 1.0, 0.20, 0.20        -- Red: cannot gather
    elseif playerSkill < reqSkill + 25 then
        label, r, g, b = "Optimal", 1.0, 0.50, 0.15        -- Orange: guaranteed skill-up
    elseif playerSkill < reqSkill + 50 then
        label, r, g, b = "Medium", 1.0, 0.88, 0.15         -- Yellow: high skill-up chance
    elseif playerSkill < reqSkill + 100 then
        label, r, g, b = "Low", 0.30, 0.85, 0.30           -- Green: low skill-up chance
    else
        label, r, g, b = "Trivial", 0.65, 0.65, 0.65       -- Grey: no skill-up
    end
    return string.format("Requires %d · %s: %d (%s)", reqSkill, who, playerSkill, label), r, g, b
end

local SKINNING_TIERS = {
    { max = 5,   text = "Ruined Scraps ~65% · Light Leather ~30% · Light Hide ~5%" },
    { max = 10,  text = "Light Leather ~68% · Ruined Scraps ~25% · Light Hide ~7%" },
    { max = 14,  text = "Light Leather ~88% · Light Hide ~8% · Ruined Scraps ~4%" },
    { max = 18,  text = "Light Leather ~76% · Medium Leather ~14% · Light Hide ~7% · Medium Hide ~3%" },
    { max = 22,  text = "Medium Leather ~68% · Light Leather ~22% · Medium Hide ~7% · Light Hide ~3%" },
    { max = 25,  text = "Medium Leather ~88% · Medium Hide ~9% · Light Leather ~3%" },
    { max = 28,  text = "Medium Leather ~76% · Heavy Leather ~14% · Medium Hide ~7% · Heavy Hide ~3%" },
    { max = 32,  text = "Heavy Leather ~68% · Medium Leather ~22% · Heavy Hide ~7% · Medium Hide ~3%" },
    { max = 35,  text = "Heavy Leather ~88% · Heavy Hide ~9% · Medium Leather ~3%" },
    { max = 38,  text = "Heavy Leather ~76% · Thick Leather ~14% · Heavy Hide ~7% · Thick Hide ~3%" },
    { max = 42,  text = "Thick Leather ~68% · Heavy Leather ~22% · Thick Hide ~7% · Heavy Hide ~3%" },
    { max = 45,  text = "Thick Leather ~88% · Thick Hide ~9% · Heavy Leather ~3%" },
    { max = 48,  text = "Thick Leather ~76% · Rugged Leather ~14% · Thick Hide ~7% · Rugged Hide ~3%" },
    { max = 52,  text = "Rugged Leather ~72% · Thick Leather ~18% · Rugged Hide ~8% · Thick Hide ~2%" },
    { max = 999, text = "Rugged Leather ~90% · Rugged Hide ~10%" },
}

local function bonusSkinningLoot(unit, lvl, cType)
    local family = WFC.Safe(UnitCreatureFamily(unit))
    local name = WFC.Safe(UnitName(unit))
    local lname = type(name) == "string" and name:lower() or ""
    if lname:find("deviate") and lvl >= 13 and lvl <= 24 then
        return "Deviate Scale ~25% · Perfect Deviate Scale ~5%"
    elseif family == "Turtle" and lvl >= 25 then
        return "Turtle Scale ~25%"
    elseif family == "Scorpid" and lvl >= 35 then
        return "Scorpid Scale ~25%"
    elseif family == "Wolf" and lvl >= 45 then
        return "Thick Wolfhide ~20%"
    elseif (family == "Devilsaur" or lname:find("devilsaur")) and lvl >= 54 then
        return "Devilsaur Leather ~100% (1-2)"
    elseif lname:find("core hound") then
        return "Core Leather ~35%"
    elseif (lname:find("chimera") or lname:find("chimaerok")) and lvl >= 55 then
        return "Chimera Leather ~40%"
    elseif cType == "Dragonkin" and lvl >= 20 then
        local color = (lname:find("black") or lname:find("flame") or lname:find("ember")) and "Black"
            or (lname:find("red") or lname:find("crimson") or lname:find("scaldr")) and "Red"
            or (lname:find("green") or lname:find("emerald") or lname:find("dream")) and "Green"
            or (lname:find("blue") or lname:find("azure") or lname:find("cobalt")) and "Blue"
        if lvl <= 34 then
            return (color and (color .. " Whelp Scale") or "Whelp Scale") .. " ~25%"
        end
        return (color and (color .. " Dragonscale") or "Worn Dragonscale") .. " ~20%"
    end
    return nil
end

local CLOTH_TIERS = {
    { max = 4,   text = "Linen Cloth ~15%" },
    { max = 14,  text = "Linen Cloth ~35%" },
    { max = 18,  text = "Linen Cloth ~25% · Wool Cloth ~10%" },
    { max = 24,  text = "Wool Cloth ~30% · Linen Cloth ~10%" },
    { max = 28,  text = "Wool Cloth ~25% · Silk Cloth ~15%" },
    { max = 36,  text = "Silk Cloth ~35% · Wool Cloth ~5%" },
    { max = 40,  text = "Silk Cloth ~25% · Mageweave Cloth ~15%" },
    { max = 48,  text = "Mageweave Cloth ~35% · Silk Cloth ~5%" },
    { max = 51,  text = "Mageweave Cloth ~20% · Runecloth ~20%" },
    { max = 999, text = "Runecloth ~35% · Mageweave Cloth ~5%" },
}

local function tierTextForLevel(tiers, lvl)
    for i = 1, #tiers do
        if lvl <= tiers[i].max then
            return tiers[i].text
        end
    end
end

local function effectiveUnitLevel(level)
    return (level and level > 0) and level or math.max(63, (UnitLevel("player") or 60) + 3)
end

local function addSkinningLootLines(tooltip, unit, level, cType)
    local lvl = effectiveUnitLevel(level)
    local baseText = tierTextForLevel(SKINNING_TIERS, lvl)
    if baseText then
        tooltip:AddDoubleLine("  Skinning Loot", baseText, 0.88, 0.78, 0.55, 0.90, 0.85, 0.70)
    end
    local bonus = bonusSkinningLoot(unit, lvl, cType)
    if bonus then
        tooltip:AddDoubleLine("  Bonus Skin", bonus, 0.88, 0.78, 0.55, 0.65, 0.90, 1.00)
    end
end

local function addHumanoidClothLine(tooltip, level)
    local text = tierTextForLevel(CLOTH_TIERS, effectiveUnitLevel(level))
    if text then
        tooltip:AddDoubleLine("Cloth Drops", text, 0.78, 0.85, 1.00, 0.90, 0.93, 1.00)
    end
end

local function addGatherLine(tooltip, label, profName, reqSkill, playerSkill, gameBand)
    local tag, r, g, b = getGatherTagAndColor(reqSkill, playerSkill, gameBand)
    local leftText = (playerSkill and playerSkill < reqSkill) and profName or label
    tooltip:AddDoubleLine(leftText, tag, r, g, b, r, g, b)
end

local function gatherReqSkillForLevel(level)
    if not level or level <= 0 then
        level = math.max(63, (UnitLevel("player") or 60) + 3)
    end
    if level <= 10 then
        return 1
    elseif level <= 20 then
        return (level * 10) - 100
    else
        return math.min(300, level * 5)
    end
end

local SKINNABLE_FAMILIES = {
    ["Raptor"] = true,
    ["Wind Serpent"] = true,
    ["Bat"] = true,
    ["Bear"] = true,
    ["Boar"] = true,
    ["Cat"] = true,
    ["Crocolisk"] = true,
    ["Gorilla"] = true,
    ["Hyena"] = true,
    ["Scorpid"] = true,
    ["Tallstrider"] = true,
    ["Turtle"] = true,
    ["Wolf"] = true,
    ["Serpent"] = true,
    ["Devilsaur"] = true,
    ["Ravager"] = true,
    ["Warp Stalker"] = true,
    ["Nether Ray"] = true,
}

local UNSKINNABLE_FAMILIES = {
    ["Spider"] = true,
    ["Carrion Bird"] = true,
    ["Owl"] = true,
    ["Crab"] = true,
}

-- Keyword must start a word ("thorn" matches "Thornling", not "Stranglethorn").
local function hasWordStart(name, word)
    return name:find("%f[%a]" .. word) ~= nil
end

-- Keyword must be a whole word ("roc" matches "Fire Roc", not "Crocolisk").
local function hasWord(name, word)
    return name:find("%f[%a]" .. word .. "%f[%A]") ~= nil
end

local function isSkinnableUnit(unit, cType)
    if not cType then return false end
    if cType == "Dragonkin" then return true end

    local name = WFC.Safe(UnitName(unit))
    if type(name) ~= "string" or name == "" then return false end
    name = name:lower()

    -- Skinnable Humanoids in Classic (Yetis, Wendigos, Worgen)
    if cType == "Humanoid" then
        return name:find("yeti") or name:find("wendigo") or name:find("worgen")
    end

    if cType ~= "Beast" then return false end

    -- 1. Check exact WoW Creature Family first when available (e.g. Sunscale Screecher -> "Raptor")
    if UnitCreatureFamily then
        local family = WFC.Safe(UnitCreatureFamily(unit))
        if type(family) == "string" and family ~= "" then
            if SKINNABLE_FAMILIES[family] then return true end
            if UNSKINNABLE_FAMILIES[family] then return false end
        end
    end

    -- 2. Explicit skinnable beast keywords (Raptors, Plainstriders, Wind Serpents / Thunderhawks, Bats)
    if name:find("strider") or name:find("raptor") or name:find("sunscale")
        or name:find("bloodfen") or name:find("thunderhawk") or name:find("wind serpent")
        or name:find("vale screecher") or name:find("dark screecher") or name:find("dragonhawk") then
        return true
    end

    -- EXCLUSION 1: Spiders and Arachnids (NEVER skinnable in Classic)
    if name:find("spider") or name:find("tarantula") or name:find("webwood")
        or name:find("night web") or name:find("nightweb") or name:find("deepmoss")
        or name:find("widow") or name:find("recluse") or name:find("spinner")
        or name:find("weaver") or name:find("silkweaver") or name:find("webweaver")
        or name:find("creeper") or name:find("arachnid") then
        return false
    end

    -- EXCLUSION 2: Flying Avian Beasts (Carrion Birds, Vultures, Buzzards, Owls, Eagles, etc.)
    -- In Classic WoW, feathered winged birds yield no leather and cannot be skinned.
    if name:find("carrion bird") or name:find("vulture") or name:find("buzzard")
        or name:find("condor") or hasWord(name, "owl") or name:find("strigid") -- "Owlbeast" stays skinnable
        or name:find("eagle") or name:find("hawk") or name:find("falcon")
        or name:find("parrot") or name:find("macaw") or name:find("gull")
        or name:find("seagull") or name:find("albatross") or hasWord(name, "roc")
        or name:find("fleshripper") or name:find("salt flats screecher")
        or name:find("corvus") or name:find("raven") or name:find("bird") then
        return false
    end

    -- EXCLUSION 3: Crabs and Crustaceans (Crawlers, Crabs, etc.)
    if name:find("crab") or name:find("crawler") or name:find("crustacean")
        or name:find("shellfish") then
        return false
    end

    -- EXCLUSION 4: Fish and Sharks (Aquatic non-reptiles)
    if name:find("shark") or name:find("frenzy") or name:find("piranha")
        or name:find("angler") then
        return false
    end

    -- EXCLUSION 5: Insects, Wasps, and Maggots (excluding Silithids/Scorpids which drop chitin/scales)
    if name:find("wasp") or name:find("hornet") or name:find("bee")
        or name:find("stingfly") or name:find("locust") or name:find("centipede")
        or name:find("maggot") or name:find("larva") or name:find("grub") then
        return false
    end

    -- EXCLUSION 6: Critters / Non-combat Vermin (even if tagged as Beast)
    if name:find("prairie dog") or name:find("squirrel") or name:find("rabbit")
        or name:find("hare") or name:find("toad") or name:find("frog")
        or hasWord(name, "rat") or name:find("mouse") or name:find("roach")
        or name:find("marmot") or name:find("fawn") or name:find("skunk")
        or name:find("chicken") then
        return false
    end

    return true
end

local function isMinableUnit(unit, cType)
    if cType == "Mechanical" then return true end
    if cType == "Elemental" or cType == "Giant" then
        local name = WFC.Safe(UnitName(unit))
        if type(name) ~= "string" then return false end
        name = name:lower()
        return name:find("rock") or name:find("stone") or name:find("earth")
            or name:find("golem") or name:find("obsidian") or name:find("shale")
            or name:find("granite") or name:find("basalt") or name:find("mineral")
            or name:find("crystal") or name:find("sand") or name:find("slag")
            or name:find("molten giant") or name:find("molten destroyer")
            or name:find("colossus") or name:find("rumbler")
    end
    return false
end

-- Plant creatures (treants, lashers, bog beasts...) are all Elemental. Gating on type keeps
-- trolls (Witherbark, Mossflayer), gnolls (Mosshide), spiders (Deepmoss) and quilboar
-- (Thornweaver) from being tagged herbable just because of their names.
local HERBABLE_WORDS = {
    "treant", "bog beast", "bog lord", "tar beast", "tar lord", "tar lurker",
    "lasher", "timberling", "tangle", "tendril", "moss", "vine", "sprout",
    "thorn", "flora", "warpwood", "swamp",
}

local function isHerbableUnit(unit, cType)
    if cType ~= "Elemental" then return false end
    local name = WFC.Safe(UnitName(unit))
    if type(name) ~= "string" then return false end
    name = name:lower()
    for i = 1, #HERBABLE_WORDS do
        if hasWordStart(name, HERBABLE_WORDS[i]) then return true end
    end
    return false
end

-- Blizzard's own corpse lines (GlobalStrings). The client adds one only when that corpse can
-- really be gathered, so on corpses they are the authority; English fallbacks if a global is missing.
local CORPSE_GATHER_LINES = {
    { text = UNIT_SKINNABLE_LEATHER or "Skinnable",         kind = "skin" },
    { text = UNIT_SKINNABLE_ROCK    or "Requires Mining",   kind = "mine" },
    { text = UNIT_SKINNABLE_HERB    or "Requires Herbalism", kind = "herb" },
}

--- For a corpse tooltip: "skin" | "mine" | "herb" when Blizzard says it is gatherable,
--- false when the lines are readable and none says so (not gatherable, not looted yet, or
--- already skinned), nil when the text can't be read (secret) so callers fall back to heuristics.
local function corpseGatherKind(tooltip)
    local texts, unreadable = {}, false
    local ok, data = pcall(function() return tooltip.GetTooltipData and tooltip:GetTooltipData() end)
    if ok and type(data) == "table" and not Compat.IsSecret(data) and type(data.lines) == "table" then
        for _, line in ipairs(data.lines) do
            local t = line and line.leftText
            if Compat.IsSecret(t) then unreadable = true
            elseif type(t) == "string" then texts[#texts + 1] = t end
        end
    else
        local name = tooltip:GetName()
        for i = 2, tooltip:NumLines() or 0 do
            local fs = name and _G[name .. "TextLeft" .. i]
            local t = fs and fs:GetText()
            if Compat.IsSecret(t) then unreadable = true
            elseif type(t) == "string" then texts[#texts + 1] = t end
        end
    end
    for _, t in ipairs(texts) do
        for _, g in ipairs(CORPSE_GATHER_LINES) do
            if t == g.text then return g.kind end
        end
    end
    if unreadable or #texts == 0 then return nil end
    return false
end

local function checkUnitGathering(tooltip)
    if not tooltip or not tooltip.GetUnit then return end
    if tooltip._wfcSkinningAdded then return end

    local _, unit = tooltip:GetUnit()
    unit = WFC.Safe(unit)
    if not unit then unit = "mouseover" end
    if not WFC.Safe(UnitExists(unit)) then return end
    -- Players and their pets are never gatherable (players report "Humanoid", pets "Beast")
    if WFC.Safe(UnitIsPlayer(unit)) or WFC.Safe(UnitPlayerControlled(unit)) then return end

    local cType = WFC.Safe(UnitCreatureType(unit))
    local level = WFC.Safe(UnitLevel(unit))
    local s = Tips.settings
    if not s then return end

    -- Humanoids: show expected cloth drops by level (excluding skinnable humanoids like Yeti/Worgen)
    if cType == "Humanoid" and s.humanoidCloth ~= false and not isSkinnableUnit(unit, cType) then
        tooltip._wfcSkinningAdded = true
        addHumanoidClothLine(tooltip, level)
        tooltip:Show()
        return
    end

    -- Corpses (where you actually gather): trust Blizzard's line when it's readable.
    -- Live mobs: Blizzard shows nothing, so predict from creature type / family / name.
    local corpseKind
    if WFC.Safe(UnitIsDead(unit)) then
        corpseKind = corpseGatherKind(tooltip)
        if corpseKind == false then return end
    end
    local function wants(kind, setting, heuristic)
        if not s[setting] then return false end
        if corpseKind ~= nil then return corpseKind == kind end
        return heuristic(unit, cType) and true or false
    end

    -- Requirement (Classic & Forever): mob level 1-10 -> 1, 11-20 -> (level-10)*10, 21+ -> level*5
    local reqSkill = gatherReqSkillForLevel(level)
    -- On a corpse, Blizzard's own gather line is coloured by difficulty: use that colour.
    local function corpseBand(kind)
        if not corpseKind then return nil end
        for _, g in ipairs(CORPSE_GATHER_LINES) do
            if g.kind == kind then
                local want = g.text:lower()
                return gameGatherBand(tooltip, function(t) return t == want end)
            end
        end
    end
    -- On a corpse Blizzard already printed "Skinnable", so our left label names the profession.
    local function add(label, profName, skillLine, kind)
        tooltip._wfcSkinningAdded = true
        local playerSkill = getPlayerProfSkill(skillLine, profName)
        addGatherLine(tooltip, corpseKind and profName or label, profName, reqSkill, playerSkill, corpseBand(kind))
        tooltip:Show()
    end

    -- Skinning: Beasts, Dragonkin, and select Humanoids (Yetis, Wendigos, Worgen)
    if wants("skin", "aliveSkinning", isSkinnableUnit) then
        tooltip._wfcSkinningAdded = true
        local playerSkill = getPlayerProfSkill(393, "Skinning")
        addGatherLine(tooltip, corpseKind and "Skinning" or "Skinnable", "Skinning", reqSkill, playerSkill, corpseBand("skin"))
        if s.skinningDrops ~= false then
            addSkinningLootLines(tooltip, unit, level, cType)
        end
        tooltip:Show()
        return
    end
    -- Mining: Elementals / Mechanicals / Golems
    if wants("mine", "mining", isMinableUnit) then return add("Minable", "Mining", 186, "mine") end
    -- Herbalism: plant Elementals (treants, lashers, bog beasts...)
    if wants("herb", "herbalism", isHerbableUnit) then return add("Herbable", "Herbalism", 182, "herb") end
end

---------------------------------------------------------------------------
-- World Nodes (Herbs and Mining Veins)
---------------------------------------------------------------------------
local HERB_PATTERNS = {
    -- High / multi-word herbs first
    { "mountain silversage", 280 },
    { "silversage", 280 },
    { "black lotus", 300 },
    { "bloodvine", 300 },
    { "icecap", 290 },
    { "plaguebloom", 285 },
    { "dreamfoil", 270 },
    { "golden sansam", 260 },
    { "gromsblood", 250 },
    { "ghost mushroom", 245 },
    { "blindweed", 235 },
    { "sungrass", 230 },
    { "arthas' tears", 220 },
    { "purple lotus", 210 },
    { "firebloom", 205 },
    { "wintersbite", 195 },
    { "khadgar's whisker", 185 },
    { "goldthorn", 170 },
    { "fadeleaf", 160 },
    { "liferoot", 150 },
    { "kingsblood", 125 },
    { "grave moss", 120 },
    { "wild steelbloom", 115 },
    { "steelbloom", 115 },
    { "bruiseweed", 100 },
    { "stranglekelp", 85 },
    { "briarthorn", 70 },
    { "mageroyal", 50 },
    { "earthroot", 15 },
    { "peacebloom", 1 },
    { "silverleaf", 1 },
    { "bloodpetal", 1 },
    { "glowcap", 1 },
    { "felweed", 300 },
    { "dreaming glory", 315 },
    { "ragveil", 325 },
    { "terocone", 325 },
    { "flame cap", 335 },
    { "netherbloom", 350 },
    { "nightmare vine", 365 },
    { "mana thistle", 375 },
}

local MINING_PATTERNS = {
    { "rich thorium", 275 },
    { "small thorium", 245 },
    { "thorium", 245 },
    { "dark iron", 230 },
    { "truesilver", 230 },
    { "mithril", 175 },
    { "gold", 155 },
    { "indurium", 150 },
    { "iron", 125 },
    { "lesser bloodstone", 75 },
    { "bloodstone", 75 },
    { "silver", 75 },
    { "incendicite", 65 },
    { "tin", 65 },
    { "copper", 1 },
    { "obsidian", 305 },
    { "fel iron", 300 },
    { "adamantite", 325 },
    { "khorium", 375 },
    { "nethercite", 350 },
}

local function lookupGatherNode(name, line2)
    if type(name) ~= "string" or name == "" then return nil end
    local cleanName = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s*(.-)%s*$", "%1"):lower()
    local cleanLine2 = (type(line2) == "string" and line2:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s*(.-)%s*$", "%1"):lower()) or ""

    -- Only the profession names: "herb"/"mine" also match NPC titles like <Herbalist> or "Undermine"
    local isHerbLine = cleanLine2:find("herbalism", 1, true)
    local isMiningLine = cleanLine2:find("mining", 1, true)

    local isMiningName = cleanName:find("vein", 1, true)
        or cleanName:find("deposit", 1, true)
        or cleanName:find("mineral", 1, true)
        or cleanName:find("seam", 1, true)
        or cleanName:find("slag", 1, true)
        or cleanName:find("lode", 1, true)

    if isMiningLine or isMiningName then
        for i = 1, #MINING_PATTERNS do
            local pat, req = MINING_PATTERNS[i][1], MINING_PATTERNS[i][2]
            local safePat = pat:gsub("%-", "%%-")
            if cleanName:find("%f[%a]" .. safePat .. "%f[%A]") then
                return "mining", req
            end
        end
        if isMiningLine then
            local num = cleanLine2:match("(%d+)")
            return "mining", tonumber(num) or 1
        end
    end

    if isHerbLine then
        for i = 1, #HERB_PATTERNS do
            local pat, req = HERB_PATTERNS[i][1], HERB_PATTERNS[i][2]
            local safePat = pat:gsub("%-", "%%-")
            if cleanName:find("%f[%a]" .. safePat .. "%f[%A]") then
                return "herbalism", req
            end
        end
        local num = cleanLine2:match("(%d+)")
        return "herbalism", tonumber(num) or 1
    end

    -- If line 2 doesn't mention herbalism, match known herbs by word boundary
    for i = 1, #HERB_PATTERNS do
        local pat, req = HERB_PATTERNS[i][1], HERB_PATTERNS[i][2]
        local safePat = pat:gsub("%-", "%%-")
        if cleanName:find("%f[%a]" .. safePat .. "%f[%A]") then
            return "herbalism", req
        end
    end

    return nil
end

local function isGatherReqLine(t)
    return t:find("herbalism", 1, true) or t:find("mining", 1, true) or t:find("requires", 1, true)
end

local function applyWorldGatherLine(tooltip, profName, reqSkill, playerSkill)
    -- Read the game's difficulty colour before we overwrite that line.
    local gameBand = gameGatherBand(tooltip, isGatherReqLine)
    local tag, r, g, b = getGatherTagAndColor(reqSkill, playerSkill, gameBand)
    local line2 = WFC.Safe(GameTooltipTextLeft2 and GameTooltipTextLeft2:GetText())
    local clean2 = (type(line2) == "string" and line2:lower()) or ""
    if type(line2) == "string" and (clean2:find("herbalism", 1, true) or clean2:find("mining", 1, true) or clean2:find("requires", 1, true)) then
        GameTooltipTextLeft2:SetText(profName .. " - " .. tag)
        GameTooltipTextLeft2:SetTextColor(r, g, b)
    else
        tooltip:AddDoubleLine(profName, tag, r, g, b, r, g, b)
    end
    tooltip:Show()
    return r, g, b
end

--- For NodeGlow: is this object name a mining vein? -> reqSkill, playerSkill, r, g, b
function Tips:MiningInfo(name)
    if not (Tips.settings and Tips.settings.mining) then return end
    local kind, req = lookupGatherNode(name, nil)
    if kind ~= "mining" or not req then return end
    local skill = getPlayerProfSkill(186, "Mining")
    if not skill then return end -- only if you have Mining
    local _, r, g, b = getGatherTagAndColor(req, skill, nil)
    return req, skill, r, g, b
end

--- For NodeGlow: is this object name an herb (and do you have Herbalism)? -> req, skill, r, g, b
function Tips:HerbInfo(name)
    if not (Tips.settings and Tips.settings.herbalism) then return end
    local kind, req = lookupGatherNode(name, nil)
    if kind ~= "herbalism" or not req then return end
    local skill = getPlayerProfSkill(182, "Herbalism")
    if not skill then return end
    local _, r, g, b = getGatherTagAndColor(req, skill, nil)
    return req, skill, r, g, b
end

--- Do you have this profession? (182 Herbalism, 186 Mining, 393 Skinning)
function Tips:HasProfession(skillLine, profName)
    return getPlayerProfSkill(skillLine, profName) ~= nil
end

--- For NodeGlow: a dead, skinnable creature you can skin? -> req, skill, r, g, b
function Tips:SkinInfo(unit)
    if not (Tips.settings and Tips.settings.aliveSkinning) then return end
    if not (unit and WFC.Safe(UnitExists(unit)) and WFC.Safe(UnitIsDead(unit))) then return end
    if WFC.Safe(UnitIsPlayer(unit)) or WFC.Safe(UnitPlayerControlled(unit)) then return end
    local skill = getPlayerProfSkill(393, "Skinning")
    if not skill then return end
    local cType = WFC.Safe(UnitCreatureType(unit))
    if not isSkinnableUnit(unit, cType) then return end
    local req = gatherReqSkillForLevel(WFC.Safe(UnitLevel(unit)))
    local _, r, g, b = getGatherTagAndColor(req, skill, nil)
    return req, skill, r, g, b
end

local function checkWorldObjectGathering(tooltip)
    if not tooltip or not WFC.Safe(tooltip:IsShown()) then return end
    -- When the client says what the tooltip holds, only Object tooltips can be nodes.
    if tooltip.GetTooltipData and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object then
        local ok, data = pcall(tooltip.GetTooltipData, tooltip)
        local dtype = ok and type(data) == "table" and WFC.Safe(data.type) or nil
        if dtype ~= nil and dtype ~= Enum.TooltipDataType.Object then return end
    end
    -- If it's a unit, item, or spell, it is NEVER a world gathering node. A secret value
    -- still means "present": unit tooltips often return a secret name, and treating that
    -- as "no unit" let NPC tooltips fall through to the herb/mining matcher.
    local function present(getter)
        if not getter then return false end
        local ok, a, b = pcall(getter, tooltip)
        if not ok then return false end
        return Compat.IsSecret(a) or Compat.IsSecret(b) or a ~= nil or b ~= nil
    end
    if present(tooltip.GetUnit) or present(tooltip.GetItem) or present(tooltip.GetSpell) then
        return
    end

    -- World objects in the 3D world are anchored to UIParent or WorldFrame, not action buttons / UI elements
    local owner = WFC.Safe(tooltip:GetOwner())
    if owner and owner ~= UIParent and owner ~= WorldFrame then
        return
    end

    local text1 = WFC.Safe(GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText())
    if type(text1) ~= "string" or text1 == "" then return end
    if tooltip._wfcGatherText == text1 then return end

    local text2 = WFC.Safe(GameTooltipTextLeft2 and GameTooltipTextLeft2:GetText())

    local kind, reqSkill = lookupGatherNode(text1, text2)
    if not kind or not reqSkill then return end

    tooltip._wfcGatherText = text1

    if kind == "herbalism" and Tips.settings and Tips.settings.herbalism then
        applyWorldGatherLine(tooltip, "Herbalism", reqSkill, (getPlayerProfSkill(182, "Herbalism")))
    elseif kind == "mining" and Tips.settings and Tips.settings.mining then
        local skill = getPlayerProfSkill(186, "Mining")
        local r, g, b = applyWorldGatherLine(tooltip, "Mining", reqSkill, skill)
        -- Sparkle + floating name above the vein (NodeGlow.lua), only for the main tooltip.
        if tooltip == GameTooltip and ns.NodeGlow and r then
            ns.NodeGlow:Show(text1, "Mining", reqSkill, skill, r, g, b)
        end
    end
end

---------------------------------------------------------------------------
-- Gatherable Items (Herbs & Ores in Bags / AH)
---------------------------------------------------------------------------
local HERB_ITEMS = {
    [765] = 1, [2447] = 1, [2449] = 15, [785] = 50, [2450] = 70, [3820] = 85,
    [2452] = 100, [3355] = 115, [3369] = 120, [3356] = 125, [3357] = 150,
    [3818] = 160, [3821] = 170, [3358] = 185, [3819] = 195, [4625] = 205,
    [8831] = 210, [8836] = 220, [8838] = 230, [8839] = 235, [8845] = 245,
    [8846] = 250, [13463] = 260, [13464] = 270, [13465] = 280, [13466] = 285,
    [13467] = 290, [13468] = 300, [19726] = 300,
}

local MINING_ITEMS = {
    [2770] = 1, [2771] = 65, [2775] = 75, [2772] = 125, [2776] = 155,
    [3858] = 175, [7911] = 230, [11370] = 230, [10620] = 245, [5833] = 150,
    [2835] = 1, [2836] = 65, [2838] = 125, [7912] = 175, [12365] = 245,
}

local function checkItemGathering(tooltip, itemId)
    if not itemId or tooltip._wfcItemGatherAdded then return end
    local herbReq = HERB_ITEMS[itemId]
    if herbReq and Tips.settings and Tips.settings.herbalism then
        tooltip._wfcItemGatherAdded = true
        local playerSkill, isAlt = getPlayerProfSkill(182, "Herbalism")
        addGatherLine(tooltip, "Herbalism", "Herbalism", herbReq, playerSkill, isAlt)
        tooltip:Show()
        return
    end
    local mineReq = MINING_ITEMS[itemId]
    if mineReq and Tips.settings and Tips.settings.mining then
        tooltip._wfcItemGatherAdded = true
        local playerSkill, isAlt = getPlayerProfSkill(186, "Mining")
        addGatherLine(tooltip, "Mining", "Mining", mineReq, playerSkill, isAlt)
        tooltip:Show()
        return
    end
end

local function setFont(tooltip, fs, fontObject)
    if not fs or not fontObject then return end
    local saved = restore[tooltip]
    if not saved then
        saved = {}
        restore[tooltip] = saved
    end
    if saved[fs] == nil then saved[fs] = fs:GetFontObject() or false end
    fs:SetFontObject(fontObject)
end

local function onCleared(tooltip)
    augmented[tooltip] = nil
    tooltip._wfcSkinningAdded = nil
    tooltip._wfcGatherAdded = nil
    tooltip._wfcItemGatherAdded = nil
    tooltip._wfcGatherText = nil
    local saved = restore[tooltip]
    if saved then
        for fs, original in pairs(saved) do
            if original then fs:SetFontObject(original) end
        end
        restore[tooltip] = nil
    end
    local rule = separators[tooltip]
    if rule then rule:Hide() end
end

local function drawSeparator(tooltip, line, hasTag)
    local rule = separators[tooltip]
    if not rule then
        rule = tooltip:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(1, 1, 1, 0.25)
        rule:SetHeight(1)
        separators[tooltip] = rule
    end
    rule:ClearAllPoints()
    rule:SetPoint("LEFT", fontStringAt(tooltip, "Left", line), "LEFT", 0, 0)
    if hasTag then
        rule:SetPoint("RIGHT", fontStringAt(tooltip, "Right", line), "LEFT", -6, 0)
    else
        rule:SetPoint("RIGHT", tooltip, "RIGHT", -10, 0)
    end
    rule:Show()
end

local function render(tooltip, lines)
    local body, head = WFC.Fonts:Get("tooltip"), WFC.Fonts:Get("tooltipHead")
    for _, line in ipairs(lines) do
        if line.separator then
            tooltip:AddDoubleLine(" ", line.right or " ")
            local n = tooltip:NumLines()
            setFont(tooltip, fontStringAt(tooltip, "Right", n), body)
            drawSeparator(tooltip, n, line.right ~= nil)
        else
            local c = line.color
            tooltip:AddLine(line.text, c.r, c.g, c.b, false)
            setFont(tooltip, fontStringAt(tooltip, "Left", tooltip:NumLines()), line.head and head or body)
        end
    end
    tooltip:Show() -- re-layout with the added lines
end

local function productName(itemId, spellId)
    local client = itemId and WFC.DB:GetItemClient(itemId)
    if client then return client.name end
    local card = itemId and WFC.DB:GetItem(itemId)
    return (card and card.name) or WFC.DB.Recipes:Name(spellId) or ("spell " .. tostring(spellId))
end

--- Required character level of a crafted item (nil when unknown or none).
local function productLevel(itemId)
    if not itemId then return nil end
    local client = WFC.DB:GetItemClient(itemId)
    local lvl = client and client.minLevel
    if not (type(lvl) == "number" and lvl > 0) then
        local card = WFC.DB:GetItem(itemId)
        lvl = card and card.reqLevel
    end
    return type(lvl) == "number" and lvl or nil
end

local function formatOptions(expanded)
    local s = Tips.settings
    return {
        expanded = expanded,
        showReasons = s.showReasons,
        maxLines = 4,
        money = Compat.FormatMoney,
        newTag = function(prefix) return WFC:NewTag(prefix) end,
        playerLevel = WFC.Player.level,
        charName = function(char) return char.name or "?" end,
        productName = productName,
        productLevel = productLevel,
    }
end

--- Lines WFC would add for an item right now (also used by specs and /wfc tips why).
function Tips:LinesFor(itemId, expanded)
    return Format.Lines(self:Evaluate(itemId), formatOptions(expanded))
end

local function onItem(tooltip, itemId)
    if not allowed[tooltip] then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local s = Tips.settings
    if not (s and s.enabled) or WFC:InCombat() then return end
    itemId = WFC.Safe(itemId)
    if type(itemId) ~= "number" or itemId <= 0 then return end
    current[tooltip] = itemId
    if augmented[tooltip] then return end -- the client may run post-calls more than once per fill
    local expanded = Compat.IsShiftKeyDown()
    if s.shiftOnly and not expanded then return end
    local ok, err = pcall(function()
        local lines = Tips:LinesFor(itemId, expanded)
        if #lines > 0 then render(tooltip, lines) end
        checkItemGathering(tooltip, itemId)
    end)
    augmented[tooltip] = itemId
    if not ok then geterrorhandler()(err) end
end

--- Refills shown tooltips (Shift pressed/released, item data arrived). Out of combat only.
local function refresh(matchItemId)
    if WFC:InCombat() then return end
    for tooltip in pairs(allowed) do
        local id = current[tooltip]
        if tooltip:IsShown() and id and (not matchItemId or id == matchItemId) then
            Compat.RefreshTooltip(tooltip)
        end
    end
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
local frames = {}
for _, name in ipairs(FRAME_NAMES) do
    local tooltip = _G[name]
    if tooltip then
        allowed[tooltip] = true
        frames[#frames + 1] = tooltip
        tooltip:HookScript("OnTooltipCleared", function(self)
            current[self] = nil
            self._wfcEnchantAdded = nil
            self._wfcSkinningAdded = nil
            self._wfcGatherAdded = nil
            self._wfcItemGatherAdded = nil
            self._wfcGatherText = nil
            onCleared(self)
        end)
    end
end

-- Unit gathering indicators (Skinning, Mining, Herbalism)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        local ok, err = pcall(checkUnitGathering, tooltip)
        if not ok then WFC:Debug("unit gathering:", err) end
    end)
elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetUnit", function(self)
        pcall(checkUnitGathering, self)
    end)
end

-- World Object gathering indicators (Herb and Mining nodes)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, function(tooltip)
        local ok, err = pcall(checkWorldObjectGathering, tooltip)
        if not ok then WFC:Debug("object gathering:", err) end
    end)
end
if GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnShow", function(self)
        pcall(checkWorldObjectGathering, self)
    end)
    local nextWorldCheck = 0
    GameTooltip:HookScript("OnUpdate", function(self)
        local now = GetTime()
        if now < nextWorldCheck then return end
        nextWorldCheck = now + 0.15
        pcall(checkWorldObjectGathering, self)
    end)
end

Tips.hookMethod = Compat.HookItemTooltips(function(tooltip, itemId)
    if not (tooltip.IsForbidden and tooltip:IsForbidden()) then
        local ok, err = pcall(addEnchantLine, tooltip, WFC.Safe(itemId))
        if not ok then WFC:Debug("enchant line:", err) end
    end
    onItem(tooltip, itemId)
end, frames)

WFC:RegisterEvent("MODIFIER_STATE_CHANGED", function(_, key)
    if key == "LSHIFT" or key == "RSHIFT" then refresh() end
end)

WFC:On("WFC_ITEM_LOADED", function(_, itemId) refresh(itemId) end)
