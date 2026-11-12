# The real Core: pikuri behind the finished UI

Milestone 2 of the popup (milestone 1, the whole UI on `Core::DummyCore`, is built and graduated
into `design/architecture.md`). A `Core` on pikuri, with the real model (llama-server,
`local-model.md`) and tools (`trifecta-and-tools.md`), emitting the same Protocol events as
`DummyCore`. Desktop doesn't change; the dummy stays as the GTK specs' backend, now
`Puri::Dummy::Backend` in `dev/`.

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
  switch, `chat_template_kwargs: {enable_thinking: false}`). `Titler`'s caps and `</think>` strip
  stay, because a server can accept that parameter and ignore it. The titler starts with the turn
  and runs beside the answer, on a permit `ServerPermits` sizes from the server's own slot count,
  never forced to 1, so the title shows while the answer streams. Measured 2026-11-11 on the
  owner's llama-server (b10438, Ornith 1.5 Q4_K_M, 4 slots sharing one 64k KV pool, a
  6.5k-token prefix):
  - **Speed.** A title takes 1.3 s cold and 0.4–0.6 s warm, or 3 s with thinking on.
  - **Racing costs ~1 s.** A title beside a 500-token answer slowed it from 24.0 to 22.9 tok/s,
    about 1 s over 21 s. pikuri-web's case for one permit is two full replies streaming at once
    (its README, *How many conversations can think at once*). A ten-token title barely overlaps
    the answer, and the popup shows one conversation.
  - **Nothing is evicted.** With no slot pinned, as pikuri runs, a title between two turn
    requests leaves the prefix cached (`cache_n` 6665 either way); prefilling it cold costs
    24–26 s. Pinning the turn to a slot while the title floats did lose it: pikuri never pins.
- **Persistence** in pikuri-web's format, ported (`D_port_pikuri_web`): a directory per
  conversation under `~/.local/state/puri/conversations/`, pikuri's `history.json` beside
  `meta.json` with `shell: "puri"`.
- **Threads** that keep the UI smooth: the main loop doesn't starve a turn's thread, but Ruby
  work on that thread holds the GVL for up to 100 ms (`R_gvl_main_loop`). So a turn runs at
  `Thread#priority = -3` (a burst stalls the UI by at most ~25 ms), and deltas reach
  `ReplyStream` coalesced through pikuri's `Listener::RateLimited`, as pikuri-tui does at
  15 fps, so re-rendering never falls behind the stream.

## The plan

Two phases. **Phase 1** puts pikuri behind Protocol with no tools: the model answers, and
everything around a turn is real (confirmations, cancel, titles, persistence, threads).
**Phase 2** adds the first tools, pikuri's new `web_search` and `web_read_cached`, which bring
the tool lines and the first real confirmations. Desktop changes in neither.

### Phase 1: pikuri, no tools

**Where it stands (2026-11-12):** steps 1–5 and 7–10 are done; 6 waits on pikuri
(`Q_early_cancel`); **11, measuring, is next**. `exe/puri` runs `PikuriCore` on Puri's own
`config.toml`, and the dummy only with `--dummy`. The owner's llama-server is
`192.168.122.1:9081` (Ornith-1.5, in `~/.config/pikuri/config.toml`, to be copied into
`~/.config/puri/config.toml`), and it wants the `api_key` on its `[[server]]`.

The classes, as built:

- `Core::PikuriCore` (`include Protocol::Backend`): the conversations, one `AgentSession` each,
  the lock, the `ThreadGroup`, `close`, and each new conversation's title thread.
  `PikuriCore.new(transport:, titler:, store:, tools: ->(confirmer) { […] })`. It lists the
  store's conversations at start, and makes a saved one's `AgentSession` on its first `ask` or
  `load_conversation`.
- `Core::Conversation`, shared with the dummy backend: blocks, activity,
  title, the messages waiting for the running turn, the redirect while a confirmation waits.
  What a turn does is its `turns:` strategy; it starts each turn's thread at priority −3.
- `Core::AgentSession`: a conversation's `turns:` strategy, holding its `Pikuri::Agent` (built
  on the first turn, kept until the conversation is deleted), `Cancellable`, `Confirmer` and
  tools, and its directory in the `Store`: it replays a saved one, loads its history into the
  agent, saves after each turn and on titling, and deletes.
- `Core::Turn`: one `run_loop` on the turn's thread, ended by a `Notice` on cancel or failure,
  then its `saved:` hook; `answer`, `redirect` and `confirming?` go to the `Confirmer`.
- `Core::TurnListener`: pikuri's events into blocks, behind `Listener::RateLimited(fps: 15)`.
  It shows nothing for `UserTurn`, since `Conversation` shows the message as the turn starts.
- `Core::Confirmer`: pikuri's `Confirmer` in the transcript (step 7).
- `Core::Config`: Puri's own required `config.toml` (step 2, `D_own_config`).
- `Core::Titler`: pikuri-web's, ported (step 8).
- `Core::Store` and `Core::Replay`: the saved conversations, and their blocks rebuilt (step 9).

