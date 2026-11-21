local _, ns = ...
local WFC = ns.WFC

-- Recipes: curated seed (Data/Recipes.lua) merged with harvested recipes.
-- Indexes are rebuilt whenever the merged set changes and are DENORMALIZED:
-- an item's "reagent for" entries carry the profession, count and product, so
-- a tooltip needs one lookup and no follow-up recipe reads.

local Data = ns.Data
local Util = WFC.Util
local Push = Util.Push

local Recipes = WFC.DB:NewSection("Recipes")

Recipes.PROFESSION_NAMES = {
    [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy",
    [182] = "Herbalism", [185] = "Cooking", [186] = "Mining", [197] = "Tailoring",
    [202] = "Engineering", [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning",
}

local recipes = {}      -- [spellId] = recipe
local byReagent = {}    -- [itemId] = { {spellId, prof, profName, count, product, learn}, ... }
local byProduct = {}    -- [itemId] = { spellId, ... }
local byRecipeItem = {} -- [recipeItemId] = spellId

local function harvested()
    local g = WFC_DB_Global
    return g and g.harvest and g.harvest.recipes or Util.EMPTY
end

local function normalize(spellId, seed, harvest)
    seed, harvest = seed or Util.EMPTY, harvest or Util.EMPTY
    -- A harvested prof of 0 (Forever's profession window reports no ID for some professions)
    -- must not override the shipped data: 0 is truthy in Lua.
    local hProf = type(harvest.prof) == "number" and harvest.prof > 0 and harvest.prof or nil
    local prof = hProf or seed.prof
    local product = harvest.product or seed.product
    -- Data/Recipes.lua marks nearly every recipe "trainer" and rarely knows the teaching item.
    -- Data/RecipeItems.lua (from QuestieDB's recipe items) fills that in: a recipe with a
    -- teaching item is NOT a trainer recipe.
    local linked = Data.RecipeItems and Data.RecipeItems[spellId]
    local recipeItems = type(linked) == "table" and linked or nil
    if seed.recipeItem and linked and not recipeItems and linked ~= seed.recipeItem then
        recipeItems = { seed.recipeItem, linked }
    end
    local recipeItem = seed.recipeItem or (recipeItems and recipeItems[1]) or linked or harvest.recipeItem
    local r = {
        spellId = spellId,
        prof = prof,
        profName = harvest.profName or Recipes.PROFESSION_NAMES[prof],
        name = harvest.name,
        product = product and { id = product[1], min = product[2] or 1, max = product[3] or product[2] or 1 } or nil,
        reagents = {},
        skill = seed.skill or harvest.skill, -- { learn, orange, yellow, green, grey }
        recipeItem = recipeItem,
        recipeItems = recipeItems,           -- every item that teaches it, when there are several
        trainer = (not recipeItem) and (seed.trainer or harvest.trainer) or nil,
        auto = seed.auto,                    -- learned automatically with the profession
        lastDifficulty = harvest.difficulty, -- snapshot from the profession window
    }
    local s = r.skill
    local learnRank = (s and s[1] and s[1] > 1 and s[1])
    if not learnRank and not r.auto and s and s[3] and s[3] > 45 then
        learnRank = math.max(1, math.floor((s[3] - 23) / 5) * 5)
    end
    r.learnRank = learnRank or 1
    local reagents = harvest.reagents or seed.reagents
    if reagents then
        for i = 1, #reagents do
            r.reagents[i] = { id = reagents[i][1], count = reagents[i][2] or 1 }
        end
    end
    local override = Data.NewOverrides.recipe[spellId]
    if override ~= nil then
        r.isNew = override
    else
        r.isNew = seed.isNew == true
    end
    return r
end

--- Rebuilds the merged recipe set and every recipe index. Cheap (hundreds of recipes).
function Recipes:Rebuild()
    recipes, byReagent, byProduct, byRecipeItem = {}, {}, {}, {}
    local seedData, harvestData = Data.Recipes or Util.EMPTY, harvested()
    for spellId, seed in pairs(seedData) do
        recipes[spellId] = normalize(spellId, seed, harvestData[spellId])
    end
    for spellId, harvest in pairs(harvestData) do
        if not recipes[spellId] then recipes[spellId] = normalize(spellId, nil, harvest) end
    end
    for spellId, r in pairs(recipes) do
        local productId = r.product and r.product.id
        for i = 1, #r.reagents do
            local reagent = r.reagents[i]
            Push(byReagent, reagent.id, {
                spellId = spellId,
                prof = r.prof,
                profName = r.profName,
                count = reagent.count,
                product = productId,
                learn = r.learnRank or (r.skill and r.skill[1]),
            })
        end
        if productId then Push(byProduct, productId, spellId) end
        -- Several spells can share a name (and so a teaching item); the lowest spellId is the
        -- original recipe, so it wins and the result doesn't depend on pairs() order.
        if r.recipeItems then
            for i = 1, #r.recipeItems do
                local itemId = r.recipeItems[i]
                if not byRecipeItem[itemId] or spellId < byRecipeItem[itemId] then byRecipeItem[itemId] = spellId end
            end
        elseif r.recipeItem then
            local itemId = r.recipeItem
            if not byRecipeItem[itemId] or spellId < byRecipeItem[itemId] then byRecipeItem[itemId] = spellId end
        end
    end
    WFC:Fire("WFC_RECIPES_CHANGED")
end

function Recipes:Init()
    self:Rebuild()
end

function Recipes:Login()
    self:RecordCharacter()
end

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------
function Recipes:Get(spellId)
    return recipes[spellId]
end

function Recipes:All()
    return recipes
end

function Recipes:Name(spellId)
    local r = recipes[spellId]
    if r and r.name then return r.name end
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellId) end
end

--- Denormalized "reagent for" entries for an item (shared table, read-only).
function Recipes:UsingReagent(itemId)
    return byReagent[itemId] or Util.EMPTY
end

--- spellIds that create the item (shared table, read-only).
function Recipes:Producing(itemId)
    return byProduct[itemId] or Util.EMPTY
end

function Recipes:TaughtBy(recipeItemId)
    return byRecipeItem[recipeItemId]
end

--- Skill-up colour for a recipe at a skill rank: "orange" | "yellow" | "green" | "grey",
--- "unavailable" below the learn rank, or the last harvested colour when thresholds are unknown.
function Recipes:Difficulty(spellId, rank)
    local r = recipes[spellId]
    if not r then return nil end
    local s = r.skill
    if not s or not rank then return r.lastDifficulty end
    local learn = r.learnRank or (s[1] and s[1] > 1 and s[1]) or 1
    if rank < learn then return "unavailable" end
    if s[3] and rank < s[3] then return "orange" end
    if s[4] and rank < s[4] then return "yellow" end
    if s[5] and rank < s[5] then return "green" end
    return "grey"
end

---------------------------------------------------------------------------
-- Account-wide professions (cache; refreshed whenever each character logs in)
---------------------------------------------------------------------------
local function charTable(charKey)
    local chars = WFC_DB_Global.chars
    local t = chars[charKey]
    if not t then
        t = { recipes = {}, professions = {} }
        chars[charKey] = t
    end
    return t
end

function Recipes:RecordCharacter()
    local P = WFC.Player
    if not P.charKey then return end
    local t = charTable(P.charKey)
    t.faction = P.faction
    t.class = P.classFile
    t.level = P.level
    t.professions = P.professions
    if UnitFullName then
        local first, last = UnitFullName("player")
        if first and last and last ~= "" then
            t.fullName = first .. " " .. last
        elseif first then
            t.fullName = first
        end
    end
    t.seen = time()
end

--- Called by the Harvester with every recipe the character knows in one profession.
function Recipes:RecordKnown(spellIds)
    local P = WFC.Player
    if not P.charKey then return end
    local known = charTable(P.charKey).recipes
    for i = 1, #spellIds do known[spellIds[i]] = true end
end

--- Characters (same faction by default) that know a recipe:
--- { {charKey, rank}, ... } where rank is their skill in that profession.
function Recipes:KnownBy(spellId, anyFaction)
    local r = recipes[spellId]
    local result = {}
    local faction = WFC.Player.faction
    for charKey, t in pairs(WFC_DB_Global.chars) do
        if t.recipes and t.recipes[spellId] and (anyFaction or t.faction == faction) then
            local prof = r and r.prof and t.professions and t.professions[r.prof]
            result[#result + 1] = { charKey = charKey, rank = prof and prof.rank }
        end
    end
    return result
end

function Recipes:Stats()
    return { recipes = Util.Count(recipes), reagents = Util.Count(byReagent) }
end

WFC:On("WFC_HARVEST_RECIPES", function()
    Recipes:Rebuild()
end)

-- Keep this character's account-wide entry current (alts read it for CRAFT advice).
WFC:On("WFC_PLAYER_CHANGED", function(_, field)
    if (field == "professions" or field == "level") and WFC_DB_Global then
        Recipes:RecordCharacter()
    end
end)
