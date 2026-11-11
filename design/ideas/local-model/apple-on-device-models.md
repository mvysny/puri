# Apple on-device models, and Hugging Face equivalents — a Claude chat transcript

The owner's `siri.txt` (2026-11-11), moved here verbatim. Its claims come from news sites; they
were checked against Apple's own pages on 2026-11-11, and *Verification* below the transcript says
which hold. *Hugging Face, November 2026* replaces the chat's model list, which dates from mid-2026.

Claude

Is the new Siri running locally, say on MacBook Air M2 with 16GB of RAM, on MacOS 27.3? It feels pretty fast and not really demanding on the CPU. How is that achieved? Which local model available from the hugging face would be comparable?

It’s mostly not running locally on your Mac, and the part that is runs a small model on the Neural Engine rather than the CPU.

What actually runs where

Siri in macOS 27 is a hybrid. Simple requests stay on the device and run on Apple’s own updated foundation models, while moderately complex requests go to Apple’s Private Cloud Compute servers, and the heaviest reasoning is routed to Google Cloud, reportedly a custom 1.2-trillion-parameter Gemini model.
Apple rebuilds Siri on a custom 1.2-trillion-parameter Gemini model +2

There are two on-device models: AFM 3 Core (3-billion-parameter dense) and AFM 3 Core Advanced (20-billion-parameter sparse, activating just 1–4B parameters). Your M2 can’t run the bigger one. AFM 3 Core Advanced needs an M3-family chip and at least 12GB of RAM. Per reporting, M1/M2 Macs and M3 Macs with only 8GB fall back to the cloud for the features that would otherwise use it. So on your MacBook Air, the local part is the ~3B AFM 3 Core, and anything substantial goes to Apple’s servers. That’s a big reason your CPU stays quiet.
Apple Reframes Siri with AFM 3 at WWDC 2026 +2

Why the local part is cheap

    It runs on the Neural Engine and GPU, not the CPU. Activity Monitor’s CPU graph mostly won’t show this work.
    The model is small and heavily compressed. The previous-generation version was quantized to 2 bits per weight, with quantization-aware training and a learnable scaling factor to limit the quality loss. A 3B model at about 2 bits is under 1GB of weights. Since LLM speed on a Mac is mostly limited by memory bandwidth, smaller weights mean faster tokens.
    emergentmind
    Task adapters instead of separate models. Features like summarization are small LoRA adapters on one shared model. The adapters developers can train are around 160MB.
    courier
    The Advanced model uses a flash-streaming trick (not on your machine). It stores parameters in NAND flash and loads only what each prompt needs into DRAM.
    letsdatascience

Comparable Hugging Face models

My knowledge of the Hugging Face landscape is from mid-2026, so check for newer releases.

    For AFM 3 Core (what your Mac runs): Qwen3-4B, Gemma 3 4B or Llama 3.2 3B, as 4-bit MLX quants from the mlx-community org. For calibration, the 2025 on-device model outperformed Qwen-2.5-3B and Gemma-3-4B on MMLU but lagged behind the larger Qwen-3-4B. Qwen3-4B is a fair “same league, probably a bit better” pick.
    emergentmind
    For AFM 3 Core Advanced (sparse, few active parameters): gpt-oss-20b is the closest analog: about 21B total and about 3.6B active per token. In its native 4-bit format it’s roughly 12–13GB, so it runs on your 16GB M2 but leaves little headroom. Gemma 3n E4B is conceptually closer to Apple’s selective-loading idea and much lighter.
    To try them: LM Studio (with the MLX backend) or Ollama are the easiest options. Expect 4B models to feel snappy on an M2. gpt-oss-20b will work but load your machine more than Siri does, because it isn’t 2-bit, isn’t ANE-optimized, and doesn’t offload anything to a cloud.

The direct comparison isn’t really model against model. A local LLM does all the work on your Mac, while Siri hands most of the heavy work to a datacenter.

