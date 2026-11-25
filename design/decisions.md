# Decisions

Why this project is the way it is and not otherwise — FAQ-shaped: each entry is a question and
its current answer. Rewrite the answer when it changes; delete the entry when nobody asks any
more. An entry is earned by what it would cost to reverse — half the code base — or by research
the next person would otherwise redo (cited as its `R_`). Not an entry: windows → panels
"because that's the trend", this red over that red, `get_foo` over `is_foo?`, the testing library,
the CI host, a version bump — a comment at the site of the choice, or nothing; nothing about
`design/` itself. Cite by slug, `D_<slug>`, never by position; `grep '^## D_' design/decisions.md`
is the index. The first entry is the ruler: every later one trims to its length — which is how
long this file gets, so keep it short. When you have written an entry, re-read it against the one
above, open the doc comments it touches and cut what they already say, then cut the fat.

---

## D_one_process — Why one Ruby process holding both Core and the GTK4 UI, rather than a backend daemon and a UI client?

Something is resident anyway: the agents, the saved conversations and the reminder timers (the
model itself runs in llama-server). And no Ruby UI starts fast enough on the hotkey — ~1.2 s
(`R_gtk4_binding_cost`) — so the UI stays resident too, hidden rather than closed, and a second
process would save only a hidden window's memory. The costs we carry: a crash in GTK or its binding
takes a running turn and the reminder timers down with it; pikuri's threads reach GTK only through
the main loop; trying a UI change restarts pikuri too. So it is drawn as two, and Protocol is kept
as the divider meticulously: Core and Desktop share no constants, and every value crosses as JSON,
so a split swaps only the connection. Only trouble with `ruby-gtk4` reopens the split
(`D_ruby_gtk4`); Protocol then rides the D-Bus session bus, never a TCP port, not even on loopback,
which every user and program on the machine can reach, where the session bus admits only the
user's own (*Private first*). Why not separate gems to hold the line: `gtk4` comes
from apt, on the default load path whatever a gemspec says, so gems enforce nothing; a grep spec
and a GTK-free load spec do. Packwerk would do the grep statically, but apt doesn't ship it.

## D_ruby_gtk4 — Why Ruby + GTK4 for the UI, with Vala as the fallback, rather than Python, the JVM or Flutter?

