# WFC_ItemTips

Adds a verdict to item tooltips: **keep**, **craft**, **auction** or **vendor**, with the reasons underneath. Requires **WFC_Database** (and through it QuestieDB). Plan: [../plan.md](../plan.md) §3. Look: [../design.md](../design.md) §3.

```
Linen Cloth
Sell Price: 13c
──────────────────────────────  new!
► Craft
   Craft: Linen Bandage · First Aid (orange)
   Craft: Heavy Linen Bandage · First Aid (orange) · uses 2
   Auction ~12s · Vendor 13c
```

## Verdicts (highest wins the headline)
| # | Verdict | Colour | When |
|---|---|---|---|
| 1 | Keep for quest | red | An objective of a quest in your log (shows `have/need`), or the item starts a quest you can accept. |
| 2 | Keep for upcoming quest | orange | Needed by a quest you can take within 3 levels, or one prerequisite away. |
| 3 | Craft | yellow | A reagent for a recipe this character, or a same-faction alt, knows or can learn within 25 skill points, where the recipe is orange/yellow or the craft is profitable. |
| 3½ | Disenchant | yellow | An enchanter on the account (this character for soulbound items) has the skill, and the expected materials are worth more than selling: by 10% and by half the minimum profit. Uses Classic's disenchant tables (dust, essence and shard chances by item level; weapons give more essence) priced from your AH data. |
| 4 | Auction | green | AH price × 0.95 − deposit beats the vendor price by 10% **and** by the minimum profit (default 50s). Never for soulbound items. |
| 5 | Vendor | grey | Junk, soulbound with no other use, or the vendor pays at least the AH net. |

Prices come from another addon's scan (Auctionator on Forever) through `WFC.DB:GetPrice`. WFC doesn't scan the auction house itself. Without price data the tooltip says "no AH data".

## Behaviour
- Lines are appended after Blizzard's and Questie's, under a thin rule, with the cyan **new!** tag for new content.
- At most 4 lines (headline + 3). **Hold Shift** to see every reason.
- **Gathering Indicators:** Displays required skill and skill-up difficulty (Red / Optimal / Medium / Low / Trivial) for:
  - **Skinning:** alive beasts and dragonkin.
  - **Mining:** world mineral veins (Copper, Tin, Iron, Thorium, etc.), minable elementals/golems, and ore items.
  - **Herbalism:** world herb nodes (Peacebloom, Silverleaf, Black Lotus, etc.), herbable plant creatures, and herb items.
  - Includes same-faction alt skills (e.g. `Requires 65 (Alt: 120)`).
- In combat nothing is added. Fonts are set only on WFC's own lines and restored when the tooltip clears.
- Only `GameTooltip` (bags, AH, merchants, world) and `ItemRefTooltip` (chat links) are touched.
- Alts: each character's professions are saved when it logs in; recipes are saved when its profession window is opened (the Database harvester). Until then, trainer recipes at or below the character's rank count as known.

## Commands
`/wfc tips` (status) · `on|off` · `reasons on|off` · `shift on|off` (only while Shift is held) · `alts on|off` · `profit <silver>` · `why <itemId>` (prints the full evaluation) · `options`

The same toggles are under **Options → AddOns → WFC → ItemTips**.

## Files
| File | Role |
|---|---|
| `Advisor.lua` | The rules. Pure Lua, no WoW API: tested directly in `spec/advisor_spec.lua`. |
| `Disenchant.lua` | Classic disenchant results, skill requirements and expected value (pure). |
| `Format.lua` | Advisor result → tooltip lines (colours, labels, line cap). |
| `Context.lua` | Builds the Advisor's input from `WFC.DB` and caches each item's result until quests, professions, prices or recipes change. |
| `Tooltip.lua` | The tooltip hook, font hygiene, Shift refresh. |
| `Settings.lua` | Defaults, SavedVariables, `/wfc tips`, the options page. |

## Tests
From `Database/`: `python tools/run_tests.py` runs these specs together with the Database ones.
