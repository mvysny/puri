# Apple's on-device models, and their open counterparts

How Siri in macOS 27 feels fast and light on a MacBook Air M2 with 16 GB, and which open models
fill the same roles. The note started from the owner's `siri.txt`, a Claude chat. Its claims were
checked against Apple's own pages on 2026-11-11. Where only the press reports a claim, the note
says so.

## The short answer

Siri feels light mostly because the hard work doesn't run on the Mac. A small model on the device
handles simple requests, and anything harder goes to Apple's servers. On an M2, the local part is
a 3B model, quantized hard. Matching Siri with a local-only stack means the local model has to do
far more of the work.

## The AFM 3 family

Apple announced AFM 3 on 2026-06-08 as "a family of five foundation models custom-built in
collaboration with Google". Two run on the device and three in Private Cloud Compute (PCC).
AFM stands for Apple Foundation Model, and AFM 3 is the third generation (Apple's 2024 paper named
the first ones AFM-on-device and AFM-server). ADM probably follows the same pattern, perhaps
Apple Diffusion Model, but Apple's post doesn't spell it out.

| Model | Runs on | Size and architecture |
|---|---|---|
| AFM 3 Core | device | 3B dense |
| AFM 3 Core Advanced | device | 20B sparse, 1–4B active, Instruction-Following Pruning (below) |
| AFM 3 Cloud | PCC | not stated; builds on 2025's Parallel-Track MoE |
| ADM 3 Cloud | PCC | image model (creation, editing, Genmoji); not stated |
| AFM 3 Cloud Pro | PCC "extended to NVIDIA GPUs in Google Cloud" | not stated |

Apple gives no parameter count for any of the cloud models.

## Core Advanced: sparse per prompt, weights in flash

- **Instruction-Following Pruning.** "The full model is stored in flash memory (NAND)". A small
  dense block picks a fixed set of experts while it reads the prompt and re-picks them now and
  then during generation. Shared experts stay in DRAM. Routed experts are loaded into DRAM only
  when a prompt needs them.
- **Why not MoE.** Apple rejects standard MoE for this model: reading weights from NAND is too
  slow to swap experts on every token. Routing once per prompt makes reading from flash workable.
- **Active size per use case.** Each feature gets a fixed number of active parameters. Apple ran
  its voice and dictation evaluations at 1B active.
- **What it powers.** According to Federighi, the more expressive Siri voices and the advanced
  system-wide dictation.
- **Hardware.** Apple says only "our most capable Apple silicon systems". Macworld and Gadget Hacks
  report an M3-family chip and at least 12 GB of RAM. On M1 and M2 Macs, Gadget Hacks says those
  features are missing, not moved to the cloud. One site claims a cloud fallback but gives no
  source. So the only local model on an M2 is AFM 3 Core.

## Why the local part is cheap

- **Small and heavily quantized.** For AFM 3, Apple says only "Quantization Aware Training", with
  no bit width. The 2025 on-device model (also 3B) used 2 bits per weight in the decoder, 4-bit
  embeddings and an 8-bit KV cache, with a learnable scaling factor (weight clipping) to limit the
  quality loss. At 2 bits, 3B weights take about 0.75 GB. That figure comes from the 2025 model;
  Apple hasn't confirmed it for AFM 3. LLM decoding speed is mostly limited by memory bandwidth, so
  smaller weights mean more tokens per second.
- **Which processor runs it.** Apple says only that the models are "optimized to run efficiently on
  Apple silicon". The chat said the Neural Engine and GPU do the work, not the CPU, which would
  explain the quiet CPU graph. That is plausible but has no source.
- **Adapters instead of separate models.** Features are small adapters on one shared base model.
  The adapters developers can train for the Foundation Models framework are about 160 MB. Each
  fits "a single specific system model version", so adapters trained for 26.0.0 don't load on
  OS 27. The AFM 3 post mentions adapters only for the ADM 3 image model and gives no size.

## The cloud tier and Gemini

- Cloud Pro is Apple's model, running in PCC on NVIDIA GPUs in Google Cloud. The word "Gemini"
  doesn't appear in Apple's post.
- Federighi, quoted by Macworld from an unrecorded briefing: "none of the models that Google
  deploys to their customers". He also said the models are "refined using outputs from Gemini
  frontier models".
- The often-repeated "custom 1.2-trillion-parameter Gemini" comes from a pre-WWDC Bloomberg report
  by Gurman, from November 2025. Neither Apple nor Google has confirmed it.

## Benchmarks

- **AFM 3:** Apple publishes no open-model comparison and no public benchmark scores. It reports
  only in-house human preference tests against its own earlier models. For example, testers
  preferred AFM 3 Core over the 2025 model on 45.6% of general-text prompts, against 23.3% the
  other way. A technical report was promised for "later this summer". It hasn't been checked
  whether one came out.
- **The 2025 on-device model** (tech report, Table 1, MMLU): AFM 67.85, Qwen-2.5-3B 66.37,
  Gemma-3-4B 62.81, Qwen-3-4B 75.10. So it was ahead of the 3–4B models of its year except
  Qwen3-4B. Apple's own words are "competitive against the larger Qwen-3-4B and Gemma-3-4B".

## What carries over to Puri

- **Siri is a small model plus a datacenter.** Puri promises *Local first*, so its cloud tier is
  opt-in. The local model has to handle the requests Siri sends to PCC.
- **Per-prompt sparsity has no open equivalent.** The open sparse models below all choose experts
  per token, which is the design Apple rejected. All their weights have to fit in RAM. Paging them
  from disk, for example through llama.cpp's mmap, runs into exactly the bandwidth problem Apple
  describes.
