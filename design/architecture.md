# Architecture

How the pieces compose — what no single symbol can say and what would be expensive to overturn:
wiring and dependency direction, the lifecycle / threading / data-flow story, the flows a newcomer
needs, where to start reading. **Normative: the code conforms.** Change this file first, then the
code. Not here: why (`decisions.md` — cite the `D_`), what upstream does (`research.md` — cite
the `R_`), one symbol's behaviour (its doc comment), the module map (`AGENTS.md`). Cap 12 KB —
over it, research or doc-comment content has crept in.

---

## Wiring

- One Ruby process, three namespaces on one Zeitwerk loader at `lib/`, eager-loaded at boot (`D_one_process`). Core → Protocol and Desktop → Protocol; nothing points at Desktop, Protocol at nothing, and only `exe/puri` names both sides.
- `exe/puri` loads GTK, Adw and Shumate before the loader eager-loads, builds Core with a listener that calls `BackendClient#deliver`, and hands the client to the one `PopupWindow`. Core is `PikuriCore.from_config` on Puri's required `config.toml`; a missing or broken one, or any other failure to build Core, shows a `FailureDialog` instead, whose close ends Puri; with `--dummy` it is `Puri::Dummy::Backend` from `dev/`, which reads no config, saves nothing, calls no model, and serves its maps' tiles from 127.0.0.1.
- Protocol is already the D-Bus API: Desktop calls `Protocol::Backend`'s methods, which would map to D-Bus methods; Core pushes `BlockChanged`, `BlockRemoved`, `ActivityChanged`, `StatusChanged`, `PendingChanged`, `ConversationsChanged` and `DictationChanged`, which would map to signals. `BackendClient` round-trips every value through JSON, so a D-Bus connection could take its place.
- A transcript is a list of blocks by id, each re-sent whole on every change: a stale event is overwritten by the next, and a `load_conversation` snapshot converges with events already in flight. A failed or cancelled turn ends in a `Notice` block, not an outcome on a turn event. Until a cancelled turn notices, at its next token or tool call, its activity says "Cancelling…": every step reaches `Conversation` through `step`, which leaves that showing.
- `PikuriCore` hosts its conversations through the workshop's `pikuri-conversations` (`D_port_pikuri_web`): `Pikuri::Conversations` runs each one's agent and turns, its `Store` keeps them in `$XDG_STATE_HOME/puri/conversations/<id>/`, its `Titler` names them, and its `Throttle` bounds the requests per server. Each conversation is a `Conversation` (blocks, activity, title; shared with the dummy, which schedules its own turns) and an `AgentSession`: the gem's live conversation, opened on the first `ask`, its `Confirmer` and what the agent is configured with, and its store entry, saved after every turn. The `AgentSession` is that live conversation's listener, and hands what shows to a `TurnListener`, which turns the agent's and the gem's events into blocks, behind the gem's `RateLimitedListener`, which coalesces the deltas. A saved conversation is listed at start and read in (`Replay`) on its first `ask` or `load_conversation`.
- `AgentSession::Initializer` builds each agent from the `Config` `PikuriCore` hands every session: its `Confirmer`, its tools, and any pikuri extension, built afresh for each agent, since it brings its own tools, prompt fragments and hooks. Every agent gets `calculator`, and with a Brave or Exa key `web_search` with page text and `web_read_cached` (`D_search_engines`); pikuri-thunderbird's extension on the `[thunderbird]` profile, whose compose and calendar hand-offs the user commits in Thunderbird, asking nothing; with `[documents]` the `Library`'s file-index tools and a `Workspace::Extension` writable only in `Notes/`, on `AutoApprove`, the memory `Notes/PURI.md` read into the prompt at boot; with `[maps]` `place_search` and `route` (`D_places`), and with `[weather]` too `weather` (`D_weather`), on the process's one `Http` and the session's `Places::Notebook`, saved in `meta.json`; and `play_music` where the session bus can start Rhythmbox (`D_music`). The system prompt is `prompts/puri.txt` plus a fragment per capability, saying what the agent has or lacks.
- A `[[server]]` with no `url` is a `llama-server` Puri runs itself (`D_embedded`): `Config.load` gives it a loopback port and a key for the run, and `PikuriCore.from_config` starts a `LlamaServer` on the model its `[[llm]]`s name, found in the `HubCache`. An agent booting on it waits in `Initializer#configure` until the model has loaded, "Starting the model…" showing; one that can't load fails the boot, its notice saying why.
- `Library` is the `[documents]` folder for every conversation at once, built by `PikuriCore.from_config`: `Notes/`, the memory, and the pair of stateless file-index tools every agent shares, rooted at the folder, over the first of pikuri-fileindex's backends whose index holds it (`D_documents`). `ToolWording` words a call's status and its `ToolLine` from the tool's own strings, with Pango markup where a data source's credit is linked, for `TurnListener` live and `Replay` from the saved call alike.
- The models are the config's `[[llm]]` connections, a `Models` catalog by name. A new conversation starts on the one picked last, the first `[[llm]]` until a pick; a saved one resumes on the connection it was saved on, while the config still has it. A pick goes to the gem's `switch_model`, so a running turn ends on its own model. Each conversation's `Status` — the model its next turn uses and the context readout — is its `AgentSession`'s: a `ContextReadout` over pikuri's `TokenLog`, zeroed at every boot, and the gem's `ContextCap`. It rides the `Transcript` and `StatusChanged`.
- Core does everything but drawing (`D_ruby_gtk4`): it orders and titles conversations, words tool lines and confirmations, and renders a reply's Markdown into `Prose` (Pango markup), `Code` and `Table` parts. Desktop places them and keeps only view state.
- `bin/setup` is a program of its own (`D_setup`): `Setup::Packages` and `Setup::Bundle` on Ruby's stdlib, then an `exec` into `Setup::Doctor` under the bundle, which reads Core's `Config` and `HubCache`, never Desktop. `rake install` and the doctor share `Setup::Install`.
- Components subscribe to `BackendClient` themselves, no controller: `PopupWindow` (the main window), `ConversationView` (a `TranscriptView` over a `PromptEntry`, a `DictationRow` while dictating, and a `StatusBar` once expanded) and `HistorySidebar`. `TranscriptView` is pure view, fed by its `ConversationView`.

