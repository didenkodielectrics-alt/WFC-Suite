local _, ns = ...

-- "Optimal next quest" ranking (plan.md §4.3). PURE: no WoW API, no WFC.DB.
-- Candidates.lua turns the database and quest log into the inputs below; specs build
-- them by hand.
--
-- candidate = {
--   id, name, level, minLevel, xp, area, dungeon, repeatable, isNew,
--   state      = "available" | "active" | "complete",
--   elite, group                          -- from the client quest tag
--   starts     = { point, ... }           -- quest giver positions (only used when "available")
--   objectives = { { kind = "kill"|"item"|"object"|"other", remaining = n, points = { point, ... } }, ... }
--   ends       = { point, ... }           -- turn-in positions
--   chainXp, rewardCopper, repValue (reputation points), batched (objectives share an area with another active quest)
-- }
-- point = { c = continentId, x = worldYards, y = worldYards }   (c = nil: position unknown)
--
-- env = {
--   level, pos = point|nil, greenRange,
--   settings = { below, above, includeDungeons, hideGrey, hideElite, inGroup,
--                eliteFactor, redFactor, xpPerGold, xpPerRep, speed (yd/s), killSeconds },
--   travel = function(from, to) -> seconds|nil    -- WFC_Travel's estimate when loaded
-- }
--
-- Rank(candidates, env) -> { { candidate, score (xp per minute), minutes, value, xp, grey, red }, ... } best first.

local Scorer = {}
ns.Scorer = Scorer

Scorer.UNKNOWN_LEG = 90          -- seconds for a leg with an unknown end
Scorer.CONTINENT_PENALTY = 300   -- seconds for a leg that crosses continents (boat/zeppelin)
Scorer.ZONE_PENALTY = 150        -- extra seconds for cross-zone travel (passes, winding paths)
Scorer.DEFAULT_COUNT = { kill = 8, item = 6, object = 3, other = 1 } -- available quests: counts unknown
Scorer.UNIT_COST = { kill = 1, item = 1.5, object = 0.75, other = 3 } -- in kills

local function questLevel(c)
    if c.level and c.level > 0 then return c.level end
    return c.minLevel or 1
end

local FALLOFF = { [6] = 0.8, [7] = 0.6, [8] = 0.4, [9] = 0.2 }

--- Classic quest XP falloff for quests below the player's level.
function Scorer.LevelMod(questLvl, playerLevel)
    local diff = playerLevel - questLvl
    if diff <= 5 then return 1 end
    return FALLOFF[diff] or 0.1
end

