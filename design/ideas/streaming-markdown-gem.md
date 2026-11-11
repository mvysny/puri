# A streaming Markdown gem, shared by the pikuri apps

pikuri stays Markdown-free, and kramdown is already the parser pikuri-tui, pikuri-web and Puri
share. What none of them should write twice is the streaming half: which part of a half-streamed
reply is final, and which part is still open.

## What exists

- pikuri-tui's `Shared::Markdown::StreamingBuffer` cuts the source into a *committed* prefix and
  an *open* block. It commits at a blank line outside a fence, or at a closing fence, renders a
  committed block once and never again, and re-renders only the open block per delta: O(block),
  not O(message). Tables stay open until their blank line, since a wider row re-pads the earlier
  ones. Setext headings and reference links aren't handled, because LLMs don't write them.
- pikuri-tui's `Renderer` also repairs LLM typography before parsing, e.g. a table separator
  written `—-` (an em-dash) that kramdown won't take as `---`.
- Puri's `Core::ReplyRenderer` re-renders the whole source on every delta: O(N²) over a reply,
  softened only by coalescing deltas (`Listener::RateLimited`, `real-core.md`).

## The gem

Target-agnostic, on kramdown alone: the block cutter and the LLM repairs, nothing that draws.
Each app keeps its converter (ANSI, HTML, Pango). A repo of its own, not a gem in pikuri's
monorepo: pikuri stays free to decide anything about Markdown, even to parse only whole messages,
without the gem having to follow.

```ruby
stream = StreamingMarkdown.new(options: { input: 'GFM', hard_wrap: false })
stream.append(delta) do |committed, open|
  # committed: blocks new since the last call, final; open: the tail, re-parsed each time
end
stream.finish   # the rest, committed
```

For Puri the cut matches Protocol: a committed block becomes a `Reply` part that is sent once
and never changes, so only the open part's `BlockChanged` repeats.

## Open questions

- `Q_gem_api`: does it yield kramdown elements (each app converts a tree) or source slices (each
  app parses again)? Elements save a parse, while slices keep the gem's surface tiny.
- `Q_gem_first`: extract it from pikuri-tui, where it is proven, and let Puri adopt it, or grow
  it in Puri first, where `ReplyRenderer` needs it before the real Core streams long replies?
