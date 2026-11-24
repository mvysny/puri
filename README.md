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
play your music in Rhythmbox. `exe/puri --dummy` runs
a canned backend instead, with no config and no model: `search`, `note`, `table`, `long`,
`coffee`, `drive`, `weather`, `fail`, `mail`, or `calendar` plus `reschedule` in a question walk the paths
the tools will take. The plan lives in `design/ideas/`.

## Install and run

Linux and GNOME only. GTK4, libadwaita and libshumate, the map widget, come from apt, never from
gems:

```sh
sudo apt install ruby ruby-bundler ruby-dev build-essential ruby-gtk4 gir1.2-adw-1 gir1.2-shumate-1.0 libgtk-4-bin ripgrep
bundle config set --local path vendor/bundle
bundle install
exe/puri
```

`exe/puri` starts Puri; Escape hides the window, and running `exe/puri` again brings it back.

## Configure the model

Puri has no built-in model: it talks to an OpenAI-compatible server you run, such as
[llama.cpp](https://github.com/ggml-org/llama.cpp)'s `llama-server`, and reads where it is from
`~/.config/puri/config.toml`. Without that file Puri won't start, and prints an example to paste
there:

```toml
[[server]]
id  = "local"
url = "http://localhost:8080"
# api_key = "…"                  # if the server wants one
# max_concurrent_requests = 1    # omitted, Puri asks the server how many slots it has

[[llm]]
name   = "Ornith 1.5"
server = "local"
model  = "Ornith-1.5"

[[llm]]
name   = "Ornith 1.5, no thinking"
server = "local"
model  = "Ornith-1.5"
params = { chat_template_kwargs = { enable_thinking = false } }

[titler]
llm = "Ornith 1.5, no thinking"
```

Conversations run on the first `[[llm]]`. `[titler]` names the connection that titles them; the
same model with its thinking switched off writes a title in about a second rather than thirty.
`chmod 600` the file if it holds a key. Conversations are saved under
`~/.local/state/puri/conversations/`. To run the model on a home server instead, see
[A home server over Tailscale](#a-home-server-over-tailscale).

To let Puri search the web, add a [Brave Search](https://api-dashboard.search.brave.com) or
[Exa](https://exa.ai) key:

```toml
[search]
brave_key = "…"
# exa_key = "…"
# engines = ["brave"]   # omitted, every engine with a key
```

Puri reads the pages a search finds from the engine's own copy, so it never opens a link itself.
That is also why DuckDuckGo isn't offered: it returns no page text. Without a key Puri still
runs, logs an error and doesn't search.

Puri reads mail, contacts and calendar from your local Thunderbird profile, snap or apt, found on
its own; it never speaks IMAP or CalDAV. Mail search needs Thunderbird's global search index, and
the calendar its Offline Support. Asked to write a mail or add an event, Puri opens the draft in
Thunderbird's compose window or import wizard, and nothing leaves until you send or add it there.
To point it elsewhere, or switch it off:

```toml
[thunderbird]
profile_dir = "~/snap/thunderbird/common/.thunderbird/abcd1234.default"
# enabled = false
```

To let Puri search and read your documents, add the table:

```toml
[documents]
# folder = "~/Documents"   # the default
```

Puri searches that folder, and nothing else, through your desktop's own file index, GNOME's
localsearch (`localsearch` and its `tinysparql` CLI, installed with GNOME), or recoll when
localsearch isn't there; it keeps no index of its own. The index already holds the text of your
PDFs and office files, so Puri reads those too. On GNOME, installing localsearch's extractor for
the zipped office formats is highly recommended: Ubuntu only suggests it, and without it the index
holds no text of DOCX, XLSX, PPTX, ODT, ODS, ODP or EPUB files. The old DOC, XLS and PPT formats
need nothing extra.

```sh
sudo apt install localsearch-extractor-office
```

Files the index already holds stay name-only after you install it, even across a restart ([a
localsearch bug](https://gitlab.gnome.org/GNOME/localsearch/-/work_items/476)), so rebuild the index once afterwards:

```sh
localsearch reset
```

It asks before erasing the index, then localsearch reads your home folder again from scratch,
office text included. That can take a while; `localsearch status` says "Data is still being
indexed" until it's done.

Make sure the index covers the folder: GNOME Settings → Search → Search Locations. Without an index that holds the folder Puri still reads its
files by path, and logs a warning. A file the
index doesn't hold, such as a mail attachment or a search result, is converted in a networkless
container when podman or docker is installed: office files, EPUB, RTF and PDF. With neither, Puri
reads only PDFs, in-process. Puri writes
only in the folder's `Notes/`, without asking, and keeps what you ask it to remember in
`Notes/PURI.md`.

To let Puri find places and drive routes, add the table with a map tile server:

```toml
[maps]
tiles = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
```

Puri then answers "where is …", "what's near …" and "how far by car …" from OpenStreetMap's
public services: [Photon](https://photon.komoot.io) finds a place by name,
[Nominatim](https://nominatim.org) what's nearby and its opening hours, and
[FOSSGIS's OSRM](https://routing.openstreetmap.de) the drive. What you ask for leaves your machine
for them, your home address included when you ask what's near you; Puri asks for that address
once and remembers it in `Notes/PURI.md`. Under the answer it draws the places on a map, whose
tiles come from the server above; a click on a pin opens the place in GNOME Maps, or on
openstreetmap.org when Maps isn't installed. Without the table Puri has no place tools and draws
no map.

To let Puri tell the weather, add an empty table next to `[maps]`, which it needs:

```toml
[weather]
# url = "https://api.open-meteo.com"   # the default; or your own Open-Meteo server
```

Puri then answers "what's the weather like in Lisbon?", "will it rain this afternoon?" and "what
will the weather be on my trip?", the trip's dates taken from your calendar, up to about two
weeks ahead. Weather data by [Open-Meteo.com](https://open-meteo.com/), under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); each weather step in the conversation
credits it with a link. The place is found on OpenStreetMap as above, and its point, rounded to
about a kilometre, goes to Open-Meteo. Temperatures and wind come in GNOME's units, as GNOME
Weather shows them.

With Rhythmbox installed (`sudo apt install rhythmbox`), Puri plays an artist, an album, a song or
a genre from its library: "play some State Azure", or "play my favourite music" once you've told it
your favourite, which it remembers in `Notes/PURI.md`. It starts Rhythmbox when it isn't running
and shows its window; an artist or a genre plays shuffled, over and over, and replaces whatever you
had queued. Pause and skip with the media keys or GNOME's media controls. It needs Rhythmbox's
"D-Bus Media Server" plugin, on by default.

To dictate, run a transcription server of your own, whisper.cpp's, and point Puri at it. apt ships
the server but no model: pick one from [Hugging Face](https://huggingface.co/ggerganov/whisper.cpp),
`ggml-small.bin` say, or `ggml-small.en.bin` if you speak only English (an `.en` model turns other
languages into English gibberish).

```sh
sudo apt install whisper.cpp
whisper-server -m ~/.local/share/whisper/ggml-small.bin --port 8081 \
  --inference-path /v1/audio/transcriptions -l auto
```

`--port`, since 8080 is llama-server's; `-l auto`, since it assumes English otherwise. To keep it
running, put that command in a systemd user unit, `~/.config/systemd/user/whisper-server.service`,
then `systemctl --user enable --now whisper-server`:

```ini
[Service]
ExecStart=/usr/bin/whisper-server -m %h/.local/share/whisper/ggml-small.bin --port 8081 --inference-path /v1/audio/transcriptions -l auto
Restart=on-failure

[Install]
WantedBy=default.target
```

```toml
[dictation]
url = "http://127.0.0.1:8081"
# api_key = "…"          # a hosted server only
# model   = "whisper-1"  # the default; whisper-server ignores it
```

Press F5 or click the mic in the prompt, speak, and press F5 again: Puri records through PipeWire,
sends the clip to the server, and types what it heard at the cursor, for you to send with Return.
Escape drops it. On a CPU even a short clip takes some 7 s with `small`; a smaller model, more
threads (`-t`) or the GPU (`libggml0-backend-vulkan`) make it faster. Any OpenAI-style transcription
server answers the same; with a hosted one, your voice leaves your machine.

Your desktop's own dictation key types into Puri like into any other field: Myna on Ubuntu,
`ibus-speech-to-text` on Fedora.

To open Puri from a global shortcut, install it for your user:

```sh
bundle exec rake install
```

It binds **Super+Alt+Space**, which GNOME leaves free; Super+Space stays the keyboard layout
switcher. To pick another key: `rake install HOTKEY='<Super>p'`. `HOTKEY=` binds nothing.

Puri keeps running from this checkout, so a `git pull` updates it. The first shortcut press
starts Puri, which takes about a second; after that it stays running and the window opens at
once. `AUTOSTART=1` also starts it at login, so even the first press is instant. Each
`rake install` sets everything again from its own options, so a plain one turns autostart off.
`bundle exec rake uninstall` removes it all.

`bundle exec rake` runs the specs, rubocop, the type signatures and the doc checks, as CI does.

## A home server over Tailscale

The recommended setup: one machine at home runs both llama-server and whisper-server, and
[Tailscale](https://tailscale.com) carries them over HTTPS to each machine you run Puri on, under
one name on port 443, llama-server at `/llama` and whisper-server at `/whisper`.

On the server, leave both on their defaults, which listen on 127.0.0.1 only: llama-server on 8080,
whisper-server on 8081 as in the dictation section above. With them as systemd user units, let your
user linger, so they start at boot rather than at your login:

```sh
sudo loginctl enable-linger $USER
```

Install [Tailscale](https://tailscale.com/download/linux) on the server and on each machine that
runs Puri, and log them all into one tailnet. On the admin console's DNS page, turn on MagicDNS,
then HTTPS Certificates; that publishes your machine names and the tailnet's name in a public
certificate ledger, so give the server a name that says nothing. Then, on the server:

```sh
sudo tailscale serve --bg --https=443 --set-path=/llama   http://127.0.0.1:8080
sudo tailscale serve --bg --https=443 --set-path=/whisper http://127.0.0.1:8081
tailscale serve status
```

`--bg` keeps both across reboots; `status` prints the server's name, `box.tailXXXX.ts.net` here.
Tailscale drops `/llama` and `/whisper` before passing a request on, so each server sees the paths
it would see locally: `https://box.tailXXXX.ts.net/llama/health` answers what
`http://127.0.0.1:8080/health` does on the server. In Puri's config, both URLs carry their path,
and each `[[llm]]` names `server = "home"`:

```toml
[[server]]
id      = "home"
url     = "https://box.tailXXXX.ts.net/llama"
api_key = "…"   # the key llama-server reads, below

[dictation]
url = "https://box.tailXXXX.ts.net/whisper"
```

A key on llama-server is recommended. Serve answers your tailnet only, never the internet, but
that is still every device on it, the VMs running on them and every user logged into one, and
Tailscale checks no key or password itself. Make a key in a file only you can read, start
llama-server with `--api-key-file ~/.config/llama-server/api-key`, and paste the same key into
`api_key` above; `/health` still answers without it.

```sh
mkdir -p ~/.config/llama-server
(umask 077; openssl rand -hex 32 > ~/.config/llama-server/api-key)
```

llama-server's web page, `https://box.tailXXXX.ts.net/llama/`, still opens without the key too,
but nothing on it works: the scripts and stylesheet it loads want the key like the API does, a
browser can't send one, and the page stays a dead form that says JavaScript is off. That is as it
should be, since a chat UI that worked without the key would be the hole the key closes. Ubuntu's
`llama.cpp-tools` serves its UI from a directory, which upstream keeps behind the key on purpose
([llama.cpp#22038](https://github.com/ggml-org/llama.cpp/pull/22038)); only the page itself slips
through.

whisper-server takes no key yet
([whisper.cpp#4197](https://github.com/ggml-org/whisper.cpp/issues/4197)), so `[dictation]` has
none, and whoever reaches the server can transcribe on it. If others share your tailnet, a grant
in its access policy can at least keep their devices off the server's port 443.

## License

MIT
