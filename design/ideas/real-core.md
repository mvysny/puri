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
  parallel with the answer, on a separate small model: pikuri-web's `Agents::Titler`, ported
  with its prompt (`D_port_pikuri_web`).
- **Persistence** in pikuri-web's format, ported (`D_port_pikuri_web`): a directory per
  conversation under `~/.local/state/puri/conversations/`, pikuri's `history.json` beside
  `meta.json` with `shell: "puri"`.
- **Threads** that keep the UI smooth: the main loop doesn't starve a turn's thread, but Ruby
  work on that thread holds the GVL for up to 100 ms (`R_gvl_main_loop`). So a turn runs at
  `Thread#priority = -3` (a burst stalls the UI by at most ~25 ms), and deltas reach
  `ReplyRenderer` coalesced through pikuri's `Listener::RateLimited`, as pikuri-tui does at
  15 fps, so re-rendering never falls behind the stream.

## Open questions

- `Q_titler`: on one local llama-server, does a parallel titling call slow the answer, or does it
  need its own slot or model?
- `Q_markdown`: pikuri-tui renders Markdown to ANSI, pikuri-web to HTML, `Core::ReplyRenderer` to
  Pango; does the parsing half move upstream, with a renderer per target?
