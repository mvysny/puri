# Apple on-device models, and Hugging Face equivalents — a Claude chat transcript

The owner's `siri.txt` (2026-11-11), moved here verbatim. Its claims come from news sites, [unverified].

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

