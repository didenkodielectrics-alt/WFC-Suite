local _, ns = ...
local WFC = WFC

-- /wfc travel: status, targets, and the in-game authoring tools (plan.md §5.3) for adding
-- docks, portals and paths the shipped data doesn't know yet (Forever's new regions).

local Travel, Flights, MapUI = ns.Travel, ns.Flights, ns.MapUI
local Compat = WFC.Compat

local MODES = { boat = true, zeppelin = true, tram = true, portal = true }

local function q(s) return ("%q"):format(s) end

--- Lua text for Data/Authored.lua (shipped nodes plus this account's recordings).
function Travel:ExportGraph()
    local nodes, links = {}, {}
    for _, src in ipairs({ ns.Data.Authored, self.authored }) do
        for name, n in pairs(src.nodes) do nodes[name] = n end
        for _, l in ipairs(src.links) do links[#links + 1] = l end
    end
    local names = {}
    for name in pairs(nodes) do names[#names + 1] = name end
    table.sort(names)
    local out = { "ns.Data.Authored = {", "    nodes = {" }
    for _, name in ipairs(names) do
        local n = nodes[name]
        out[#out + 1] = ("        [%s] = { map = %d, x = %.4f, y = %.4f, kind = %s%s%s },"):format(q(name), n.map, n.x, n.y,
            q(n.kind or "node"), n.faction and (", faction = " .. q(n.faction)) or "", n.isNew and ", isNew = true" or "")
    end
    out[#out + 1] = "    },"
    out[#out + 1] = "    links = {"
    for _, l in ipairs(links) do
        out[#out + 1] = ("        { a = %s, b = %s, mode = %s, seconds = %d%s%s },"):format(q(l.a), q(l.b), q(l.mode),
            l.seconds or 10, l.wait and (", wait = " .. l.wait) or "", l.oneWay and ", oneWay = true" or "")
    end
    out[#out + 1] = "    },"
    out[#out + 1] = "}"
    return table.concat(out, "\n")
end

local function status()
    local target = Travel:GetTarget()
    WFC:Print(("travel: %d flight points known · target: %s"):format(Flights:KnownCount(),
        target and (target.name or "set") or "none"))
    local lines = MapUI.Lines()
    print("  " .. lines.eta)
    for _, s in ipairs(lines.steps) do print("  " .. s) end
end

WFC:AddCommand("travel",
    "[show|hide|toggle|here|target <x> <y>|clear|mode safe|deathrun|path <questId>|dungeon <id>|sync|addnode <name> [kind] [A|H|B]"
        .. "|link <a> <b> <mode> <seconds> [wait] [oneway]|removenode <name>|exportgraph|options]",
    function(rest)
        local a, b = strsplit(" ", rest or "", 2)
        a = (a or ""):lower()
        if a == "" or a == "route" then
            status()
        elseif a == "show" then
            MapUI:ShowBox()
            Compat.OpenWorldMap()
        elseif a == "hide" then
            MapUI:HideBox()
        elseif a == "toggle" then
            MapUI:ToggleBox()
        elseif a == "here" then
            local map, x, y = Compat.GetPlayerMapPosition()
            WFC:Print(map and x and ("uiMap %d · %.2f, %.2f"):format(map, x * 100, y * 100) or "no position here")
        elseif a == "target" then
            local x, y = strsplit(" ", b or "", 2)
            local map = Compat.GetPlayerMapPosition()
            if map and tonumber(x) and tonumber(y) then
                Travel:SetTarget(map, tonumber(x) / 100, tonumber(y) / 100, ("%s, %s"):format(x, y))
            else
                WFC:Print("usage: /wfc travel target 45.2 61.0 (coordinates on your current zone map)")
            end
        elseif a == "clear" then
            Travel:ClearTarget()
        elseif a == "path" and tonumber(b) then
            Travel:PathToQuest(tonumber(b))
        elseif a == "dungeon" and tonumber(b) then
            Travel:PathToDungeon(tonumber(b))
        elseif a == "mode" and (b == "safe" or b == "deathrun") then
            Travel:SetMode(b)
            WFC:Print("travel mode:", b)
        elseif a == "sync" then
            WFC:Print(Flights:KnownCount(), "flight points known; open any flight master's map to sync")
        elseif a == "addnode" and b then
            local name, kind, faction = strsplit(" ", b, 3)
            local map, x, y = Compat.GetPlayerMapPosition()
            if not (map and x) then return WFC:Print("no position here") end
            Travel.authored.nodes[name] = { map = map, x = x, y = y, kind = kind or "node",
                faction = faction and faction:upper() or nil }
            Travel:RebuildGraph()
            WFC:Print(("node %s at uiMap %d %.2f, %.2f"):format(name, map, x * 100, y * 100))
        elseif a == "link" and b then
            local from, to, mode, seconds, wait, oneWay = strsplit(" ", b, 6)
            if not (from and to and MODES[mode or ""] and tonumber(seconds)) then
                return WFC:Print("usage: /wfc travel link <nodeA> <nodeB> boat|zeppelin|tram|portal <seconds> [wait] [oneway]")
            end
            table.insert(Travel.authored.links, { a = from, b = to, mode = mode, seconds = tonumber(seconds),
                wait = tonumber(wait), oneWay = oneWay == "oneway" or nil })
            Travel:RebuildGraph()
            WFC:Print(("linked %s -> %s by %s"):format(from, to, mode))
        elseif a == "removenode" and b then
            Travel.authored.nodes[b] = nil
            for i = #Travel.authored.links, 1, -1 do
                local l = Travel.authored.links[i]
                if l.a == b or l.b == b then table.remove(Travel.authored.links, i) end
            end
            Travel:RebuildGraph()
        elseif a == "exportgraph" then
            WFC.UI:ShowTextBox("Paste into Travel/Data/Authored.lua", Travel:ExportGraph())
        elseif a == "options" then
            if not WFC.UI:OpenSettings(Travel.category) then WFC:Print("options panel unavailable; use /wfc travel") end
        else
            WFC:Print("unknown option; see /wfc travel")
        end
    end)
