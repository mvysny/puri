# Model eval, day two: the small tier with thinking on

Goal: the same 35 tasks as `model-eval.md`'s first pass, on the small models with their thinking
switched on, to see whether thinking turns their failures into passes, and at what cost in time.
Owner, 2026-11-23: "both results will be interesting".

## Why

The first pass (2026-11-23, `~/.local/state/puri/eval/2026-11-23/report.md`) ran the small tier
with thinking off. Where those models failed, they mostly failed to act:

| Configuration | Pass | Simple | Medium | Hard |
|---|---|---|---|---|
| Ornith-1.5, no thinking | 79 % | 40/45 | 32/42 | 11/18 |
| Qwen3.5-4B | 62 % | 38/45 | 24/42 | 4/18 |
| Granite-4.2-3B | 11 % | 8/45 | 4/42 | 0/18 |

- **Granite called no tool in 89 of its 105 runs.** It asked instead: "which Thursday?", "which
  insurance policy?", "which bank?".
- **Qwen holds the simple tier and loses the hard one.** It is close enough to Ornith that
  `model-eval.md`'s own rule ("a small model gets a thinking-on run only if it lands close to
  Ornith") calls for this run anyway.
- Bolt, gpt-oss and Ornith with thinking were still running when this was written; their
  numbers are in the same report.

**The cost to watch is time.** The small models are no faster per token than Ornith: 20–25 tok/s
generated for every model, and a 9.6k-token prompt (system prompt and tools) before each request.
In the smoke round Qwen thought about 400 tokens over "17 × 23", which took 36 s, and with
thinking on it thinks again before every tool call. Ornith thinks 10–20 s per step
(`R_llama_server_turns`).

## What runs

Three configurations, already in `Runner::CONFIGURATIONS`:

| Configuration | Preset | Sent with every request |
|---|---|---|
| `Qwen3.5-4B, thinking` | `Qwen3.5-4B` | `enable_thinking: true`, temperature 1.0, top-p 0.95 (the card's thinking values) |
| `Nemotron-3.5-Bolt-E4B, thinking` | `Nemotron-3.5-Bolt-E4B` | `enable_thinking: true` |
| `Granite-4.2-3B, thinking` | `Granite-4.2-3B` | `enable_thinking: true` |

Each runs the 35 tasks 3 times: 315 runs. A guess at one to three hours in all, Qwen's the
longest; started in the morning, it ends well before midnight, which the runner won't cross
anyway.

## The day's steps

One run, one day: the world gets the day's date, and the recording of the map and weather
services starts empty in the day's own folder.

1. **Stop yesterday's testbed session, if it still runs**, since the build refuses while
   Thunderbird runs: `pikuri-thunderbird/dev/testbed/session stop`, from pikuri's checkout.
2. **Build the world:** `pikuri-thunderbird/dev/testbed/build`, which writes `~/Documents` too.
3. **Restart the file indexer:** `systemctl --user restart localsearch-3`. Without it, the index
   knows the rebuilt folder and none of its files; `localsearch search pulla` should list
   `~/Documents/Recipes/grandmas-pulla.txt`.
4. **Start the testbed on its display:** `DISABLE_WAYLAND=1
   pikuri-thunderbird/dev/testbed/session start --display`, and note the display it prints.
   On 2026-11-23 it was started from outside Claude Code's sandbox; inside, it wasn't tried.
5. **Check the box:** the presets unloaded, nothing else loaded, and nothing else using it all
   day, Puri included.
6. **Run:** from Puri's checkout,

   ```
   DISPLAY=:99 DISABLE_WAYLAND=1 bundle exec rake eval \
     CONFIGS='Qwen3.5-4B, thinking;Nemotron-3.5-Bolt-E4B, thinking;Granite-4.2-3B, thinking'
   ```

   with the display step 4 printed. Both variables must be set when it starts: a hand-off spawns
   Thunderbird on the environment the process started with.
7. **Report:** it writes `report.md` when it ends; `rake eval:report` writes it again, and
   `rake eval:regrade` grades the day again after a fix to a check.

## What to compare

- Each model's pass rate per tier, thinking off (2026-11-23) against on.
- Granite's runs with no tool call: 89 of 105 with thinking off.
- Time: the median first word and turn, per tier. A pass that takes a minute isn't the same
  pass in a popup.
- Whether a small model with thinking on comes near Ornith with thinking off, which is about as
  fast per token and needs 21.7 GB of weights against their 2.2–6.2 GB.

## The hypothesis: a small model on an 8 GB dGPU

Owner, 2026-11-23: a small model that scores well with thinking on, run fully on an 8 GB
graphics card, should be the recommended way to run Puri. 8 GB cards are within reach of many
users, and on one the small models should be fast even while thinking.

Why it's plausible:
- **Decode speed follows memory bandwidth** (`model-eval.md` § Two halves). On the test box every
  model generates at 20–25 tok/s; Qwen's 3.0 GB at 20 tok/s means the iGPU reads about 60 GB/s.
  An RTX 4060 reads 272 GB/s, so Qwen's ceiling there is about 90 tok/s.
- **The owner's RTX 4060 8 GB** ran Qwen3.6-35B-A3B with Strata, on CUDA, at an 8K context, at
  around 40 tok/s. The owner's guess for a small model wholly on the card, through llama.cpp and
  Vulkan: around 55 tok/s. Neither is measured here.
- **The prompt goes faster too:** each conversation starts with about 9.6k tokens of system
  prompt and tools, which this box takes 17–35 s to read cold.
- **Thinking costs little on Ornith:** with thinking on it passed 96 % of its first 63 runs at
  22.3 s a run, against 79 % at 20.0 s with thinking off.

What isn't shown yet:
- **That a small model scores well with thinking on.** Day two answers it. With thinking off the
  best was Qwen, at 62 %.
- **That it fits.** The weights fit (Qwen 3.0 GB, Granite 2.2 GB, Bolt 6.2 GB), but Puri runs a
  64K context, and the KV cache grows with the conversation. The router reports no memory, so
  only the card itself can say; Bolt looks tight.
- **That 8K is enough for the 40 tok/s run:** it isn't, for Puri. The first prompt alone is
  9.6k tokens, and a bigger context leaves less of the card for the model.

If both hold, the recommendation goes to `local-model.md`'s v2, beside its "a small model alone
on the laptop".

- `Q_dgpu`: measure the hypothesis on the owner's RTX 4060 8 GB: tokens/s, prompt tokens/s and
  memory for each small model at Puri's 64K context, through llama.cpp on Vulkan, and the
  eval's timings there. Include Ornith with its experts in system RAM (llama.cpp's
  `--n-cpu-moe`): it is a 35B-A3B like the owner's 40 tok/s Qwen3.6, and if it's usable there it
  stays the accuracy leader on the same card.
- `Q_anchor`: rerun `Ornith-1.5, no thinking` on day two too? It costs about 35 minutes, and it
  shows how much of a difference between the days comes from the day: the dates, the forecast,
  the routes in the recording.
- `Q_week_dates`: Qwen, Bolt and gpt-oss got "Thursday"'s date wrong in the smoke round. The
  system prompt gives only today's date; spelling out the next seven days is our own prompt's
  change (`D_own_prompts`). Not before day two, or it measures two changes at once.
- `Q_granite_low_effort`: Granite's card has `low_effort: true` between thinking on and off. A
  fourth configuration, if thinking on helps but costs too much time?
- LFM3 still waits on a llama.cpp newer than Debian's b10438 (`model-eval.md`'s `Q_box`).
