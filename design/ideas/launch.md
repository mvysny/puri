# Launch: a pitch, a page, a short install and a video

Goal: Puri now does enough to promote (owner, 2026-11-23). That needs a web page on GitHub Pages
under its own domain, an install of a few steps on a small starter model, and a short video of a
few scenarios. Brainstormed 2026-11-23; decided since: the domain, `puri-ai.de`, the page, and the
install guide's shape. The pitch comes first, since the page's
headline and the video's scenarios follow from it. The starter model is the first build item,
since the install steps, the RAM the page asks for and what the video can show all hang on it.

## The pitch

### Against OpenClaw

OpenClaw is the personal agent everyone compares to in 2026, and it answers a different question:
an agent that *acts for you*. It is a daemon you message from WhatsApp or Telegram, with shell,
browser and file access and third-party skills. In practice it runs on cloud models, since it wants
64K+ context and a strong model and small local ones degrade (MindStudio). It is best known for its
security record: leaked credentials, and a Meta researcher racing to stop it from deleting her
inbox (Built In, NYU Shanghai RITS).

Puri's answer: **an assistant safe to point at your real inbox.**

- **An injected mail has no way out.** Puri reads untrusted mail, but has no fetch, no shell, no
  remote images and no send; a search query goes only to an engine Puri picks. The trifecta is
  broken by design, not guarded by a confirm (`trifecta-and-tools.md`).
- **Every outbound action is your click.** A mail opens in Thunderbird's compose window and an
  event in its import wizard.
- **The model runs on your machine.** No API key, no subscription.
- **It uses what GNOME already has.** Thunderbird, localsearch's index, Rhythmbox, GNOME Maps and
  GNOME's units. Everything comes from apt: no npm, no Electron, no `curl | sh`.

The limits go on the page too: it does nothing on its own, can't be reached from a phone, and
needs GNOME and Thunderbird. The audience isn't the people who want OpenClaw. It's the people who
looked at OpenClaw and backed off.

### What leaves your machine

A table on the page, which no other assistant seems to publish. It is honest marketing for
*Local first* and *Search, never fetch*:

