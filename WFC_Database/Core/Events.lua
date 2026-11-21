local _, ns = ...
local WFC = ns.WFC

-- One event frame for the whole addon, plus a message bus for cross-addon events
-- (WFC_DB_READY, WFC_INDEX_READY, WFC_ITEM_LOADED, ...).
-- Handler lists are copy-on-write, so a handler may (un)register during dispatch.

local pcall, geterrorhandler = pcall, geterrorhandler

local function dispatch(list, ...)
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end

local function withAdded(list, fn)
    local copy = {}
    if list then
        for i = 1, #list do
            if list[i] == fn then return list end
            copy[i] = list[i]
        end
    end
    copy[#copy + 1] = fn
    return copy
end

local function withRemoved(list, fn)
    if not list then return nil end
    local copy = {}
    for i = 1, #list do
        if list[i] ~= fn then copy[#copy + 1] = list[i] end
    end
    return #copy > 0 and copy or nil
end

---------------------------------------------------------------------------
-- Game events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local events = {}

frame:SetScript("OnEvent", function(_, event, ...)
    local list = events[event]
    if list then dispatch(list, event, ...) end
end)

--- fn(event, ...) is called for every `event`.
function WFC:RegisterEvent(event, fn)
    if not events[event] then
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then return end
    end
    events[event] = withAdded(events[event], fn)
end

function WFC:UnregisterEvent(event, fn)
    events[event] = withRemoved(events[event], fn)
    if not events[event] then pcall(frame.UnregisterEvent, frame, event) end
end

---------------------------------------------------------------------------
-- Messages (addon-to-addon)
---------------------------------------------------------------------------
local messages = {}

--- fn(message, ...) is called whenever `message` is fired.
function WFC:On(message, fn)
    messages[message] = withAdded(messages[message], fn)
end

function WFC:Off(message, fn)
    messages[message] = withRemoved(messages[message], fn)
end

function WFC:Fire(message, ...)
    local list = messages[message]
    if list then dispatch(list, message, ...) end
end
