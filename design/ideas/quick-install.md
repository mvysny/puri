# Quick install: Puri runs its servers, and one setup script

Goal: a privacy-minded user who isn't a programmer gets Puri running in a few commands, with
nothing to configure and no moving parts to understand (owner, 2026-11-25). Two paths: the quick
one, for whoever just wants it running, and today's `install.html`, the long one, for the power
user who wants every setting.

## Decided (owner, 2026-11-25)

- **How the model runs is an implementation detail**, as long as it runs locally or somewhere the
  user controls: privacy is what Puri is. The simplest way wins, whether `llama-cli`, llama.cpp
  itself or `llama-server`.
- **Today that is `llama-server` as Puri's child**, and `whisper-server` beside it: Puri starts
  them, restarts one that crashes, and stops them when Puri quits. Apt's binaries, nothing linked
  into Puri. A game then needs only Ctrl+Q. It lives here, per *Prototype here*.
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
- **It writes the config only when there is none**, the long guide's config with the servers as
  Puri's children.

## The servers, sketched

- `llama-server -m <file> -c 65536 --no-mmproj`: a file the setup downloaded, never `-hf`, so the
  server itself needs no network. `--no-mmproj` because Puri sends no images, and Qwen's repo
  ships a 0.34–0.63 GiB vision projector that `-hf` fetches and loads by default.
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

## The setup script, sketched

- **One idempotent command:** the first run installs, and any later run is the doctor. Ruby's
  stdlib only, since `bundle install` is one of its fixes. Never sudo, never `curl | sh`: it sits
  in the clone, readable before it runs.
- **In order, each check with its fix:**
  - apt packages: one `sudo apt install` line of what's missing, then stop;
  - `bundle install`, then `rake install AUTOSTART=1`;
  - the models: asks which, and downloads with a progress bar, resuming with `Range` and checking
    the SHA-256 that Hugging Face's API lists. Ornith only where `llama-server --list-devices` and
    the RAM say it fits (`models.html`'s rule); the `ttm` kernel parameters printed, never applied;
  - the config, written when missing, never edited;
  - Thunderbird's global search and the calendar's Offline Support, printed as where to click;
  - localsearch: its status, the office extractor, `localsearch reset` after asking, Documents in
    Search Locations.
- The quick path is then: the apt line, `git clone`, the setup script, the shortcut.

## Changes to what `launch.md` decided

- *The user walks the path, every download a command the user types* holds for the long guide
  only; the quick path's script downloads.
- *Both servers run as per-user systemd services* becomes the long guide's way, and the home
  server's. Whether the long guide switches to Puri's children too is `Q_long_guide`.

## The site

- The CPU-only warning links to `models.html#no-gpu`.
- Untested: the install guide's own setup on a computer with no graphics card. It installs
  `libggml0-backend-vulkan`, and with Mesa's software Vulkan (lavapipe) beside it, llama.cpp may
  take lavapipe for a GPU (`launch.md`'s *lavapipe*). The numbers on the page are llama.cpp's CPU
  backend with no GPU backend installed. Testing it on the owner's VM needs that package
  installed there.

## Open questions

- `Q_config_template`: one `docs/config.toml` for both paths, its `[[server]]` naming the model
  file Puri runs, with `url` commented as the way to a server of your own? Then the script copies
  it verbatim and nothing drifts.
- `Q_long_guide`: does the long guide keep its service files, or use Puri's children too and keep
  the service files for the home server alone?
- `Q_setup_name`: `bin/setup`, `exe/puri-setup` or `rake setup`?
- `Q_dictation_cli`: `whisper-cli` once per clip instead of a resident `whisper-server`: no
  process, port or memory held all day, at the price of loading the model per clip. Worth it
  only if that load is small beside the encoder's 7 s floor on a CPU; unmeasured. It also forks
  dictation into a local and a remote path, where today both are one OpenAI-shaped request
  (`D_dictation`).
