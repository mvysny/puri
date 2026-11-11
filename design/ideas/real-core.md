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
- **Titles**: "New conversation" at once, then renamed from the opening question alone by
  pikuri-web's `Agents::Titler`, ported with its prompt (`D_port_pikuri_web`), on the main model
  with its thinking off. One model stays loaded, and thinking off is what makes a title cost ~1 s
  rather than ~30 s; pikuri-web measured both, and the small instruct models it tried failed the
  job (wrong language, obeying the opener; its `D_titler_connection`). The titler is a second
  connection to the same llama-server that differs only in `params` (Ornith 1.5's thinking-off
  switch). `Titler`'s caps and `</think>` strip stay, because a server can accept that parameter
  and ignore it. Both connections share the server's one permit (`ServerPermits`), so the title
  queues instead of racing the answer: on a local box a second stream costs nearly its full share
  of memory bandwidth (pikuri-web's README, *How many conversations can think at once*). Core
  starts the titler on the turn's first event, so the answer holds the permit first and the title
  lands after that request ends.
- **Persistence** in pikuri-web's format, ported (`D_port_pikuri_web`): a directory per
  conversation under `~/.local/state/puri/conversations/`, pikuri's `history.json` beside
  `meta.json` with `shell: "puri"`.
- **Threads** that keep the UI smooth: the main loop doesn't starve a turn's thread, but Ruby
  work on that thread holds the GVL for up to 100 ms (`R_gvl_main_loop`). So a turn runs at
  `Thread#priority = -3` (a burst stalls the UI by at most ~25 ms), and deltas reach
  `ReplyStream` coalesced through pikuri's `Listener::RateLimited`, as pikuri-tui does at
  15 fps, so re-rendering never falls behind the stream.

## Open questions

- `Q_titler_cache`: one llama-server slot holds one prefix cache, so the titling request evicts
  the conversation's prefix, and the first turn's next request prefills the system prompt, tools
  and history again. pikuri-memory measured the same eviction with mem0's extraction call. Does
  llama-server's host-memory prompt cache (`--cache-ram`) restore that prefix, or does the titler
  need a second slot (`--parallel 2` with one permit, which splits `--ctx-size`)? This needs
  measuring on Ornith 1.5.
- `Q_reply_parts`: `ReplyStream` converts each finished block once, but Protocol still re-sends
  the whole `Reply` per delta, and Desktop rebuilds it. Should a finished part cross once, so only
  the open tail's parts repeat? It would shrink the JSON per delta and the widgets Desktop
  replaces, at the cost of a Protocol change.
