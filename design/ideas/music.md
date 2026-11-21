# Music: "play my favourite music" through Rhythmbox

The scenario: "Remember my favourite music these days is State Azure" lands in `Notes/PURI.md`;
later "Play my favourite music" plays State Azure, shuffled, in the owner's player. That player is
Rhythmbox (owner, 2026-11-21), so v1 drives Rhythmbox alone; pause, next and "what's playing" go
through MPRIS and so work with any player.

Graduates into `R_rhythmbox_dbus` (the flow's facts below), `R_gnome_music_mpris` and `D_music`.

## Why not "the default player"

No desktop standard says "play artist X". MPRIS, what every player and GNOME Shell's media widget
speak, is a remote control: play, pause, next, `Shuffle`, `Metadata`, `OpenUri` of one URI, and an
optional `Playlists` interface that starts one of the player's own playlists. No search
([Player interface](https://specifications.freedesktop.org/mpris-spec/2.2/Player_Interface.html)).

- **GNOME Music can't be handed a track at all:** its `OpenUri` is `"""Not implemented."""` and
  `pass`, and its `.desktop` declares no `MimeType=` (`gnomemusic/mpris.py`,
  `data/org.gnome.Music.desktop.in.in`, master, read 2026-11-21). Its only levers are
  `ActivatePlaylist` on its own playlists and a writable `Shuffle`.
- **The generic route** — Puri finds the tracks in localsearch, writes a shuffled `.m3u`, opens it
  with the default playlist handler — works only for players that play a file they're given, and
  Ubuntu's localsearch reads MP3 tags alone without `localsearch-extractor-ffmpeg` (this box ships
  only `libextract-mp3.so`). Kept for a player other than Rhythmbox, not v1.
- **Rhythmbox opened on a local `.m3u`** (MPRIS `OpenUri` or as a file) imports it as a static
  playlist and deliberately doesn't play it: `data->play = FALSE; /* maybe we should play the new
  playlist? */` (`shell/rb-shell.c`, `load_uri_parser_finished_cb`). Such a playlist would loop,
  but each import adds another, named after the file — two imports of `Puri.m3u` left two
  `Puri.m3u` playlists (spike) — and no D-Bus call deletes one.
- **Puri playing it itself** (GStreamer `playbin`, its own MPRIS for the top-bar widget): one code
  path whatever the player, but a music player inside *a desktop UI and nothing else*, and the
  music dies with Puri. A fallback at most.

## The Rhythmbox flow

Read in Rhythmbox's source (GitHub mirror of GNOME/rhythmbox, master, 2026-11-21), then run end
to end with `gdbus` on the dev box (Rhythmbox 3.4.9-3ubuntu3, 2026-11-21): a private bus, a scratch
home, five `ffmpeg` tones tagged `artist=State Azure` or another artist, on Broadway, no sound
server — `PlaybackStatus` still reads `Playing`. Every step below behaved as written.

1. **Find.** The `dbus-media-server` plugin, `InitiallyEnabled=true`, owns
   `org.gnome.UPnP.MediaServer2.Rhythmbox` and publishes the library at
   `/org/gnome/UPnP/MediaServer2/Library` (`DisplayName` "Music"), whose four child containers are
   `artist`, `album`, `genre` and `all` (owner's desktop, `gdbus introspect`, 2026-11-21). Each
   is an `org.gnome.UPnP.MediaContainer2` with `ListChildren`, `ListContainers` and
   `ListItems(u offset, u max, as filter)`. An artist's container is `…/Library/artist/<name>`,
   the name kept alphanumeric and every other byte written `_XX` in hex, so State Azure is
   `…/artist/State_20Azure` (`encode_property_value`); each item carries `URLs`, `Artist`,
   `DisplayName` (`plugins/dbus-media-server/rb-dbus-media-server-plugin.c`). `Searchable` is
   false and `SearchObjects` answers "search not supported", so Puri lists `artist`'s containers
   and matches the `DisplayName`s in Ruby. Live: `ListContainers` on `…/artist` gives `Path`,
   `DisplayName` and `ChildCount` per artist; `ListItems` on one gives `URLs` as a list of
   percent-encoded `file://` URIs; `…/artist/state_20azure`, lowercased, is an empty list, not an
   error — so match the names, never build the path.
   The tracks are the library the owner sees, in every format Rhythmbox reads: no extractor, no
   `~/Music` root next to `D_documents`' documents folder. The Library is the local library source
   alone; radio and podcasts are sources of their own, so no web URL reaches the player.
2. **Queue.** `org.gnome.Rhythmbox3.PlayQueue` at `/org/gnome/Rhythmbox3/PlayQueue`:
   `ClearQueue` and `AddToQueue(s uri)`, what `rhythmbox-client --clear-queue --enqueue` calls
   (`remote/dbus/rb-client.c`). Puri shuffles; the queue plays in its own order whatever
   Rhythmbox's shuffle says. `ClearQueue` it is, dropping whatever the user queued by hand (owner,
   2026-11-21).
   **The queue never loops** (spike): entries leave it as they play, so MPRIS
   `LoopStatus = Playlist` doesn't reach it. Started through `OpenUri`, the library resumes after
   the last queued track; started as a playlist (MPRIS lists it, as "Play Queue (3)", the name
   localised and carrying the count), it stops. The owner wants the artist to loop (2026-11-21),
   so Puri queues several rounds up front, each shuffled afresh — no listener refilling the queue,
   which would have to tell a drained queue from the user picking other music.
3. **Start.** MPRIS `OpenUri(first)` runs `rb_shell_load_uri`, which plays a library entry at once
   (`plugins/mpris/rb-mpris-plugin.c`, `shell/rb-shell.c`). When it ends the queue takes over: "if
   the new entry isn't from the play queue anyway, let the play queue override the regular play
   order" (`shell/rb-shell-player.c`). Not MPRIS `Play`: from stopped, `rb_shell_player_playpause`
   plays the sidebar's selected source ("no playing source, using selected source"), not the queue.
4. **Control.** MPRIS `PlayPause`, `Next`, `Metadata`, `Volume`; Rhythmbox's `Shuffle` is writable
   (`rb_shell_player_set_playback_state`).
5. **Show it.** Rhythmbox's window opening on a D-Bus start is wanted (owner, 2026-11-21): the
   user sees the action spring to life, where a player in the background gives no sign at all when
   the sound is muted or the headphones are off. By the same reason Puri calls MPRIS `Raise` when
   Rhythmbox already runs (proposed).

```
play_music(artist: "State Azure")
  start Rhythmbox unless org.gnome.UPnP.MediaServer2.Rhythmbox is on the bus; wait for it
  Library/artist → match "State Azure" by DisplayName; no match → the nearest names to the model
  tracks = its items' URLs
  rounds = several shuffles of tracks, each afresh, concatenated            (Q_loop_length)
  PlayQueue.ClearQueue; PlayQueue.AddToQueue each of rounds[1..]
  MPRIS OpenUri(rounds[0]); MPRIS Raise
```

## Promises

- **Search, never fetch.** The tool takes names — an artist, later an album or a genre — never a
  URI, and the URIs come from Rhythmbox's Library alone. A URI parameter would let a mail's "play
  https://…" make the player fetch.
- **No confirmation.** Local playback is no outbound leg, and one pause undoes it.
- **The favourite is a line in `Notes/PURI.md`**, like the home address in `D_places`; the model
  passes the name it reads there.

## Where it lives

Upstream, per *a gap is a missing pikuri primitive*: a Rhythmbox extension in pikuri-workshop, the
MPRIS control perhaps a generic one beside it; Puri mixes its prompt fragment in (`D_own_prompts`).
Wherever it lives it loads into Core, which must stay free of GLib (`spec/boundaries_spec.rb`
aborts when `::GLib` is defined), so no Gio: apt's `ruby-dbus` (0.25.0, pure Ruby, not installed
yet) or shelling out to `gdbus` and parsing GVariant text.

