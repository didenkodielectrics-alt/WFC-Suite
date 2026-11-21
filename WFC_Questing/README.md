# WFC_Questing

Ranks the best next quests for your character and adds a quest panel next to your quest log. Requires **WFC_Database** (and through it QuestieDB). **Questie itself is optional**: with it loaded, the panel uses Questie's icons and refreshes on Questie's quest updates. Plan: [../plan.md](../plan.md) §4. Look: [../design.md](../design.md) §4.

```
┌ WFC Quests ─────────────────────────────── ✕ ┐
│ ! [24] The Defias Brotherhood  new!  Westfall │
│        ~6 min · ★ 412 xp/min                  │
│ ! [22] Shadow Magic                  Duskwood │
│        ~12 min · ★ 271 xp/min                 │
│ ! [25] Riverglades Survey  new!   Riverglades │
│        ~18 min · ★ 168 xp/min · hard          │
├───────────────────────────────────────────────┤
│ 12 quests                    ☐ Show ignored   │
└ [ Active ] [ Next Up ] ───────────────────────┘
```

## How quests are ranked
- **Candidates:** every quest in your log, plus every quest you can take right now, from QuestieDB:
  - correct faction, race and class
  - prerequisites done
  - not completed, ignored or blocked by an exclusive quest
- **Level window:** quest levels from the grey cutoff up to **+3** (both configurable). Grey quests are hidden.
- **Score:** XP per minute.
  - **XP:** QuestieDB's XP table with the Classic falloff for low quests, plus 30% of the next quest in the chain, plus the best reward item's value at 20 XP per gold. Reputation counts too if you give it a value in the options (off by default; useful for repeatable turn-ins).
  - **Minutes:** walk (7 yd/s, mount speed from level 40/60) to the nearest giver, to each objective camp and to the turn-in, plus about 20 s per kill. The boat penalty is 5 min.
  - Quests sharing a zone with others in your log get 15% off.
- **Penalties:** elite and group quests while solo ×0.3 (or hidden), red quests ×0.5, dungeon quests left out unless enabled.
- **Travel:** once **WFC Travel** is installed, its route times replace the straight-line estimate automatically.
- **When it re-scores:** about 2 s after quest log changes, level-ups, zone changes and Questie updates, never in combat. Scoring runs in the background, a few milliseconds per frame.

