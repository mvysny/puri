# The real Core: pikuri behind the finished UI

Milestone 2 of the popup (milestone 1, the whole UI on `Core::DummyCore`, is built and graduated
into `design/architecture.md`). A `Core` on pikuri, with the real model (llama-server,
`local-model.md`) and tools (`trifecta-and-tools.md`), emitting the same Protocol events as
`DummyCore`. Desktop doesn't change; `DummyCore` stays as the GTK specs' backend.

## What Core has to do that the dummy fakes

- **Tool lines** worded by Core from pikuri's tool events (`🔍 Searched: "avocado
  preservation"`, `📝 Read note: Shopping`), and the status under the progress bar from the
  latest step.
- **Confirmations** through pikuri-workspace's `Confirmer` (`Approved`, `Rejected`,
  `Redirected`; pikuri#12). `ask` while one waits is the redirect. The question names everything
  that matters: which calendar, which note.
- **Cancel**: the confirmer, parked in `#ask` on the agent's thread, raises
  `Agent::Control::Cancellable::Cancelled` when the cancel arrives, which ends the turn and
  repairs the stranded tool call. The turn then ends in a `Notice` block, as the dummy's does.
- **Titles**: "New conversation" at once, then renamed from the opening question alone, in
  parallel with the answer, on a separate small model (pikuri-web's `Agents::Titler`, which
  belongs upstream with the store, `Q_history_store`).
- **Persistence** like pikuri-web's: a directory per conversation under
  `~/.local/state/puri/conversations/`, `history.json` (pikuri's `Agent::History`) and
  `meta.json`.

## Open questions

- `Q_main_loop_threads`: do pikuri's threads, blocked in socket I/O streaming from llama-server,
  keep running while Ruby-GNOME's main loop sits idle, or does the GVL starve them? First look
  (2026-11-11, Broadway): `DummyCore`'s thread (`sleep` between words) streamed into the idle
  window through `GLib::Idle.add` without stalling. A starving main loop is a trigger for the
  Vala fallback (`D_ruby_gtk4`).
- `Q_history_store`: lift pikuri-web's conversation store and its `Agents::Titler` into pikuri, or
  copy its on-disk format? (*Conventions* forbid a code copy.) On one local llama-server, does a
  parallel titling call slow the answer, or does it need its own slot or model?
- `Q_markdown`: pikuri-tui renders Markdown to ANSI, pikuri-web to HTML, `Core::ReplyRenderer` to
  Pango; does the parsing half move upstream, with a renderer per target?