| What | To | When |
|---|---|---|
| a search query, which may quote your mail | Brave or Exa (Exa's ToS licenses it for training) | `[search]` has a key |
| a place name; your home address when you ask what's near you | Photon, Nominatim, FOSSGIS's OSRM | `[maps]` |
| the map tiles of the area on screen | the `[maps]` tile server | `[maps]` |
| a point rounded to about 1 km | Open-Meteo | `[weather]` |
| your voice | the dictation server | only a hosted one |
| the conversation | the model server | only a hosted one |
| a mail or an invite | its recipients | when you click Send in Thunderbird |

### On GNOME, look first

A GNOME user compares Puri with these before OpenClaw. Check what they do before the page claims
that Puri is "the only" anything:

- **Newelle** is on Flathub, runs on llama.cpp, and its 1.2 added a command-execution tool. Seen in
  a Phoronix headline only.
- **Alpaca** is an Ollama chat client on Flathub [from memory]. It is a chat client, not an
  assistant with your data, as far as known.

## Install: what apt already does

Checked 2026-11-23 on the Ubuntu 26.04 `.deb`s with `apt-get download` and `dpkg-deb`. Nothing was
installed or run.

- **`llama.cpp-tools` 8681+dfsg-1 ships a system service.**
  - `/usr/lib/systemd/system/llama-server.service` runs as `_llama-server` with
    `LLAMA_CACHE=/var/cache/llama-server` and `EnvironmentFile=/etc/default/llama-server`. It stays
    off until enabled.
  - The defaults file documents `LLAMA_ARG_HF_REPO=`, which downloads one model from Hugging Face,
    plus `LLAMA_ARG_CTX_SIZE` and `LLAMA_API_KEY`.
  - It depends on libssl3, not libcurl, and the binary's strings carry `-hf` and `HF_TOKEN`. So the
    download is built in, and apt's own binary fetches the model. [unverified that it runs]
- **The binary has `--fit` (`LLAMA_ARG_FIT`, `--fit-ctx`, `--fit-target`).** Upstream says it
  places as many layers as free device memory holds and leaves the rest on the CPU. That is the
  owner's "GPU first, CPU fallback, never ask about VRAM", as llama.cpp's own behaviour.
  [unverified here]
- **It also has router mode** (`--models-dir`, `--models-preset`, `LLAMA_ARG_MODELS_MAX`): several
  models behind one server. That is `local-model.md`'s small tier plus big tier.
- **The GPU backends are separate packages.** `libggml0` 0.9.11 suggests the BLAS, CUDA, HIP and
  Vulkan backends. `libggml0-backend-vulkan` (55 MB installed) suggests `mesa-vulkan-drivers` and
  `nvidia-vulkan-icd`; `libggml0-backend-hip` is in the archive, `libggml0-backend-cuda` isn't. So
  Vulkan is the one backend for an AMD, Intel or NVIDIA GPU, integrated or not.
- **`whisper.cpp` 1.8.3+dfsg-2 is only binaries.** It has `whisper-server` and friends, including
  `whisper-vad-speech-segments`, but no unit, no model and no download flag. The model is the one
  file the user fetches by hand.

To test before the page relies on it:

- **lavapipe:** on a machine with no real GPU, can Mesa's software Vulkan device get picked as "the
  GPU" and be slower than plain CPU?
- **`--fit` on the 890M:** does it fit, and what context does it settle on?
- **The `-hf` download:** does it work under the system unit?
- **A clean 26.04 VM:** with no GPU at all.
- **`wget`** on a clean 26.04 desktop, for the Whisper model's step.

The page's steps, first sketched; § The install guide replaces the system unit with per-user
services:

```sh
sudo apt install ruby ruby-bundler ruby-dev build-essential ruby-gtk4 gir1.2-adw-1 \
  gir1.2-shumate-1.0 libgtk-4-bin ripgrep llama.cpp-tools libggml0-backend-vulkan whisper.cpp \
  localsearch-extractor-office
echo 'LLAMA_ARG_HF_REPO=<starter model>' | sudo tee -a /etc/default/llama-server
sudo systemctl enable --now llama-server
# the Whisper model by wget, and its user unit
git clone https://github.com/mvysny/puri && cd puri
bundle config set --local path vendor/bundle && bundle install
bundle exec rake install AUTOSTART=1
```

`llama.cpp-tools`, not the `llama.cpp` metapackage, which also recommends `-tools-extra` and
`python3-gguf`.

- **Puri isn't in apt.** git clone plus rake is fine for the early adopters a launch reaches.
  `Q_packaging` is for later.
- **Which distros:** Ubuntu 26.04, which is what CI runs. Debian or Fedora only once tested.
- **A system unit holds the model from boot,** for every user. On an 8 GB laptop that is several
  GB gone all day, which is why the guide runs per-user services.

## The install guide

Shaped with the owner, 2026-11-24; nothing written yet. Once it is, `AGENTS.md`'s rows for
`docs/` and `README.md` change to match.

- **Home:** `docs/` owns the user install, since users read the site; the README keeps the
  developer setup and links there (owner). The front page's Install section stays short and links
  to the guide.
- **Pages:** `install.html`, the quickstart, with a section for each feature under it;
  `models.html`, the model choice (owner). No site generator (owner): the pages share little beyond
  `style.css`, so each copies the `<head>`, header and footer, a spec checks they match, and the
  icon sprite moves to `icons.svg`.
- **On top, why there's no `curl | bash`** (owner): a piped script runs before you've read it, as
  you and often with sudo, and a server may send a pipe something other than what a browser shows.
  Every step here is a command you read first. A section at the end says where each piece comes
  from: GTK, Ruby, llama.cpp, whisper.cpp and localsearch from Ubuntu's archive; Puri a git clone
  of plain Ruby; its gems from rubygems.org, pinned in `Gemfile.lock` with a SHA-256 each, and
  pikuri's at one commit from GitHub; the models from Hugging Face, weights rather than programs.
  `rake install` writes three files under your home and one GNOME shortcut, prints each, and never
  runs sudo, so the guide's one sudo is `apt install`.
- **The user walks the path** (owner): every download is a command the user types, and `rake
  install` stays as it is. llama-server fetches its model with `-hf`; the Whisper model is a
  `wget` line, or a link and the folder to save it in. The guide shows each service file, and the
  user writes it.
- **The quickstart's steps,** each ending in a check that it worked: before you start (Ubuntu
  26.04 with GNOME, Thunderbird with your mail, the hardware, the disk); Thunderbird's global
  search index and the calendar's Offline Support; one `apt install`; llama-server as a user
  service; whisper-server as a user service, its model by `wget`; clone, `bundle install`, `rake
  install AUTOSTART=1`; the config, checked by running `exe/puri` in a terminal once, since a
  config error from the shortcut goes nowhere (owner, for now; `Q_startup_error`); `localsearch
  reset` and Search Locations; one question per
  feature, which is the test; last, a Brave or Exa key. Then updating, uninstalling, and
  troubleshooting by symptom.
