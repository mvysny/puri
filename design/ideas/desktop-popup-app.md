# The popup: a search bar that grows into a conversation, history in the same window

Goal: replicate macOS 27.3's Siri popup on GNOME as a native GTK4 app, and fix the one thing
Siri gets wrong: its conversation history lives in a second app (the Siri app). Here it's one
window. Started in pikuri-tui as the secretary's "v3" (`secretary-shell.md` there, moved here
2026-11-11 and split into this file and `trifecta-and-tools.md`).

## What Siri on macOS 27 does (to verify on the owner's Mac)

From secondary sources, [unverified]; the owner has a Mac, so each bullet is a thing to check:

- **Cmd-Space opens Spotlight's "Search or Ask" bar.** Return sends the query to Siri. The answer
  opens *in a separate window*, where the conversation continues
  ([allthings.how](https://allthings.how/siri-ai-in-macos-27-starting-rich-conversations-from-spotlight/),
  [Apple: Use the Siri app on Mac](https://support.apple.com/guide/mac-help/q7ny3g54v9lk)).
  The owner remembers the bar itself growing taller. Which is it? See `Q_siri_growth`.
- **The Siri app has the history**: a sidebar on the left, grid or list view, search, pin, rename,
  delete; synced via iCloud. System Settings picks whether the app opens on the recent
  conversation or a new one, and how many preview lines (0–5) a history row shows.
- **Since 27.2, Siri recalls past conversations** in a new one
  ([geeky-gadgets](https://www.geeky-gadgets.com/siri-ai-mac-test/)). That's memory across
  conversations, not just a history list.

## Our shape

1. **Collapsed:** one rounded, undecorated window holding a single entry ("Ask anything…"), like
   Spotlight. Escape or focus-out hides it.
2. **After Return:** the window grows downward. The user's message on top; under it, while the
   model thinks, an **indeterminate progress bar** (`Gtk::ProgressBar#pulse` from a
   `GLib::Timeout`, or `Adw::Spinner`); then the reply **streams in** as it arrives. The window
   grows with the text up to a maximum height, then the transcript scrolls.
3. **Follow-up:** a new entry appears below the reply (or above it; `Q_followup_position`).
4. **History:** a button (top-right, or a shortcut) widens the window to the left and reveals a
   sidebar of earlier conversations, pikuri-web style: newest first, ordered by start time, a
   `●` on one whose turn is still running, click to load it into the right pane. A second click
   on the button narrows the window back.
5. **Hidden, not closed.** The process stays alive between popups, so the next one is instant and
   the conversation is still there. A setting (as on the Mac) picks "reopen on the last
   conversation" vs "always a new one"; `Q_reopen_policy`.

Confirmations (a gated search, a mail hand-off, a note edit) are an inline row in the transcript:
the question plus two buttons, focused so Enter answers. That's pikuri-tui's
transcript-confirmer, as widgets.

## Process architecture: a daemon and a thin UI, over D-Bus

Nothing decided. The facts to start from:

- **A resident daemon is what makes the rest cheap.** One process owns the agents, the saved
  conversations, the pikuri-rag index of the notes (current the moment the popup opens, no boot
  re-embed) and the reminder timers (`trifecta-and-tools.md`). The UI can come and go.
- **A local socket, never a TCP port.** Privacy first means no network listener, not even on
  loopback. So the D-Bus session bus, GNOME's native IPC: a `.service` file starts the daemon on
  the first call, so it needs no autostart. (A Unix socket in `$XDG_RUNTIME_DIR`, `0700`, is the
  fallback.)
- **The API is pikuri's event stream, serialized.** pikuri-web (Sinatra plus one SSE stream of
  agent events) is the existing proof that a pikuri agent drives a remote UI. Sketch: methods
  `Ask(conversation, text)`, `Cancel(conversation)`, `Answer(confirmation, choice)`,
  `ListConversations()`, `LoadConversation(id)`; signals `TurnStarted`, `TextDelta`, `ToolLine`,
  `ConfirmRequested`, `TurnFinished`. A token-rate stream of D-Bus signals is cheap.
- **Ruby D-Bus without a new dependency:** `ruby-gio2` (already pulled in by `ruby-gtk4`) wraps
  GDBus, which runs on the GLib main loop the GTK side already has. `ruby-dbus` (apt) is the
  pure-Ruby alternative, for a daemon that shouldn't load GLib. `Q_dbus_binding`.
- **The UI can be any language once the API is D-Bus.** Ruby GTK4 first: the owner reads Ruby,
  the stack is all in apt, and it shares pikuri's code. Vala + GTK4 is the runner-up, Flutter the
  wildcard; the candidates, the owner's language tiers and measured startup / memory are in
  `desktop-popup-app/ui-toolkit.md`. Swapping the UI must not touch the daemon.
- **Or no D-Bus between them at all.** The daemon is resident anyway, so a Ruby UI can live in its
  process: it then costs only GTK's share of memory, and its ~1.2 s start is paid once at login.
  The owner counts that as a bonus. `Q_one_process`.
- **Conversations persist like pikuri-web's**: a directory per conversation under
  `~/.local/state/puri/conversations/` with `history.json` (pikuri's `Agent::History`) and
  `meta.json`. Can pikuri-web's persistence move upstream into pikuri so both use one? `Q_history_store`.

## The global shortcut

- **On Wayland no app can grab a global key.** Either a custom shortcut in GNOME Settings that
  runs a command, or the XDG `GlobalShortcuts` portal (recent GNOME implements it; version to
  check).
- **The "ping the running app" script comes free with GApplication.** A `Gtk::Application` is
  single-instance on the session bus: launching the binary a second time only sends `activate` to
  the running one and exits. So the GNOME shortcut runs the app's own binary (or
  `gapplication activate <app-id>`), and no extra script is needed. The app id is reverse-DNS,
  also names the D-Bus service, and is hard to change once shortcuts and `.service` files carry
  it. Leaning `io.github.mvysny.Puri`, matching the GitHub repo: Flathub accepts `io.github.<user>.*`
  and verifies it through `mvysny.github.io`, and has stopped accepting new `com.github.*` ids.
  (Codeberg, and with it `page.codeberg.*`, is out: its Terms of Use §2.7, a July 2026 member
  vote, bars mostly-AI-written projects, and it goes down often.) `Q_app_id`.
- **Super+Space is taken** (GNOME: switch input source). Super alone opens the Activities
  overview. `Q_hotkey`.

## Wayland will fight the Spotlight look

[unverified], to check on the owner's GNOME:

- **A Wayland client can't place its window.** xdg-shell has no absolute positioning; Mutter
  decides. `org.gnome.mutter center-new-windows` centers new windows, but the user may have it
  off, and "a third of the way down the screen" is not on offer. gtk4-layer-shell would do it, but
  Mutter doesn't implement layer-shell. `Q_placement`.
- **Growing the window:** a client may resize itself; Mutter then keeps the top-left corner, so a
  window grows down and right. Growing *centered* (Spotlight-like) isn't possible. Growing down
  is what we want anyway. When the history sidebar widens the window, it grows right; the sidebar
  may have to open on the right, or the window re-centers on its own.
- **Focus-out to hide:** Wayland gives the app `is-active` changes; hiding on loss of focus should
  work, but a confirmation dialog or the file chooser also steals focus.

## Streamed Markdown in GTK

The reply is Markdown, streamed. Options: a `Gtk::TextView` with `TextTag`s, appending as deltas
arrive (rich and selectable; tables are hard), or a `Gtk::Label` re-set with Pango markup per
delta (simplest, but re-parses the whole message each time). pikuri-tui has a streaming Markdown
renderer to ANSI, pikuri-web one to HTML; a Pango target is a third. The parsing half should be
shared, upstream. `Q_markdown`.

**Never load a remote image** the reply names, and treat links with care: both are egress
(`trifecta-and-tools.md`, *Links in the reply*).

## Prototype first: milestones

1. **Single Ruby process, dummy backend.** The popup, the growing window, the progress bar, the
   history sidebar with fake conversations. The backend "thinks" for one second, then streams
   lorem ipsum word by word at ~30 words/s. Developed and screenshotted under Broadway
   (the `gtk4-dev` skill), checked natively on GNOME now and then.
2. **The backend behind the D-Bus-shaped interface**, still dummy, still one process: the UI
   talks only through `Ask` / signals, so the split is mechanical.
3. **The daemon**, a separate Ruby process on pikuri, with the real model and tools.

Components, per the `cop` skill: `PopupWindow` (the one window), `PromptEntry`, `TranscriptView`
(messages, the progress bar, inline confirmations), `HistorySidebar`. Each subscribes to the
backend's events itself; no controller.

## Open questions

- `Q_siri_growth`: on the Mac, does the Spotlight bar grow into the conversation, or does Return
  open a separate window? Copy what feels right, not necessarily what Apple shipped.
- `Q_followup_position`: is the follow-up entry under the last reply, or does the bar stay on top
  and the conversation grow beneath it? Check on the Mac.
- `Q_reopen_policy`: after the popup is hidden for an hour, does it reopen on the old
  conversation? Siri makes it a setting; the default matters more than the setting.
- `Q_one_process`: daemon and GTK UI in one Ruby process, or two over D-Bus? One process drops
  the IPC, the second process and milestone 3's split; the cost is that a GTK crash takes the
  agent and the reminder timers down with it, the daemon needs a graphical session to start (no
  D-Bus activation from a `.service` file; autostart instead), and pikuri's threads reach GTK only
  through the main loop (`GLib::Idle`, the GTK twin of Tuile's `event_queue.submit`). Does a TUI
  or a second UI still want D-Bus later (`Q_tui_client`)?
- `Q_dbus_binding`: GDBus via `ruby-gio2`, or `ruby-dbus`? Does the daemon want GLib at all?
- `Q_history_store`: lift pikuri-web's conversation store into pikuri, or copy its on-disk format?
- `Q_hotkey`: which default shortcut? Super+Space is taken; Alt+Space opens the window menu.
- `Q_placement`: is Mutter's centering good enough, or does the popup need the GNOME Shell
  extension route (which can place windows, but is JavaScript and per-GNOME-version)?
- `Q_markdown`: TextView with tags, or Label with Pango markup? Where does the shared streaming
  parser live upstream?
- `Q_test_harness`: rspec driving the widget tree directly (`button.clicked`, `entry.text =`,
  then a `GLib::MainContext` iteration), the GTK twin of `Tuile::Testing`, with Playwright kept
  for exploratory looks? Specs that take in-process PNGs need a browser attached to Broadway
  (`gtk4-dev` skill).
- `Q_ci`: does Woodpecker's image get `gtk4-broadwayd` + `ruby-gtk4` from apt the same way?
- `Q_tui_client`: once the daemon exists, is a TUI just another client (pikuri-tui talking
  D-Bus)? Not planned; noted because the API makes it cheap.
