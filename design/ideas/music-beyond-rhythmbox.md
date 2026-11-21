# Music beyond `play_music` in Rhythmbox

`play_music` plays an artist, an album, a song or a genre in Rhythmbox (`D_music`,
`R_rhythmbox_dbus`). What it left open:

- `Q_music_control`: a `music_control` tool for pause, next and "what's playing", through MPRIS so
  it works with any player? Left to the media keys and GNOME's media widget for now (owner,
  2026-11-21).
- `Q_other_players`: GNOME Music through its own playlists and `Shuffle`, or the generic route —
  the tracks from localsearch, a shuffled `.m3u` opened with the default playlist handler, which
  needs `localsearch-extractor-ffmpeg` for anything but MP3 (`R_gnome_music_mpris`) — only once
  someone asks.
- `Q_siri_music`, on the owner's Mac: what does Siri say and show for "play my favourite music" and
  "play some State Azure"? Does it shuffle unasked?
- `Q_upstream`: the move to pikuri-workshop, a Rhythmbox extension with its prompt fragment, the
  MPRIS control perhaps a generic one beside it; Puri mixes the fragment in (`D_own_prompts`).
