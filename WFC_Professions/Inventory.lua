local _, ns = ...
local WFC = WFC

-- Inventory & Character Roster Bridge.
-- Merges WFC_DB_Global.chars (professions, skill ranks, learned recipes) with
-- BagBrother's BrotherBags SavedVariables (bags, bank tabs, mail, equipped items)
-- and a live container scan fallback for the active character.

local Inventory = {}
ns.Inventory = Inventory
WFC.Professions.Inventory = Inventory

local Compat = WFC.Compat -- was an undefined global, so the profession fallback never ran

--- Shallow copy. Character entries must not alias WFC.Player.professions or the saved
--- WFC_DB_Global tables: merging duplicate characters writes into entry tables.
local function copy(t)
    local out = {}
    if type(t) == "table" then for k, v in pairs(t) do out[k] = v end end
    return out
end

local CLASS_COLORS = {
    WARRIOR     = "ffc79c6e",
    PALADIN     = "fff58cba",
    HUNTER      = "ffabd473",
    ROGUE       = "fffff569",
    PRIEST      = "ffffffff",
    DEATHKNIGHT = "ffc41f3b",
    SHAMAN      = "ff0070de",
    MAGE        = "ff40c7eb",
    WARLOCK     = "ff8787ed",
    MONK        = "ff00ff96",
    DRUID       = "ffff7d0a",
    DEMONHUNTER = "ffa330c9",
    EVOKER      = "ff33937f",
}

function Inventory.ClassColorCode(classFile)
    if classFile and CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFile] and CUSTOM_CLASS_COLORS[classFile].colorStr then
        return "|c" .. CUSTOM_CLASS_COLORS[classFile].colorStr
    end
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] and RAID_CLASS_COLORS[classFile].colorStr then
        return "|c" .. RAID_CLASS_COLORS[classFile].colorStr
    end
    return "|c" .. (CLASS_COLORS[classFile or ""] or "ffeeeeee")
end

function Inventory.ColorizeName(name, classFile)
    return Inventory.ClassColorCode(classFile) .. tostring(name or "?") .. "|r"
end

---------------------------------------------------------------------------
-- BagBrother Item Entry Parser
---------------------------------------------------------------------------
local function parseBagBrotherEntry(data)
    if not data then return nil, 0 end
    local num = tonumber(data)
    if num then return num, 1 end
    if type(data) ~= "string" then return nil, 0 end
    local id = tonumber(data:match("^(%d+)")) or tonumber(data:match("item:(%d+)")) or tonumber(data:match("(%d+)"))
    if not id then return nil, 0 end
    local count = tonumber(data:match(";(%d+)$")) or 1
    return id, count
end

local function addItemsFromList(target, list)
    if type(list) ~= "table" then return end
    local items = list.items or list
    if type(items) ~= "table" then return end
    for slot, data in pairs(items) do
        if type(slot) == "number" then
            local id, count = parseBagBrotherEntry(data)
            if id and count > 0 then
                target[id] = (target[id] or 0) + count
            end
        end
    end
end

local function extractOwnerCounts(ownerData)
    local counts = {
        bags = {},
        bank = {},
        mail = {},
        equip = {},
        total = {},
    }
    if type(ownerData) ~= "table" then return counts end

    for k, v in pairs(ownerData) do
        if type(k) == "number" and type(v) == "table" and type(v.items) == "table" then
            -- In BagBrother on Forever:
            -- k = 0..5 (without bankType) are backpack & character bags.
            -- k = -1 or k >= 6 or v.bankType ~= nil are bank / bank tabs.
            if v.bankType ~= nil or k < 0 or k > 5 then
                addItemsFromList(counts.bank, v)
            else
                addItemsFromList(counts.bags, v)
            end
        end
    end

    if type(ownerData.mail) == "table" then
        addItemsFromList(counts.mail, ownerData.mail)
    end
    if type(ownerData.equip) == "table" then
        addItemsFromList(counts.equip, ownerData.equip)
    end

    -- Combine bags + bank + mail into total crafting material pool
    for id, n in pairs(counts.bags) do counts.total[id] = (counts.total[id] or 0) + n end
    for id, n in pairs(counts.bank) do counts.total[id] = (counts.total[id] or 0) + n end
    for id, n in pairs(counts.mail) do counts.total[id] = (counts.total[id] or 0) + n end

    return counts
