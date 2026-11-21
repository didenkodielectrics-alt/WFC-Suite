# WFC_Travel

Finds the fastest way to any spot. It walks, uses **the flight paths you know**, takes **boats, zeppelins and the Deeprun Tram**, and uses **your hearthstone** when it's ready. The route is drawn on the world map: solid lines for walking, dashed lines for flights and transports. Requires **WFC_Database**. Plan: [../plan.md](../plan.md) §5. Look: [../design.md](../design.md) §5.

```
┌ WFC Travel  • Safe  Deathrun ⊕ ✕ ┐
│ ETA 4m 12s · 3 legs             │
│ No risky stretches              │
│ • Run to Stormwind          2s  │
│ • Fly Stormwind to Ironforge 4m │
│ • Run to Ironforge          8s  │
└─────────────────────────────────┘
```

## Using it
- **Click a spot on the map:** press **⊕** in the WFC Travel box (top right of the world map), then click the map. Right-click or Esc cancels. While ⊕ isn't armed, map clicks work as normal.
- **From the quest panel:** right-click a quest, then **Path**. It routes to the quest giver if you haven't taken the quest, to the turn-in when it's complete, or otherwise to the objective that's quickest to reach. Then it opens the map.
- **Closing & Reopening:** Click the close button **✕** on the travel box to close it. Click the **Travel** button on the World Map header (or `/wfc travel show` / `/wfc travel toggle`) to reopen it at any time.
- **Clearing:** The stop button clears the target and route. It also clears itself when you arrive (within 25 yd).
- **Map pin:** the end of the current leg gets the game's own map pin (or TomTom's arrow on clients without one). It moves to the next stop as you go.
- **Flight paths:** open any flight master's map once per character, and Travel knows every flight path you have. Newly discovered ones are added as you find them.

## How routes are found
- **Flight data:** flight masters and flight paths come from Forever's own game tables. `tools/build_taxi.py` generates `Data/Taxi.lua`: 72 flight masters (5 Forever-new, in Mount Hyjal and Riverglades) and 294 direct flights.
  - **Flight time:** the flight path's length at 32 yd/s, plus 5 s for takeoff.
  - **Rules:** only flight masters you know and your faction can use. Chained flights show as one leg.
  - **Learned times:** every flight you take is timed, from takeoff to landing. A route you've flown uses its measured time, and the account-wide ratio of real to estimated times corrects every other flight estimate (kept between 0.6× and 1.6×).
- **Boats, zeppelins and the tram** are in `Data/Transports.lua`. The wait counts as half the departure interval.
  - Their dock positions are **approximate until checked in game**: stand on each dock, run `/wfc travel here`, and correct the line.
- **Walking & Cross-Zone Travel**:
  - Same-zone walking uses a straight line ×1.3 for roads and terrain. Running is 7 yd/s, and riding is assumed from level 40 (60%) and 60 (100%).
  - Cross-zone walking uses a 2.0× detour multiplier plus a configurable 120 s zone transition buffer to account for mountain ranges, passes, and winding roads.
  - Cross-zone travel never assumes a direct Euclidean walk through mountains; the router evaluates known flight paths, boats, and transports before selecting a cross-zone walk.
- **Hearthstone:** 30 s (cast plus loading), only when it's off cooldown. The destination is where you last set your hearth, or the flight master named like your inn.
- **Islands:** Forever's detached islands (Zephras Isle, Darkspear Islands) have no world position, so they're reached only through boat, portal or hand-added links.
- **New content:** legs touching new content show **new!**.
- **Combat:** a route is never computed in combat. The current route stays drawn and updates once combat ends.

## Safe vs Deathrun
Toggle it in the travel box (or `/wfc travel mode safe|deathrun`). It's remembered per character, and Safe is the default.
- **Where the danger comes from:** the database only, never live units. Hostile mobs come from QuestieDB spawns, with their levels and elite status.
- **How a walk is judged:** it's checked every 30 yd. A mob counts when that point is inside its aggro radius: 20 yd, plus a yard per level it's above you, between 5 and 45 yd.
- **Danger per mob:** grey or green 0, yellow 0.2, orange 0.6, red 1.5, elites ×3.
- **Patrols:** QuestieDB's patrol paths count too, so a walking guard is dangerous along its whole route, not only where it spawns.
- **Safe** weighs walking time by danger (×(1 + 2 × danger)) and refuses walks past a red elite or with too much danger. It bends around camps with detour points beside them, or takes a flight, boat or tram. If no safe way exists, it shows the direct route and says so.
- **Deathrun** takes the fastest route and ignores danger.
- **Map lines:** Safe colours walking by danger (green, yellow, orange, red). Deathrun draws walking white with red ticks across the risky stretches.
- **Risk line:** the box sums up the risk, e.g. "Risk: 1 risky stretch (Wetlands, lvl 25-28 Mottled Crocolisk)". Forever's new regions add "danger data incomplete here", since their NPC data is thinner.
- **Questing's estimates** ignore danger, so ranking stays fast.

## Adding connections in game (Forever's new regions)
```
/wfc travel addnode RivergladesPier dock B      (stand on the spot; kind and faction optional)
/wfc travel addnode MenethilPier dock
/wfc travel link RivergladesPier MenethilPier boat 120 150    (crossing seconds, wait seconds, add "oneway" if needed)
/wfc travel exportgraph                          (copy the text into Data/Authored.lua so it ships)
```

## Commands
`/wfc travel` (route) · `here` · `target <x> <y>` (on your current map) · `clear` · `mode safe|deathrun` · `path <questId>` · `dungeon <dungeonId>` · `sync` · `addnode` · `link` · `removenode <name>` · `exportgraph` · `options`

Options: **Options → AddOns → WFC → Travel**.

## For other addons
```lua
WFC.Travel:SetTarget(uiMapID, x, y, label)   WFC.Travel:ClearTarget()   WFC.Travel:GetRoute()
WFC.Travel:PathToQuest(questId)              WFC.Travel:PathToDungeon(dungeonId)
WFC.Travel:EstimateTime(fromPoint, toPoint)  -- seconds; WFC_Questing ranks with it automatically
WFC.Travel:IsTaxiKnown(taxiNodeId)
```
Messages: `WFC_TRAVEL_ROUTE`, `WFC_TRAVEL_TARGET`, `WFC_FLIGHTPOINTS_CHANGED`.

## Files
| File | Role |
|---|---|
| `Router.lua` | Fastest-route search. Pure Lua, tested in `spec/router_spec.lua`. A search takes about 0.3 ms on Lua 5.1. |
| `Safety.lua`, `SafeRoute.lua` | Danger model (pure, `spec/safety_spec.lua`) and Safe/Deathrun routing with detours. |
| `Graph.lua` | Builds the network from the data files and in-game recordings. |
| `Travel.lua` | Target, route, map pin, arrival, Questing estimates (cached per start spot). |
| `Flights.lua` | Known flight path sync. |
| `MapUI.lua`, `RouteDrawer.lua` | The map box with the ⊕ crosshair, and the route lines. |
| `Commands.lua` | `/wfc travel` and the recording tools. |
| `Data/Taxi.lua` (generated), `Data/Transports.lua`, `Data/Authored.lua` | Network data. |

Regenerate flights after a new Forever build: `python tools/build_taxi.py --fetch` (downloads into `tools/.cache/`).

## Not yet
- **Boat and zeppelin schedules:** waits are still half the departure interval.
- Map icons at transfer points.
- Hand-drawn road networks (walking is a straight line ×1.3 for now).
