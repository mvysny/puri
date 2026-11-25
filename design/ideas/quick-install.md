# Quick install: one setup script

Goal: a privacy-minded user who isn't a programmer gets Puri running in a few commands, with
nothing to configure and no moving parts to understand (owner, 2026-11-25). Two paths: the quick
one, for whoever just wants it running, and today's `install.html`, the long one, for the power
user who wants every setting.

Built (2026-11-25): Puri runs `llama-server` and `whisper-cli` itself when the config gives no
`url` (`D_embedded`, `R_llama_server_embedded`, `R_whisper_cli`, `R_hub_cache`). Left: the setup
script, the guides and the site.

## Decided (owner, 2026-11-25)

- **A server the user runs is the user's to secure;** the guides offer Puri's own two, a key and
  `--cors-origins localhost`, as tips.
- **A machine without a GPU:** the setup script warns that answers will be very slow, links to a
  page of the site with the other options, and lets the user carry on.
- **A setup script, plain CLI** (no Tuile, a progress bar at most). It checks everything, fixes
  what needs no sudo once the user says yes, and prints what needs sudo for the user to run. The
  big fix is the downloads: Qwen or Ornith, and the Whisper model.
- **It writes the config only when there is none**, the long guide's config with the model and
  dictation both embedded.

## The setup script, sketched

- **One idempotent command:** the first run installs, and any later run is the doctor. Ruby's
  stdlib only, since `bundle install` is one of its fixes. Never sudo, never `curl | sh`: it sits
  in the clone, readable before it runs.
- **In order, each check with its fix:**
  - apt packages: one `sudo apt install` line of what's missing, then stop;
  - `bundle install`, then `rake install AUTOSTART=1`;
  - the models: asks which, and downloads into the hub cache with a progress bar, resuming with
    `Range` and checking the SHA-256 that Hugging Face's API lists (`R_hub_cache`): Qwen or
    Ornith, `-hf`'s `org/repo:quant`, and Whisper's `ggerganov/whisper.cpp:ggml-small.bin`. Ornith
    only where `llama-server --list-devices` and the RAM say it fits (`models.html`'s rule); the
    `ttm` kernel parameters printed, never applied;
  - the config, written when missing, never edited;
  - Thunderbird's global search and the calendar's Offline Support, printed as where to click;
  - localsearch: its status, the office extractor, `localsearch reset` after asking, Documents in
    Search Locations.
- The quick path is then: the apt line, `git clone`, the setup script, the shortcut.
- Once it exists, the "isn't downloaded" errors of `LlamaServer` and `WhisperCli` name it, in
  place of `llama-server -hf` and the cache's folder.
- The long guide's per-user `llama-server` service reads the same cache, so switching between it
  and embedded downloads nothing twice.

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
  nothing drifts. Today it still names `localhost:8080`, the long guide's service.
- `Q_long_guide`: does the long guide keep its service files, or use embedded too and keep the
  service files for the home server alone?
- `Q_setup_name`: `bin/setup`, `exe/puri-setup` or `rake setup`?
