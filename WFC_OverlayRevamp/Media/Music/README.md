# Theme music

The **Panelka** theme plays a track from this folder in place of the zone music while it's the active theme. No music ships with the addon, so supply your own copy.

1. Put your own copy of the song here, named exactly **`toska.mp3`**. Any MP3 works. To use a different song, keep that filename or change `music.file` in `StylePanelka.lua`.
2. **Fully restart WoW**, not just `/reload`. The game only finds files that existed when it started.
3. Pick Panelka from the THEMES button. The song loops until you switch to another theme.

**Commands:**
- `/wfcui music off` turns theme music off. `/wfcui music on` turns it back on.
- `/wfcui debug chrome` shows which track is playing.

The game's Music sound channel has to be on (Esc → Options → Audio). Switching to another theme hands control back to the normal zone music.
