# Fonts

These fonts are used by `Core/Fonts.lua` (see design.md §2). All are licensed under the SIL Open Font License 1.1. The licence for each family is in the `OFL-<Family>.txt` file next to its fonts.

| File | Family | Source |
|---|---|---|
| `Teko-SemiBold.ttf`, `Teko-Medium.ttf` | Teko (Indian Type Foundry) | static TTFs from github.com/googlefonts/teko (`fonts/ttf`); Google Fonts itself only ships the variable font |
| `BarlowSemiCondensed-Medium.ttf`, `BarlowSemiCondensed-SemiBold.ttf` | Barlow Semi Condensed (Jeremy Tribby) | github.com/google/fonts `ofl/barlowsemicondensed` |
| `AlegreyaSans-MediumItalic.ttf`, `AlegreyaSans-BoldItalic.ttf` | Alegreya Sans (Huerta Tipográfica) | github.com/google/fonts `ofl/alegreyasans` |

They were downloaded on 2026-10-29. All of them cover Basic Latin, Latin-1 and the "·", "~" and "≈" characters the tooltips use.

**After adding or replacing a font file, restart WoW fully.** The client only picks up new files at startup; `/reload` isn't enough.