- **One config, whole** (owner): `docs/config.toml`, every table present and commented with what
  it does, what it sends out and how to turn it off, since fragments get missed. Only `[search]`
  stays commented out, waiting for a key. Maps and weather are on, and the guide says what they
  send. The quickstart copies the file from the clone, and the site serves it for reading first.
  Puri's missing-config error points at it instead of printing `EXAMPLE_CONFIG`, a second copy;
  a spec loads it through Core's config, so a renamed key fails the gate. Dropped: Puri writing
  the config on first run. Puri reads it only at start, so after an edit the guide says Ctrl+Q,
  or `gapplication action io.github.mvysny.Puri quit`, then the shortcut.
- **Both servers run as per-user systemd services** (owner), from login, rather than apt's system
  unit, which holds the model from boot for every user. The model stays resident, for an instant
  answer; no `--sleep-idle-seconds` (owner), and a game is the one time to stop the service.
- **One model for everyone, Qwen3.5-4B** (owner): small, the likeliest to run, a small download.
  Once it works, Ornith is the upgrade if the machine takes it. One `-hf` model per server, no
  router mode (`--models-preset`): these models take too much memory to load two. Titles come
  from the same model with thinking off.
- **`models.html`:** Qwen against Ornith: 76 % against 92 % of the eval tasks, the planted bank
  account, 3–4 GB against about 23 GB to download (21.7 GB of weights), and memory: Ornith needs
  about 32 GB for itself at 64K, so a machine of 48 GB or more (owner). Which hardware takes
  which. The home server over Tailscale, moved from the README.
- **Ornith on integrated graphics** (owner): the GPU's share of RAM may need raising, in the BIOS
  or, on a Radeon, with the kernel's `ttm.pages_limit=N ttm.page_pool_size=N`. N counts 4 KiB
  pages, so GiB × 262144; the owner's 18350080 is 70 GiB. On Intel the user looks up their own.
- **12–16 GB cards: Strata** (<https://github.com/niko1221/strata>), short and marked advanced.
  Qwen3.6-35B-A3B, which the owner found solid on pikuri-tui and pikuri-web; Strata probably has
  no Ornith. It serves an OpenAI-compatible API on localhost, so Puri needs one `[[server]]` URL.
  It installs from its own releases, an AppImage that downloads its engine or an `install.sh`,
  outside apt, so the section says the guide doesn't vouch for it. The section is marked
  experimental (owner): Puri's first prompt alone is 9.6K tokens, the owner's 8 GB card held an 8K
  context, too small, and a 12 GB card may hold 32K or 64K, unverified. Strata's README (read
  2026-11-24) gives no context length.
