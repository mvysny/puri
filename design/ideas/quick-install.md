# Quick install: Puri can run its own servers, and one setup script

Goal: a privacy-minded user who isn't a programmer gets Puri running in a few commands, with
nothing to configure and no moving parts to understand (owner, 2026-11-25). Two paths: the quick
one, for whoever just wants it running, and today's `install.html`, the long one, for the power
user who wants every setting.

## Decided (owner, 2026-11-25)

- **How the model runs is an implementation detail**, as long as it runs locally or somewhere the
  user controls: privacy is what Puri is. The simplest way wins, whether `llama-cli`, llama.cpp
  itself or `llama-server`.
- **Two ways to run a server, side by side, never one instead of the other.** *Embedded:* Puri
  runs `llama-server` and `whisper-server` as its children, starts them, restarts one that
  crashes, and stops them when Puri quits; apt's binaries, nothing linked into Puri. *The user's
  own:* a server the user runs, here as a systemd service, on a home server or hosted; Puri knows
  only its URL, as today. One Puri may use both at once, in any combination.
- **Embedded is for the first run:** a new user gets Puri answering without running a
  `llama-server` or a `whisper-server` of their own. A game then needs only Ctrl+Q. It lives
  here, per *Prototype here*.
- **A `[[server]]` without `url` is the embedded one**, and at most one may lack it. Every
  `[[llm]]` on it names the same `model`, the one the child loads, while each keeps its own
  `params`, so the titler can still turn thinking off.
- **Puri secures its own children any way it likes:** a key and `--cors-origins localhost`. A
  server the user runs is the user's to secure; the guides offer the same two as tips.
- **A machine without a GPU:** the setup script warns that answers will be very slow, links to a
  page of the site with the other options, and lets the user carry on.
- **llama.cpp places the model, not us.** `--fit` is on by default and adjusts only the arguments
  left unset (`llama-server --help`), so Puri passes `-c 65536` and no `-ngl`: what fits goes on
  the GPU, the rest stays on the CPU. The long guide's `-ngl 99` turns that off for the layers.
- **The model stays loaded** (`D_model_resident`).
- **A setup script, plain CLI** (no Tuile, a progress bar at most). It checks everything, fixes
  what needs no sudo once the user says yes, and prints what needs sudo for the user to run. The
  big fix is the downloads: Qwen or Ornith, and the Whisper model.
- **It writes the config only when there is none**, the long guide's config with both servers
  embedded.

## The config, sketched

```toml
[[server]]
id = "local"                      # no url: Puri runs llama-server itself
# url = "http://localhost:8080"   # or a llama-server of your own

[[server]]
id      = "home"
url     = "http://homebox:8080"
api_key = "…"

[[llm]]                           # conversations, on the home server
name   = "Ornith 1.5"
server = "home"
model  = "…"

[[llm]]                           # titles, on the embedded one
name   = "Qwen 3.5 4B, no thinking"
server = "local"
model  = "ggml-org/Qwen3.5-4B-GGUF:Q4_K_M"

[titler]
llm = "Qwen 3.5 4B, no thinking"
```

- A `url`-less `[[server]]` takes no `api_key`, since Puri makes its own each start (below).
  Two `url`-less servers, or two models on one, are a `Config::Error` naming the entries.
- Dictation the same way: `[dictation]` without `url` is the embedded `whisper-server`, so `url`
  stops being required there.
- **`[dictation]`'s `model` names the model, as `[[llm]]`'s does** (owner, 2026-11-25): with a
  `url`, sent as written, as today; without one, the model the embedded server loads, as
  `repo:file`, e.g. `ggerganov/whisper.cpp:ggml-small.bin`. whisper.cpp's repo has no quant tags:
  a quant is part of the file name. The default stays `whisper-1` with a `url`, which a hosted
  server reads even though `whisper-server` ignores it; without a `url`, `model` is required, so
  Puri never guesses which model to load.
- Switching a server between embedded and the user's own is one `url` line; the `[[llm]]`s
  stay as they are.

## The embedded servers, sketched

- `llama-server -hf <model> --offline -c 65536 --no-mmproj`: the `[[llm]]`'s `model`, a file the
  setup downloaded (below), so the server itself needs no network. `--no-mmproj` because Puri
  sends no images, and Qwen's repo ships a 0.34–0.63 GiB vision projector that `-hf` fetches and
  loads by default.