Testing without mocks: the real Rhythmbox runs headless, so a spec can drive it as the spike did —
generated tones, a private bus, Broadway (GTK 3's `broadwayd`), and asserting on MPRIS `Metadata`;
CI would need apt's `rhythmbox`. The trap: export the scratch `HOME`, `XDG_*` and
`GSETTINGS_BACKEND=keyfile` *before* `dbus-run-session`, since the bus daemon hands its own
environment to the Rhythmbox it activates; set inside the session, the spike's first run wrote the
real dconf and `~/.cache/rhythmbox`. A fake on ruby-dbus, the way `spec/support/fake_index.rb`
stands in for localsearch, is the fallback if that is too slow or flaky.

## Open questions

- `Q_loop_length`: how many rounds — a fixed count, or enough for some hours by each item's
  `Duration`? A long queue shows in Rhythmbox's window; after the last round the library resumes.

Answered: the queue is cleared (step 2) and the artist loops (step 2's rounds). No paging:
`ListContainers 0 0` on `…/artist` returned all 826 artists of the owner's library in one call
(2026-11-21). The start is D-Bus activation — any call to `org.gnome.Rhythmbox3` (the spike sent
`org.freedesktop.DBus.Peer.Ping`) runs `/usr/bin/rhythmbox`, the MediaServer2 and MPRIS names
follow — and its window opening is wanted (step 5).
- `Q_match`: "state azure", "State Azur", "Azure": case-folded exact match, else the nearest names
  back to the model, as place search hands back candidates?
- `Q_tool_shape`: one `play_music(artist:, album:, genre:)` or one per container; a
  `music_control` tool for pause, next and "what's playing", or leave those to the media keys?
- `Q_siri_music`, on the owner's Mac: what does Siri say and show for "play my favourite music" and
  "play some State Azure"? Does it shuffle unasked?
- `Q_other_players`: GNOME Music through its own playlists and `Shuffle`, or the localsearch +
  `.m3u` route — only once someone asks.
