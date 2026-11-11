# Which model: Ornith-1.5 for v1, smaller and cheaper later

Goal: answer "which model runs this?" in two steps. **v1: Ornith-1.5**, the model pikuri is
already tuned and measured against, so the first version tests the app, not the model. **v2:
optimize** — smaller models, routing, and the NPU — once there's a working app to measure.

Background: `local-model/apple-on-device-models.md`, which covers how Siri runs so cheaply on a
MacBook Air M2 and which open models match its tiers.

## How Siri does it (checked 2026-11-11, sources at the end of that file)

- **Tiers.** Two on-device models, then Private Cloud Compute, whose biggest model (AFM 3 Cloud Pro)
  runs on NVIDIA GPUs in Google Cloud. It is Apple's model refined from Gemini outputs, not Gemini
  itself; the "1.2T Gemini" is a pre-WWDC Bloomberg report nobody confirmed. The local CPU stays
  quiet mostly because the hard work isn't local.
- **On the device:** AFM 3 Core, 3B dense, quantization-aware trained (2025's model was 2 bits per
  weight; AFM 3's bit-width is undisclosed). AFM 3 Core Advanced is 20B sparse with 1–4B active,
  experts picked per prompt and loaded from NAND flash; per Macworld it needs an M3 and 12 GB. On an
  M2, its features (expressive voices, advanced dictation) are missing, not moved to the cloud.
- **Task adapters:** adapters of ~160 MB on one shared model, each tied to one model version.
- **Comparable open models (Nov 2026):** Qwen3.5-4B, Gemma 4 E4B, NVIDIA's Nemotron 3.5 Bolt E4B
  (a Gemma 4 E4B tuned for device-assistant tool use), Granite 4.2 3B and LFM3-1.7B for the small
  tier; gpt-oss-20b, Gemma 4 26B-A4B and Qwen3.6-35B-A3B for the sparse tier. The tables are in
  that file's *Hugging Face, November 2026*.

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
  The candidates are the small tier above; tool-calling reliability is what decides, not MMLU.
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
