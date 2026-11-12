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
- `exe/puri` loads GTK and Adw before the loader eager-loads, builds Core with a listener that calls `BackendClient#deliver`, and hands the client to the one `PopupWindow`. Core is `PikuriCore.from_config` on Puri's required `config.toml`, a missing or broken one aborting before any window; with `--dummy` it is `Puri::Dummy::Backend` from `dev/`, which reads no config, saves nothing and calls no model.
- Protocol is already the D-Bus API: Desktop calls `Protocol::Backend`'s methods, which would map to D-Bus methods; Core pushes `BlockChanged`, `BlockRemoved`, `ActivityChanged` and `ConversationsChanged`, which would map to signals. `BackendClient` round-trips every value through JSON, so a D-Bus connection could take its place.
- A transcript is a list of blocks by id, each re-sent whole on every change: a stale event is overwritten by the next, and a `load_conversation` snapshot converges with events already in flight. A failed or cancelled turn ends in a `Notice` block, not an outcome on a turn event.
- Core does everything but drawing (`D_ruby_gtk4`): it orders and titles conversations, words tool lines and confirmations, and renders a reply's Markdown into `Prose` (Pango markup), `Code` and `Table` parts. Desktop places them and keeps only view state.
- Components subscribe to `BackendClient` themselves, no controller: `PopupWindow` (the one window), `ConversationView` (a `TranscriptView` over a `PromptEntry`) and `HistorySidebar`. `TranscriptView` is pure view, fed by its `ConversationView`.

## Threads and lifecycle

- Core runs each turn on a thread of its own and calls its listener there. `BackendClient#deliver` re-posts each event onto the GTK main loop with `GLib::Idle.add`, the one hop; Core never learns GLib exists. Desktop's calls into Core come from the main loop and return at once.
- Resident: the session bus starts Puri on the first `gapplication launch io.github.mvysny.Puri`, the shortcut's command, or the session does at login with `AUTOSTART=1`; both pass `--gapplication-service`, so no window opens (`R_gnome_activation`). `app.hold` keeps the process alive with every window hidden, and each later launch only activates it: it registers before building Core, and a launch that finds Puri running builds none.
- Escape and `×` hide the window, never close it; the next activation shows the empty pill. A turn left running carries on hidden and is kept, `●` in the history.

## Flows

**A question** (`PikuriCore` and the dummy emit the same; tool lines arrive with the tools):

1. Enter in `PromptEntry` → `ConversationView` → `client.ask(nil, text)`, which returns the new conversation's id at once; `PopupWindow` expands to its full size.
2. On Core's thread: `ConversationsChanged` (a "New conversation" row), `BlockChanged(UserMessage)`, `ActivityChanged(working, status)` — the progress bar and the status under it.
3. Each tool step: `BlockChanged(ToolLine)`, and a new status.
4. `ActivityChanged(streaming)`, then `BlockChanged(Reply)` per delta, the whole reply each time; `ReplyView` updates its parts in place.
5. `ConversationsChanged` again once Core has titled it; `ActivityChanged(idle)` when the turn ends.

**A confirmation** (`D_confirmation_answers`):

1. `ActivityChanged(confirming)` and `BlockChanged(Confirmation, state: pending)`: `ConfirmationRow` shows the question and two buttons; the entry keeps focus.
2. A button → `client.answer(id, block, approved)`; typed text → `client.ask(id, text)`, a redirect; Escape → `client.cancel(id)`.
3. Core re-sends the `Confirmation` with its final state, and the turn goes on or ends.

## Keeping the split honest

- `spec/boundaries_spec.rb` greps each namespace for names across its line (under Zeitwerk every dependency is a constant name), and loads Core and Protocol in a fresh process with no GTK in sight.
- `spec/puri/loader_spec.rb` eager-loads everything: Zeitwerk's own check that file names match constants.
- `Puri::Dummy::Backend` (`dev/`) is the backend the GTK specs drive the widget tree against and `exe/puri --dummy` runs; Core's specs drive `PikuriCore` on `Pikuri::Testing.fake_transport`.

## Where to start reading

`exe/puri` for the wiring, then `lib/puri/protocol.rb` and `Protocol::Backend` for everything the two sides say to each other, then `PopupWindow`.
