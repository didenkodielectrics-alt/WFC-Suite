local _, ns = ...
local WFC = ns.WFC

-- /wfc slash commands. Other WFC addons add subcommands with WFC:AddCommand.

local commands = {}
local help = {}

--- fn(rest) handles "/wfc <name> <rest>".
function WFC:AddCommand(name, usage, fn)
    commands[name] = fn
    help[#help + 1] = "/wfc " .. name .. (usage ~= "" and (" " .. usage) or "")
end

local function dump(label, t, depth)
    depth = depth or 0
    if depth > 2 then return end
    local indent = string.rep("  ", depth)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    if label then print(indent .. "|cff4dd9ff" .. label .. "|r") end
    for _, k in ipairs(keys) do
        local v = t[k]
        if type(v) == "table" then
            local n = WFC.Util.Count(v)
            if n <= 8 and depth < 2 then
                dump(tostring(k) .. ":", v, depth + 1)
            else
                print(indent .. "  " .. tostring(k) .. " = {" .. n .. " entries}")
            end
        else
            print(indent .. "  " .. tostring(k) .. " = " .. tostring(v))
        end
    end
end

---------------------------------------------------------------------------
-- /wfc db ...
---------------------------------------------------------------------------
local function dbCommand(rest)
    local DB = WFC.DB
    local sub, a, b = strsplit(" ", rest or "", 3)
    sub = (sub or ""):lower()
    if sub == "" or sub == "stats" then
        WFC:Print(DB.Source:Status(), DB.ready and "(ready)" or "(not ready)")
        dump(nil, DB:Stats())
    elseif sub == "quest" then
        local card = DB:GetQuest(tonumber(a))
        if card then dump("Quest " .. a, card) else WFC:Print("unknown quest", a) end
        if card then WFC:Print("available:", DB:IsQuestAvailable(card.id)) end
    elseif sub == "item" then
        dump("Item " .. tostring(a), DB:GetItem(tonumber(a)))
    elseif sub == "npc" then
        local card = DB:GetNpc(tonumber(a))
        if card then dump("NPC " .. a, card) else WFC:Print("unknown npc", a) end
    elseif sub == "object" then
        local card = DB:GetObject(tonumber(a))
        if card then dump("Object " .. a, card) else WFC:Print("unknown object", a) end
    elseif sub == "recipe" then
        local r = DB:GetRecipe(tonumber(a))
        if r then dump("Recipe " .. a, r) else WFC:Print("unknown recipe", a) end
    elseif sub == "new" then
        WFC:Print(a, b, "new! =", tostring(DB:IsNew(a, tonumber(b))))
    elseif sub == "newaudit" then
        WFC:Print("auditing quests in the background...")
        DB.New:Audit(function(list)
            WFC:Print(#list .. " quests disagree with the ID hint (showing up to 20):")
            for i = 1, math.min(20, #list) do
                local brief = DB:GetQuestBrief(list[i][1])
                print(("  %d %s  new!=%s"):format(list[i][1], brief and brief.name or "?", tostring(list[i][2])))
            end
        end)
    elseif sub == "index" then
        if a == "rebuild" then
            DB.Indexes:Rebuild(b)
            WFC:Print("rebuilding", b or "all indexes", "in the background")
        else
            for _, s in ipairs(DB.Indexes:Status()) do
                print(("  %s: %s (%d)"):format(s.name, s.ready and "|cff40c040ready|r" or "|cffffff00building|r", s.entries))
            end
        end
    elseif sub == "price" then
        local id = tonumber(a)
        local ah, vendor, key, age = DB:GetPrice(id)
        WFC:Print(("item %s: AH %s (%s, %s days), vendor %s"):format(tostring(id),
            ah and GetMoneyString(ah) or "-", tostring(key), tostring(age), vendor and GetMoneyString(vendor) or "-"))
    else
        WFC:Print("usage: /wfc db [stats|quest|item|npc|object|recipe <id>|new <kind> <id>|newaudit|index [rebuild [name]]|price <id>]")
    end
end

WFC:AddCommand("db", "[stats|quest|item|npc|object|recipe|new|newaudit|index|price] ...", dbCommand)

WFC:AddCommand("harvest", "[on|off|stats|flush|wipe]", function(rest)
    local sub = (rest or ""):lower()
    local settings = WFC_DB_Global.settings
    if sub == "on" or sub == "off" then
        settings.harvest = sub == "on"
        WFC:Print("harvester", sub)
    elseif sub == "flush" then
        WFC.UI:ShowTextBox("WFC harvest (copy and keep this)", WFC.Harvester:ExportString())
    elseif sub == "wipe" then
        WFC.Harvester:Wipe()
        WFC:Print("harvest data wiped")
    else
        dump("Harvester", WFC.Harvester:Stats())
    end
end)

WFC:AddCommand("export", "", function()
    WFC.UI:ShowTextBox("WFC export (copy and keep this)", WFC.Store:Export())
end)

WFC:AddCommand("import", "", function()
    WFC.UI:ShowTextBox("WFC import (paste an export string)", "", function(text)
        local ok, err = WFC.Store:Import(text)
        WFC:Print(ok and "import complete" or ("import failed: " .. tostring(err)))
    end)
end)

WFC:AddCommand("selftest", "", function()
    WFC:Print("self-test, build " .. tostring(WFC.Compat.build))
    for _, probe in ipairs(WFC.Compat.Probe()) do
        print(("  %s %s"):format(probe[2] and "|cff40c040PASS|r" or "|cffff1a1aFAIL|r", probe[1]))
    end
    print("  " .. WFC.DB.Source:Status())
end)

WFC:AddCommand("debug", "", function()
    local s = WFC_DB_Global.settings
    s.debug = not s.debug
    WFC:Print("debug", s.debug and "on" or "off")
end)

SLASH_WFC1 = "/wfc"
SlashCmdList.WFC = function(msg)
    local name, rest = strsplit(" ", msg or "", 2)
    name = (name or ""):lower()
    local fn = commands[name]
    if fn then
        fn(rest)
    elseif name == "show" or name == "hide" or name == "toggle" then
        if commands["quests"] then
            commands["quests"](name .. (rest and (" " .. rest) or ""))
        elseif commands["travel"] then
            commands["travel"](name .. (rest and (" " .. rest) or ""))
        end
    elseif name == "" then
        if commands["quests"] then
            commands["quests"]("toggle")
        else
            WFC:Print("commands:")
            for _, line in ipairs(help) do print("  " .. line) end
        end
    else
        WFC:Print("commands:")
        for _, line in ipairs(help) do print("  " .. line) end
    end
end
