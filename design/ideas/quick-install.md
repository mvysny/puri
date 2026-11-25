# Quick install: the site leads with `bin/setup`

Goal: a privacy-minded user who isn't a programmer gets Puri running in a few commands, with
nothing to configure and no moving parts to understand (owner, 2026-11-25). Two paths: the quick
one, for whoever just wants it running, and today's `install.html`, the long one, for the power
user who wants every setting.

Built (2026-11-25): `bin/setup`, the setup that is also the doctor (`D_setup`, `Puri::Setup`),
and the embedded `llama-server` and `whisper-cli` it sets up (`D_embedded`). The site leads with
it: the front page's "Install (Super-Quick)", its three commands and the setup's four actions,
and the guide's "Super-quick" above "Step by step". The "why there's no one-line installer" box
is gone (owner, 2026-11-25). Left: `models.html`.

## `models.html`

- **The funnel** (owner, 2026-11-25): a user who tried Puri locally and got hooked is the one who
  later sets up a desktop PC or a home server for a smarter model. `models.html` is the upgrade
  story: Ornith, a home server over Tailscale, the laptop's battery spared. It can also say what
  Siri can't: no account, no subscription, no server of ours.
- **Its switch to Ornith** then reads: edit the config, run `bin/setup`, which downloads it; the
  `hf download` line stays for the step-by-step path. The setup's tip points at `#ornith`, and,
  on integrated Radeon graphics, `#igpu` with the `ttm` options worked out.

## Untested

- **`localsearch reset --file ~/Documents`** brings the office files' text back once
  `localsearch-extractor-office` is in, as the setup assumes; the guide's step 6 resets the whole
  index instead (`R_localsearch_cli`). Check on the VM: install the extractor, run `bin/setup`,
  say yes, wait, run it again.
- **What `llama-server --list-devices` reads on the 890M** (`R_llama_list_devices`): the
  firmware's share or what the kernel lends, with and without the owner's `ttm` options. The
  setup's Ornith tip assumes a GPU reporting 30 GiB or more holds it.
- **Both paths, top to bottom,** on a clean 26.04 VM. The quick one's headless half, the apt
  line to the doctor's second run, is `rake fresh_install`; left for the VM are the shortcut
  opening Puri in a real session, a GPU, and the long guide, whose calendar click path
  (right-click the calendar → Properties → Offline Support) was written from memory; check it in
  Thunderbird.