Ruby lives in Core's process and shares pikuri's code (`D_one_process`). Its measured start and
memory (`R_gtk4_binding_cost`) count only against an on-demand launch, which a resident process
never does; every other option adds a second language and IPC from day one to buy back exactly
those two. GTK4 gives any binding the headless Broadway + Playwright loop. Why not Python: the
leanest binding measured, but a tier-2 language for the owner and still a binding. Why not
Flutter: a GTK3 shell from a snap, no Broadway, and its strength, animation, aimed at a window
whose size Mutter controls. Why not Swing or Compose: XWayland, blurry under fractional scaling,
and tests on Xvfb. The fallback is the binding, not the numbers: `ruby-gtk4` is far less used
than PyGObject, so if it segfaults or misbehaves (widgets losing their Ruby object, signals
misfiring, a main loop starving pikuri's threads) and the cause is the binding, Desktop alone is
rewritten in Vala as its own process, Protocol over D-Bus, Core still Ruby: `valac` is in apt,
GTK4, libadwaita and GDBus are first-class, it starts like C, and no binding layer is left to go
wrong. That is why Desktop only draws — widgets and `BackendClient`, view state only, one plain
widget class per file, Markdown rendered in Core — so a rewrite has nothing to migrate.

## D_confirmation_answers — Why does a confirmation take four answers, told apart by gesture, rather than buttons alone?

The answer's type carries the meaning, the gesture picks the type, and the model never guesses
it from text. Update is `Approved`. Cancel is `Rejected`, with no reason: the model carries on
and stops by itself, saying so, as Siri does; a retry would only ask again, since the
confirmation is the safety, not the stop, and the other half of a two-part request can still
happen. Typed text and Enter is `Redirected`: the model follows the words and proposes again,
which asks again, the way Siri's row stays non-modal (`R_siri_popup`). Escape cancels the turn,
as it does everywhere. Desktop never decides which: the buttons call `answer`, and typed text
goes through `ask`, which Core takes as the redirect while a confirmation waits. Why Enter on an
empty entry does nothing and the buttons never take focus: a stray Enter must never press a red
button. The three results and their prompt wording are pikuri's `Confirmer` (pikuri#12), not
ours. The question names everything that matters, which calendar, which note, because Siri's
unconfirmed create picked the wrong calendar.

## D_port_pikuri_web — Why host conversations through pikuri-conversations rather than our own store, or pikuri?

Puri is pikuri-web ported onto a backend that doesn't care what its frontend is, and both hosts
need the same hosting around pikuri's `Agent`: a turn per thread, mid-turn messages, cancel,
one folder per conversation, a titler, a throttle per server. Two copies drifted, so it lives
once, in the workshop's `pikuri-conversations`; pikuri itself stays the synchronous loop, since
none of it matters to one conversation alone. The folder format is the one both already wrote:
pikuri's `history.json` beside a `meta.json` envelope, where Puri adds `last_question` and
`asked_at`. Displaying a turn stays ours: blocks, Markdown, wording.

## D_own_prompts — Why write our own system prompts rather than use pikuri's as they are?

What an agent needs to be told differs per app and per model (a dense 4B and Ornith 1.5 are
different beasts), so pikuri's system prompts are examples, and Puri writes its own. The line is
the code: a prompt whose wording pikuri's code depends on stays pikuri's and is never reworded
here. That covers a tool's description, the Confirmer's answers, a cancelled call's repair text
and memory extraction. A model that needs one worded otherwise is a gap to fix upstream. pikuri's
fragments also carry instructions an agent does worse without, like `agent-loop.txt`'s tool-loop
hygiene, so our system prompt keeps every fragment our extensions bring. It drops or rewords one
only for a reason seen on the model in question.

## D_app_id — Why `io.github.mvysny.Puri` as the app id?

It names the D-Bus service, the desktop entry, the `.service` file and the command the shortcut
runs, so it is hard to change once installed. Reverse-DNS on the GitHub repo: Flathub accepts
`io.github.<user>.*`, verified through `mvysny.github.io`, and no longer accepts new
`com.github.*` ids. Why not Codeberg's `page.codeberg.*`: its Terms of Use §2.7, a July 2026
member vote, bar mostly-AI-written projects, and it goes down often.

## D_domain — Why `puri-ai.de` for the web page, rather than Puri's name alone?

"Puri" alone is a city in Odisha and a fried bread, so the domain carries a qualifier, as the
page's title does: read one way it's "Puri aide", the other "Puri AI". It is in every link to the
page, so it is hard to change once shared. Registered at Hetzner (owner, 2026-11-24), its zone on
Hetzner's DNS, the page GitHub Pages' from `docs/` through its `CNAME`. A `.de` asks no
residency: a holder abroad names an authorised recipient in Germany only when DENIC asks, and it
asks only when someone wants to serve papers in a dispute over the domain
([DENIC's terms](https://www.denic.de/en/domain-terms-and-conditions/) §3(4), read 2026-11-24 in
the English translation, which isn't binding).

## D_whole_reply — Why does Core re-send the whole `Reply` per delta, rather than only what changed?

Because the bytes are not the cost. A 10 KB reply crosses `Protocol.round_trip` in 0.05 ms,
0.1% of a core at 15 fps, and Desktop skips a part whose content is unchanged. What costs is
laying out the prose that changed (`R_label_layout_cost`), and a Protocol that sent finished
parts once wouldn't shrink it: merged prose made the open part the whole prose run so far. So
`ReplyStream` keeps the open block apart from the finished prose until the reply ends. Per
delta, one paragraph is laid out again, and a selection spans the tail once the reply is done.


## D_own_config — Why Puri's own required `config.toml`, rather than pikuri's shared one?

pikuri-tui and pikuri-web share `~/.config/pikuri/config.toml`, so each must accept every table
the other writes, and a key one shell adds must never stop the other starting. Puri wants none
of that: its own `~/.config/puri/config.toml` holds only what Puri reads, and a key it doesn't
know is an error. The loader is pikuri-web's, copied (`D_port_pikuri_web`). The file is required
and nothing has a default, the titler included: a built-in model tag would be a second, invisible
place a connection comes from, so a missing file fails at once and quotes the example to paste.

## D_titler_model — Why title on the main model with thinking off, after the first answer, rather than on a small model or beside it?

One model stays loaded, and the small instruct models pikuri-web tried failed the job: they
titled in the wrong language, or obeyed the opener instead of naming it. Thinking off makes the
main model cheap enough (`R_llama_server_titles`), so `[titler]` is a second connection to the
same server that differs only in `params`. The Titler's caps and `</think>` strip stay, since a
server can accept that parameter and ignore it. The title is asked once the first turn has ended:
beside it, on a one-slot server, the title wins the permit and the answer waits about a second
for it. The cost is a "New conversation" row until the answer is in. Why no slot is pinned:
pinning the turn lost its cached prefix.

## D_model_resident — Why keep the model loaded all day, rather than unloading it while Puri sits idle?

An unload costs little in itself: a reload takes 2–4 s on the owner's 890M, even Ornith's 22 GB
(`R_llama_server_reload`), and 3–4.5 s on a CPU alone (`R_llama_server_cpu`). What goes with it is
the prompt cache, and Puri's prefix, some 10K tokens of tools and system prompt, then prefills
again before the first token: 16 s on Qwen 3.5 4B, 32 s on Ornith, over three minutes on a CPU
alone, against under half a second cached. Every first question after an idle spell would wait
that long, so nothing unloads the model: no `--sleep-idle-seconds`, no router idling (owner,
2026-11-25). The price is the memory it holds all day; a game is the time to give it back, by
stopping the server.

## D_search_engines — Why Brave or Exa with page text, no DuckDuckGo, and no confirmation per search?

*Search, never fetch* leaves the agent the snippets, and snippets alone rarely answer. Brave and
Exa return each result's page text from their own index, which `web_read_cached` reads by handle
with no request of its own, so the agent reads whole pages and still opens no URL. DuckDuckGo
returns no page text, so it is refused rather than mixed in, where half the results would read
and half not. Without a Brave or Exa key Puri still starts, logs an error and has no web tools,
and its system prompt says so. No search asks first (owner, 2026-11-15): Siri never asks.
Revisited when Thunderbird's mail and calendar joined (owner, 2026-11-16), and kept: a query can
now quote the user's mail, but it lands in Brave's or Exa's logs, where no attacker reads it back
(egress `:tool_vouched`), and that privacy cost is accepted. `Web::Search.build(confirmer:)` is
there if it isn't any more.

## D_documents — Why does Puri write notes unasked, and search through the desktop's file index rather than an index of its own?

The documents are pikuri's secretary's (`book/secretary.md` there), with one cut undone: the
secretary confirms each write with its diff, and Puri doesn't (owner, 2026-11-17). The folder is
the gate: writes land only in `Notes/`, and each write's line names its file for the user to open.
That leaves the secretary's stored injection open, a mail planting a note a later conversation
trusts; the prompt still says to quote a stranger, never to write as the user, and a confirmation
with a readable diff waits for v2.

Search is pikuri-fileindex's `fileindex_search` over GNOME's localsearch, or recoll (owner,
2026-11-17), as Siri searches through the OS's index rather than one of its own
(`R_siri_spotlight`). It costs no embedder, no reranker, no Qdrant, no extractors' container and no
hours of first indexing, and the index has already extracted PDFs' and office files' text, under
the desktop's own sandbox. The price is keyword recall, where Spotlight's index searches by meaning
too: the index knows no synonym and no other language, so the prompt has the model list them in one
query, which a file matches by any of its words. And the index reads only what the desktop's
extractors do: Ubuntu's localsearch reads no DOCX, ODF or EPUB without
`localsearch-extractor-office`, which it only suggests, so the install guide installs it. The index
often covers the whole home, but the tools' roots are the documents folder alone (owner, 2026-11-18): the
reach of `read` and `glob`, so the folder is the gate for search too, and an index that lacks the
folder doesn't count as ready. A file elsewhere in the home is out of reach, even when the user
asks for it. The legs are private and hard untrusted, since the agent quotes mail into `Notes/`.

## D_extractors — Why convert office files and PDFs in a container where podman or docker is, and read only PDFs, in-process, where neither is?

Files outside the index reach the agent too: a mail's attachment, a page the search engine
returned, a file read by path. Their bytes are a stranger's, and pandoc, markitdown and poppler
are native parsers, so pikuri-extractors runs them in a one-shot container with no network, no
mounts (owner, 2026-11-17). Without a runtime it would fall back to the same parsers unsandboxed on
the host; we register pikuri-pdf instead: pure Ruby, so a hostile PDF only burns CPU, and an
office file stays unread, its text still in the desktop index for the documents folder
(`D_documents`). Never both: pikuri-pdf goes first in the registry and would take every PDF out of
the sandbox. The price: a docker whose daemon doesn't answer still takes the container's place, and
pikuri-extractors then falls back to the host's parsers after all; podman, picked first, has no
daemon to be down.

## D_places — Why place and route tools of Puri's own, on OpenStreetMap's public services, rather than asking GNOME Maps, or waiting for pikuri?

GNOME Maps answers no queries (`R_gnome_maps`), so Puri asks the services Maps itself asks: Photon
finds a place by name, Nominatim what's nearby by kind and its opening hours, which Photon can't,
and FOSSGIS's OSRM the drive, every hit's in one `table` request (`R_osm_services`). They are free,
keyless, and their terms are met: Puri's User-Agent with the repository as contact (owner,
2026-11-21), a request a second per host, answers cached. Not self-hosted, and no leave-by times
from the calendar (owner, 2026-11-21). Each place found is numbered, `[3]`, up through the conversation, and `route` takes a number, an
address or coordinates: a small model copies a number where it slips on ten digits of an OSM id
or four of coordinates, and each end comes back as "name (category), address", so a wrong match
shows. No `home` keyword: the model passes the address it keeps in `Notes/PURI.md`, which it asks
for when it isn't there. The numbers and each call's map are saved in `meta.json`, so both outlive
a restart.

## D_place_map — Why a map under the answer with clickable pins and nothing else, rather than Siri's buttons and rows?

Siri draws a map under a place answer, a Directions button and a row per place (`R_siri_maps`);
Puri keeps the map alone (owner, 2026-11-21). It is libshumate, GNOME Maps' own widget, from apt
like Adw (`R_shumate`). Rows would repeat the answer, which names each place by its pin's number; a
car button would have to ask the model for the route, half a minute a click
(`R_llama_server_turns`); Linux can't call. A pin opens its place's openstreetmap.org URL in GNOME
Maps, which shows the place itself, or in the browser without Maps: the human's click, so *Search,
never fetch* holds. Over the map the wheel zooms and a drag pans, as in any map, never scrolling the
answer or moving the window (owner, 2026-11-21); the price is a wheel scrolling the answer that
stops once the map reaches the pointer. Tiles load on view with no click, the same class of egress
as a search's query; OSM's terms want Puri's User-Agent, the attribution on the map, and the tile
server a setting, hence `[maps] tiles`, which turns the feature on. No photo: OSM rarely has one,
and its URL would be a stranger's to fetch.

## D_weather — Why a weather tool of Puri's own, on Open-Meteo, its credit on the tool line, rather than MET Norway, or a card?

Open-Meteo is free, keyless and asks for no User-Agent; MET Norway, as solid, wants one naming a
version Puri lacks (owner, 2026-11-22; `R_open_meteo`). It needs `[maps]`: Photon finds the place, a
street address included, which Open-Meteo's GeoNames can't, and `Places::Ends` numbers it for
`route`. Only the point leaves for Open-Meteo, rounded to 0.01°. Dates are the model's only by
choice: no dates gives a week, a line a day with its weekday, so "this weekend" is a line to read,
not sums a small model slips on; the description names the last date, today + 14, as the sixteenth
day comes back empty. Text only, no card (owner). Open-Meteo's terms want a link beside its data,
which in a desktop window CC BY alone doesn't (`R_open_meteo`); the tool line carries it, "Weather
from Open-Meteo" linked (owner), costing a `markup` on `ToolLine` rather than a widget. Units are
GNOME's `org.gnome.GWeather4` (owner), so Puri says what GNOME Weather says.

## D_music — Why play music in Rhythmbox alone, over its D-Bus, rather than in the default player, or in Puri itself?

No standard can ask "the default player" for an artist, and GNOME Music can't be handed a track
(`R_gnome_music_mpris`). Handing any player a shuffled `.m3u` works only where it plays a file it
is given, Rhythmbox imports one as a playlist instead, and localsearch misses every tag but MP3's;
Puri playing it itself would make Puri a music player, the music dying with it. Rhythmbox is the owner's player (owner, 2026-11-21), and its D-Bus does it all
(`R_rhythmbox_dbus`): the library the owner sees, in every format it reads, a play queue, MPRIS.
One `play_music(artist:, album:, song:, genre:)`, the model sorting a name into its kind (owner):
names only, never a URI, which would let a mail's "play https://…" make the player fetch. A name
matches case-folded and exactly; anything else comes back as candidates, never played. "My
favourite music" is a line of the memory, `Notes/PURI.md`, as the home address is. An artist
or a genre clears the queue (owner) and fills it with fresh shuffles cut at a day: the owner wants
it endless, the queue never loops, and a listener refilling it couldn't tell it running dry from
the user picking other music. An album plays in order once, a song alone. No confirmation: no
outbound leg, and a pause undoes it. Rhythmbox's window opens or rises, so the music shows even
with the sound off (owner). No pause or next tool: the media keys and GNOME's widget have them
(owner). It talks ruby-dbus, since Core must not load GLib.

## D_dictation — Why a mic of Puri's own, on the user's whisper-server through RubyLLM, rather than Myna's key, or pikuri?

The desktop's dictation key (Myna, `ibus-speech-to-text`) types into Puri already, but no app can
start it from a mic of its own (`R_dictation_tools`), so that mic is ours. The user owns the
server, the model and the language, whisper.cpp from apt (`R_whisper_server`); Puri records and
posts OpenAI's shape, so a bigger model or a hosted server, an explicit opt-in, changes nothing
here. One clip per press, like Myna: phrases at each pause would each pay the encoder's 7 s floor,
and a clip under 0.5 s isn't sent at all. The request goes through a RubyLLM context of Core's own
(owner, 2026-11-21): a URL and a key share nothing of a chat's transport, and pikuri has no
transcriber; should it grow one, Puri moves. `[dictation]`
names its URL, not a `[[server]]`, which is a chat server, throttled and slot-sized; without one,
Puri runs `whisper-cli` itself (`D_embedded`). The state shows in a row under the entry, not the
turn's progress bar: the pill, where dictation mostly starts, hides the transcript, and a turn's
`Activity` is what Escape and the queue read. Hiding the window drops it: the mic never records
behind a hidden window.

## D_embedded — Why can Puri run llama-server and whisper-cli itself, beside servers of the user's own, rather than only reach those?

So a new user gets answers without running a server (owner, 2026-11-25): a `[[server]]` with no
`url` is a `llama-server` Puri runs as its child, and a `[dictation]` with none runs `whisper-cli`
per clip, apt's binaries both, beside any server of the user's, which Puri knows by URL alone.
Why not apt's own `llama-server.service` (`R_llama_cpp_apt`): a system unit holds the model from
boot, for every user, several GB of an 8 GB laptop gone all day, where Puri's child holds it from
login and quitting Puri gives it back. llama-server lets any web page use the model by default (`R_llama_server_embedded`), so the child
gets a key and a free loopback port, kept for the whole run so a restart after a crash strands no
open conversation; with the port new each run, a saved conversation resumes on it by model.
`--offline` loads what the setup downloaded into the hub cache (`R_hub_cache`); Puri checks the
file first, as llama-server's own message names none. The install guide's config runs both
(owner, 2026-11-25), and the guide downloads both models with apt's `hf`, which writes that cache:
llama-server downloads only by serving, and whisper.cpp has no download at all. `hf` comes
`--no-install-recommends`, or apt adds a hundred Python packages. `-c 65536` and no `-ngl`:
llama.cpp places the model. A crash restarts it, three in a minute stop it with the log's tail,
and the next agent's boot starts it over, as for a model missing: a resident Puri must not need a
restart once the cause is gone. `setpriv --pdeathsig`, not a pidfile the next run reads: the
kernel stops the child however Puri dies. An
agent on it waits at boot for the model, since pikuri-conversations caches a failed probe for a
minute. Dictation is per clip, not a resident `whisper-server`, because the load costs 0.3–0.5 s
on the 890M and a CPU alike (`R_whisper_cli`), and nothing, no memory and no keyless port, is held
between clips. Its `language` defaults to `auto`; naming one saves a second encoder pass.

## D_one_model — Why one model on the user's own machine, rather than Siri's small model on the device and bigger ones in a cloud?

Siri runs a 3B model on the Mac and hands harder requests to bigger ones in Apple's Private Cloud
Compute (`competitors.md`). Puri runs no cloud tier (owner, 2026-11-25): *local first*, and a user
who wants a bigger model runs or rents one and gives its `url`, the conversation then leaving, as
the config says. Nor would a small model in front of a big one buy speed on one machine: Ornith
1.5 reads only some 3B of its weights a token, so Qwen 3.5 4B writes no faster, and on the 890M,
both thinking, it took 33 s a turn to Ornith's 24 s and was right less often
(`R_model_eval`). A router would add a model call before each answer. So each machine runs
the one model that suits it, Ornith where its 32 GB fit, Qwen elsewhere, and never on the NPU
(`D_no_npu`).

## D_no_npu — Why the GPU and not the NPU, though the NPU draws half the power?

Speed no longer rules it out: FastFlowLM, through Lemonade, runs Qwen 3.5 4B on the HX 370's NPU,
reading a prompt as fast as the 890M and writing 1.3–1.5× slower, at 18.5 W above idle against
35 W (`R_qwen_npu`). Four other things do (owner, 2026-11-25). It runs small models only, and an
XDNA NPU always sits beside an iGPU, which runs the same Qwen faster, or Ornith where memory
allows (`D_one_model`). The same weights did worse there: 74 % of the eval's first 14 tasks
against 90 % on llama.cpp, looping on tool calls. The saving, 0.45 J a token, comes to a tenth of
a watt-hour per thousand, and only while it answers: a loaded model idles on either chip. And
Lemonade comes as a snap and FastFlowLM runs on AMD alone, neither from apt. FastFlowLM 1.0.11
kept a `think: false` across requests, so 1.0.13 might lift the 74 %, but not the first reason.

## D_starter_model — Why start everyone on Qwen 3.5 4B with its thinking on, rather than a smaller model, or Ornith?

It did best of the small models Puri's eval ran, and only thinking: 76 % of the tasks, against
Bolt E4B's 66, Granite 4.2 3B's 55 and gpt-oss 20b's 45 (`R_model_eval`). Thinking off, the small
models often didn't act, asking "which Thursday?" rather than looking, so the config turns it on
and pays in time, 33 s a turn on the 890M; only the titler runs it off (`D_titler_model`). Its
weights and 64K cache come to 4.8 GiB, so it fits an 8 GB card, where Granite's 7.1 don't. Ornith
1.5 does far better, 92 %, and is faster too where its 32 GB fit (`D_one_model`), so the install
starts on the small one, a short download and the likeliest to run, and `docs/models.html` says
when to switch (owner, 2026-11-24). The price: Qwen passed a payment redirect's new account on as
real in most runs, which Ornith never did, so the models page tells the user to check payment
details themselves.

## D_setup — Why one `bin/setup` that installs and is the doctor, downloading the models itself, rather than the guide's dozen commands, or `hf`?

So a user who isn't a programmer gets Puri running with nothing to understand (owner,
2026-11-25): the apt line, `git clone`, `bin/setup`, the shortcut. Run again, it checks each piece
the long guide sets up and fixes what needs no sudo once the user says yes; sudo it only prints,
and it sits in the clone, read before it runs, never `curl | sh`. Ruby's stdlib until `bundle
install`, one of its fixes, then a process of its own under the bundle, which pins newer json and
net-http than the ones already loaded. The config decides the models (owner): written only when
missing, `docs/config.toml` as it is, so Qwen; switching to Ornith is an edit and a rerun, and
where Ornith fits the setup says so. It downloads them itself, resuming and checking each SHA-256
(`R_hub_cache`), where `hf` would cost an apt line, its warnings, and a restart from zero after a
stop. `bin/setup` is Rails' name for this job; `rake setup` can't run before the gems.
