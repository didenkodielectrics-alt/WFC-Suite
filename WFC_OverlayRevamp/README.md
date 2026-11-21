# WFC_OverlayRevamp

> **7.2: Panelka, music, readable dialogue.**
> - **Panelka** is Soviet post-punk / coldwave, in the mood of Molchat Doma. Cold black-and-white:
>   - hard square concrete frames, poured-concrete texture, flickering film grain and a VHS band rolling down;
>   - a row of grey panel apartment blocks with a few lit windows at the bottom of each window;
>   - constructivist bars in the corners, a red constructivist emblem on the top edge, a red poster stripe under the title, and signal-red buttons.
>
>   A panel tower with a red aircraft light replaces the gryphons, a radio dial turns around the minimap, and slow grey snow falls under a heavy cold vignette. Teko titles with paper-white labels.
> - **Theme music:** a pack can name a track (`spec.music`). Panelka plays `Media/Music/toska.mp3` in place of the zone music while it's active. You supply the file yourself; none ships with the addon (see `Media/Music/README.md`). Commands: `/wfcui music on|off`.
> - **Dialogue stands out:** Forever's gossip and quest-greeting lists are ScrollBoxes. Each line and option is now recoloured as it appears: text in the pack's reading colour, options in its heading colour, lit on hover. The quest text fonts take the pack's reading colours too. The quest-text hooks are now installed once instead of again on every addon load.
> - **Film grain:** tiled art can `jitter` (jumps to a random spot a few times a second).

