# Puri — AGENTS.md

## What this is

A Siri-style desktop assistant for Linux and GNOME, on top of [pikuri](https://github.com/mvysny/pikuri).
A global shortcut pops up a search bar; you type, and the bar grows into a streamed conversation,
with every earlier conversation one click away in the same window.
It reads your Thunderbird mail and calendar and your documents, keeps notes, drafts a mail or an
event for you to send, and can search the web, but never opens a URL, and the model runs on your
own machine whenever it can.

Pikuri owns the agent loop, the tools, the prompts and the LLM transport. This project owns the
popup window, the conversation history beside it, and the resident process that keeps the agent
warm.

## Promises

- **Local first.** The model runs on this machine whenever it can; a hosted provider is an explicit opt-in, and pikuri's *Privacy first* holds at this layer.
- **Search, never fetch.** The agent talks only to the configured search engines and map services and never opens a URL; every other outbound leg — a mail, an invite, a place opened from the map — waits on the human.
- **One window.** The popup, the running conversation and every earlier one live in one app; nothing needs a second app to find an old answer.
- **A desktop UI and nothing else.** Loop, tools, transport, and every prompt their code depends on, stay pikuri's; a behaviour implemented on both sides drifts. The system prompts are ours, mixing our own text with the fragments pikuri's extensions bring (`D_own_prompts`).

## Design docs

| File | Owns | Loaded |
|---|---|---|
| `README.md` | the pitch, install, how to run | — |
| `docs/` | the web page at puri-ai.de, plain files GitHub Pages serves from `master`: the pitch and a short install, linking to the README for the rest | — |
| `AGENTS.md` (this) | promises, invariants, the module map, conventions, commands | every turn |
| `design/architecture.md` | how the pieces compose — wiring, dependency direction, threads, the flows; normative | lazy |
| `design/decisions.md` | why this and not that — `D_` entries, FAQ-shaped | lazy |
| `design/research.md` | what Siri, the GTK stack and the map services actually do — `R_` entries, each claim with provenance | lazy |
| `design/ideas/` | not yet decided — one file per idea, `ls` is the index, deleted on graduation | transient |
| doc comments | what one symbol does and why it is shaped so | at the symbol |

Every fact lives in exactly one of these; the others link to it.

## Invariants

- **Core and Protocol never name GTK; Desktop never names Pikuri or Core.** Only `exe/puri` knows both sides; `spec/boundaries_spec.rb` checks it. See `D_one_process`.
- **Every argument, result and event crosses as JSON** (`Protocol.round_trip`), so splitting into two processes swaps only the connection.
- **Core's events reach widgets only through `BackendClient#deliver`**, the one hop onto the GTK main loop.

## Module map

- `lib/puri/core/` — `Puri::Core`, the backend on `pikuri-conversations`: conversations, their display, the agent's tools, the mic's dictation; never GTK.
- `lib/puri/protocol/` — `Puri::Protocol`: the `Backend` methods Desktop calls, and the JSON-able `Data` they and Core's events carry.
- `lib/puri/desktop/` — `Puri::Desktop`, the GTK4 widgets and `BackendClient`, nothing else.
- `exe/puri` — the composition root: loads GTK, Adw and Shumate, wires Core to Desktop.
- `dev/` — development only, loaded by `exe/puri --dummy` and the specs, never otherwise: `Puri::Dummy`, the canned backend the GTK specs drive. Code a dev-only mode loads, never loose scripts.

## Conventions

- **Linux and GNOME only, Wayland first.** No macOS or Windows code paths; X11 works only where it comes for free.
- **Ruby, GTK4, libadwaita and libshumate from distro packages** — apt's `ruby` (pikuri needs ≥ 3.3), `ruby-gtk4`, `gir1.2-adw-1` and `gir1.2-shumate-1.0` loaded through GObject Introspection; a gem or binary apt does not ship waits on the owner.
- **`gtk4` stays out of the Gemfile:** Bundler would compile it from source, while `require 'gtk4'` finds apt's copy under `bundle exec` anyway; the gtk4-dev skill has the details.
- **Desktop only draws:** ordering, titling, wording a tool line or a confirmation, rendering Markdown are Core's, and Desktop keeps view state only (`D_ruby_gtk4`); a feature that grows Desktop belongs in Core.
- **A gap is a missing pikuri primitive**, never a workaround here: a tool, a prompt or a listener event goes upstream, and whatever this app shares with pikuri-tui or pikuri-web lives in pikuri or its workshop, never in a copy; hosting conversations is `pikuri-conversations`' (`D_port_pikuri_web`). The place tools, `weather`, `play_music` and dictation's transcription are the exceptions, until they move (`D_places`, `D_weather`, `D_music`, `D_dictation`).

## Commands

- `bundle exec rake` — the gate: specs, rubocop, `sig/puri.rbs` from the YARD tags, the doc tripwires.
- CI: `.github/workflows/ci.yml` runs the gate in `ubuntu:26.04` on apt's Ruby, then fails on a `sig/` diff.
- `bundle lock --add-checksums` — after any Gemfile change, or CI's frozen bundle rejects the lockfile.
- `ADW_DISABLE_PORTAL=1 GDK_BACKEND=broadway BROADWAY_DISPLAY=:5 dbus-run-session -- exe/puri --dummy` — the app on Broadway, canned answers, on a bus of its own so a resident Puri doesn't take the launch; natively just `exe/puri`.
- `bundle exec rake install` / `uninstall` — the per-user D-Bus activation and the global shortcut (`HOTKEY`, `AUTOSTART=1`; README); `spec/install_spec.rb` runs it against a scratch home.
- GTK specs start their own `gtk4-broadwayd` on `:90`–`:99` unless `GDK_BACKEND` is set.
- `design/verify_design_tripwires.sh` — the doc-layer tripwire.
- `python3 -m http.server -d docs` — the web page locally; it loads nothing from other sites, and its footer says so.

## Skills this project follows

- **Ruby:** YARD tags are the types (sord writes `sig/puri.rbs`, never hand-edited), rspec-core with minitest asserts, no mocks; the `ruby` skill.

- **Component-oriented:** self-sufficient components that reach their data directly, no MVC layers; the `cop` skill has the rules.
- **GTK4 dev, headless:** run, drive and screenshot the app on Broadway with Playwright; the `gtk4-dev` skill has the loop and the gotchas.

## Maintenance of this file

Loaded every turn; cap 34 KB, a module's own `AGENTS.md` 10 KB. Over it, in this order:
delete what has no home — status, history, class lists, what the code already says; trim
each line to its fact plus one clause and send the explanation home — why →
`design/decisions.md`, how across symbols → `design/architecture.md`, how in one symbol →
its doc comment, what upstream does → `design/research.md`; only then a module's own
`AGENTS.md`, peripheral modules first, never the core. Never paraphrase a lazy entry into a
line here. `design/verify_design_tripwires.sh` checks the caps and the cites.
