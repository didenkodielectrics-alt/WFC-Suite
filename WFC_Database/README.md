# WFC_Database

The data layer and shared core for the WFC suite. It requires the **QuestieDB** addon, which ships with Questie for Forever. Rules: [../CoreRules.md](../CoreRules.md). Plan: [../plan.md](../plan.md) §2.

## How it stays fast

| Layer | What it does | Cost per call |
|---|---|---|
| **Cards** (Sections) | `DB:GetQuest/GetItem/GetNpc(id)` read only that entity's QuestieDB fields once. They normalize them (0→nil, 0–100→0–1, AreaID→UiMapID) and memoize the result. | First call: a few field reads. Afterwards: one table lookup (~0.1 µs). |
| **Denormalized data** | Item cards already contain their quest uses, quest rewards, vendors, drop sources and *recipe uses with profession/count/product copied in*. A tooltip needs one call. | Same as above. |
| **Background indexes** | Reverse lookups that must visit every entity (quests by zone, quests by dungeon, quest rewards, quests starting in a zone, NPCs by area). They're built once in time-sliced jobs (4 ms/frame, paused in combat), then **saved in `WFC_DB_Cache`**, so later logins load them instantly. | Before ready: `nil, "pending"`. After: one lookup. |
| **Lazy heavy data** | The drop-rate table (a large Lua string) loads once during the login loading screen. Spawns are cached weakly. Travel-safety grids are built per map on first use. | One-time. |

Returned tables are **shared**: treat them as read-only.

## Public API (`WFC.DB`, see DB/Facade.lua)

```lua
DB:GetQuest(id) DB:GetQuestBrief(id) DB:IsQuestAvailable(id, {levelSlack=n}) -- ok, reason, detail
DB:GetQuestPositions(id) DB:GetQuestRewards(id)* DB:GetQuestsInArea(areaId)* DB:GetQuestsStartingIn(areaId)*
DB:GetQuestsByLevel(minLevel, maxLevel)* DB:GetDungeons() DB:GetDungeon(id) DB:GetDungeonQuests(dungeonId)*
DB:GetDungeonDetails(dungeonId)* -- level range, bosses, the dungeon's own uiMap, entrances
DB:GetItem(id) DB:GetItemClient(id) DB:GetItemSources(id) DB:GetQuestsUsingItem(id) DB:GetRecipesUsingItem(id)
DB:GetRecipe(spellId) DB:GetNpc(id) DB:GetNpcSpawns(id) DB:GetObject(id) DB:GetObjectSpawns(id)
DB:GetHostileNpcsNear(uiMapId, x, y, radius, side)* DB:IsNew(kind, id) DB:GetPrice(itemId) -- ah, vendor, provider, age
```
\* index-backed: returns `nil, "pending"` until built. Use `DB.Indexes:WhenReady(name, fn)` or listen for `WFC_INDEX_READY`.

**Messages:**
- Lifecycle: `WFC_STORE_READY`, `WFC_DB_READY`, `WFC_INDEX_READY(name)`, `WFC_DB_INVALIDATED`
- Data updates: `WFC_ITEM_LOADED(itemId)`, `WFC_PRICES_UPDATED`, `WFC_RECIPES_CHANGED`
- Player and harvest: `WFC_PLAYER_CHANGED(field)`, `WFC_HARVEST_LOOT`, `WFC_HARVEST_RECIPES`
- Combat: `WFC_COMBAT_START`, `WFC_COMBAT_END`

## Shared helpers for the other addons
- **Fonts** (`Core/Fonts.lua`): `WFC.Fonts:Get("tooltip"|"tooltipHead"|"header"|"subheader"|"body"|"small"|"mapLabel")`, also as globals `WFC_FontTooltip` etc.
  - The TTFs ship in `Media/Fonts/` (Teko, Barlow Semi Condensed and Alegreya Sans, all OFL; see its README). If a file fails to load, and always on non-Latin clients, the font object stays a copy of a Blizzard font, so text never disappears.
  - `settings.fontScale` (0.8–1.3) scales all of them.
- **new! tag:** `WFC:NewTag(prefix)` returns the cyan tag, or `""` when `settings.showNew` is off.
- **Settings panel:** `WFC.UI:AddSettingsPage(name, store, defaults, controls, onChange)` adds a page under Options → AddOns → **WFC**. It's pcall-guarded, so slash commands still work if the panel can't be built.
- **Compat** also has:
  - tooltips and money: `FormatMoney` (coin icons), `IsShiftKeyDown`, `HookItemTooltips` (TooltipDataProcessor, or `OnTooltipSetItem` on Classic Era), `RefreshTooltip`
  - quest log: `GetQuestObjectives`, `OpenQuestInLog`, `IsQuestWatched` / `SetQuestWatched`, `GetQuestLogRewards`, `GetQuestLogFrame`
  - map: `MapToWorld` (world yards), `OpenWorldMap`, `SetWaypoint` (native pin, or TomTom), `GetAreaName`
  - other: `GetFactionName`, `GetItemIcon`, `HasContextMenu`

