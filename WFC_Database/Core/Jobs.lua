local _, ns = ...
local WFC = ns.WFC

-- Time-sliced background jobs. A job is a function run in a coroutine; inside its
-- loops it calls WFC.Jobs:Checkpoint(), which yields once the frame budget is spent.
-- Jobs pause in combat and resume afterwards. Jobs:RunNow(name) finishes one
-- synchronously (for slash commands and tests).

local coroutine, debugprofilestop = coroutine, debugprofilestop
local InCombatLockdown = InCombatLockdown

local Jobs = {
    budgetMs = 1.5, -- per frame, out of combat
}
WFC.Jobs = Jobs

local queue = {}  -- sorted by priority, highest first
local byName = {}
local sliceStart = 0
local forcing = false

local frame = CreateFrame("Frame")
frame:Hide()

local function finish(job, ok, result)
    byName[job.name] = nil
    for i = 1, #queue do
        if queue[i] == job then
            table.remove(queue, i)
            break
        end
    end
    if job.onDone then
        local cbOk, err = pcall(job.onDone, ok, result)
        if not cbOk then geterrorhandler()(err) end
    end
end

-- Resumes a job once. Returns true when the job has ended.
local function step(job)
    local ok, result = coroutine.resume(job.co)
    if not ok then
        geterrorhandler()("WFC job '" .. job.name .. "' failed: " .. tostring(result))
        finish(job, false, result)
        return true
    end
    if coroutine.status(job.co) == "dead" then
        finish(job, true, result)
        return true
    end
    return false
end

--- Queues fn as a background job. onDone(ok, result) runs when it finishes.
--- A job with the same name already queued is returned instead of a duplicate.
function Jobs:Add(name, fn, onDone, priority)
    if byName[name] then return byName[name] end
    local job = { name = name, co = coroutine.create(fn), onDone = onDone, priority = priority or 0 }
    byName[name] = job
    local pos = #queue + 1
    for i = 1, #queue do
        if queue[i].priority < job.priority then
            pos = i
            break
        end
    end
    table.insert(queue, pos, job)
    frame:Show()
    return job
end

function Jobs:IsQueued(name)
    return byName[name] ~= nil
end

--- Call inside job loops. Cheap when there is budget left.
function Jobs:Checkpoint()
    if forcing then return end
    if debugprofilestop() - sliceStart > Jobs.budgetMs and coroutine.running() then
        coroutine.yield()
    end
end

--- Runs a queued job to completion right now. Returns false if no such job.
function Jobs:RunNow(name)
    local job = byName[name]
    if not job then return false end
    forcing = true
    while not step(job) do end
    forcing = false
    return true
end

frame:SetScript("OnUpdate", function()
    if InCombatLockdown() then return end
    sliceStart = debugprofilestop()
    while queue[1] and debugprofilestop() - sliceStart < Jobs.budgetMs do
        step(queue[1])
    end
    if not queue[1] then frame:Hide() end
end)
