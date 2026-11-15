# The real Core: pikuri behind the finished UI

Milestone 2 of the popup: a `Core` on pikuri, with the real model (llama-server, `local-model.md`)
and tools (`trifecta-and-tools.md`), emitting the same Protocol events as the dummy. Desktop
doesn't change.

Two phases. **Phase 1** puts pikuri behind Protocol with no tools; **phase 2** adds the first
tools. Phase 1 is built and graduated into `design/architecture.md` (Core's composition, threads),
`D_titler_model`, `R_llama_server_titles`, `D_own_config` and the classes' doc comments. Phase 2's
web search is built and graduated into `D_search_engines`, `design/architecture.md` and
`ToolWording`. What is left of both is below.

The owner's llama-server is `192.168.122.1:9081` (Ornith 1.5, in `~/.config/puri/config.toml`
with the Brave key), and it wants the `api_key` on its `[[server]]`.

## Phase 1: what's left

- **Cancel, the other half.** `cancel` already calls
  `Cancellable#cancel!`, which stops a streaming reply at the next token and a parked confirmer
  within 0.1 s; live, Escape mid-stream stopped the reply within 2.5 s and kept the partial text.
  Missing: a cancel during prefill lands only on the first token (a Faraday read is
  uninterruptible), up to a cold 25 s, so the activity should say "Cancelling…" meanwhile.
  Untested live: a cancel while the model still thinks.
- **Measure on the owner's machine** (next) and write it up as an `R_` entry: time to first
  token from Return, tok/s, the prefix size before the first word, and the main loop's jitter
  while a reply streams (a 16 ms `GLib::Timeout` logging its lateness), at priority 0 and −3. A
  stall over ~25 ms is a finding: profile the turn thread's Ruby (`ReplyStream`,
  `ReplyRenderer`, `Protocol.round_trip`) before blaming GTK. The informal baseline from
  watching screenshots: first token 13.6–18 s after Return, then 15 updates a second. With search
  (2026-11-15, headless): 10–20 s of thinking before each step, a Brave search ~1.3 s, a
  `web_read_cached` read instant; a two-search answer took 30–57 s.
- **A live spec**: one spec against the owner's llama-server through their own config, skipped
  unless `PURI_LIVE=1`.

## Phase 2: what's left

- **The read line names no page.** `web_read_cached`'s call is a handle and its summary a size
  (`Read 12.4 kB`), so the line says only "📄 Read a page the search found". The fix is
  upstream: `ReadCached` summarizing as `Read 12.4 kB of docs.ruby-lang.org` or the title
  (*a gap is a missing pikuri primitive*), and `ToolWording` then shows that summary.
- **A declined call reads as done.** A `Rejected` or `Redirected` observation doesn't start with
  `Error:`, so its line looks like the tool ran. No tool here asks yet; the first one that does
  needs the outcome on the line, from pikuri rather than by matching the observation's words.
- **The first real confirmations** come with the first private or writing tool, not with search
  (`D_search_engines`).

## Open questions

- `Q_approve_label`: `Protocol::Confirmation` has `approve_label` and `destructive`, a
  `Confirmer::Request` has neither. Phase 1 shows "Approve", not destructive. If the tools need
  more, the fields go upstream into `Request` (*a gap is a missing pikuri primitive*), not into
  a per-tool table here.