## Threads and lifecycle

- Core runs each turn on a thread of its own, the gem's, and calls its listener there. `BackendClient#deliver` re-posts each event onto the GTK main loop with `GLib::Idle.add`, the one hop; Core never learns GLib exists. Desktop's calls into Core come from the main loop and return at once.
- A turn's thread runs at `priority = -3`, so a burst of Ruby on it stalls the main loop by ~25 ms at most rather than a 100 ms slice (`R_gvl_main_loop`), and the limiter hands `TurnListener` a streaming reply's deltas at most 15 times a second, so re-rendering never falls behind the stream. `TurnListener` keeps its state on the turn thread, lock-free: the gem's other events may come from the thread that submits or cancels, and change nothing there. A new conversation's title runs on a thread of its own once its first turn has ended (`D_titler_model`); `PikuriCore#close` is the gem's `shutdown`: it cancels every turn and waits, 5 s in all, for each to be saved and its agent closed. Whether a conversation shows as working is the gem's `Status#busy?`, re-read on every event.
- `LlamaServer` runs its child under `setpriv --pdeathsig`, tied to the thread that waits on it and restarts it, so a killed Puri leaves no model loaded; `PikuriCore#close` stops it once the turns are saved.
- Resident: the session bus starts Puri on the first `gapplication launch io.github.mvysny.Puri`, the shortcut's command, or the session does at login with `AUTOSTART=1`; both pass `--gapplication-service`, so no window opens (`R_gnome_activation`). `app.hold` keeps the process alive with every window hidden, and each later launch only activates it: it registers before building Core, and a launch that finds Puri running builds none.
- Escape and `×` hide the window, never close it; the next activation shows the empty pill. A turn left running carries on hidden and is kept, `●` in the history. An activation while it shows unfocused maps it afresh, as it is (`R_gnome_activation`).