> **7.1: seven themes, hotbars and every window.**
>
> **Three new themes:**
>
> | Theme | Look |
> |---|---|
> | **Nightdrive** | Retro-80s synthwave. Purple-black glass lit by a hot-pink neon tube with a cyan inner tube. A striped sunset sun sinks into a neon perspective grid, over magenta horizon haze and CRT scanlines. Pill buttons flood pink and flash cyan. Teko titles with cyan labels. The minimap gets a double neon ring, neon palms replace the gryphons, and stars twinkle across the screen. |
> | **Wildwood** | A bioluminescent forest at night. Moss-green glass in bark-gold trim with an inner leaf line, glowing vine-and-bud corners, a fern silhouette and a teal mist at the bottom of each window. Marcellus SC titles with lime-gold labels. The minimap sits in a vine wreath, glowing trees of life replace the gryphons, and fireflies wander the screen. |
> | **Frostbound** | A glacial citadel under the northern lights. Blue-black frosted glass with faceted ice edges, ice-crystal corners, an aurora ribbon across the top, glacier peaks at the bottom and a snowflake emblem that turns. Michroma titles with ice-blue labels. The minimap gets a crown of ice shards, ice-crystal spires replace the gryphons, and snow falls over the screen. |
>
> **Also new in 7.1:**
> - **Hotbars:** every style pack reframes the action buttons (main, multi, pet and stance bars) with its own rim and glow, which lights up on hover. Blizzard's button frame art is faded; icons, cooldowns, counts and hotkeys stay. Original and Original+ leave the bars alone.
> - **Screen chrome is data:** each pack's `chrome` table (minimap ring layers, the art that replaces the gryphons, hotbar buttons, ambience gradients and particles) is drawn by `Chrome.lua`. Minimap rings are children of the minimap, so they follow its scale.
> - **Every Blizzard window:** frames from the UI-panel table, the Escape-close list and every `ShowUIPanel` call are themed automatically, including the world map and quest log, the Legacy Points window and anything Forever adds. Only windows whose global was created by Blizzard's own code are picked up, never another addon's. The world map's frame art on `BorderFrame` is faded; the map canvas itself is never touched.
> - **Bagnon:** its inventory and bank windows are themed when Bagnon opens them.
>
> New art is in `Media/Nightdrive/`, `Media/Wildwood/` and `Media/Frostbound/` (`nd_*`, `ww_*`, `fb_*` drawn with Gemini). Mock-ups are `Media/preview_nightdrive.png`, `preview_wildwood.png` and `preview_frostbound.png`. Commands: `/wfcui style nightdrive|wildwood|frostbound`, `/wfcui debug chrome` (what was found for the minimap, gryphons and hotbars), and `/wfcui skin <Frame> off` (keep one window Blizzard's).

> **7.0: four whole-UI themes**, picked from the **THEMES** button. It sits next to the WFC launchers in the top-left, drawn as a 2×2 swatch. Left-click opens the picker, right-click cycles, drag moves it, and Shift+right-click puts it back. `/wfcui themes` also opens the picker.
>
> | Theme | Look |
> |---|---|
> | **Original** | Blizzard's own windows, fonts and colours (skinning off). |
> | **Original+** | The 6.0 stone-and-gold skin accented by your race (everything below). |
> | **Modern** | Graphite glass: rounded cards, a soft 44 px shadow and frosted noise. An aurora glow (Gemini art) sits behind the title, with an indigo-to-cyan accent line along the top. Pill buttons light up indigo, tabs are segmented, and tooltips get a left quality bar. Type is Barlow Semi Condensed with cool-white labels instead of gold. The minimap gets a glass ring, the gryphons are hidden, and the screen gets a soft cinematic vignette. |
> | **Futuristic** | An amber holo-city, inspired by a golden art-deco metropolis. Warm-black glass sits under an amber sky haze with a city glow rising from below. A skyline and halo watermark, circuit traces and drifting scanlines fill the panel. Edges are chamfered double gold lines with an amber glow. Art-deco corner brackets frame each window, a halo emblem turns on the top edge, light rails run up the sides, and a light sweeps the top border. Chip buttons and tabs carry glowing nodes, and the reading panel is a holo grid. Type is Teko headers with amber labels. The minimap gets a gold HUD ring with a turning dial, art-deco spires replace the gryphons, and golden motes drift up the screen. |
>
> Files: `Styles.lua` (the pack painter) with `StyleModern.lua` / `StyleFuturistic.lua` (data), `Chrome.lua` (minimap, end caps, ambience), `ThemeButton.lua` (launcher and picker). Art is in `Media/Modern/` and `Media/Futuristic/`: `fx_*`/`md_*` were drawn with Gemini, the rest is procedural. Mock-ups are `Media/preview_modern.png` and `Media/preview_futuristic.png`. New commands: `/wfcui style original|originalplus|modern|futuristic`, `ambience on|off`, `module chrome off|on`. `GetTheme()` returns the style's tokens, with `pack` set, for Modern and Futuristic.

An **optional** addon that restyles Forever's windows and tooltips in Forever's own visual language (dark stone panels, burnished gold trim, filigree corners, a jewelled crest), accented by your character's race and faction colour.

> **6.0 look** (supersedes the flat style described further down where they differ): stone-textured panel with a soft drop shadow and inner vignette; 6 px gold bevelled trim; gold filigree corners (top-left, bottom corners) and a crest on the top edge whose gem takes the race accent; accent glow under the title with a fading gold divider; an accent hairline inside the trim; lacquered buttons with a bronze rim that warms to the accent on hover; framed tabs with an accent underline. Headers use Marcellus SC for every race; body text keeps Blizzard's font. Art lives in `Media/Frame/` (corner and crest drawn with Gemini, border/shadow/stone generated procedurally); `Media/preview_*.png` are mock-ups. Every icon is kept, and decoration stays away from text and buttons. Requires **WFC_Database**. Design: [../design.md](../design.md) §7. Rules: [../CoreRules.md](../CoreRules.md) R4–R6.

## Themes
Picked automatically: your race's theme, else your faction's, else neutral. Or choose one with `/wfcui theme <name>`.

| Horde | Accent | Ornaments | Alliance | Accent | Ornaments |
|---|---|---|---|---|---|
| Orc | blood red | riveted iron brackets, spiked band | Human | gold | crown caps, gold rule |
| Forsaken | plague green | thorns | Dwarf | bronze | rune plates |
| Tauren | ochre | feather tips, totem band | Night Elf | lavender | moon and leaf |
| Troll | jungle teal | tusk hooks | Gnome | teal | cog quarters |
| Skyborne (Horde) | storm blue | wind curls | Skyborne (Alliance) | white-gold | wing tips |
| *Horde* | Questie Horde red | notched corners | *Alliance* | Questie Alliance blue | notched corners |

*Neutral* (no faction yet): cyan, no ornaments.
- **Fonts:** Horde headers use Teko; Alliance headers use Marcellus SC (shipped in `Media/Fonts/`, OFL); if it ever fails to load, they fall back to Teko. Body text uses Barlow Semi Condensed in both.
- **Readability:** every theme passes the contrast rule (text at least 7:1 and muted text at least 4.5:1 on the window colour), checked by the specs.

## What it changes
- **Windows:** the frame art is faded (`SetAlpha(0)`, never hidden), and our own backdrop sits behind the content. It has a flat fill, a 1 px border, a short gradient band behind the title, and ornaments only in the outer zone: the bottom corners, the top-left corner when nothing's there, and a thin band on the top edge. Never the top-right, where close buttons live.
  - **Buttons:** flat surface fill with a 1 px border; hover tints them with the accent.
  - **Tabs:** flat, with a 2 px accent underline on the selected one.
  - **Titles and tabs:** use the theme fonts.
- **Fonts:** Blizzard's font objects are re-pointed to the theme families, keeping each one's size and outline. Chat, quest text, numbers, combat text and nameplates are left alone, and non-Latin clients keep Blizzard's fonts.
- **Tooltips:** flat at 95%, with a 1 px border; item tooltips get a 1 px top edge in the item's quality colour. The WFC tooltip lines keep their italic font.
- **Windows covered:**
  - Character, spellbook, quest log, merchant, mail, gossip and quest dialogue, friends, group finder, game menu, settings, bags, loot, popups and more.
  - Load-on-demand windows (auction house, professions, trainer, communities) when they load.
  - Bank, trade, and the WFC windows (quest panel, rewards, dungeon map, travel box, dev log).
- **WFC windows** keep their own fonts unless "Use theme header fonts in WFC windows" is on.
- **Not touched:** unit frames, action bars, nameplates, Edit Mode positions, the cooldown manager, the damage meter, and the world map. The map is taint-sensitive, so its border stays Blizzard's.

## Safety (CoreRules)
- **Purely cosmetic:** it only fades art and adds our own frames. It never calls `SetPoint`, `SetSize`, `Show` or `Hide` on Blizzard frames, never writes attributes, and never replaces scripts; it only uses `HookScript` and `hooksecurefunc`. Nothing is written onto Blizzard frames: our state lives in weak tables.
- **Timing:** each window is skinned the first time it shows, and only out of combat. A window that first opens in combat is done when combat ends.
- **Reversible:** `/wfcui theme blizzard` restores Blizzard's look live, including the fonts.
- **Conflict guard:** with ElvUI or Aurora loaded, only the WFC windows are skinned. With ForeverUI or ForeverClassicUI, their windows are left to them. Either way it says so once in chat.

## Commands
`/wfcui` (status) · `theme <name|auto|blizzard>` · `ornaments off|subtle|normal` · `skin <FrameName> off|on` · `module fonts|tooltips|core|economy|wfc off|on` · `list` · `debug zones` (ornaments in magenta, to check the 8 px rule) · `options`

Also available as `/wfc ui …`, and in **Options → AddOns → WFC → OverlayRevamp**.

## Files
| File | Role |
|---|---|
| `Themes.lua` | Theme tokens, theme choice, contrast maths (pure). |
| `Skin.lua` | The skin engine: backdrop, ornaments, buttons, tabs, lazy and reversible application. |
| `Fonts.lua` | Global font re-pointing and the theme font objects. |
| `Frames.lua` | Which frames get skinned, the conflict guard, tooltip quality edges, start-up. |
| `Settings.lua` | Defaults, SavedVariables, `GetTheme()`, `/wfcui`, the options page. |
| `Media/Ornaments/*.tga` | Corner pieces (64×64) and title bands (128×16), white on transparent, tinted per theme. |
| `tools/build_ornaments.py` | Draws the ornaments. They're simple geometric placeholders; swap in hand-drawn art with the same names and sizes. |

## For WFC addons
`WFC_OverlayRevamp.GetTheme()` (also `WFC.OverlayRevamp.GetTheme()`) returns the active token table (`bg`, `surface`, `border`, `accent`, `accentSoft`, `text`, `textMuted`, `headerFont`, `bodyFont`, `ornament`, `titleBand`), or nil for Blizzard's look.