The specs drive the real pikuri loop on `Pikuri::Testing.fake_transport`. A streaming agent
takes only the streamed verbs: `llm.stream(…)`, and `llm.stream_tool_call(…)`, added to pikuri
for this. A `Gate` subclass in the spec says when a turn has reached the model.

Steps, each one landing green on `bundle exec rake`:

1. **Bump pikuri.** Done; now at `c7b972c`.
2. **The config.** Done, but `exe/puri` doesn't load it until step 10. pikuri-web's `Config`
   ported as `Core::Config`, onto Puri's own file: `$XDG_CONFIG_HOME/puri/config.toml`, under
   `/etc/xdg/puri/` layered beneath it the same way,
   and never pikuri's `~/.config/pikuri/config.toml`, which pikuri-tui and pikuri-web share.
   It comes with its gems, `tomlrb` and `typemap` (plus `rbs`, which `typemap` reads the types
   from at runtime: sord's `sig/puri.rbs`). Since no other shell writes this file, the schema
   keeps only what Puri reads: `[[server]]`, `[[llm]]` with its `params`, and `[titler]` now;
   `[search]` with phase 2. `[web]`, `[ui]`, `[code]` and `[[code.mcp]]` go, and a key Puri
   doesn't know is an error. **The file is required and nothing has a default**: no built-in
   server, model or titler, and `[titler]` is required rather than optional as in pikuri-web.
   With no file, or a broken one, `exe/puri` refuses to start before any window opens, with
   `Config::Error`'s text: the path to write, and `EXAMPLE_CONFIG` to paste there (the local
   llama-server, Ornith 1.5, the titler connection with thinking off). It goes to stderr, which
   the journal keeps when the session bus started Puri.
3. **The connection.** Done. `Config::Llm#transport`, through `ChatTransport.from_openai_server`.
   No `with_detected_modalities`: Puri sends no attachments, so knowing the model's modalities
   buys nothing for two HTTP requests at startup. When the server is down, the turn ends in an
   error `Notice` naming the URL, and nothing crashes (step 4).