## Flows

**A question** (`PikuriCore` and the dummy emit the same):

1. Enter in `PromptEntry` → `ConversationView` → `client.ask(nil, text)`, which returns the new conversation's id at once; `PopupWindow` expands to its full size.
2. On Core's thread: `ConversationsChanged` (a "New conversation" row), `ActivityChanged(working, status)` — the progress bar and the status under it — and `BlockChanged(UserMessage)` once the turn starts.
3. Each tool step: `ActivityChanged(working, "Searching the web…")` as the call starts, then `BlockChanged(ToolLine)` and "Thinking…" once it answers.
4. `ActivityChanged(streaming)`, then `BlockChanged(Reply)` per delta, the whole reply each time; `ReplyView` updates its parts in place.
5. `ActivityChanged(idle)` when the turn ends; `ConversationsChanged` again a second later, once Core has titled it.

**A place answer** (`D_place_map`): a place tool's `ToolResult` shows its `ToolLine`, and `TurnListener` looks the result's text up in the `Notebook` for the map that call drew; a completed turn ends in `BlockChanged(Map)` of its last one, under the answer. `Replay` closes a saved turn the same way. `PlaceMap` draws it with libshumate, whose tiles come from the `[maps]` server; a pin click opens the place in GNOME Maps or the browser.

**A message sent while a turn runs** reaches the model after the turn's current step, through pikuri's `Interloper`, and its `UserMessage` shows then; a turn that has already answered starts another to read it. Until then it waits as a dimmed "queued" bubble at the bottom of the transcript: the gem's `PendingChanged` carries the whole queue, which `AgentSession` hands on as the texts of its user items, a `PendingChanged` of ours that `Transcript#pending` also carries. The first message, waiting while the agent boots, shows so too. Escape drops it, shown as a `UserMessage`, before the `Cancelled` notice.

**A confirmation** (`D_confirmation_answers`):

1. `ActivityChanged(confirming)` and `BlockChanged(Confirmation, state: pending)`: `ConfirmationRow` shows the question and two buttons; the entry keeps focus.
2. A button → `client.answer(id, block, approved)`; typed text → `client.ask(id, text)`, a redirect; Escape → `client.cancel(id)`.
3. Core re-sends the `Confirmation` with its final state, and the turn goes on or ends.

**Dictation** (`D_dictation`), the entry's, not a conversation's: F5 or the entry's mic →
`client.toggle_dictation`. With `[dictation]`, `PikuriCore`'s `Dictation` reads `pw-record`'s raw
PCM on a thread of its own, `DictationChanged(listening)` carrying the level ~15 times a second;
the next toggle stops it, `transcribing`, and its transcriber turns the clip into text: `Transcriber`
posts it as a WAV through a RubyLLM context of its own, or, with no `url`, `WhisperCli` pipes it
through `whisper-cli`; `idle` carries the text, which `ConversationView` inserts at the
cursor. Escape or hiding the window → `cancel_dictation`; a late answer is dropped.

## Keeping the split honest

- `spec/boundaries_spec.rb` greps each namespace for names across its line (under Zeitwerk every dependency is a constant name), and loads Core and Protocol in a fresh process with no GTK in sight.
- `spec/puri/loader_spec.rb` eager-loads everything: Zeitwerk's own check that file names match constants.
- `Puri::Dummy::Backend` (`dev/`) is the backend the GTK specs drive the widget tree against and `exe/puri --dummy` runs; Core's specs drive `PikuriCore` on `Pikuri::Testing.fake_transport`.

## Where to start reading

`exe/puri` for the wiring, then `lib/puri/protocol.rb` and `Protocol::Backend` for everything the two sides say to each other, then `PopupWindow`.