- **Games and VRAM** (owner): Qwen holds most of an 8 GB card, 2.8 GiB of weights and 2 GiB of
  cache at 64K before the projector and buffers, so a big game may not run until llama-server
  stops. The guide gives `systemctl --user stop llama-server` and `start`, and sends the user to
  Resources, which shows the card's memory and comes with `ubuntu-desktop-minimal`. A sentence at
  the model step, a section of its own, and a troubleshooting entry.
- **The Whisper model:** multilingual, since an `.en` model turns other languages into English
  gibberish; likely `small`, since the Vulkan backend comes for llama.cpp anyway
  (`Q_recommended_model` in `whisper-models.md`).

## The starter model

**Decided:** Qwen3.5-4B for everyone (owner, 2026-11-24), § The install guide. What led there:

Gated on `Q_eval_suite` in `local-model.md`: a few dozen real requests, each with its expected
tool call, run against each candidate. Candidates from `local-model/apple-on-device-models.md`:

- **Nemotron 3.5 Bolt E4B 4GB:** tuned for device-assistant tool use, and the least prone to
  calling tools that don't exist.
- **Qwen3.5-4B:** best on Tau2, but the most prone to calling tools that don't exist.
- **Granite 4.2 3B.**
- **LFM3-1.7B:** about 1 GB; its deferred tools shrink the prompt.

What to measure on each:

- the eval's pass rate;
- time to first token with Puri's full prefix (about 20 tools plus the system prompt), on CPU only
  and on the 890M over Vulkan;
- tokens/s;
- RAM at the context `--fit` settles on;
- the download size.

Download size probably isn't what decides it. Time to first token on a CPU-only laptop may be.
Per `D_own_prompts`, the winner may need a system prompt of its own.

The page then offers two tiers. The starter model runs on 8 GB of RAM. Ornith 1.5, or a sparse
model from the research file, runs on a bigger box or on a home server over Tailscale (the README
already has that section).

Whisper's starter model is `Q_recommended_model` in `whisper-models.md`, the same question. The
owner measured `small.en` at 7–8 s a clip on CPU, so `base.en` (~150 MB) is the candidate for a
first run; `small.en` is ~0.5 GB.

## The page and the domain

- **The page is built** (owner, 2026-11-24): `docs/`, in libadwaita's own look, a GNOME desktop
  in the hero with the popup replaying three invented conversations, the what-leaves table drawn
  as a diagram of the computer's edge, and Kuri as the logo. Two other directions were drawn and
  set aside: a gold, mascot-led page, too cute for a first visit that must earn trust, and the
  diagram as the whole page, which sold safety before use. Left: Pages switched on, the DNS, the
  headline, the video in place of the replay.
- **Hosting:** GitHub Pages from `docs/` on `master`, with a `CNAME` file, and the DNS records in
  Hetzner Robot, which holds the domain.
- **The domain:** `puri-ai.de`, registered at Hetzner (owner, 2026-11-24). Read one way it's
  "Puri aide", the other way "Puri AI". "Puri" alone collides with the city in Odisha and the
  fried bread, so the page's title needs the qualifier too. A `.de` asks no citizenship or
  residency. A holder living outside Germany has two weeks to name an authorised recipient in
  Germany, but only if DENIC asks, and DENIC asks only when someone wants to serve papers over a
  dispute about the domain (DENIC terms §3(4)).
- **Not on it yet:** the tiers and the home server beyond one FAQ link, and dictation. The install
  starts llama-server in the foreground on Qwen3.5-4B (owner, 2026-11-24), until the install guide
  makes it a per-user service.
- **One home for the install:** the site, in the install guide; the README keeps the developer
  setup (owner, 2026-11-24).

## The video

- **Scenarios that each show a promise, not just a feature:**
  - "What's the weather on my trip?": the calendar, then the forecast.
  - "Tell Anna I'll be 10 minutes late": the draft opens in Thunderbird, and the cursor clicks
    Send.
  - "Find the invoice from Acme": documents.
  - F5 dictation.
  - A drive, with the map under the answer.
  - Optional: a mail with an injection in it, which Puri reads, and nothing happens. The contrast
    with OpenClaw in ten seconds.
