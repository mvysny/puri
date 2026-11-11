# Puri

A Siri-style desktop assistant for Linux and GNOME, on top of [pikuri](https://codeberg.org/mvysny/pikuri).
A global shortcut pops up a search bar; you type, and the bar grows into a streamed conversation,
with every earlier conversation one click away in the same window.
It reads and writes your notes and reminders and can search the web, but never opens a URL, and
the model runs on your own machine whenever it can.

Pikuri owns the agent loop, the tools, the prompts and the LLM transport. This project owns the
popup window, the conversation history beside it, and the resident process that keeps the agent
warm.

The name is *pikuri* with the middle dropped; it rhymes with Siri and with Kuri, pikuri's pika
mascot. "Ask Puri."

**Status:** a skeleton. The window asks a dummy backend, which streams lorem ipsum back; the plan
lives in `design/ideas/`.

## Install and run

Linux and GNOME only. GTK4 and libadwaita come from apt, never from gems:

```sh
sudo apt install ruby ruby-bundler ruby-dev build-essential ruby-gtk4 gir1.2-adw-1 libgtk-4-bin
bundle config set --local path vendor/bundle
bundle install
exe/puri
```

`bundle exec rake` runs the specs, rubocop, the type signatures and the doc checks, as CI does.
