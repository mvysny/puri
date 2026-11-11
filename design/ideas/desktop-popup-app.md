# The popup: a search bar that grows into a conversation, history in the same window

Goal: replicate macOS 27.3's Siri popup on GNOME as a native GTK4 app, and fix the one thing
Siri gets wrong: its conversation history lives in a second app (the Siri app). Here it's one
window. Started in pikuri-tui as the secretary's "v3" (`secretary-shell.md` there, moved here
2026-11-11 and split into this file and `trifecta-and-tools.md`).

## What Siri on macOS 27 does

From reviews and their screenshots (beta-era, September 2026); [unverified] marks what still
waits on the owner's Mac. Screenshots, linked rather than copied into the repo:
[Spotlight bar](https://9to5mac.com/wp-content/uploads/sites/6/2026/09/Search-of-Ask-Siri-AI-Beta-macOS-27.jpg),
[the bar after an answer](https://cdn.macstories.net/images/uploads/2026/09/12/cleanshot-2026-09-12-at-120741-pm2x-1789229297255-ba7389b063.png),
[Siri app, new conversation](https://9to5mac.com/wp-content/uploads/sites/6/2026/09/Siri-AI-on-macOS-27.jpg),
[the same, titled](https://9to5mac.com/wp-content/uploads/sites/6/2026/09/Siri-AI-beta-dedicated-Siri-app-macOS-27.jpg),
[Siri app with a table](https://cdn.macstories.net/images/uploads/2026/09/12/cleanshot-2026-09-12-at-120958-pm2x-1789229423988-612f9fd04b.png),
[settings](https://cdn.macstories.net/images/uploads/2026/09/08/cleanshot-2026-09-08-at-81559-am2x-1788869773054-52a3f943c7.png).

**The popup.**

- **Cmd-Space opens a pill:** "Search or Ask", a mic on the right, nothing else. **Return guesses**
  (owner, 2026-11-11): "Safari" lists Safari.app and Settings panes and the bar reads "– Open";
  only once more words follow ("Safari something else") does it flip to "– Ask Siri".
- **While it works, the pill shrinks** into an animation with a status word ("Working",
  "Searching") and nothing else. The typed question disappears (owner, 2026-11-11).
- **Then it grows into the answer**, a table included, inside the popup. It's now a dark rounded
  card: `×` top-left, an expand button top-right, the answer, and at the bottom `+` (attach), an
  "Ask Siri" entry and the mic. So the follow-up entry sits **at the bottom**, under the answer
  (owner; [MacMost](https://macmost.com/getting-started-with-siri-ai-in-macos-golden-gate.html)).
  Whether the answer streams in or appears whole is [unverified].
- **Up in the pill brings back the previous question**, shell-style (owner; the first question or
  the last follow-up is [unverified]).
- **After Escape, Cmd-Space brings an empty pill**, not the conversation (owner). The old one is
  only in the Siri app, whose *Opens To* setting applies to the app, not to the pill.
- **Escape closes the card; clicking outside doesn't** (owner). The empty pill, before any
  question, does close on a click outside.
- **The card can be dragged and resized** (owner). Dragging on the answer selects text instead,
  so it drags only by its empty margins.
- **Expand** opens the current conversation in the Siri app, a second window, and closes the
  popup (owner;
  [9to5Mac](https://9to5mac.com/2026/09/17/macos-27-golden-gate-siri-ai-top-features-apples-assistant-finally-comes-to-life-video/)).
  Every popup conversation also lands in the app's history. The owner finds the hand-off weird;
  it's the split we fix.
- **Actions:** creating an event just does it and shows a link to Calendar; a mail opens as a
  draft in Mail for the user to send (MacMost). Changing an event asks first, with two buttons
  in the transcript: grey **Cancel** and red **Update**, white text on both (owner, 2026-11-11).
  The unconfirmed create went wrong for the owner: asked for the private calendar, Siri used the
  family one.

**The Siri app.**

- **Two panes.** Left: the history. Right: the conversation, with a compose button
  (new conversation) top-left and search top-right; the same `+` / "Ask Siri" / mic row at the bottom.
- **History as cards** (grid; a list "like Messages" is the alternative, picked behind an Options
  button). A card: time or date (a pin glyph if pinned), a bold title, then the preview lines,
  which come from the **latest reply**, not the first. An image from the reply becomes a
  thumbnail. The selected card has a blue outline. Newest first, pinned on top.
- **Titles are generated after the fact:** a second after Return, "New Conversation" appears in
  the app; about when the answer is ready, it's renamed by content ("Avocado Preservation")
  (owner, 2026-11-11). Probably from the question alone [unverified].
- **The transcript:** the user's message is a right-aligned grey bubble; the reply is unbubbled
  full-width rich text: headings, bullets, bold, tables, inline images with captions. Each
  paragraph ends in a **source chip** ("sunwarrior.com +2"). Under the last reply: share and `⋯`
  (copy); MacMost also saw thumbs up/down.
- **Control-click a card:** Pin, Rename, Delete (confirmed). Command-click to multi-select.
- **Shortcuts, app only** (owner, 2026-11-11): Cmd-N starts a new conversation, Cmd-F searches,
  Cmd-Delete or Delete asks to delete the conversation. None of them does anything in the popup.
- **Settings live in System Settings → Siri → Siri App:** *Opens To* (Recent Conversations / A New
  Conversation), *Keep Conversations* (Forever / 1 year / 30 days), *Preview* (lines; 0–5 or
  1–5, sources differ). The app has no settings of its own.
- **Siri recalls past conversations** in a new one: asked about yesterday's, it summarized them
  (owner, 2026-11-11; since 27.2 per
  [geeky-gadgets](https://www.geeky-gadgets.com/siri-ai-mac-test/)). That's memory across
  conversations, not just a history list; ours is in `trifecta-and-tools.md`, *Memory*.

## Our shape

1. **Collapsed:** one rounded, undecorated window holding a single entry ("Ask anything…"), like
   Spotlight. **Escape while a turn runs cancels it** (`Cancel`, which interrupts the agent) and
   leaves the window open on the partial answer; **any other Escape hides** the window, so
   Escape twice always hides, even if the cancel hasn't landed (decided 2026-11-11). An
   unstopped turn then runs on hidden and is still saved, `●` in the history. The `×` button
   hides without cancelling.
   Losing focus hides only the empty pill; once a conversation is on screen it doesn't, as in
   Siri, so a glance at another window never loses a running answer. **Return always asks
   Puri.** There's no app or
   settings search and no guessing like Siri's "Open" vs "Ask"; GNOME's Super search does the
   former (decided 2026-11-11).
2. **After Return, the window jumps to its full size at once:** about **33 % of the screen
   width, 70 % of its height**, one resize, no growing with the text (decided 2026-11-11).
   Growing sentence by sentence looks bad, and Siri's card is tall even for a short answer.
   The user's message on top; under it, while the model thinks, an **indeterminate progress
   bar** (`Gtk::ProgressBar#pulse` from a `GLib::Timeout`) with a **status label** under it, the
   latest step as Core words it ("Searching the web…", from `ToolLine`); Siri does the same with
   "Working", "Searching". The reply **streams in from the first turn**, so the first words show
   as soon as they exist. Siri shows a first answer whole and seems to stream follow-ups, too
   fast to tell. The transcript scrolls. **No animations at first:** the resize is one step;
   Siri's shrink-and-grow can come later.
   **Each tool call stays in the transcript as one dimmed line** (`🔍 Searched: "avocado
   preservation"`, `📝 Read note: Shopping`), where Siri shows nothing (decided 2026-11-11). It
   shows what left the machine (*Search, never fetch*), and a local model's many slow steps look
   like progress, not a stall. Core words the line (`ToolLine`); Desktop only draws it. Text the
   model writes between steps streams into the reply like the rest. If it gets noisy, a finished
   turn can fold them into a "3 steps" toggle later.
   *Placement:* if the pill is already 33 % wide, the jump only grows it downward, and Mutter's
   keep-the-top-left rule leaves it centered horizontally. Whether Mutter keeps a 70 %-tall
   window on screen when the pill sat at mid-height is `Q_placement`.
3. **Follow-up:** a new entry appears below the reply.
   **Up** in an empty entry recalls the last question, as in Siri: this conversation's, or in a
   fresh pill the last conversation's. It comes from the transcript or from Core, so Desktop
   keeps no state of its own for it.
   **Drag and resize** like Siri's card: the empty margins drag the window (`Gtk::WindowHandle`),
   and text stays selectable. Does the next popup keep the user's size? `Q_user_resize`.
4. **History, with no expand button and no second app:** where Siri's expand button hands off to
   another app, a button (top-right, or a shortcut) widens the window to the left and reveals a
   sidebar of earlier conversations, pikuri-web style: newest first, ordered by start time, a
   `●` on one whose turn is still running, click to load it into the right pane. A second click
   on the button narrows the window back. **Titles as in Siri and pikuri-web:** "New
   conversation" at once, then Core renames it from the opening question alone, in parallel
   with the answer, on a separate small model (pikuri-web's `Agents::Titler`, which belongs
   upstream with the store, `Q_history_store`). Siri's app shortcuts work everywhere here, since the
   popup *is* the app: **Ctrl-N** a new conversation, **Ctrl-F** opens the sidebar on its search,
   **Delete** on a selected conversation asks to delete it (in an entry, Delete stays a text key).
5. **Hidden, not closed.** The process stays alive between popups, so the next one is instant.
   **The popup always reopens as an empty pill**, as Siri's does (decided 2026-11-11); the last
   conversation is one click away in the history, and Up recalls its last question. No setting
   for now.

Confirmations (a gated search, a mail hand-off, a note edit, an event) are an inline row in the
transcript, as in Siri: the question plus two buttons, focused so Enter answers. That's
pikuri-tui's transcript-confirmer, as widgets. The question names everything that matters
(which calendar, which note), since that is where Siri's create slipped. A destructive action
(update, delete) gets Adw's red `destructive-action` button, a harmless one `suggested-action`.
Enter takes the action; Escape answers Cancel, which then cancels the turn as everywhere else.

## Process architecture: one Ruby process, split as if it were two

Decided 2026-11-11: **one long-running Ruby process** holds both the backend and the GTK4 UI.
It is drawn so that splitting it into two processes over D-Bus later is mechanical.

Also decided: **the UI is Ruby + GTK4 first, Vala + GTK4 second.** If `ruby-gtk4` segfaults or
misbehaves and the cause is the binding, not our code, Desktop alone is rewritten in Vala as its
own process, talking Protocol over D-Bus; Core stays Ruby. The trigger, and why not Python or
Flutter: `desktop-popup-app/ui-toolkit.md`, *Ranking*.

### Why one process

- **Something is resident anyway.** One process owns the agents, the saved conversations, the
  pikuri-rag index of the notes (current the moment the popup opens, no boot re-embed) and the
  reminder timers (`trifecta-and-tools.md`). The model itself runs in llama-server
  (`local-model.md`), not here.
- **No UI starts fast enough on the hotkey**, so the UI stays resident too: hidden, not closed.
  Ruby GTK4's ~1.2 s and ~116 MB (`desktop-popup-app/ui-toolkit.md`) are paid once, at login.
  A second process would save only memory while the UI is hidden.
- **Started by XDG autostart** (`~/.config/autostart/`), not systemd and not D-Bus activation:
  GTK in the process needs the graphical session. The hotkey runs the app's own binary, and
  GApplication hands `activate` to the running instance (*The global shortcut*); if none runs,
  that launch becomes it.
- **The costs, accepted:** a crash in GTK or its bindings takes a running turn and the reminder
  timers down with it; pikuri's threads reach GTK only through the main loop (`GLib::Idle.add`,
  the GTK twin of Tuile's `event_queue.submit`; `Q_main_loop_threads`); restarting to try a UI
  change also reloads pikuri. Any of these hurting is a reason to split; a binding that
  segfaults or misbehaves is a reason to rewrite Desktop in Vala
  (`desktop-popup-app/ui-toolkit.md`, *Ranking*).

### Three namespaces, one Zeitwerk loader

Zeitwerk from day 1, as pikuri does: one loader at `lib/` (pikuri mounts one per gem), eager-loaded
at boot. No `require` between our own files, so a dependency *is* a constant reference.

```
lib/puri/core/       Puri::Core      pikuri, agents, conversation store, reminders, Markdown parsing
lib/puri/protocol/   Puri::Protocol  commands and events as Data.define, JSON-able fields only
lib/puri/desktop/    Puri::Desktop   the widgets and BackendClient
exe/puri             the composition root: requires gtk4, loads Adw, sets up the loader,
                     builds Core, connects it to the Desktop app
```

Allowed: `Core → Protocol`, `Desktop → Protocol`. Forbidden: anything `→ Desktop`,
`Desktop → Core`, `Desktop → Pikuri`, and `Protocol →` anything. Only `exe/puri` knows both
sides.

- **`Puri::Desktop`, not `Puri::Gtk`:** inside `Puri`, a bare `Gtk::Button` would resolve to
  `Puri::Gtk::Button`, and Zeitwerk would go looking for `puri/gtk/button.rb`.
- **GTK and Adw load before the loader.** Desktop classes subclass `Adw::ApplicationWindow` at
  load time, and `module Adw; end` plus `GObjectIntrospection::Loader.load` (`gtk4-dev` skill) is
  not a Zeitwerk-shaped file. So `exe/puri` does both first.
- **Protocol is the D-Bus API, already.** Commands `Ask(conversation, text)`,
  `Cancel(conversation)`, `Answer(confirmation, choice)`, `ListConversations()`,
  `LoadConversation(id)`; events `TurnStarted`, `TextDelta`, `ToolLine`, `ConfirmRequested`,
  `TurnFinished`, `ConversationsChanged` (a new one, a title landed). It is pikuri's event stream, serialized: pikuri-web (Sinatra plus one SSE
  stream) is the existing proof that a pikuri agent drives a remote UI.
- **Markdown is parsed in Core** and crosses as blocks; Desktop only draws them. Even the Ruby UI
  never calls pikuri's parser, so a UI in another language draws the same blocks (`Q_markdown`).
- **The thread hop is Desktop's.** Core emits events on pikuri's threads; `Desktop::BackendClient`
  subscribes and re-delivers each one on the GTK main loop. Core never learns GLib exists (the
  `cop` skill: dependencies point toward data, never toward UI). Components (`TranscriptView`,
  `HistorySidebar`, …) subscribe to the client themselves; no controller.

### Desktop stays lean, so Vala can replace it

Desktop is the part that gets thrown away if the binding fails, so it holds as little as it can:

- **Only widgets and `BackendClient`.** Whatever isn't drawing or input is Core's: ordering and
  titling conversations, formatting a tool line, deciding what a confirmation asks. Desktop
  shows what the event says.
- **No state beyond view state.** Scroll position, which conversation is on screen, whether the
  sidebar is open. Everything else is asked of Core, so a rewrite has nothing to migrate.
- **Plain widget subclasses, one class per file,** each of which maps onto one Vala class. No
  metaprogramming and no Ruby-only tricks in the widget tree.
- **Protocol stays D-Bus-shaped:** flat commands and events with JSON-able fields, nothing that
  needs a Ruby object on the other side.

A feature that makes Desktop grow is a sign that its logic belongs in Core.

### Keeping the split honest

Ruby has no package-private code, and `gtk4` comes from apt, on the default load path whatever a
gemspec says. So separate gems wouldn't enforce anything; checks do:

1. **A boundary tripwire**, grep-based like `design/verify_design_tripwires.sh`, run as a spec and
   in CI. `core/` and `protocol/` never name `Gtk`, `Adw`, `GLib`, `Gio` or `Puri::Desktop`;
   `desktop/` never names `Pikuri` or `Puri::Core`; `protocol/` names neither side. Under
   Zeitwerk every dependency is a constant name, so grep sees all of them.
2. **A runtime spec:** in a fresh process, set up the loader, `eager_load_dir` Core and Protocol,
   and assert `!defined?(::Gtk)`. It catches what grep can't, a gem that drags GTK in. A second
   spec eager-loads everything, Zeitwerk's own check that file names match constants.
3. **Every message round-trips through JSON in-process.** The in-process connection serializes
   each command and event and parses it back, so Desktop never holds a Ruby object from Core
   (say, a pikuri `Agent::History`). Splitting later swaps this connection for D-Bus and nothing
   else.

Packwerk (Shopify) would do 1 statically, but it's a gem apt doesn't ship and the grep is enough
at this size.

### When it splits

Splitting is optional, not a milestone: when the costs above bite, when a second client becomes
real (`Q_tui_client`), or when the UI leaves Ruby for Vala (`desktop-popup-app/ui-toolkit.md`,
*Ranking*). The facts for that day:

- **A local socket, never a TCP port.** Privacy first means no network listener, not even on
  loopback. So the D-Bus session bus, GNOME's native IPC; a `.service` file could then start
  Core on the first call. (A Unix socket in `$XDG_RUNTIME_DIR`, `0700`, is the fallback.)
- **Ruby D-Bus without a new dependency:** `ruby-gio2` (already pulled in by `ruby-gtk4`) wraps
  GDBus on the GLib main loop; `ruby-dbus` (apt) is the pure-Ruby alternative, for a Core that
  shouldn't load GLib. `Q_dbus_binding`.

### Persistence

**Conversations persist like pikuri-web's**: a directory per conversation under
`~/.local/state/puri/conversations/` with `history.json` (pikuri's `Agent::History`) and
`meta.json`. Can pikuri-web's persistence move upstream into pikuri so both use one?
`Q_history_store`.

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
- **Focus-out to hide** is only for the empty pill (*Our shape*): Wayland gives the app
  `is-active` changes, and the pill has no dialog or file chooser that could take focus away.

## Streamed Markdown in GTK

The reply is Markdown, streamed. Options: a `Gtk::TextView` with `TextTag`s, appending as deltas
arrive (rich and selectable; tables are hard), or a `Gtk::Label` re-set with Pango markup per
delta (simplest, but re-parses the whole message each time). pikuri-tui has a streaming Markdown
renderer to ANSI, pikuri-web one to HTML; a Pango target is a third. The parsing half should be
shared, upstream, and runs in Core: Desktop gets parsed blocks through Protocol (*Process
architecture*). `Q_markdown`.

**Never load a remote image** the reply names, and treat links with care: both are egress
(`trifecta-and-tools.md`, *Links in the reply*).

## Prototype first: milestones

1. **The skeleton with a dummy Core.** The three namespaces, the Zeitwerk loader, Protocol, the
   JSON round-trip and the boundary checks from the first commit. The popup, the growing window,
   the progress bar, the history sidebar with fake conversations. The dummy Core "thinks" for one
   second, then streams lorem ipsum word by word at ~30 words/s. Developed and screenshotted under
   Broadway (the `gtk4-dev` skill), checked natively on GNOME now and then.
2. **The real Core** on pikuri, with the real model and tools. Desktop doesn't change.

Splitting into two processes is not a milestone (*When it splits*).

Components, per the `cop` skill: `Desktop::PopupWindow` (the one window), `PromptEntry`,
`TranscriptView` (messages, the progress bar, inline confirmations), `HistorySidebar`. Each
subscribes to `BackendClient`'s events itself; no controller.

## Open questions

- `Q_user_resize`: does the next popup remember a size the user dragged, or always open at
  33 % × 70 %? Also: can an undecorated GTK4 window be resized from its edges on Mutter, or does
  it need GTK's own CSD resize borders?
- `Q_main_loop_threads`: do pikuri's threads (streaming HTTP to llama-server) keep running while
  Ruby-GNOME's main loop sits idle waiting for events, or does the GVL starve them? The first thing
  milestone 1 tests: a dummy Core streaming from a plain Ruby thread is exactly this case.
- `Q_dbus_binding`: only once it splits. GDBus via `ruby-gio2`, or `ruby-dbus`? Does Core want
  GLib at all?
- `Q_history_store`: lift pikuri-web's conversation store and its `Agents::Titler` into pikuri, or
  copy its on-disk format? (*Conventions* forbid a code copy.) On one local llama-server, does a
  parallel titling call slow the answer, or does it need its own slot or model?
- `Q_hotkey`: which default shortcut? Super+Space is taken; Alt+Space opens the window menu.
- `Q_placement`: is Mutter's centering good enough, or does the popup need the GNOME Shell
  extension route (which can place windows, but is JavaScript and per-GNOME-version)?
- `Q_markdown`: TextView with tags, or Label with Pango markup? Where does the shared streaming
  parser live upstream, and what do the parsed blocks look like as JSON in Protocol?
- `Q_test_harness`: rspec driving the widget tree directly (`button.clicked`, `entry.text =`,
  then a `GLib::MainContext` iteration), the GTK twin of `Tuile::Testing`, with Playwright kept
  for exploratory looks? Specs that take in-process PNGs need a browser attached to Broadway
  (`gtk4-dev` skill).
- `Q_ci`: does Woodpecker's image get `gtk4-broadwayd` + `ruby-gtk4` from apt the same way?
- `Q_tui_client`: is a TUI just another client of Protocol (pikuri-tui talking D-Bus)? Not
  planned; noted because Protocol makes it cheap, and it would be a reason to split.
