# Puri

A Siri-style desktop assistant for Linux and GNOME, on top of [pikuri](https://github.com/mvysny/pikuri).
A global shortcut pops up a search bar; you type, and the bar grows into a streamed conversation,
with every earlier conversation one click away in the same window.
It reads your Thunderbird mail and calendar and your documents, keeps notes, drafts a mail or an
event for you to send, and can search the web, but never opens a URL, and the model runs on your
own machine whenever it can.

The web page, [puri-ai.de](https://puri-ai.de), shows it at work and lists everything that
leaves your computer.

Pikuri owns the agent loop, the tools, the prompts and the LLM transport. This project owns the
popup window, the conversation history beside it, and the resident process that keeps the agent
warm.

The name is *pikuri* with the middle dropped; it rhymes with Siri and with Kuri, pikuri's pika
mascot. "Ask Puri."

**Status:** the UI is done, and the model answers through pikuri. It can search the web, read
your Thunderbird mail, contacts and calendar, search, read and take notes in your documents, and
find places and car routes on OpenStreetMap, with a map under the answer, tell the weather, and
play your music in Rhythmbox. The plan lives in `design/ideas/`.

## Install

To use Puri, follow the [install guide](https://puri-ai.de/install.html): the packages, the model
and dictation as services of your own, Puri, and its config, with a check after each step.
[Choose a model](https://puri-ai.de/models.html) covers a smarter model than the guide's, which
computer runs which, and a home server over Tailscale. The rest of this README is for working on
Puri.

## Develop

Linux and GNOME only. GTK4, libadwaita and libshumate, the map widget, come from apt, never from
gems:

```sh
sudo apt install ruby ruby-bundler ruby-dev build-essential ruby-gtk4 gir1.2-adw-1 gir1.2-shumate-1.0 libgtk-4-bin ripgrep
bundle config set --local path vendor/bundle
bundle install
exe/puri --dummy
```

`exe/puri --dummy` runs a canned backend, with no config and no model: `search`, `note`, `table`,
`long`, `coffee`, `drive`, `weather`, `fail`, `mail`, or `calendar` plus `reschedule` in a
question walk the paths the tools will take. Plain `exe/puri` runs the real one, which needs a
model server and `~/.config/puri/config.toml`: copy `docs/config.toml`, whose comments say what
each part does. Escape hides the window, running `exe/puri` again brings it back, and Ctrl+Q
quits it, as does `gapplication action io.github.mvysny.Puri quit`.

`bundle exec rake` runs the specs, rubocop, the type signatures and the doc checks, as CI does.
`AGENTS.md` has the module map, the conventions and the rest of the commands; `design/` the
architecture, the decisions and the research behind them.

## License

MIT