- **Nothing else may use them.** llama-server's default CORS approves every origin, credentials
  included, and it takes no key unless given one, so a web page may use the model, as far as the
  browser lets it reach `localhost`. It can't read Puri's conversations: `/slots` shows no prompt
  text. `--cors-origins localhost` stops a page reading any answer, but a request that needs no
  preflight still runs; only a key stops that. (All verified 2026-11-25, b10438.) So the child
  gets both: a fresh key each start, in `LLAMA_API_KEY` rather than on the command line, which
  every user can read in `/proc`, and a free port on loopback, since pikuri's transport speaks
  HTTP over TCP alone. whisper-server takes no key (whisper.cpp#4197).
- Its log goes to `$XDG_STATE_HOME/puri/llama-server.log`. A crash restarts it with a back-off;
  three in a minute stop it, with the log's tail in the window. A pidfile in `$XDG_RUNTIME_DIR`
  lets the next Puri kill a child a killed Puri left behind.
- A question asked while the model loads waits on `/health`, and the window says the model is
  starting.

## Where the models live

Verified 2026-11-25 on b10438, with `HF_ENDPOINT` pointed at a dead port.

- **`-hf <repo:quant> --offline`, the setup downloading** (owner, 2026-11-25): the `[[llm]]`'s
  `model` stays the `repo:quant` it is today, whoever runs the server.
- **The location is a standard already: Hugging Face's hub cache.** `-hf` reads and writes
  `~/.cache/huggingface/hub` in the layout of Hugging Face's own `huggingface_hub`:
  `models--<org>--<repo>/blobs/<sha256>`, `snapshots/<commit>/<file>` a symlink to its blob, and
  `refs/main` holding the commit. `LLAMA_CACHE` wins over `HF_HUB_CACHE`; `HF_HOME` and
  `XDG_CACHE_HOME` each move it too.
- **The setup script writes that layout itself.** The blob is named by its SHA-256, the one
  Hugging Face's API lists and the script checks, and the snapshot by the API's commit. Offline,
  llama.cpp finds the file through `refs/main` alone: a hand-built cache whose `refs/main` named a
  made-up commit loaded. The long guide's per-user `llama-server` service reads the same cache, so
  switching between it and embedded downloads nothing twice.
- **A missing model is Puri's to report.** `--offline` on an empty cache exits at once and tries no
  download, but says only "exactly one out metadata, path_model, and file must be defined", never
  which file. So Puri looks in the cache before starting the child, and the window says the model
  isn't downloaded and names the setup script.
- **`whisper-server` takes only `-m <path>`**, no `-hf`. Its models are on Hugging Face too
  (`ggerganov/whisper.cpp`), so the setup puts the one it downloads in the same cache, and Puri
  resolves `[dictation]`'s `repo:file` itself, through `refs/main` to `snapshots/<commit>/<file>`,
  and passes that path to `-m`: one place, and one way of naming, for both models.

## The setup script, sketched

- **One idempotent command:** the first run installs, and any later run is the doctor. Ruby's
  stdlib only, since `bundle install` is one of its fixes. Never sudo, never `curl | sh`: it sits
  in the clone, readable before it runs.
- **In order, each check with its fix:**
  - apt packages: one `sudo apt install` line of what's missing, then stop;
  - `bundle install`, then `rake install AUTOSTART=1`;
  - the models: asks which, and downloads into the hub cache with a progress bar, resuming with
    `Range` and checking the SHA-256 that Hugging Face's API lists. Ornith only where `llama-server --list-devices` and
    the RAM say it fits (`models.html`'s rule); the `ttm` kernel parameters printed, never applied;
  - the config, written when missing, never edited;
  - Thunderbird's global search and the calendar's Offline Support, printed as where to click;
  - localsearch: its status, the office extractor, `localsearch reset` after asking, Documents in
    Search Locations.
- The quick path is then: the apt line, `git clone`, the setup script, the shortcut.

## On graduation

- `AGENTS.md`'s and the README's *What this is* gain the model server: "…and the resident process
  that keeps the agent warm, and, to start quickly, the model server itself" (owner, 2026-11-25).

## Changes to what `launch.md` decided

- *The user walks the path, every download a command the user types* holds for the long guide
  only; the quick path's script downloads.
- *Both servers run as per-user systemd services* stays, as the user's own way beside the
  embedded one: the long guide's way, and the home server's. Whether the long guide switches to
  embedded too is `Q_long_guide`.

## The site

- **The funnel** (owner, 2026-11-25): a user who tried Puri locally and got hooked is the one who
  later sets up a desktop PC or a home server for a smarter model. The quick install is the hook,
  so it comes before new tools. The site then leads with the quick path, and `models.html`
  becomes the upgrade story: Ornith, a home server over Tailscale, the laptop's battery spared.
  It can also say what Siri can't: no account, no subscription, no server of ours.
- The CPU-only warning links to `models.html#no-gpu`.
- Untested: the install guide's own setup on a computer with no graphics card. It installs
  `libggml0-backend-vulkan`, and with Mesa's software Vulkan (lavapipe) beside it, llama.cpp may
  take lavapipe for a GPU (`launch.md`'s *lavapipe*). The numbers on the page are llama.cpp's CPU
  backend with no GPU backend installed. Testing it on the owner's VM needs that package
  installed there.

## Open questions

- `Q_config_template`: one `docs/config.toml` for both paths, its `[[server]]` the embedded one,
  with `url` commented as the way to a server of your own? Then the script copies it verbatim and
  nothing drifts.
- `Q_long_guide`: does the long guide keep its service files, or use embedded too and keep the
  service files for the home server alone?
- `Q_setup_name`: `bin/setup`, `exe/puri-setup` or `rake setup`?
- `Q_dictation_cli`: `whisper-cli` once per clip instead of a resident `whisper-server`: no
  process, port or memory held all day, at the price of loading the model per clip. Worth it
  only if that load is small beside the encoder's 7 s floor on a CPU; unmeasured. It also forks
  dictation into a local and a remote path, where today both are one OpenAI-shaped request
  (`D_dictation`).