## Testing on Classic Era
The TOCs list both Forever (16001) and Classic Era 1.15.9 (11509), so the suite loads on Era as a smoke test alongside Era's QuestieDB:
```powershell
.\tools\deploy.ps1 -AddOns "C:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns"
```
(run from the `WowForever` folder; it creates junctions, so edits show up after `/reload`).

What differs on Era:
- Professions come from the skill list, matched by English name.
- The recipe harvester does nothing, because Era has no `C_TradeSkillUI`.
- `/wfc selftest` fails the Forever-only probes.
- Everything else (quests, items, drops, prices, tooltips, dev log) runs normally.

## Auction prices

WFC doesn't scan the auction house. It reads other addons' scan data through providers in `DB/Sections/Prices.lua`:
- **Auctionator** (built in, has a Forever build).
- **TSM** (built in, dormant until a Forever build exists).

Any scanner can be added with `WFC.DB.Prices:RegisterProvider{ key, GetPrice, ... }`.

## Commands
`/wfc dev` (dev mode) · `/wfc selftest` · `/wfc db stats|quest|item|npc|object|recipe <id>|new <kind> <id>|newaudit|index [rebuild [name]]|price <id>` · `/wfc harvest on|off|stats|flush|wipe` · `/wfc export` · `/wfc import` · `/wfc debug`

## Tests
```bash
pip install lupa
python tools/run_tests.py
```
The specs boot the real addon files in TOC order against `spec/support/wow.lua` (WoW API mock) and `spec/support/questiedb.lua` (a small fixture world that follows QuestieDB's read semantics).

## Recipes
`Data/Recipes.lua` is generated from Forever's own game tables, using wago.tools DB2 CSV exports of the latest `wowf` build:
- **Coverage:** 2,492 recipes across all professions, including about 930 Forever-new ones (flagged `isNew`).
- **Per recipe:** product, reagents, skill thresholds (learn/orange/yellow/green/grey), the recipe item that teaches it, and whether it's a trainer recipe or learned automatically.
- **Learn rank caveat:** the client data often lists the learn rank as 1, because trainers set the real one on the server.

**Recipe items:** the generated data marks almost every recipe as a trainer recipe and links only three teaching items. `Data/RecipeItems.lua` corrects that. It's built from QuestieDB's recipe items (item class 9), matched to recipes by profession and name, and covers 1,812 recipes. A recipe listed there is treated as taught by the item, not by a trainer; `DB:GetItemSources(itemId)` says where the item comes from. 245 of the items have no source in QuestieDB yet. A recipe that is both trainer-taught and has a teaching item will read as item-taught.

The in-game Harvester still overrides reagents and products with what the profession window shows. To regenerate after a new Forever build:
```bash
python tools/build_recipes.py --fetch
```
`--fetch` downloads into `tools/.cache/` (keep that folder out of git).

## Dev mode (temporary)
Dev mode is on by default while `Dev/` exists. It records the following, with timestamps:
- every **WFC Lua error** (passed on to BugSack afterwards)
- **blocked protected calls** (taint) from any WFC addon
- Lua warnings
- section Init/Login timings and background job timings
- **slow `WFC.DB` calls** (over 5 ms)
- the startup self-test
- `WFC:Log(...)` lines

**In game:**
- A **WFC Dev Log** window pops up whenever an error or warning is captured.
- `/wfc dev` toggles the window.
- The window's buttons: filter level, Copy, Clear, and **Reload UI (sync console)**.
- `/wfc dev popup off` stops it popping up. `/wfc dev all on` also captures other addons' errors. `/wfc dev test` checks the whole pipeline.

**Separate cmd window:** double-click `tools/devconsole.bat`, or run `python tools/devconsole.py --wow "<WoW>\_forever_"`.
- WoW only writes SavedVariables on /reload or logout, so the console shows new lines after each reload. The window's Reload button does that.
- The console also tails `Logs/taint.log` live once you run `/console taintLog 1` in game.

**To remove dev mode:**
1. Delete the `Dev/` folder, `spec/dev_spec.lua`, `tools/devconsole.py` and `tools/devconsole.bat`.
2. Delete both `DEV MODE` blocks in `WFC_Database.toc`.
3. Remove `WFC_DevLog` from the TOC's SavedVariables line.

`WFC:Log` calls left in the code become no-ops.

## Regenerating the Era ID snapshot
```bash
python tools/build_era_ids.py --fetch
```
`--fetch` downloads QuestieDB's Classic data. Alternatively use `--questiedb <clone>` or `--files quest=... item=... npc=... object=...`.
