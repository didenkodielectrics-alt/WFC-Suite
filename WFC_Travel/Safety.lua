local _, ns = ...

-- Danger model for Safe vs Deathrun routing (plan.md §5.6). PURE: no WoW API.
-- Danger comes only from database NPCs (levels, elite, faction, spawns), never live units,
-- so secret values can't affect it (CoreRules R4). SafeRoute.lua feeds it mobs per sample.
--
-- mob = { name, level, elite, x, y }  (world yards; already known hostile to the player)
-- Evaluate(samples, mobsAt, playerLevel, greenRange) where samples = { {x, y}, ... } every
-- ~30 yd along a walk, and mobsAt(i) returns the mobs within MAX_RADIUS of sample i.

local Safety = {}
ns.Safety = Safety

Safety.SPACING = 30         -- yards between samples
Safety.MAX_RADIUS = 45      -- yards: widest aggro radius considered
Safety.K = 2                -- Safe mode cost = seconds x (1 + K x danger)
Safety.MAX_DANGER = 1.5     -- Safe mode skips walks above this average danger
Safety.WEIGHT = { grey = 0, green = 0, yellow = 0.2, orange = 0.6, red = 1.5 }
Safety.ELITE = 3
Safety.RANK = { grey = 0, green = 1, yellow = 2, orange = 3, red = 4 }

--- Level-difference category, the same scale as quest and mob colours (design §1.1).
function Safety.Category(mobLevel, playerLevel, greenRange)
    local diff = (mobLevel or playerLevel) - playerLevel
    if diff >= 5 then return "red" end
    if diff >= 3 then return "orange" end
    if diff >= -2 then return "yellow" end
    if -diff <= (greenRange or 5) then return "green" end
    return "grey"
end

--- Aggro radius in yards: ~20 yd, a yard more per level the mob is above you (5-45 yd).
function Safety.AggroRadius(mobLevel, playerLevel)
    return math.max(5, math.min(Safety.MAX_RADIUS, 20 + ((mobLevel or playerLevel) - playerLevel)))
end

--- { danger, blocked, perSample = {weight}, categories = {cat}, worst = mob, stretches, incomplete }
--- stretches = { { first, last, minLevel, maxLevel, name } } runs of orange/red samples.
function Safety.Evaluate(samples, mobsAt, playerLevel, greenRange)
    local per, cats, total, blocked, worst, worstWeight = {}, {}, 0, false, nil, 0
    for i, s in ipairs(samples) do
        local weight, top = 0, "grey"
        for _, mob in ipairs(mobsAt(i) or {}) do
            local dx, dy = mob.x - s.x, mob.y - s.y
            if dx * dx + dy * dy <= Safety.AggroRadius(mob.level, playerLevel) ^ 2 then
                local cat = Safety.Category(mob.level, playerLevel, greenRange)
                local w = Safety.WEIGHT[cat] * (mob.elite and Safety.ELITE or 1)
                weight = weight + w
                if Safety.RANK[cat] > Safety.RANK[top] then top = cat end
                if cat == "red" and mob.elite then blocked = true end
                if w > worstWeight then worst, worstWeight = mob, w end
            end
        end
        per[i], cats[i] = weight, top
        total = total + weight
    end
    local danger = #samples > 0 and total / #samples or 0
    -- Runs of dangerous samples, for the "risky stretch" summary and line colours.
    local stretches, current = {}, nil
    for i, cat in ipairs(cats) do
        if Safety.RANK[cat] >= Safety.RANK.orange then
            if not current then
                current = { first = i, last = i, count = 0 }
                stretches[#stretches + 1] = current
            end
            current.last = i
            for _, mob in ipairs(mobsAt(i) or {}) do
                local dx, dy = mob.x - samples[i].x, mob.y - samples[i].y
                if dx * dx + dy * dy <= Safety.AggroRadius(mob.level, playerLevel) ^ 2 then
                    current.minLevel = math.min(current.minLevel or mob.level, mob.level)
                    current.maxLevel = math.max(current.maxLevel or mob.level, mob.level)
                    current.name = current.name or mob.name
                end
            end
        else
            current = nil
        end
    end
    return { danger = danger, blocked = blocked or danger > Safety.MAX_DANGER, perSample = per,
        categories = cats, worst = worst, stretches = stretches }
end

--- Seconds as Safe mode weighs them, or nil when the walk is too dangerous to take.
function Safety.Cost(seconds, result)
    if not result then return seconds end
    if result.blocked then return nil end
    return seconds * (1 + Safety.K * result.danger)
end

--- Points every SPACING yards from a to b (both included), at most `cap` of them.
function Safety.Samples(a, b, cap)
    local dx, dy = b.x - a.x, b.y - a.y
    local length = math.sqrt(dx * dx + dy * dy)
    local n = math.max(1, math.min(cap or 400, math.ceil(length / Safety.SPACING)))
    local out = {}
    for i = 0, n do
        out[#out + 1] = { x = a.x + dx * i / n, y = a.y + dy * i / n, c = a.c }
    end
    return out
end

return Safety