4. **A turn, end to end.** Done. `PikuriCore`, `Conversation`, `Turn`, `TurnListener`, and our
   own short system prompt (`prompts/puri.txt` plus today's date, `D_own_prompts`), on a
   `streaming: true` agent. The event mapping:
   - `UserTurn` → nothing; `Conversation` already showed the `UserMessage`;
   - `ThinkingDelta` → `ActivityChanged(working, "Thinking…")`; thinking is never shown;
   - `AssistantDelta` → `ReplyStream#append`, `BlockChanged(Reply)`, `ActivityChanged(streaming)`;
     `Assistant` → `ReplyStream#finish`, and the next delta opens a new `Reply`;
   - `ToolCall` / `ToolResult`: nothing until phase 2, whose tools word their own lines;
   - `Cancelled` → `Notice("Cancelled")`; a `StandardError` out of `run_loop` → an error `Notice`.

   A message sent while a turn runs waits for it to end, as `Backend#ask` promises
   (`Q_interloper`). A down server ends the turn in "Can't reach the model at <url>: …"
   (`RubyLLM::ConnectionError`, ~1 s after ruby_llm's retries). First live turn on Ornith 1.5:
   first token 18 s after Return, then 15 updates a second.
5. **Threads.** Done. The turn thread at `priority = -3`; `TurnListener` behind
   `Listener::RateLimited(fps: 15)`. Lossless flushing stays on: `Assistant` carries the final
   text, but the last flush is what puts it into `ReplyStream`.
6. **Cancel.** Half done: `cancel` calls `Cancellable#cancel!`, which ends a streaming reply and
   a parked confirmer; "Cancelling…" and the early-cancel fix wait on pikuri. pikuri checks
   before every streamed chunk, so a streaming answer stops at the next token; a prefill does not
   (a Faraday read is uninterruptible), so a cancel during a cold 25 s prefill lands on the first
   token. Until then the activity says "Cancelling…". **A pikuri gap:** `run_loop` starts with
   `Cancellable#reset!`, so a cancel sent before the turn's thread reaches it (Escape right
   after Return) is lost; the fix is upstream (`Q_early_cancel`).
7. **The Confirmer.** Done. `Core::Confirmer < Pikuri::Workspace::Confirmer`, one per
   conversation, handed to its tools through `PikuriCore.new(tools:)`. `#ask` runs on the turn
   thread: puts a pending `Confirmation` (the question through `Pikuri::Sanitizer`, a spoof
   warning first, the detail after), sets `confirming`, and waits for `answer` or `redirect`,
   checking the `Cancellable` every 0.1 s. `Approved` / `Rejected` / `Redirected(text)`, or it
   raises `Cancellable::Cancelled`; the block is re-sent with its final state either way. No
   tool calls it in phase 1, so its spec drives it through a spec-only tool (`Q_approve_label`).
8. **The Titler.** Done. `Core::Titler`, pikuri-web's `Agents::Titler` ported with its prompt,
   caps, `</think>` strip and reasoning canary, logging through `Pikuri.logger_for('Titler')`.
   `PikuriCore` starts it on a thread of its own (priority −3, in the core's `ThreadGroup`) as
   it creates a conversation, so the title races the first answer; a failure is logged and the
   title stays "New conversation", and a conversation deleted meanwhile isn't renamed.
9. **Persistence.** Done. `Core::Store`: pikuri-web's on-disk format, its code rewritten around
   `ConversationSummary`: `$XDG_STATE_HOME/puri/conversations/<id>/` (default
   `~/.local/state`), 0700, ids minted as pikuri-web's start stamps
   (`2026-11-12T09-14-03Z-3f9a`), `history.json` by `History#save`, then `meta.json` (schema 1,
   `shell: "puri"`, the `[model, server]` pair, plus `last_question` and `asked_at`) last as the
   commit point, and removed first on delete. A `meta.json` that can't be read is skipped with a
   warning; nothing lists it as unopenable, since `ConversationSummary` has no field for that.
   `AgentSession` saves after every turn, a cancelled or failed one too, before a waiting
   message starts, and on titling; its own mutex keeps one conversation's writes apart, and
   nothing writes after a delete. A save that fails ends in an error `Notice`; a `history.json`
   that can't be read shows one, and the conversation is never saved over it. `Core::Replay`
   turns the history back into `UserMessage` and `Reply` blocks; phase 2's tool lines must be
   worded there by the same code as `TurnListener`'s. A reload loses what never became a
   message (notices, a cancelled reply's partial text), as pikuri-web's does. A restored
   conversation isn't retitled, even one still "New conversation".
10. **Wiring.** Done. `exe/puri` loads the config and builds `PikuriCore.from_config` on a
    `Store` at `Store.default_root`, unless `--dummy` is given, loading `dev/` only then.
    `from_config` builds the `Titler` from `config.titler_llm` (`params_declared:
    !params.empty?`) and sets each `[[server]]`'s `max_concurrent_requests` as a
    `ServerPermits.limit`, as pikuri-web's `bin/pikuri-web-chat` does. `exe/puri` now
    registers on the bus before building any backend, so a launch that only raises a running
    Puri reads no config; `core.close` runs once the app exits. Checked on Broadway: service
    mode starts with no window, a second launch raises it, a question against a closed port
    ends in the error notice and is saved. The README gains the config file. **`--dummy` fakes pikuri
    whole:** it loads no config, builds no `Titler`, `Store` or permits, and never reaches a
    model; `Puri::Dummy::Backend` titles from `Script.title` and keeps its conversations in
    memory. So a fresh checkout walks the UI with no `config.toml`, and a dev session never
    writes into the real conversations directory.
11. **Measure on the owner's machine** and write it up as an `R_` entry: time to first token from
    Return, tok/s, the prefix size before the first word, and the main loop's jitter while a
    reply streams (a 16 ms `GLib::Timeout` logging its lateness), at priority 0 and −3. A stall
    over ~25 ms is a finding: profile the turn thread's Ruby (`ReplyStream`, `ReplyRenderer`,
    `Protocol.round_trip`) before blaming GTK.

**Specs**: Core against `Pikuri::Testing.fake_transport` (the real loop on scripted HTTP; no
mocks), its `Gate` holding a turn open to test cancel, a redirect and a message that waits;
`Store` and the replay on a scratch directory; the Titler on a fake transport; `Config` on
scratch XDG directories passed through its `env:`. One spec against a live llama-server, through
the owner's own config, skipped unless `PURI_LIVE=1`. The GTK specs stay on the dummy.

**Docs**: `architecture.md` loses "the dummy Core emits the same as the real one will" and gains
the agent per conversation, the shared `Conversation`, the store and the config; a `D_` entry
for each open question as it closes. `D_own_config` is written.

### Phase 2: the first tools

`web_search` and `web_read_cached` (pikuri `a1ca7d1`): each tool's line worded by Core, the
search engines configured through `Config`'s `[search]` table (*Search, never fetch*), and the
system prompt taking the fragments the tools bring. Planned once phase 1 is in.

## Open questions

- `Q_early_cancel`: a cancel that lands before `run_loop`'s `reset!` is lost. Filed as pikuri's
  `design/ideas/early-cancel.md` (pushed), recommending that the host owns the reset; once it
  lands, `Turn` resets as `Conversation` starts it, and step 6 goes on.
- `Q_interloper`: a message typed during a turn waits for it (today's contract) or reaches the
  model at the next tool batch through `Control::Interloper`, as in pikuri-web. Moot without
  tools; recommended: keep waiting in phase 1, decide with phase 2.
- `Q_approve_label`: `Protocol::Confirmation` has `approve_label` and `destructive`, a
  `Confirmer::Request` has neither. Phase 1 shows "Approve", not destructive. If the tools need
  more, the fields go upstream into `Request` (*a gap is a missing pikuri primitive*), not into
  a per-tool table here.