end

---------------------------------------------------------------------------
-- Live Container Fallback for Current Character
---------------------------------------------------------------------------
-- Container API: Forever is Retail-based, so only C_Container exists. The Classic globals
-- are kept as a fallback for the Classic Era interface (11509) this TOC also declares.
local numSlotsFn = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local itemInfoFn = C_Container and C_Container.GetContainerItemInfo
local itemIdFn = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
local itemLinkFn = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink

local function plainNumber(v)
    if Compat and Compat.IsSecret and Compat.IsSecret(v) then return nil end
    return type(v) == "number" and v or nil
end

--- Adds every item in container `bag` into `into` ([itemId] = count).
local function readContainer(bag, into)
    if not numSlotsFn then return end
    local ok, n = pcall(numSlotsFn, bag)
    n = ok and plainNumber(n) or 0
    for slot = 1, n do
        local itemID, qty
        if itemInfoFn then
            local ok2, info = pcall(itemInfoFn, bag, slot)
            if ok2 and type(info) == "table" then
                itemID = plainNumber(info.itemID)
                qty = plainNumber(info.stackCount)
            end
        end
        if not itemID and itemIdFn then
            local ok2, id = pcall(itemIdFn, bag, slot)
            if ok2 then itemID = plainNumber(id) end
        end
        if not itemID and itemLinkFn then
            local ok2, link = pcall(itemLinkFn, bag, slot)
            if ok2 and type(link) == "string" and not (Compat and Compat.IsSecret(link)) then
                itemID = tonumber(link:match("item:(%d+)"))
            end
        end
        if not qty and not itemInfoFn and GetContainerItemInfo then -- Classic: (texture, count, ...)
            local ok2, _, count = pcall(GetContainerItemInfo, bag, slot)
            if ok2 then qty = plainNumber(count) end
        end
        if itemID and itemID > 0 then
            into[itemID] = (into[itemID] or 0) + ((qty and qty > 0) and qty or 1)
        end
    end
end

