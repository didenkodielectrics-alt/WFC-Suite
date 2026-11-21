local _, ns = ...
local WFC = ns.WFC

-- The stable public API (plan.md §2.7). Other WFC addons call only these.
-- Every getter returns memoized, already-normalized data: treat returned tables
-- as READ-ONLY (they are shared between callers).
--
-- Index-backed calls return nil, "pending" while their index is still building;
-- use WFC.DB.Indexes:WhenReady(name, fn) or listen for WFC_INDEX_READY.

local DB = WFC.DB
local Util = WFC.Util
local EMPTY = Util.EMPTY

local function pending() return nil, "pending" end

-- Quests ------------------------------------------------------------------
function DB:GetQuest(id) return DB.Quests:Card(id) end
function DB:GetQuestBrief(id) return DB.Quests:Brief(id) end
function DB:IsQuestAvailable(id, opts) return DB.Quests:IsAvailable(id, opts) end
function DB:GetQuestPositions(id) return DB.Quests:Positions(id) end

function DB:GetQuestRewards(id)
    local index = DB.Indexes:Get("questRewardItems")
    if not index then return pending() end
    return index[id] or EMPTY
end

function DB:GetQuestsInArea(areaId)
    local index = DB.Indexes:Get("questsByArea")
    if not index then return pending() end
    return index[areaId] or EMPTY
end

function DB:GetQuestsStartingIn(areaId)
    local index = DB.Indexes:Get("questsStartingIn")
    if not index then return pending() end
    return index[areaId] or EMPTY
end

--- Quest ids whose required level is in [minLevel, maxLevel] (a fresh list).
function DB:GetQuestsByLevel(minLevel, maxLevel)
    local index = DB.Indexes:Get("questsByLevel")
    if not index then return pending() end
    local list = {}
    for level = math.max(1, minLevel), maxLevel do
        local ids = index[level]
        if ids then
            for i = 1, #ids do list[#list + 1] = ids[i] end
        end
    end
    return list
end

-- Dungeons ----------------------------------------------------------------
function DB:GetDungeons() return DB.Zones:GetDungeons() end
function DB:GetDungeon(id) return DB.Zones:GetDungeon(id) end

--- Level range, bosses and the dungeon's own map; nil, "pending" until the NPC index is built.
function DB:GetDungeonDetails(dungeonId) return DB.Dungeons:Details(dungeonId) end

function DB:GetDungeonQuests(dungeonId)
    local index = DB.Indexes:Get("questsByDungeon")
    if not index then return pending() end
    return index[dungeonId] or EMPTY
end

-- Items -------------------------------------------------------------------
function DB:GetItem(id) return DB.Items:Card(id) end
function DB:GetItemClient(id) return DB.Items:Client(id) end
function DB:GetQuestsUsingItem(id) return DB.Items:Card(id).usedByQuests or EMPTY end
function DB:GetRecipesUsingItem(id) return DB.Items:Card(id).reagentFor end

--- { drops = {{npc, rate}}, vendors = {npcIds}, craftedBy = {spellIds}, containers = {itemIds} }
function DB:GetItemSources(id)
    local card = DB.Items:Card(id)
    return {
        drops = DB.Drops:ForItem(id),
        objects = card.dropObjects or EMPTY,
        vendors = card.vendors or EMPTY,
        craftedBy = card.craftedBy,
        containers = card.dropItems or EMPTY,
    }
end

-- Recipes -----------------------------------------------------------------
function DB:GetRecipe(spellId) return DB.Recipes:Get(spellId) end
function DB:GetRecipes() return DB.Recipes:All() end

-- NPCs / objects / zones --------------------------------------------------
function DB:GetNpc(id) return DB.Npcs:Card(id) end
function DB:GetNpcSpawns(id) return DB.Npcs:Spawns(id) end
function DB:GetObject(id) return DB.Objects:Card(id) end
function DB:GetObjectSpawns(id) return DB.Objects:Spawns(id) end
function DB:AreaToUiMap(areaId) return DB.Zones:AreaToUiMap(areaId) end

--- Aggressive NPC spawns near a map point; nil, "pending" until npcsByArea is built.
function DB:GetHostileNpcsNear(uiMapId, x, y, radius, side)
    local list = DB.Npcs:HostileNear(uiMapId, x, y, radius, side or WFC.Player.side)
    if not list then return pending() end
    return list
end

-- new! --------------------------------------------------------------------
function DB:IsNew(kind, id) return DB.New:IsNew(kind, id) end

-- Prices ------------------------------------------------------------------
--- auctionCopper|nil, vendorCopper|nil, providerKey|nil, ageDays|nil
function DB:GetPrice(itemId)
    local ah, key, age = DB.Prices:Auction(itemId)
    return ah, DB.Prices:Vendor(itemId), key, age
end
