# WFC Suite

Addons for **WoW: Forever**: quest planning, travel routes, crafting help, item advice, class helpers and whole-UI themes. They share one core and show up as a single group in the AddOns list.

## Addons

| Folder | Version | What it does |
|---|---|---|
| `WFC_Suite` | 1.0 | Groups the WFC addons in the AddOns list, so each module can be ticked on or off. |
| `WFC_Database` | 5.3 | Shared core for the suite: a QuestieDB layer, recipes, prices and "new!" data. **Required by all the others.** |
| `WFC_Questing` | 5.2 | Ranks your best next quests, and adds a quest panel with a map, rewards, and ignore and track actions. |
| `WFC_Travel` | 5.1 | Finds the fastest route with your flight paths, boats, zeppelins and the tram, and draws it on the world map. |
| `WFC_Professions` | 2.0 | Crafting materials across your characters, scroll recipes, craftable gear for your level, and a skill-up planner. |
| `WFC_ItemTips` | 5.7 | A keep / craft / auction / vendor verdict on item tooltips. Also shows gathering skill on nodes and mobs, and adds a sparkle with a floating name to the nearest vein, herb or skinnable corpse. |
| `WFC_Caster` | 5.2 | A hunter dead-zone range indicator, a Cheetah → Hawk aspect swap, and a Mage AoE cooldown tracker. |
| `WFC_OverlayRevamp` | 7.2 | Whole-UI themes from the **THEMES** button (top-left). |

## Themes

`WFC_OverlayRevamp` has eight looks:

- **Original:** Blizzard's own look.
- **Original+:** stone and gold trim in your race's colours.
- **Modern:** graphite glass.
- **Futuristic:** an amber art-deco holo-city.
- **Nightdrive:** synthwave neon.
- **Wildwood:** a glowing forest.
- **Frostbound:** glacial ice under the aurora.
- **Panelka:** Soviet post-punk concrete and film grain.

Each theme restyles more than windows. It also covers fonts and text colours, the minimap ring, the art that replaces the action-bar gryphons, the hotbar buttons, and screen ambience: haze, motes, fireflies, stars or snow. Panelka can play a song you supply yourself; see `WFC_OverlayRevamp/Media/Music/README.md`.

## Install

1. Copy the `WFC_*` folders into `World of Warcraft/_forever_/Interface/AddOns/`.
2. Make sure **Questie** is installed. `WFC_Database` reads its quest database.
3. Restart WoW fully the first time, so the fonts and textures load.

Type `/wfc` in game for commands, and `/wfcui themes` for the theme picker.

## Market data

`data/` and `Market Research.md` hold auction-house prices and research for the RP-PvP realm (Horde), from Auctionator's saved scans:

- `data/prices.csv`: one row per item, with the latest scan, the deepest scan and the last-seen price.
- `data/price-history.json`: every item's price and listing count for each scan date.
- `data/scans.json`: which scan dates are included, and how many items each one saw.

Prices are minimum buyouts in copper (1g = 10,000c). Under 20 listed, a single seller can set the price.