local function distance(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

--- Seconds to get from a to b.
local function leg(env, a, b)
    if not a or not b then return Scorer.UNKNOWN_LEG end
    -- Travel knows boats, flights and islands (points without a continent), so ask it first.
    if env.travel then
        local t = env.travel(a, b)
        if t then return t end
    end
    if not a.c or not b.c then return Scorer.UNKNOWN_LEG end
    if a.c ~= b.c then return Scorer.CONTINENT_PENALTY end
    local dist = distance(a, b)
    local detour = 1.3
    local penalty = 0
    if a.map and b.map and a.map ~= b.map then
        detour = 2.0
        penalty = Scorer.ZONE_PENALTY
    end
    return (dist * detour) / env.settings.speed + penalty
end

--- Closest point to `from` (same continent and zone preferred); nil for an empty list.
local function nearest(from, points)
    if not points or #points == 0 then return nil end
    if not from or not from.c then return points[1] end
    local best, bestD
    for i = 1, #points do
        local p = points[i]
        if p.c == from.c then
            local d = distance(from, p)
            if from.map and p.map and from.map ~= p.map then
                d = d * 1.8 + 1000 -- prioritize same-zone points
            end
            if not bestD or d < bestD then best, bestD = p, d end
        end
    end
    return best or points[1]
end

--- Estimated seconds to finish the quest from the player's position.
function Scorer.Seconds(c, env)
    local s = env.settings
    local cur, total = env.pos, 0
    local function go(points)
        local p = nearest(cur, points)
        if p then
            total = total + leg(env, cur, p)
            cur = p
        elseif points then
            total = total + Scorer.UNKNOWN_LEG
        end
    end
    if c.state == "available" then go(c.starts) end
    if c.state ~= "complete" then
        -- Higher-level mobs take longer to kill.
        local hard = 1 + math.max(0, questLevel(c) - env.level) * 0.15
        for _, o in ipairs(c.objectives or {}) do
            local remaining = o.remaining or Scorer.DEFAULT_COUNT[o.kind] or 1
            if remaining > 0 then
                go(o.points)
                total = total + remaining * (Scorer.UNIT_COST[o.kind] or 1) * s.killSeconds * hard
            end
        end
    end
    go(c.ends)
    if c.batched then total = total * 0.85 end
    return math.max(60, total)
end

--- nil when the candidate is outside the window or filtered out; else the scored entry.
--- keepAll = true skips the window/filters (used to explain why a quest is not worth doing).
function Scorer.Score(c, env, keepAll)
    local s = env.settings
    local lvl = questLevel(c)
    local active = c.state ~= "available"
    local below = s.below or env.greenRange or 5
    local grey = lvl < env.level - (env.greenRange or below)
    local red = lvl >= env.level + 5
    if not active and not keepAll then
        if lvl < env.level - below or lvl > env.level + (s.above or 3) then return nil end
        if grey and s.hideGrey then return nil end
        if c.dungeon and not s.includeDungeons then return nil end
        if (c.elite or c.group) and not s.inGroup and s.hideElite then return nil end
    end
    local xp = (c.xp or 0) * Scorer.LevelMod(lvl, env.level)
    local value = xp + (c.chainXp or 0) * 0.3 + (c.rewardCopper or 0) / 10000 * (s.xpPerGold or 0)
        + (c.repValue or 0) * (s.xpPerRep or 0)
    if (c.elite or c.group) and not s.inGroup then value = value * (s.eliteFactor or 0.3) end
    if red then value = value * (s.redFactor or 0.5) end
    local minutes = Scorer.Seconds(c, env) / 60
    return { candidate = c, score = value / minutes, minutes = minutes, value = value, xp = xp, grey = grey, red = red }
end

function Scorer.Rank(candidates, env)
    local ranked = {}
    for i = 1, #candidates do
        local entry = Scorer.Score(candidates[i], env)
        if entry then ranked[#ranked + 1] = entry end
    end
    table.sort(ranked, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.minutes ~= b.minutes then return a.minutes < b.minutes end
        return a.candidate.id < b.candidate.id
    end)
    return ranked
end

local function median(list)
    local n = #list
    if n == 0 then return 0 end
    table.sort(list)
    if n % 2 == 1 then return list[(n + 1) / 2] end
    return (list[n / 2] + list[n / 2 + 1]) / 2
end

Scorer.FAR_FACTOR = 2.5      -- "far away" = this many times the typical quest time...
Scorer.FAR_MIN_MINUTES = 8   -- ...and at least this long
Scorer.LOW_YIELD = 0.4       -- "low yield" = below this fraction of the typical xp/min

--- Quests already accepted in the log that are NOT worth doing right now, each with plain-text reasons (worst first).
--- `ranked` = Rank(candidates, env); candidates the normal filters dropped are re-scored
--- with keepAll so they can be explained too. Only active quests in the log are returned. Turn-ins are never listed.
--- entry.reasons = { "text", ... }. env.checkpoint (optional) is called every few quests.
function Scorer.SkipList(candidates, env, ranked)
    local s = env.settings
    local solo = not s.inGroup
    local scores, minutes, seen, all = {}, {}, {}, {}
    for _, e in ipairs(ranked) do
        seen[e.candidate.id] = true
        if e.candidate.state == "active" then
            all[#all + 1] = e
        elseif e.candidate.state == "available" and e.score > 0 then
            scores[#scores + 1] = e.score
            minutes[#minutes + 1] = e.minutes
        end
    end
    local medScore, medMinutes = median(scores), median(minutes)
    for i, c in ipairs(candidates) do
        if c.state == "active" and not seen[c.id] then
            local e = Scorer.Score(c, env, true)
            if e then all[#all + 1] = e end
        end
        if env.checkpoint and i % 10 == 0 then env.checkpoint() end
    end

    local out = {}
    for _, e in ipairs(all) do
        local c = e.candidate
        if c.state == "active" then
            local lvl, reasons = questLevel(c), {}
            if e.red then
                reasons[#reasons + 1] = ("Too hard: %d levels above you"):format(lvl - env.level)
            end
            if e.grey then
                reasons[#reasons + 1] = ("Outleveled: only %d%% XP"):format(math.floor(Scorer.LevelMod(lvl, env.level) * 100 + 0.5))
            end
            if c.dungeon then
                reasons[#reasons + 1] = "Dungeon quest: needs a group"
            elseif (c.elite or c.group) and solo then
                reasons[#reasons + 1] = "Elite/group quest: needs a party"
            end
            if medMinutes > 0 and e.minutes > math.max(Scorer.FAR_MIN_MINUTES, medMinutes * Scorer.FAR_FACTOR) then
                reasons[#reasons + 1] = ("Far away: ~%d min (typical ~%d)"):format(
                    math.floor(e.minutes + 0.5), math.floor(medMinutes + 0.5))
            end
            if medScore > 0 and e.score < medScore * Scorer.LOW_YIELD and not e.grey and not e.red then
                reasons[#reasons + 1] = ("Low yield: %d xp/min (typical %d)"):format(
                    math.floor(e.score + 0.5), math.floor(medScore + 0.5))
            end
            if #reasons > 0 then
                e.reasons = reasons
                out[#out + 1] = e
            end
        end
    end
    table.sort(out, function(a, b)
        if #a.reasons ~= #b.reasons then return #a.reasons > #b.reasons end
        if a.score ~= b.score then return a.score < b.score end
        return a.candidate.id < b.candidate.id
    end)
    return out
end

return Scorer