- **Adapters are tied to one model version.** Any per-task tuning we add has to be redone every
  time the base model changes.
- **Format.** Puri runs on Linux through llama-server, so the right format is GGUF. The chat's
  MLX quants and LM Studio suggestions are for macOS and don't apply.

## Hugging Face, November 2026

Read from the Hub API and the model cards on 2026-11-11. All benchmarks are the vendors' own.

**Small dense tier (AFM 3 Core's counterpart, ~2–4B):**

| Model | Released | Size | License | Note |
|---|---|---|---|---|
| [Qwen/Qwen3.5-4B](https://huggingface.co/Qwen/Qwen3.5-4B) | 2026-02 | 4B dense, 262K ctx | Apache-2.0 | Still the newest small Qwen; Qwen3.6 and 3.8 ship only 27B and up. Also 0.8B, 2B and 9B. |
| [google/gemma-4-E4B-it](https://huggingface.co/google/gemma-4-E4B-it) | 2026-03 | 4.5B effective, 8B with per-layer embeddings, 128K | Apache-2.0 | Text, image and audio. Replaces Gemma 3n and keeps its PLE trick. E2B: 2.3B effective. Its own card puts Tau2 at 42.2%. |
| [nvidia/NVIDIA-Nemotron-3.5-Bolt-E4B-4GB](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Bolt-E4B-4GB) | 2026-10 | Gemma 4 E4B, Q4_K_M, 64K | OpenMDW-1.1 | Post-trained for "local voice and device assistants" and multi-turn tool use, which is this app's use case. NVIDIA's table (BF16), Bolt / Gemma 4 E4B / Qwen3.5-4B: BFCL-v3 68.5 / 66.4 / 71.0, Tau2 55.1 / 38.5 / 75.1, RelyToolBench (tool hallucination) 63.2 / 61.6 / 43.4. |
| [ibm-granite/granite-4.2-3b](https://huggingface.co/ibm-granite/granite-4.2-3b) | 2026-08 | 3.7B | Apache-2.0 | Reasoning, plus agentic RL aimed at tool calling. Also 8B. |
| [LiquidAI/LFM3-1.7B](https://huggingface.co/LiquidAI/LFM3-1.7B) | 2026-10 | 1.7B, ~1 GB at 4-bit | LFM Open License 1.0 | "Designed for local agents, tool calling". Its template supports *deferred tools*: definitions stay out of the prompt until a search tool returns them. That is one answer to our ~15-tool prefix. |

The chat's 2024–25 picks are out of date: Qwen3-4B and Gemma 3 4B have successors above. Llama
3.2 3B (2024) is out of date too, and Meta has released no small model since.

**Sparse tier (Core Advanced's counterpart, ~20–35B total, ~3–4B active):**

| Model | Released | Size | License |
|---|---|---|---|
| [openai/gpt-oss-20b](https://huggingface.co/openai/gpt-oss-20b) | 2025-08 | 21B / 3.6B active, MXFP4, 13.8 GB; fits "within 16GB of memory" | Apache-2.0 |
| [google/gemma-4-26B-A4B-it](https://huggingface.co/google/gemma-4-26B-A4B-it) | 2026-03 | 25.2B / 3.8B active, 128 experts (8 + 1 shared), 256K; Tau2 68.2% | Apache-2.0 |
| [Qwen/Qwen3.6-35B-A3B](https://huggingface.co/Qwen/Qwen3.6-35B-A3B) | 2026-04 | 35B / 3B active, 262K | Apache-2.0 |
| [nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-BF16) | 2026-08 | 30B / 3B active, hybrid Mamba-2 + MoE | OpenMDW-1.1 |

gpt-oss-20b is still OpenAI's newest open model. It runs on a 16 GB machine but leaves little
headroom. Even then it works harder than Siri does: it isn't 2-bit, isn't tuned for any one
accelerator, and hands nothing off to a cloud.

## Sources

Apple, primary:

- [Introducing the third generation of Apple Foundation Models](https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models), 2026-06-08
- [Apple Foundation Models 2025 updates](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)
  and the [2025 tech report](https://arxiv.org/abs/2507.13575). Table 1 was read through a
  summarizing fetch, not from the PDF.
- [Foundation Models adapter training](https://developer.apple.com/apple-intelligence/foundation-models-adapter/)

Press, for what Apple doesn't state:

- Macworld: [how much Gemini is in the new Siri](https://www.macworld.com/article/3162330/how-much-gemini-is-really-in-the-new-siri-ai.html)
  (Federighi's quotes) and [macOS 27 requirements](https://www.macworld.com/article/3160007)
  (M3 + 12 GB)
- Gadget Hacks: [macOS 27 Siri AI features and who can use them](https://apple.gadgethacks.com/news/macos-27-siri-ai-features-whats-new-and-who-can-use-it/)
- MacTech: [the 1.2T Gemini report](https://www.mactech.com/2025/11/05/apple-will-pay-almost-1-billion-a-year-for-a-custom-gemini-model-to-power-siri),
  relaying Bloomberg

The chat also cited DataNorth, The Next Web, Let's Data Science, macos-tahoe.com, Emergent Mind and
Courier. None of them adds anything that Apple's pages or the sources above don't already cover.
DataNorth and TNW give no source for the 1.2T figure. DataNorth also contradicts itself, placing the
model in PCC in one place and in Google Cloud in another. Emergent Mind summarizes the 2025 tech
report. The Courier page couldn't be found.
