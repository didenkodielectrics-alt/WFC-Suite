local _, ns = ...

-- Turns an Advisor result into tooltip lines (design.md §3.1/§3.2). Pure apart from
-- WFC.Colors (pure) and the injected helpers in `opts`, so specs can check exact text.
--
-- opts = { expanded (Shift held), showReasons, maxLines (4), money(copper) -> string,
--          newTag(prefix) -> string, playerLevel, charName(char) -> string, productName(itemId, spellId) -> string }
-- Returns { {separator = true, right = "new!"|nil}, {text, color, head}, ... } or an empty list.

local Format = {}
ns.Format = Format

local WFC = WFC
local Colors = WFC.Colors
local P = Colors.palette

local ARROW = "|TInterface\\ChatFrame\\ChatFrameExpandArrow:0|t "
local INDENT = "   "

Format.VERDICTS = {
    keep_active   = { label = "Keep for quest", color = P.IMPOSSIBLE },
    keep_starts   = { label = "Keep: starts a quest", color = P.IMPOSSIBLE },
    keep_upcoming = { label = "Keep for upcoming quest", color = P.DIFFICULT },
    craft         = { label = "Craft", color = P.FAIR },
    disenchant    = { label = "Disenchant", color = P.FAIR },
    auction       = { label = "Auction", color = P.EASY },
    vendor        = { label = "Vendor", color = P.TRIVIAL },
}

local function verdictKey(entry)
    if entry.verdict == "keep" then return "keep_" .. entry.kind end
    return entry.verdict
end

local function questRef(quest, opts)
    local level = quest.level and quest.level > 0 and quest.level or quest.minLevel
    local c = Colors.ForQuest(quest.id, level, opts.playerLevel)
    return Colors.Wrap(("[%s] %s"):format(level and tostring(level) or "?", quest.name or ("Quest " .. quest.id)), c)
end

local function newTag(isNew, opts)
    return isNew and opts.newTag(" ") or ""
end

--- One reference line per entry (nil when the entry has nothing to add under the headline).
local function refLine(entry, opts)
    local v = entry.verdict
    if v == "keep" then
        local text = questRef(entry.quest, opts)
        if entry.kind == "active" then
            if entry.have and entry.need then
                text = text .. " · " .. Colors.Progress(entry.have, entry.need) .. entry.have .. "/" .. entry.need .. "|r"
            end
        elseif entry.kind == "starts" then
            text = "Starts " .. text
        elseif entry.via then
            text = text .. Colors.Wrap(" · after ", P.TEXT_MUTED) .. questRef(entry.via, opts)
        elseif entry.needsLevel then
            text = text .. Colors.Wrap(" · at level " .. entry.needsLevel, P.TEXT_MUTED)
        end
        return text .. newTag(entry.isNew, opts)
    elseif v == "craft" then
        local c = Colors.ForSkill(entry.color)
        -- "Cooking 40 (grey)": the skill the recipe is learned at; "lvl 15" when the product has a level requirement
        local skill = (type(entry.learn) == "number" and entry.learn > 0) and (" " .. entry.learn) or ""
        local lvl = opts.productLevel and opts.productLevel(entry.product)
        local lvlText = (type(lvl) == "number" and lvl > 1) and (" · lvl " .. lvl) or ""
        local text = Colors.Wrap(("Craft: %s%s · %s%s (%s)"):format(
            opts.productName(entry.product, entry.spellId), lvlText,
            entry.profName or "?", skill, entry.color or "?"), c)
        local extra = {}
        if entry.count and entry.count > 1 then extra[#extra + 1] = "uses " .. entry.count end
        if not entry.char.isCurrent then extra[#extra + 1] = opts.charName(entry.char) end
        if entry.learnable then extra[#extra + 1] = "learnable" end
        if #extra > 0 then text = text .. Colors.Wrap(" · " .. table.concat(extra, " · "), P.TEXT_MUTED) end
        return text .. newTag(entry.isNew, opts)
    elseif v == "disenchant" then
        local text = Colors.Wrap(("Disenchant ~%s"):format(opts.money(entry.value)), P.FAIR)
        local extra = {}
        if entry.mat then extra[#extra + 1] = "mostly " .. opts.productName(entry.mat) end
        if not entry.char.isCurrent then extra[#extra + 1] = opts.charName(entry.char) end
        if #extra > 0 then text = text .. Colors.Wrap(" · " .. table.concat(extra, " · "), P.TEXT_MUTED) end
        return text
    elseif v == "auction" then
        local gain = entry.net - (entry.vendor or 0)
        local text = Colors.Wrap(("Auction: +%s over vendor"):format(opts.money(gain)), P.EASY)
        if entry.count and entry.count > 1 then
            text = text .. Colors.Wrap((" · +%s for %d"):format(opts.money(gain * entry.count), entry.count), P.TEXT_MUTED)
        end
        return text
    elseif v == "vendor" and entry.why == "price" then
        return Colors.Wrap(("Vendor: the AH nets only %s"):format(opts.money(math.max(0, entry.net))), P.TRIVIAL)
    end
    return nil -- junk / soulbound vendoring needs no reason line
end

local function priceLine(prices, opts)
    local parts = {}
    if prices.ah then
        parts[#parts + 1] = "Auction ~" .. opts.money(prices.ah) -- "~": Blizzard fallback fonts lack "≈"
        if prices.age and prices.age >= 2 then parts[#parts] = parts[#parts] .. (" (%dd old)"):format(prices.age) end
        -- AH fee = 5% cut + deposit estimate; net (what actually lands in the mailbox) goes first.
        if prices.fee and prices.net then
            table.insert(parts, 1, "Net " .. opts.money(math.max(0, prices.net)))
            parts[#parts + 1] = "fee " .. opts.money(prices.fee)
        end
    end
    if prices.vendor and prices.vendor > 0 then parts[#parts + 1] = "Vendor " .. opts.money(prices.vendor) end
    if #parts == 0 then return nil end
    if not prices.ah then parts[#parts + 1] = "no AH data" end
    return Colors.Wrap(table.concat(parts, " · "), P.TEXT_MUTED)
end

function Format.Lines(result, opts)
    local lines = {}
    local entries = result.entries
    local prices = priceLine(result.prices, opts)
    if #entries == 0 and not prices then return lines end

    lines[1] = { separator = true, right = result.isNew and opts.newTag() ~= "" and opts.newTag() or nil }
    local head = entries[1]
    if head then
        local v = Format.VERDICTS[verdictKey(head)]
        lines[#lines + 1] = { text = ARROW .. v.label, color = v.color, head = true }
    end
    if opts.showReasons == false then return lines end

    -- References in priority order, deduplicated, then the price summary.
    local maxSub = opts.expanded and math.huge or ((opts.maxLines or 4) - #lines + 1)
    local refs, seen = {}, {}
    for i = 1, #entries do
        local text = refLine(entries[i], opts)
        if text and not seen[text] then
            seen[text] = true
            refs[#refs + 1] = text
        end
    end
    local room = maxSub - (prices and 1 or 0)
    for i = 1, math.min(#refs, room) do
        lines[#lines + 1] = { text = INDENT .. refs[i], color = P.TEXT }
    end
    if #refs > room and room >= 0 then
        -- Say how much Shift would reveal instead of silently dropping reasons.
        local last = lines[#lines]
        if last and not last.head then
            last.text = last.text .. Colors.Wrap((" (+%d, hold Shift)"):format(#refs - room), P.TEXT_MUTED)
        end
    end
    if prices then lines[#lines + 1] = { text = INDENT .. prices, color = P.TEXT_MUTED } end
    return lines
end

return Format
