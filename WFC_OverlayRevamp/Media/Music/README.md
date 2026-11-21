# Theme music

The **Panelka** theme shuffles songs from this folder in place of the zone music while it's the active theme.

## Credits

The bundled songs come from the **YouTube Audio Library** and are marked free to use. Some Audio Library tracks require the artist to be credited, so fill in each row from the track's Audio Library page.

| File | Title | Artist | License |
|---|---|---|---|
| `toska.mp3` | | | YouTube Audio Library, free to use |
| `track1.mp3` | | | YouTube Audio Library, free to use |
| `track2.mp3` | | | YouTube Audio Library, free to use |
| `track3.mp3` | | | YouTube Audio Library, free to use |
| `track4.mp3` | | | YouTube Audio Library, free to use |
| `track5.mp3` | | | YouTube Audio Library, free to use |
| `track6.mp3` | | | YouTube Audio Library, free to use |

`silence.mp3` was generated for the addon and isn't a song.

## Adding your own songs

1. Put your songs here. WoW can't list a folder, so these are the only names it looks for:
   - `toska.mp3`
   - `track1.mp3`, `track2.mp3` … up to `track20.mp3`. `.ogg` works too.

   Use any of those names, in any order. Gaps are fine: names that don't exist are skipped.
2. **Fully restart WoW**, not just `/reload`. The game only finds files that existed when it started.
3. Pick Panelka from the THEMES button.

**How it plays:**
- The playlist is shuffled. When a song ends the next one starts, every round is reshuffled, and the same song never plays twice in a row.
- Songs play on the **Music** channel, so the music volume slider applies.
- `silence.mp3` is part of the addon, not a song: it keeps Blizzard's zone music quiet while your playlist plays. Leave it in place.

**Music bar:** while the playlist runs, three buttons appear in the top-left, right of the THEMES button:
- **|<** goes back to the previous song.
- **||** pauses, and **>** plays again. WoW can't resume a sound partway through, so play starts the song over. The zone music stays quiet while paused.
- **>|** skips to the next song.

Hover any of them to see what's playing.

**Commands:**
- `/wfcui music next` skips to another song.
- `/wfcui music prev` goes back to the previous song.
- `/wfcui music pause` pauses, and running it again plays.
- `/wfcui music list` shows what's playing and how many songs it has found.
- `/wfcui music off` turns theme music off, and `/wfcui music on` turns it back on.

The game's Music sound channel has to be on (Esc → Options → Audio). Switching to another theme hands control back to the normal zone music.
