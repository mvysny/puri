# Puri — AGENTS.md

## What this is

A Siri-style desktop assistant for Linux and GNOME, on top of [pikuri](https://codeberg.org/mvysny/pikuri).
A global shortcut pops up a search bar; you type, and the bar grows into a streamed conversation,
with every earlier conversation one click away in the same window.
It reads and writes your notes and reminders and can search the web, but never opens a URL, and
the model runs on your own machine whenever it can.

Pikuri owns the agent loop, the tools, the prompts and the LLM transport. This project owns the
popup window, the conversation history beside it, and the resident process that keeps the agent
warm.

## Promises

- **Local first.** The model runs on this machine whenever it can; a hosted provider is an explicit opt-in, and pikuri's *Privacy first* holds at this layer.
- **Search, never fetch.** The agent talks only to the configured search engines and never opens a URL; every other outbound leg — a mail, an invite — waits on the human.
- **One window.** The popup, the running conversation and every earlier one live in one app; nothing needs a second app to find an old answer.
- **A desktop UI and nothing else.** Loop, tools, transport *and prompts* stay pikuri's; a behaviour implemented on both sides drifts.

## Design docs

| File | Owns | Loaded |
|---|---|---|
| `README.md` | the pitch, install, how to run | — |
| `AGENTS.md` (this) | promises, invariants, the module map, conventions, commands | every turn |
| `design/ideas/` | not yet decided — one file per idea, `ls` is the index, deleted on graduation | transient |
| doc comments | what one symbol does and why it is shaped so | at the symbol |

Every fact lives in exactly one of these; the others link to it.

## Conventions

- **Linux and GNOME only, Wayland first.** No macOS or Windows code paths; X11 works only where it comes for free.
- **Ruby, GTK4 and libadwaita from distro packages** — `ruby-gtk4`, `gir1.2-adw-1` loaded through GObject Introspection; a gem or binary apt does not ship waits on the owner.
- **A gap is a missing pikuri primitive**, never a workaround here: a tool, a prompt or a listener event goes upstream, and whatever this app shares with pikuri-tui or pikuri-web lives in pikuri, never in a copy.

## Commands

- `design/verify_design_tripwires.sh` — the doc-layer tripwire.

## Skills this project follows

- **Component-oriented:** self-sufficient components that reach their data directly, no MVC layers; the `cop` skill has the rules.

## Maintenance of this file

Loaded every turn; cap 34 KB, a module's own `AGENTS.md` 10 KB. Over it, in this order:
delete what has no home — status, history, class lists, what the code already says; trim
each line to its fact plus one clause and send the explanation home — why →
`design/decisions.md`, how across symbols → `design/architecture.md`, how in one symbol →
its doc comment, what upstream does → `design/research.md`; only then a module's own
`AGENTS.md`, peripheral modules first, never the core. Never paraphrase a lazy entry into a
line here. `design/verify_design_tripwires.sh` checks the caps and the cites.
