# Quick install: the site leads with `bin/setup`

Goal: a privacy-minded user who isn't a programmer gets Puri running in a few commands, with
nothing to configure and no moving parts to understand (owner, 2026-11-25). Two paths: the quick
one, for whoever just wants it running, and today's `install.html`, the long one, for the power
user who wants every setting.

Built (2026-11-25): `bin/setup`, the setup that is also the doctor (`D_setup`, `Puri::Setup`),
and the embedded `llama-server` and `whisper-cli` it sets up (`D_embedded`). The install guide's
troubleshooting and Puri's "isn't downloaded" errors name it. Left: the site leading with it.

## The site

- **The quick path:** the apt line, `git clone`, `bin/setup`, the shortcut. Its apt line is
  `Puri::Setup::Packages::LIST`, which `spec/site_spec.rb` already holds the long guide's first
  line to; no `hf` line, since the setup downloads the models itself.
- **The funnel** (owner, 2026-11-25): a user who tried Puri locally and got hooked is the one who
  later sets up a desktop PC or a home server for a smarter model. The quick install is the hook,
  so it comes before new tools. The site then leads with the quick path, and `models.html`
  becomes the upgrade story: Ornith, a home server over Tailscale, the laptop's battery spared.
  It can also say what Siri can't: no account, no subscription, no server of ours.
- **`models.html`'s switch to Ornith** then reads: edit the config, run `bin/setup`, which
  downloads it; the `hf download` line stays for the long path. The setup's tip points at
  `#ornith`, and, on integrated Radeon graphics, `#igpu` with the `ttm` options worked out.
- **The "why there's no one-line installer" box** gains the setup: one command, but one in the
  clone, read before it runs, that asks before each fix and never uses `sudo`.

## Changes to what `launch.md` decided

- *The user walks the path, every download a command the user types* holds for the long guide
  only; the quick path's script downloads.
- *Both servers run as per-user systemd services* holds for the home server alone; the long
  guide runs embedded too (owner, 2026-11-25).

## Untested

- **`localsearch reset --file ~/Documents`** brings the office files' text back once
  `localsearch-extractor-office` is in, as the setup assumes; the guide's step 6 resets the whole
  index instead (`R_localsearch_cli`). Check on the VM: install the extractor, run `bin/setup`,
  say yes, wait, run it again.
- **What `llama-server --list-devices` reads on the 890M** (`R_llama_list_devices`): the
  firmware's share or what the kernel lends, with and without the owner's `ttm` options. The
  setup's Ornith tip assumes a GPU reporting 30 GiB or more holds it.
- **lavapipe:** a computer with no graphics card, `libggml0-backend-vulkan` and Mesa's software
  Vulkan beside it. Does `--list-devices` list lavapipe, and does llama.cpp then run on it? The
  setup counts it as no GPU and warns; llama.cpp may still pick it (`launch.md`'s *lavapipe*).
- **The quick path, top to bottom,** on a clean 26.04 VM.