--- Carried bags: backpack, bags 1-4 and (Retail/Forever) the reagent bag, where most
--- crafting materials live. The old 0..NUM_BAG_SLOTS loop skipped the reagent bag.
local function carriedBagIds()
    local ids, seen = {}, {}
    local function add(b) if b and not seen[b] then seen[b] = true; ids[#ids + 1] = b end end
    for b = 0, NUM_BAG_SLOTS or 4 do add(b) end
    local BI = Enum and Enum.BagIndex
    if BI and BI.ReagentBag then add(BI.ReagentBag) end
    return ids, seen
end

--- Bank containers. Forever uses Retail bank tabs (C_Bank); the legacy bank (-1) and bank bags
--- only exist on Classic. The old code scanned NUM_BAG_SLOTS+1.., which on Forever is the
--- reagent bag (counted as "bank") and then the tabs only by coincidence.
local function bankBagIds(carried)
    local ids = {}
    local BI = Enum and Enum.BagIndex
    if C_Bank and C_Bank.FetchPurchasedBankTabIDs and Enum and Enum.BankType and Enum.BankType.Character then
        local ok, tabs = pcall(C_Bank.FetchPurchasedBankTabIDs, Enum.BankType.Character)
        if ok and type(tabs) == "table" then
            for _, id in ipairs(tabs) do ids[#ids + 1] = id end
        end
        if #ids > 0 then return ids end
    end
    if BI and BI.CharacterBankTab_1 then
        for i = 1, 6 do
            local id = BI["CharacterBankTab_" .. i]
            if id then ids[#ids + 1] = id end
        end
        return ids
    end
    -- Classic layout
    ids[1] = (BI and BI.Bank) or BANK_CONTAINER or -1
    local first = (NUM_BAG_SLOTS or 4) + 1
    for b = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do
        if not carried[b] then ids[#ids + 1] = b end
    end
    return ids
end

-- BankFrame:IsShown() is false while Bagnon/BagBrother replace the bank window,
-- so bank state is tracked from the events instead.
local bankOpen = false
WFC:RegisterEvent("BANKFRAME_OPENED", function() bankOpen = true end)
WFC:RegisterEvent("BANKFRAME_CLOSED", function() bankOpen = false end)

local function scanCurrentCharacterLive()
    local g = (ns.Professions and ns.Professions.global) or _G["WFC_Professions_Global"]
    local curFirst = UnitName and UnitName("player")
    local f2, last = UnitFullName and UnitFullName("player")
    local curFull = (f2 and last and last ~= "" and (f2 .. " " .. last)) or curFirst

    local bags = {}
    local carried, carriedSet = carriedBagIds()
    for _, bag in ipairs(carried) do readContainer(bag, bags) end

    local bank = nil
    if bankOpen or (BankFrame and BankFrame:IsShown()) then
        bank = {}
        for _, bag in ipairs(bankBagIds(carriedSet)) do readContainer(bag, bank) end
    end

    if g and g.inventories then
        local names = {}
        if curFull then names[#names + 1] = curFull end
        if curFirst and curFirst ~= curFull then names[#names + 1] = curFirst end
        for _, n in ipairs(names) do
            local inv = g.inventories[n] or { bags = {}, bank = {}, mail = {}, equip = {} }
            inv.bags = bags
            if bank then inv.bank = bank end
            g.inventories[n] = inv
        end
    end

    return bags, bank
end

---------------------------------------------------------------------------
-- Unified Character Roster & Inventory Cache
---------------------------------------------------------------------------
local cachedChars = nil
local cachedTotals = nil
local cachedByItem = nil

function Inventory:Invalidate()
    cachedChars = nil
    cachedTotals = nil
    cachedByItem = nil
end

local function currentPlayerNames()
    local first = UnitName("player")
    local f2, last = UnitFullName and UnitFullName("player")
    local full = (f2 and last and last ~= "" and (f2 .. " " .. last)) or first
    return first, full
end

--- Builds and returns the merged list of all characters on the realm:
--- {
---   {
---     key, name, shortName, class, level, faction, money, isCurrent,
---     professions = { [skillLineId] = { name, rank, max } },
---     recipes = { [spellId] = true },
---     counts = { bags = {}, bank = {}, mail = {}, equip = {}, total = {} },
---   }, ...
--- }
function Inventory:GetCharacters()
    if cachedChars then return cachedChars end

    local curFirst, curFull = currentPlayerNames()
    local dbChars = (WFC_DB_Global and WFC_DB_Global.chars) or {}

    -- Collect BagBrother character tables (excluding guilds ending in '*')
    local brotherOwners = {} -- [ownerName] = ownerTable
    if type(BrotherBags) == "table" then
        -- Prefer "forever" table first, then any other non-account realm table
        if type(BrotherBags.forever) == "table" then
            for ownerName, data in pairs(BrotherBags.forever) do
                if type(ownerName) == "string" and type(data) == "table" and not ownerName:find("%*$") then
                    brotherOwners[ownerName] = data
                end
            end
        end
        for realmKey, realmTable in pairs(BrotherBags) do
            if realmKey ~= "account" and realmKey ~= "forever" and type(realmTable) == "table" then
                for ownerName, data in pairs(realmTable) do
                    if type(ownerName) == "string" and type(data) == "table" and not ownerName:find("%*$") and not brotherOwners[ownerName] then
                        brotherOwners[ownerName] = data
                    end
                end
            end
        end
    end

    local matchedBrother = {}
    local charsByFirst = {}
    local list = {}

    -- Live bag scan for the current player right now
    local liveBags, liveBank = scanCurrentCharacterLive()

    -- 1. Start from WFC_DB_Global.chars (carries professions & learned recipes)
    for charKey, cData in pairs(dbChars) do
        if type(charKey) == "string" and type(cData) == "table" then
            local firstName = charKey:match("^([^%-]+)") or charKey
            local fullName = cData.fullName or firstName

            -- Find matching BagBrother owner by full name or first name prefix
            local bName, bData
            if brotherOwners[fullName] then
                bName, bData = fullName, brotherOwners[fullName]
            elseif brotherOwners[firstName] then
                bName, bData = firstName, brotherOwners[firstName]
            else
                for ownerName, data in pairs(brotherOwners) do
                    local ownerFirst = ownerName:match("^(%S+)")
                    if ownerFirst and ownerFirst:lower() == firstName:lower() then
                        bName, bData = ownerName, data
                        break
                    end
                end
            end

            if bName then
                matchedBrother[bName] = true
                fullName = bName
            end

            local counts = bData and extractOwnerCounts(bData) or { bags = {}, bank = {}, mail = {}, equip = {}, total = {} }

            local isCurrent = (curFirst and firstName:lower() == curFirst:lower())
                or (curFull and fullName:lower() == curFull:lower())

            local g = (ns.Professions and ns.Professions.global) or _G["WFC_Professions_Global"]
            local fb = g and g.inventories and (g.inventories[fullName] or g.inventories[firstName])

            if isCurrent then
                -- Current character ALWAYS uses live scanned bag counts!
                if liveBags then
                    counts.bags = liveBags
                elseif fb and fb.bags then
                    counts.bags = fb.bags
                end
                if liveBank then
                    counts.bank = liveBank
                elseif not next(counts.bank) and fb and fb.bank then
                    counts.bank = fb.bank -- last bank visit, when BagBrother has nothing
                end
            else
                -- Fallback if BagBrother had no bag items for this alt
                if (not next(counts.bags)) and fb and fb.bags and next(fb.bags) then
                    for id, n in pairs(fb.bags) do
                        counts.bags[id] = n
                    end
                end
                if (not next(counts.bank)) and fb and fb.bank and next(fb.bank) then
                    for id, n in pairs(fb.bank) do
                        counts.bank[id] = n
                    end
                end
            end

            -- Recompute total
            counts.total = {}
            for id, n in pairs(counts.bags or {}) do counts.total[id] = (counts.total[id] or 0) + n end
            for id, n in pairs(counts.bank or {}) do counts.total[id] = (counts.total[id] or 0) + n end
            for id, n in pairs(counts.mail or {}) do counts.total[id] = (counts.total[id] or 0) + n end

            -- Current player professions check live table
            local profs = cData.professions or {}
            if isCurrent then
                if WFC and WFC.Player and WFC.Player.professions and next(WFC.Player.professions) then
                    profs = WFC.Player.professions
                elseif Compat and Compat.GetProfessions then
                    local p = Compat.GetProfessions()
                    if p and next(p) then profs = p end
                end
            end

            local entry = {
                key = charKey,
                name = fullName,
                shortName = firstName,
                class = cData.class or (bData and bData.class) or (isCurrent and WFC.Player and WFC.Player.classFile),
                level = (isCurrent and WFC.Player and WFC.Player.level) or cData.level or (bData and bData.level) or 1,
                faction = cData.faction or (isCurrent and WFC.Player and WFC.Player.faction) or "Horde",
                money = (isCurrent and GetMoney and GetMoney()) or (bData and bData.money) or 0,
                isCurrent = isCurrent == true,
                professions = copy(profs),
                recipes = copy(cData.recipes),
                counts = counts,
            }

            local existing = charsByFirst[firstName:lower()]
            if existing then
                -- Merge if duplicate charKey existed
                for pId, pInfo in pairs(entry.professions) do existing.professions[pId] = pInfo end
                for sId in pairs(entry.recipes) do existing.recipes[sId] = true end
                if (entry.level or 0) > (existing.level or 0) then existing.level = entry.level end
            else
                charsByFirst[firstName:lower()] = entry
                list[#list + 1] = entry
            end
        end
    end

    -- 2. Add any BagBrother characters not yet in WFC_DB_Global.chars
    for ownerName, bData in pairs(brotherOwners) do
        if not matchedBrother[ownerName] then
            local firstName = ownerName:match("^(%S+)") or ownerName
            if not charsByFirst[firstName:lower()] then
                local isCurrent = (curFirst and firstName:lower() == curFirst:lower())
                    or (curFull and ownerName:lower() == curFull:lower())

                local counts = extractOwnerCounts(bData)
                local g = (ns.Professions and ns.Professions.global) or _G["WFC_Professions_Global"]
                local fb = g and g.inventories and (g.inventories[ownerName] or g.inventories[firstName])

                if isCurrent then
                    if liveBags then counts.bags = liveBags
                    elseif fb and fb.bags then counts.bags = fb.bags end
                    if liveBank then counts.bank = liveBank
                    elseif not next(counts.bank) and fb and fb.bank then counts.bank = fb.bank end
                else
                    if (not next(counts.bags)) and fb and fb.bags and next(fb.bags) then
                        for id, n in pairs(fb.bags) do counts.bags[id] = n end
                    end
                    if (not next(counts.bank)) and fb and fb.bank and next(fb.bank) then
                        for id, n in pairs(fb.bank) do counts.bank[id] = n end
                    end
                end

                counts.total = {}
                for id, n in pairs(counts.bags or {}) do counts.total[id] = (counts.total[id] or 0) + n end
                for id, n in pairs(counts.bank or {}) do counts.total[id] = (counts.total[id] or 0) + n end
                for id, n in pairs(counts.mail or {}) do counts.total[id] = (counts.total[id] or 0) + n end

                local profs = {}
                if isCurrent then
                    if WFC and WFC.Player and WFC.Player.professions and next(WFC.Player.professions) then
                        profs = WFC.Player.professions
                    elseif Compat and Compat.GetProfessions then
                        local p = Compat.GetProfessions()
                        if p and next(p) then profs = p end
                    end
                end

                local entry = {
                    key = ownerName,
                    name = ownerName,
                    shortName = firstName,
                    class = bData.class or (isCurrent and WFC.Player and WFC.Player.classFile),
                    level = bData.level or (isCurrent and WFC.Player and WFC.Player.level) or 1,
                    faction = bData.faction == true and "Alliance" or "Horde",
                    money = (isCurrent and GetMoney and GetMoney()) or bData.money or 0,
                    isCurrent = isCurrent == true,
                    professions = copy(profs),
                    recipes = {},
                    counts = counts,
                }
                charsByFirst[firstName:lower()] = entry
                list[#list + 1] = entry
            end
        end
    end

    -- 3. Ensure the current character is ALWAYS in the roster even if not yet saved to DB
    local curFound = false
    for _, ch in ipairs(list) do
        if ch.isCurrent then
            curFound = true
            break
        end
    end
    if not curFound and (curFirst or curFull) then
        local g = (ns.Professions and ns.Professions.global) or _G["WFC_Professions_Global"]
        local fb = g and g.inventories and (g.inventories[curFull or ""] or g.inventories[curFirst or ""])
        local cBags = liveBags or {}
        local cBank = liveBank or (fb and fb.bank) or {}
        local cTotal = {}
        for id, n in pairs(cBags) do cTotal[id] = (cTotal[id] or 0) + n end
        for id, n in pairs(cBank) do cTotal[id] = (cTotal[id] or 0) + n end

        local profs = (WFC and WFC.Player and WFC.Player.professions) or {}
        if not next(profs) and Compat and Compat.GetProfessions then
            local p = Compat.GetProfessions()
            if p and next(p) then profs = p end
        end

        local entry = {
            key = curFull or curFirst,
            name = curFull or curFirst,
            shortName = curFirst or curFull,
            class = (WFC and WFC.Player and WFC.Player.classFile) or (UnitClass and select(2, UnitClass("player"))),
            level = (WFC and WFC.Player and WFC.Player.level) or (UnitLevel and UnitLevel("player")) or 1,
            faction = (WFC and WFC.Player and WFC.Player.faction) or (UnitFactionGroup and UnitFactionGroup("player")) or "Horde",
            money = (GetMoney and GetMoney()) or 0,
            isCurrent = true,
            professions = copy(profs),
            recipes = {},
            counts = {
                bags = cBags,
                bank = cBank,
                mail = {},
                equip = {},
                total = cTotal,
            },
        }
        charsByFirst[(curFirst or curFull):lower()] = entry
        list[#list + 1] = entry
    end

    -- Sort: current character first, then by level descending, then by name
    table.sort(list, function(a, b)
        if a.isCurrent ~= b.isCurrent then return a.isCurrent end
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return (a.name or "") < (b.name or "")
    end)

    cachedChars = list
    return list
end

--- Returns:
---   totals[itemId] = totalCountAcrossAllChars
---   byItem[itemId] = { { char = charEntry, total = n, bags = b, bank = k, mail = m }, ... }
function Inventory:GetItemIndex()
    if cachedTotals and cachedByItem then
        return cachedTotals, cachedByItem
    end
    local totals = {}
    local byItem = {}
    local chars = self:GetCharacters()

    for _, char in ipairs(chars) do
        local c = char.counts
        for itemId, total in pairs(c.total) do
            if total > 0 then
                totals[itemId] = (totals[itemId] or 0) + total
                local holders = byItem[itemId]
                if not holders then
                    holders = {}
                    byItem[itemId] = holders
                end
                holders[#holders + 1] = {
                    char = char,
                    total = total,
                    bags = c.bags[itemId] or 0,
                    bank = c.bank[itemId] or 0,
                    mail = c.mail[itemId] or 0,
                }
            end
        end
    end

    -- Also check account-wide bank tabs in BrotherBags.account if present
    if type(BrotherBags) == "table" and type(BrotherBags.account) == "table" then
        local accCounts = extractOwnerCounts(BrotherBags.account)
        for itemId, total in pairs(accCounts.total) do
            if total > 0 then
                totals[itemId] = (totals[itemId] or 0) + total
                local holders = byItem[itemId]
                if not holders then
                    holders = {}
                    byItem[itemId] = holders
                end
                holders[#holders + 1] = {
                    char = { name = "Account Bank", shortName = "Account", class = nil, professions = {}, recipes = {} },
                    total = total,
                    bags = 0,
                    bank = total,
                    mail = 0,
                }
            end
        end
    end

    cachedTotals = totals
    cachedByItem = byItem
    return totals, byItem
end

function Inventory:GetTotalCount(itemId)
    local totals = self:GetItemIndex()
    return totals[itemId] or 0
end

function Inventory:GetHolders(itemId)
    local _, byItem = self:GetItemIndex()
    return byItem[itemId] or WFC.Util.EMPTY
end

---------------------------------------------------------------------------
-- Events to keep cache fresh
---------------------------------------------------------------------------
local refreshTimer
local function scheduleRefresh()
    if refreshTimer then refreshTimer:Cancel() end
    refreshTimer = C_Timer.NewTimer(0.4, function()
        refreshTimer = nil
        scanCurrentCharacterLive()
        Inventory:Invalidate()
        if ns.Panel and ns.Panel.Refresh then
            ns.Panel:Refresh()
        end
    end)
end

WFC:RegisterEvent("PLAYER_ENTERING_WORLD", scheduleRefresh)
WFC:RegisterEvent("PLAYER_LOGIN", scheduleRefresh)
WFC:RegisterEvent("BAG_UPDATE", scheduleRefresh)
WFC:RegisterEvent("BAG_UPDATE_DELAYED", scheduleRefresh)
WFC:RegisterEvent("BANKFRAME_OPENED", scheduleRefresh)
WFC:RegisterEvent("BANKFRAME_CLOSED", scheduleRefresh)
WFC:RegisterEvent("MAIL_INBOX_UPDATE", scheduleRefresh)
WFC:RegisterEvent("SKILL_LINES_CHANGED", scheduleRefresh)
WFC:RegisterEvent("TRADE_SKILL_SHOW", scheduleRefresh)
WFC:RegisterEvent("TRADE_SKILL_LIST_UPDATE", scheduleRefresh)
WFC:On("WFC_HARVEST_RECIPES", scheduleRefresh)
WFC:On("WFC_PLAYER_CHANGED", scheduleRefresh)
WFC:On("WFC_DB_READY", scheduleRefresh)