## Panel
- **Docking:** it docks to the right of whichever quest log is open (the map's quest log, Blizzard's `QuestLogFrame` or Kerzo's ClassicQuestLog). Closing the docked panel (with the close button or `/wfc quests hide`) disables auto-show, so the panel **stays closed when closing and reopening the map**. You can re-open it at any time with the **Quests** toggle button on the World Map header, `/wfc quests`, or `/wfc quests autoshow on`.
- **Tabs:**
  - **Active:** your current log with live count (e.g. `Active (4)`), turn-ins first, then by score.
  - **Circuit (top of Next Up):** the zone where your best quests cluster, with your unfinished quests there, in visiting order (nearest next stop first), e.g. "★ Circuit: Westfall · ~22 min · 3,400 xp". Click it to path to the first stop. It can be turned off in the options.
  - **Next Up:** the top 10 quests to pick up, numbered `#1`, `#2`, ... with the quest giver's name and coordinates (e.g. `Pick up: Sergra Darkthorn (52, 31)`). Never quests already in your log or completed before, except repeatable quests, which compete on score like any other.
  - The panel remembers the last tab you picked across reloads and sessions.
  - **Dungeons:** pick a dungeon (it defaults to the one that fits your level) and see every quest for it, grouped into **In log**, **Available** (where to pick it up), **Needs prerequisite** ("Do *X* (Westfall) first") and **Not eligible** (with the reason, e.g. "Requires level 30", "Horde only"; collapsed by default). Also its **bosses** with levels, its level range, and a summary like `5 quests · 9,850 xp available`.
    - **Map** opens the **Dungeon Map** window (Atlas-style). It shows Blizzard's own map of the dungeon, with buttons per floor (e.g. Deadmines / Ironclad Cove, the four Scarlet Monastery wings), plus the level range, bosses and your quests with progress. There's no player position.
      - Forever's client contains these map images but has no map entries for dungeons, so the game itself can't show them. WFC draws them from your install by file ID; `Data/DungeonMaps.lua` is just a list of numbers, and no artwork ships with the addon.
      - **Coverage:** 65 floors across 23 Classic dungeons and raids. Zul'Farrak, Zul'Gurub and the Ruins of Ahn'Qiraj have no map art in any client, so for those Map pins the entrance instead.
      - **Pins:** a skull on every boss, and Questie's icons (sword = kill, bag = loot, cog = object) on the mobs and objects your quests need. Hover a pin for its name and level, or the quest and your progress. Floor buttons show how many of your objectives are on each floor, e.g. "Ironclad Cove (2)". Finished objectives drop off.
      - **Where the positions come from:** QuestieDB has no positions inside dungeons, so they come from the **CMaNGOS Classic database** (GPL-3) spawn tables, placed on Blizzard's floors with retail's map-to-world tables. Checked against Blizzard's painted boss skulls on both Deadmines floors. `Data/DungeonSpawns.lua` holds 11,129 spawns as compact text (120 KB). Where floors overlap or stack (all six Lower Blackrock Spire maps cover one footprint), the generator reads the map art: each floor shows its own rooms pale and the rest as faded parchment, so a pin goes to the floor that's pale there. Spawns no map shows (e.g. Upper Blackrock Spire, a separate dungeon in modern WoW) are skipped, decoded per floor only when you open it.
      - Regenerate with `python tools/build_dungeon_maps.py --fetch`, then `python tools/build_dungeon_spawns.py --fetch` (downloads the 13 MB CMaNGOS dump and ~27 MB of multi-floor map tiles into `tools/.cache/`; needs Pillow).
      - If a client ever has real dungeon maps, a legend box also appears on the world map while one is shown.
    - **Path** routes to the entrance (with WFC Travel), or pins the entrance on the map.
- **Left-click** opens a quest in the native log, or the rewards popup for quests you haven't taken.
- **Shift-click** opens the map and pins the quest giver/next location with a waypoint.
- **Right-click:**
  - **Show on map:** opens the map at the giver, the nearest objective or the turn-in, and places the native map pin (TomTom on clients without one).
  - **Path:** greyed out until WFC Travel exists (M5/M6).
  - **Show rewards:** XP, money, reputation and item buttons whose tooltips carry the WFC ItemTips verdict. The most valuable choice is outlined in green.
  - **Track / Untrack**
  - **Ignore / Unignore:** per character, included in `/wfc export`.
- **Fonts and icons:** rows use the WFC fonts, and Questie's icons when Questie is loaded (Blizzard's quest icons otherwise).

## Commands
`/wfc quests` (toggle) · `show|hide` · `dock|undock` · `autoshow [on|off]` · `reset` · `rescore` · `next` (prints the top 5 with givers) · `ignored` · `unignore <id>` · `options`

Options: **Options → AddOns → WFC → Questing**.

## For other addons
- `WFC.Questing:GetNextUp(n)` returns only quests not yet started or completed (repeatables excepted). `:GetRanked()` returns everything scored, including your log. Both return entries of `{ candidate, score, minutes, value, xp, grey, red }`.
- Also: `:GetEntry(questId)`, `:IsIgnored(id)`, `:SetIgnored(id, on)`.
- Messages: `WFC_QUESTS_SCORED`, `WFC_QUEST_IGNORED(questId, on)`, `WFC_QUEST_SHOWN_ON_MAP(questId, point)`.
- Travel plugs in by defining `WFC.Travel:EstimateTime(from, to)` and `WFC.Travel:PathToQuest(questId)`.

## Files
| File | Role |
|---|---|
| `Scorer.lua` | The ranking. Pure Lua, tested directly in `spec/scorer_spec.lua`. |
| `Candidates.lua` | Gathers quests, converts map points to world yards (cached per quest), runs the Scorer in a background job. |
| `QuestieBridge.lua` | The only file that touches Questie (public `Questie.API` only), plus Show on map. |
| `Panel.lua`, `Menu.lua`, `Rewards.lua` | The window, the right-click menu, the rewards popup. |
| `Dungeons.lua`, `DungeonAtlas.lua`, `DungeonMap.lua` | The Dungeons tab, the Dungeon Map window, and the boss/quest legend text. |
| `Data/DungeonMaps.lua` (generated) | Tile file IDs per dungeon floor (`tools/build_dungeon_maps.py`). |
| `Data/DungeonSpawns.lua` (generated) | Creature/object positions on each floor, from CMaNGOS (`tools/build_dungeon_spawns.py`). |
| `Settings.lua` | Defaults, SavedVariables, `/wfc quests`, the options page. |
