# Measure Puri on an 8 GB card, and try Ornith with its experts in RAM

`docs/models.html` puts Qwen 3.5 4B on an 8 GB card from two numbers: the owner's RTX 4060 writes
50–60 tok/s on it, and its weights and 64K cache come to 4.8 GiB by the GGUF header
(`R_model_eval`). Neither the card's prompt speed nor its memory at Puri's 64K is measured, and
the ~10K-token prefix is what the first answer waits on (`R_llama_server_reload`).

The owner measures, on the RTX 4060 through llama.cpp on Vulkan:

- Qwen 3.5 4B and Bolt E4B at `-c 65536`: prompt tokens/s, memory, and the eval's timings there.
- Ornith 1.5 with its experts in system RAM (`--n-cpu-moe`): a 35B-A3B like the Qwen 3.6 the
  owner ran at about 40 tok/s through Strata at 8K. If it's usable at 64K, it is the accuracy
  leader on the same card, and the models page's "doesn't fit" changes.

That card is the one place routing could pay, Qwen on the card and Ornith in RAM taking the hard
requests; `D_one_model` rules routing out on one machine, so it needs measurements to reopen.
