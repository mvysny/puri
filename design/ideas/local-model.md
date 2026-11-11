# Which model: Ornith-1.5 for v1, smaller and cheaper later

Goal: answer "which model runs this?" in two steps. **v1: Ornith-1.5**, the model pikuri is
already tuned and measured against, so the first version tests the app, not the model. **v2:
optimize** — smaller models, routing, and the NPU — once there's a working app to measure.

Background: `local-model/apple-on-device-models.md` (the owner's `siri.txt`, a Claude chat on how
Siri runs so cheaply on a MacBook Air M2).

## How Siri does it (from that chat, [unverified])

- **Three tiers.** Simple requests run on the device; moderate ones on Apple's Private Cloud
  Compute; the heaviest reportedly on a custom Gemini in Google's cloud. The local CPU stays quiet
  mostly because the hard work isn't local.
- **On the device:** AFM 3 Core, ~3B dense, quantized to ~2 bits with quantization-aware training,
  so under 1 GB of weights; runs on the Neural Engine, not the CPU. AFM 3 Core Advanced (20B sparse,
  1–4B active) needs an M3 and 12 GB.
- **Task adapters:** summarization and the like are LoRA adapters (~160 MB) on one shared model.
- **Comparable open models:** Qwen3-4B, Gemma 3 4B, Llama 3.2 3B for the small tier; gpt-oss-20b
  (21B total, 3.6B active, ~12–13 GB at 4-bit) and Gemma 3n E4B for the sparse tier.

The lesson for us: Siri's speed is a small model *plus* a datacenter. We promise *Local first*, so
our cloud tier is opt-in, and the local tier has to carry more than Siri's does.

## v1: Ornith-1.5 on llama-server

pikuri's defaults wire a local llama.cpp server, and pikuri's book and ideas measure against
Ornith-1.5 (vision tokens, reasoning-format handling). The daemon keeps it loaded, so there's no
cold start per popup. What v1 should record, as the baseline for v2: time to first token from
Return, tokens/s, and the prompt size before the user's first word (system prompt + tool
definitions + memory). That last number is what a smaller model will pay for every turn.

## v2: the levers, roughly by expected payoff

- **Keep the prefix cached.** The system prompt, tools and memory are the same every turn;
  llama-server's prompt cache reuses their KV, so time-to-first-token is the user's text only.
  Fewer tools (this app has ~15) means a shorter prefix too.
- **A smaller model for the simple tier.** "Add milk to my shopping list" doesn't need Ornith.
  Candidates from the chat above; tool-calling reliability is what decides, not MMLU.
- **Routing, Siri-style:** a small model answers or escalates to the big one (local, or an opt-in
  hosted one). The router itself is a model call, so it has to be cheap and rarely wrong.
  pikuri-shaped question: is escalation a tool, or a transport fallback?
- **The NPU, through Lemonade.** The owner's development box is a VM on an AMD Ryzen AI 9 HX 370
  (Strix Point: Radeon 890M iGPU, an XDNA 2 NPU). AMD's Lemonade server runs small models on the
  NPU (or NPU + iGPU hybrid) and speaks an OpenAI-compatible API, so pikuri would reach it as one
  more `[[llm]]` connection. Far more energy-efficient than the iGPU, which is the point for
  something that idles in the background all day. The other track is llama.cpp on Vulkan on the
  iGPU. Both to measure. Lemonade isn't in Ubuntu's apt; installing it waits on the owner.
- **An eval suite before any swap.** One tester ran 62 tasks against Siri 27.2 (34 passed). We want
  the same: a few dozen real requests ("what's on Thursday", "remind me to call Bob at 5", "find
  the invoice from Acme") with an expected tool call each, run against every candidate. Without
  it, "the small model feels fine" is anecdote.

## Open questions

- `Q_target_hardware`: the app runs on the owner's desktop, the Ryzen AI 9 HX 370 host (the VM has
  7 GB RAM and a virtio GPU)? How much RAM does the host have for model + embedder + daemon?
- `Q_embedder`: which embedding model for pikuri-rag, and does it share the llama-server with the
  chat model or get its own (on the NPU)?
- `Q_eval_suite`: where does the task suite live — here, or in pikuri as a general tool-calling
  benchmark?
- `Q_hosted_tier`: is there an opt-in hosted tier at all, and is a query that quotes a note allowed
  to go there? That's an egress leg like the search engine's, with the same confirm question.