Sources:

    DataNorth: Apple rebuilds Siri on a custom 1.2T Gemini model
    The Next Web: Siri AI three-tier architecture
    Let’s Data Science: AFM 3 at WWDC 2026
    Gadget Hacks: macOS 27 Siri AI requirements
    macos-tahoe.com: M3 + 12GB barrier
    Emergent Mind: Apple Foundation Models Tech Report 2025
    Courier: Apple on-device AI models


Claude is AI and can make mistakes.


---

## Verification, 2026-11-11

Primary sources: Apple's [AFM 3 post](https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models)
(2026-06-08), the [2025 model post](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates),
the [2025 tech report](https://arxiv.org/abs/2507.13575) and Apple's
[adapter page](https://developer.apple.com/apple-intelligence/foundation-models-adapter/).

| Claim in the chat | Verdict |
|---|---|
| Two on-device models: AFM 3 Core (3B dense), Core Advanced (20B sparse, 1–4B active) | **Confirmed** by Apple. The sparsity is Instruction-Following Pruning, chosen per prompt, and Apple contrasts it with MoE: NAND is "too slow to swap weights token by token, as standard MoE models require". |
| Core Advanced keeps its weights in NAND flash and loads only what a prompt needs | **Confirmed**: "the full model is stored in flash memory (NAND)", loaded "incrementally across requests". |
| Three tiers, the heaviest is a custom 1.2T Gemini in Google Cloud | **Half right.** Apple names five AFM 3 models; AFM 3 Cloud Pro runs in Private Cloud Compute extended "to NVIDIA GPUs in Google Cloud". Federighi, per [Macworld](https://www.macworld.com/article/3162330/how-much-gemini-is-really-in-the-new-siri-ai.html) from an unrecorded briefing: "none of the models that Google deploys to their customers"; the models are "refined using outputs from Gemini frontier models". The 1.2T figure is Gurman's (Bloomberg) pre-WWDC report from Nov 2025 ([MacTech](https://www.mactech.com/2025/11/05/apple-will-pay-almost-1-billion-a-year-for-a-custom-gemini-model-to-power-siri)); neither Apple nor Google confirmed it, and Apple's post has no parameter count for any cloud model. DataNorth contradicts itself (PCC in the intro, Google Cloud later). |
| Core Advanced needs an M3 and 12 GB | **Reported** by [Macworld](https://www.macworld.com/article/3160007) and [Gadget Hacks](https://apple.gadgethacks.com/news/macos-27-siri-ai-features-whats-new-and-who-can-use-it/); Apple's post says only "our most capable Apple silicon systems". |
| M1/M2 Macs fall back to the cloud for Core Advanced's features | **Weak.** Only macos-tahoe.com says so. Gadget Hacks: M1/M2 Macs get Siri AI without "more expressive Siri voices and more advanced systemwide dictation", which are exactly what Core Advanced powers (Federighi). So the features are missing, not offloaded, and the local model on an M2 is AFM 3 Core. |
| It runs on the Neural Engine and GPU, not the CPU | **Unsourced**; plausible, not checked. |
| ~2 bits per weight, QAT, a learnable scaling factor | **Confirmed for the 2025 model** (2 bpw decoder, 4-bit embeddings, 8-bit KV cache; the report's learnable scaling factor, the post's "learnable weight clipping"). **AFM 3's bit-width is not disclosed**: Apple says only "Quantization Aware Training". "Under 1 GB" is an extrapolation from 2025. |
| Developer adapters ~160 MB | **Confirmed** on Apple's adapter page, which also says an adapter fits "a single specific system model version": 26.0.0 adapters do not load on OS 27. The Courier source was not found. |
| The 2025 model beat Qwen-2.5-3B and Gemma-3-4B on MMLU but trailed Qwen-3-4B | **Confirmed**: the report's Table 1 has MMLU 67.85 vs 66.37, 62.81 and 75.10 (read via a summarizing fetch, not the PDF). Apple's post words it as "competitive against the larger Qwen-3-4B and Gemma-3-4B in English". AFM 3 has no open-model comparison; Apple compares only against its 2025 models. |
| gpt-oss-20b: 21B total, 3.6B active, ~12–13 GB at 4-bit | **Confirmed**: the [card](https://huggingface.co/openai/gpt-oss-20b) says MXFP4 and "within 16GB of memory"; `original/model.safetensors` is 13.8 GB. |

The sources the chat cites are secondary: Emergent Mind summarizes arXiv 2507.13575, DataNorth and
TNW name no source for 1.2T, and Let's Data Science is the only news page with the NAND detail,
which Apple's post confirms.

## Hugging Face, November 2026

Read from the Hub API and the model cards on 2026-11-11. Benchmarks are the vendors' own. This app
runs on Linux through llama-server, so the right format is GGUF, not the chat's MLX quants or LM
Studio.

**Small dense tier (AFM 3 Core's counterpart, ~2–4B):**

| Model | Released | Size | License | Note |
|---|---|---|---|---|
| [Qwen/Qwen3.5-4B](https://huggingface.co/Qwen/Qwen3.5-4B) | 2026-02 | 4B dense, 262K ctx | Apache-2.0 | Still the newest small Qwen: Qwen3.6 and 3.8 ship only 27B and up. Also 0.8B, 2B and 9B. |
| [google/gemma-4-E4B-it](https://huggingface.co/google/gemma-4-E4B-it) | 2026-03 | 4.5B effective, 8B with per-layer embeddings, 128K | Apache-2.0 | Text, image and audio. Replaces Gemma 3n and keeps its PLE trick. E2B: 2.3B effective. Its own card puts Tau2 at 42.2%. |
| [nvidia/NVIDIA-Nemotron-3.5-Bolt-E4B-4GB](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Bolt-E4B-4GB) | 2026-10 | Gemma 4 E4B, Q4_K_M, 64K | OpenMDW-1.1 | Post-trained for "local voice and device assistants" and multi-turn tool use, which is this app's use case. NVIDIA's table (BF16), Bolt / Gemma 4 E4B / Qwen3.5-4B: BFCL-v3 68.5 / 66.4 / 71.0, Tau2 55.1 / 38.5 / 75.1, RelyToolBench (tool hallucination) 63.2 / 61.6 / 43.4. |
| [ibm-granite/granite-4.2-3b](https://huggingface.co/ibm-granite/granite-4.2-3b) | 2026-08 | 3.7B | Apache-2.0 | Reasoning, plus agentic RL aimed at tool calling. Also 8B. |
| [LiquidAI/LFM3-1.7B](https://huggingface.co/LiquidAI/LFM3-1.7B) | 2026-10 | 1.7B, ~1 GB at 4-bit | LFM Open License 1.0 | "Designed for local agents, tool calling". Its template supports *deferred tools* (definitions stay out of the prompt until a search tool returns them), one answer to our ~15-tool prefix. |

Llama 3.2 3B (2024) is out of date, and Meta has released no small model since.

**Sparse tier (Core Advanced's counterpart, ~20–35B total, ~3–4B active):**

| Model | Released | Size | License |
|---|---|---|---|
| [openai/gpt-oss-20b](https://huggingface.co/openai/gpt-oss-20b) | 2025-08 | 21B / 3.6B active, MXFP4, 13.8 GB | Apache-2.0 |
| [google/gemma-4-26B-A4B-it](https://huggingface.co/google/gemma-4-26B-A4B-it) | 2026-03 | 25.2B / 3.8B active, 128 experts (8 + 1 shared), 256K; Tau2 68.2% | Apache-2.0 |
| [Qwen/Qwen3.6-35B-A3B](https://huggingface.co/Qwen/Qwen3.6-35B-A3B) | 2026-04 | 35B / 3B active, 262K | Apache-2.0 |
| [nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-BF16) | 2026-08 | 30B / 3B active, hybrid Mamba-2 + MoE | OpenMDW-1.1 |

gpt-oss-20b is still OpenAI's newest open model. All four route per token, which is the MoE
design Apple chose against; none chooses its experts per prompt the way Core Advanced does.
