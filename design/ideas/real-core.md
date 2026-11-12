# The real Core: pikuri behind the finished UI

Milestone 2 of the popup: a `Core` on pikuri, with the real model (llama-server, `local-model.md`)
and tools (`trifecta-and-tools.md`), emitting the same Protocol events as the dummy. Desktop
doesn't change.

Two phases. **Phase 1** puts pikuri behind Protocol with no tools; **phase 2** adds the first
tools. Phase 1 is built and graduated into `design/architecture.md` (Core's composition, threads),
`D_titler_model`, `R_llama_server_titles`, `D_own_config` and the classes' doc comments; what is
left of it is below.

The owner's llama-server is `192.168.122.1:9081` (Ornith 1.5, in `~/.config/pikuri/config.toml`,
to be copied into `~/.config/puri/config.toml`), and it wants the `api_key` on its `[[server]]`.

## Phase 1: what's left

- **Cancel, the other half** (waits on `Q_early_cancel`). `cancel` already calls
  `Cancellable#cancel!`, which stops a streaming reply at the next token and a parked confirmer
  within 0.1 s; live, Escape mid-stream stopped the reply within 2.5 s and kept the partial text.
  Missing: a cancel during prefill lands only on the first token (a Faraday read is
  uninterruptible), up to a cold 25 s, so the activity should say "Cancelling…" meanwhile; and a
  cancel sent before the turn's thread reaches `run_loop`'s `reset!` (Escape right after Return)
  is lost. Untested live: a cancel while the model still thinks.
- **Measure on the owner's machine** (next) and write it up as an `R_` entry: time to first
  token from Return, tok/s, the prefix size before the first word, and the main loop's jitter
  while a reply streams (a 16 ms `GLib::Timeout` logging its lateness), at priority 0 and −3. A
  stall over ~25 ms is a finding: profile the turn thread's Ruby (`ReplyStream`,
  `ReplyRenderer`, `Protocol.round_trip`) before blaming GTK. The informal baseline from
  watching screenshots: first token 13.6–18 s after Return, then 15 updates a second.
- **A live spec**: one spec against the owner's llama-server through their own config, skipped
  unless `PURI_LIVE=1`.

## Phase 2: the first tools

`web_search` and `web_read_cached`, in their own `pikuri-web` gem since pikuri `bf884ac` (a new
Gemfile line): each tool's line worded by Core (`🔍 Searched: "avocado preservation"`), and the
status under the progress bar from the latest step; the search engines configured through
`Config`'s `[search]` table (*Search, never fetch*); the system prompt taking the fragments the
tools bring. `Replay` must word a saved tool line by the same code as `TurnListener`. The first
real confirmations come with them. Planned once phase 1 is in.

## Open questions

- `Q_early_cancel`: a cancel that lands before `run_loop`'s `reset!` is lost. Filed as pikuri's
  `design/ideas/early-cancel.md` (pushed), recommending that the host owns the reset; once it
  lands, `Turn` resets as `Conversation` starts it.
- `Q_interloper`: a message typed during a turn waits for it (today's contract) or reaches the
  model at the next tool batch through `Control::Interloper`, as in pikuri-web. Moot without
  tools; recommended: keep waiting in phase 1, decide with phase 2.
- `Q_approve_label`: `Protocol::Confirmation` has `approve_label` and `destructive`, a
  `Confirmer::Request` has neither. Phase 1 shows "Approve", not destructive. If the tools need
  more, the fields go upstream into `Request` (*a gap is a missing pikuri primitive*), not into
  a per-tool table here.