- **Demo data, not the owner's mail:** a Thunderbird profile, a calendar and a `~/Documents` of
  invented people. That also makes a retake reproducible (`Q_demo_data`).
- **Record on the starter model the page recommends,** so the video shows what an install gets.
  If it can't carry the demo, that is a finding before launch. Cutting the wait is fine, but say
  so on screen ("shortened; <model> on <machine>"), or the first issue filed is "it's slow"
  (`Q_video_speed`).
- **Tools:** GNOME's own screen recorder (Ctrl+Shift+Alt+R); Kdenlive or Shotcut to cut, both in
  apt [from memory].

## Before launch: the free public services

One user is light use; a launch may bring hundreds, each hitting the same free services. Their
policies are already in `R_osm_services` and `R_open_meteo`; what a launch changes:

- **Nominatim and FOSSGIS's OSRM:** a request a second and an identifying User-Agent each. Does
  the limit count per install, or for every install behind Puri's one User-Agent? Not read yet;
  check before launch.
- **Photon:** throttles "extensive usage", with no number given.
- **OSM's tiles:** an identifying User-Agent. libshumate sends its own, and Puri's never reaches
  the wire (`Q_tiles_ua` in `map-tiles-user-agent.md`). Settle that first.
- **Open-Meteo:** under 10,000 calls a day, non-commercial. Fine per user.
- **Brave Search's free tier:** what it costs now. Check before the page says "free".

## Proposed order (not decided)

1. The eval suite, and the starter model.
2. The apt-only install on a clean 26.04 VM and on the 890M host; measure.
3. `docs/config.toml`, then the install guide.
4. The public services' policies, `Q_tiles_ua` first.
5. The page, and the domain's DNS pointed at it.
6. The video, on the documented setup.

## Open questions

- `Q_headline`: "Siri for the Linux desktop that runs on your machine", or the inbox angle, "an
  assistant safe to point at your real inbox"? Any claim must survive the what-leaves table: a
  search query *can* carry mail text to Brave.
- `Q_startup_error`: started from the shortcut, Puri prints a config error to stderr and exits,
  so the press does nothing. Show the error in a window? Revisit after the guide (owner).
- `Q_packaging`: one day `apt install puri`? Options: a Launchpad PPA, which builds from source
  with the gems vendored; Debian packages for pikuri's gems, slow; or Flatpak, whose sandbox
  would need holes for the Thunderbird profile, localsearch, podman and Rhythmbox's D-Bus.
- `Q_demo_data`: where does the invented profile live? It's code that `dev/` would load, per the
  module map: a Dummy-side fixture, or a separate repo?
- `Q_video_speed`: real time on the starter model, or a cut with a caption?
- `Q_competitors`: Newelle and Alpaca, tried before the page compares?

## Sources (2026-11-23)

- [MindStudio: What is OpenClaw](https://www.mindstudio.ai/blog/what-is-openclaw-ai-agent): the
  64K context, and local models degrading.
- [Built In: What is OpenClaw](https://builtin.com/articles/what-is-openclaw): the inbox incident.
- [NYU Shanghai RITS: OpenClaw, beware the risks](https://rits.shanghai.nyu.edu/ai/openclaw-the-open-source-ai-agent-you-can-run-locally-but-beware-the-risks/)
- [HackerNoon: OpenClaw is a security nightmare](https://hackernoon.com/openclaw-is-a-security-nightmare-here-are-the-alternatives-to-use-instead)
- [Phoronix: Newelle 1.2](https://phoronix.com/news/gnome-ai-newelle-1.2)
- [DENIC Domain Terms and Conditions](https://www.denic.de/en/domain-terms-and-conditions/),
  §3(4), §7(2), §8(3), read 2026-11-24 in the English translation, which isn't binding: no
  residency rule, the authorised recipient only on request.
- The Ubuntu 26.04 archive: `llama.cpp-tools` 8681+dfsg-1, `whisper.cpp` 1.8.3+dfsg-2, `libggml0`
  0.9.11-1, read with `apt-cache` and `dpkg-deb`.
