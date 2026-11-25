# Research — Siri on macOS 27, the reference; GTK4 and its bindings, the stack; the map services

What the things we don't own actually do. About *them*, never us: a sentence starting "we chose"
is a `D_`. `## R_<slug> — <title>`, one claim per bullet, one provenance marker per claim —
**[docs]**, **[src]**, **[verified <date>, <version>]**, **[unverified]** (a hypothesis; a design
built on it says so). A claim is earned by its provenance, or by having cost real work to find
out. Siri is checked against macOS 27.3 on the owner's Mac (**[verified]**), or a linked review
(**[unverified]**); the stack against Ubuntu 26.04. Cite by slug, `R_<slug>`, never by position;
`grep '^## R_' design/research.md` is the index. The first entry is the ruler: every later one
trims to its length — which is how long this file gets, so keep it short. When you have written
an entry, re-read it against the one above and cut the fat — a marker already says where a claim
came from.

---

## R_siri_popup — Siri's popup on macOS 27

Screenshots:
[the bar](https://9to5mac.com/wp-content/uploads/sites/6/2026/09/Search-of-Ask-Siri-AI-Beta-macOS-27.jpg),
[the card after an answer](https://cdn.macstories.net/images/uploads/2026/09/12/cleanshot-2026-09-12-at-120741-pm2x-1789229297255-ba7389b063.png).

- Cmd-Space opens a pill, "Search or Ask" and a mic. Return guesses: "Safari" lists Safari.app
  and Settings panes and reads "– Open"; more words flip it to "– Ask Siri".
  **[verified 2026-11-11]**
- While it works the pill shrinks to an animation and a status word ("Working", "Searching");
  the typed question disappears. **[verified 2026-11-11]**
- Then it grows into a dark rounded card: `×` top-left, expand top-right, the answer (tables
  too), and at the bottom `+`, an "Ask Siri" entry and the mic, so the follow-up sits under the
  answer. **[verified 2026-11-11]**
- The first answer appears whole; follow-ups seem to stream, too fast to tell. **[unverified]**
- Up in the pill brings back the previous question, shell-style; the first question or the last
  follow-up is unchecked. **[verified 2026-11-11]**
- Voice starts only on a key or a click: the dictation key (F5) types into the pill's field; the
  mic turns the pill into a glowing orb that listens, shows no transcript, then answers.
  **[verified 2026-11-21]**
- After Escape, Cmd-Space brings an empty pill, not the conversation; the app's *Opens To* setting
  doesn't apply to the pill. **[verified 2026-11-11]**
- Escape closes the card; a click outside doesn't. The empty pill does close on a click outside.
  **[verified 2026-11-11]**
- The card drags and resizes; a drag on the answer selects text, so it drags by its empty margins
  only. **[verified 2026-11-11]**
- Expand opens the conversation in the Siri app and closes the popup; every popup conversation
  lands in the app's history too. **[verified 2026-11-11]**
- Creating an event just does it and links to Calendar; a mail opens as a draft in Mail
  ([MacMost](https://macmost.com/getting-started-with-siri-ai-in-macos-golden-gate.html)).
  **[unverified]**
- Asked for the private calendar, an unconfirmed create used the family one. **[verified 2026-11-11]**
- Changing an event asks first: grey Cancel and red Update in the transcript, white text on both.
  Cancel answers "OK. I won't make any changes to your appointment". **[verified 2026-11-11]**
- The row isn't modal: the entry stays live, Enter on it empty does nothing, Escape closes, and a
  typed correction is sent as a message, after which Siri proposes and asks again.
  **[verified 2026-11-11]**

## R_siri_app — The Siri app on macOS 27

Screenshots:
[new conversation](https://9to5mac.com/wp-content/uploads/sites/6/2026/09/Siri-AI-on-macOS-27.jpg),
[titled](https://9to5mac.com/wp-content/uploads/sites/6/2026/09/Siri-AI-beta-dedicated-Siri-app-macOS-27.jpg),
[a table](https://cdn.macstories.net/images/uploads/2026/09/12/cleanshot-2026-09-12-at-120958-pm2x-1789229423988-612f9fd04b.png),
[settings](https://cdn.macstories.net/images/uploads/2026/09/08/cleanshot-2026-09-08-at-81559-am2x-1788869773054-52a3f943c7.png).

- Two panes: the history left; the conversation right, compose top-left, search top-right, the
  popup's `+` / entry / mic row at the bottom. **[unverified]**
- History is a grid of cards or a list, picked behind Options. A card: time or date (a pin glyph
  if pinned), a bold title, preview lines from the *latest* reply, an image as a thumbnail.
  Newest first, pinned on top; the selected card outlined blue. **[unverified]**
- A title appears a second after Return as "New Conversation" and is renamed by content about
  when the answer is ready. **[verified 2026-11-11]** It comes from the question alone.
  **[unverified]**
- The user's message is a right-aligned grey bubble; the reply full-width rich text with
  headings, bullets, tables and captioned images, each paragraph ending in a source chip
  ("sunwarrior.com +2"); share and `⋯` under the last reply. **[unverified]**
- Control-click a card: Pin, Rename, Delete (confirmed); Command-click multi-selects.
  **[unverified]**
- Cmd-N, Cmd-F and Cmd-Delete work in the app only, never in the popup. **[verified 2026-11-11]**
- Settings live in System Settings → Siri → Siri App: *Opens To*, *Keep Conversations* (Forever,
  1 year, 30 days), *Preview* lines. **[unverified]**
- Asked about yesterday's conversations in a new one, Siri summarized them
  ([geeky-gadgets](https://www.geeky-gadgets.com/siri-ai-mac-test/): since 27.2).
  **[verified 2026-11-11]**

## R_siri_spotlight — Siri searches the Spotlight index, not one of its own

Sources: [Apple's Siri AI announcement](https://www.apple.com/newsroom/2026/06/apple-introduces-siri-ai-a-profoundly-more-capable-and-personal-assistant/)
(2026-06-08), [WWDC24 session 10131](https://developer.apple.com/videos/play/wwdc2024/10131/).

- Siri AI reaches the user's data through "the system orchestrator", which taps "the Spotlight
  index and App Toolbox, which work entirely on device". **[docs]**
- Its personal context reaches a third-party app only when the app integrates with Spotlight.
  **[docs]**
- Core Spotlight has a semantic index since WWDC24: a donated item's `title` and `textContent`
  "will be processed in the semantic index", which stays on the device. **[docs]**
- Apple publishes neither the embedding model nor the index format; the query side's models are
  downloaded to the device and run in the app's process. **[docs]**
- Items donated before WWDC24 reach the semantic index by re-indexing, which Spotlight schedules
  "when the device is sleeping or idle"; whether new items wait for idle too is unsaid. **[docs]**

## R_gtk4_binding_cost — Startup and memory of a GTK4 + libadwaita app, per binding

A minimal `Adw::Application` with one window holding a label, on Broadway with
`ADW_DISABLE_PORTAL=1`, timed from process start to the first frame; three runs each. GTK 4.22.4,
libadwaita 1.9.1.

- Ruby (`ruby-gtk4` 4.3.4, Ruby 3.3.8, no YJIT in the distro build): ~1.2 s, 0.8 s of it in
  `require 'gtk4'` and 0.1 s loading Adw; ~116 MB max RSS. **[verified 2026-11-11]**
- Python (`python3-gi` 3.56): ~0.2 s, ~71 MB. **[verified 2026-11-11]**
- GJS 1.88: ~71 MB; its start hit a portal timeout (`org.freedesktop.host.portal.Registry`) in a
  tty session. **[verified 2026-11-11]**
- So GTK4 and libadwaita themselves take ~60–70 MB, and Ruby's binding adds ~45 MB and ~1 s.
  **[verified 2026-11-11]**
- Broadway draws without GL; a native GL or Vulkan renderer adds Mesa's memory on top.
  **[unverified]**

## R_gvl_main_loop — Ruby threads beside the GTK main loop

A pikuri `Agent` (ruby_llm over Faraday) streaming on its own thread from a fake llama-server,
150 tokens at 50/s after a 2 s silent prefill, each delta re-posted with `GLib::Idle.add`; lag
from the server's send. `ruby-gtk4` 4.3.4, Ruby 3.3.8, on Broadway.

- An idle main loop releases the GVL while it polls (`glib2.so` calls
  `rb_thread_call_without_gvl`): token to listener p99 1.2 ms, to the `Idle.add` block 1.4 ms,
  as fast as with no GTK at all. **[verified 2026-11-11]**
- Another thread's `Idle.add` wakes that poll at once; no polling timeout is needed. Streaming
  adds no jitter to a 16 ms main-loop timer (p99 1.1 ms). **[verified 2026-11-11]**
- Ruby work on either side holds the GVL for up to one time slice, 100 ms: a 15 ms callback
  delays tokens up to 16 ms, and a 300 ms burst on the worker stalls the main loop up to
  184 ms. **[verified 2026-11-11]**
- `Thread#priority = -n` cuts that thread's slice to 100 ms >> n: at −3 the same burst stalls
  the main loop by at most 24 ms (at −2, 46 ms). **[verified 2026-11-11]**

## R_gnome_activation — Starting and raising an app from a GNOME shortcut

- On Wayland no app can grab a global key; a custom keybinding in GNOME Settings runs a command
  (`org.gnome.settings-daemon.plugins.media-keys`), or the XDG `GlobalShortcuts` portal binds
  one. **[docs]**
- GNOME's input-source switcher sits on Super+Space (`org.gnome.desktop.wm.keybindings
  switch-input-source`). **[verified 2026-11-11, GNOME on Ubuntu 26.04]**
- `gapplication launch <id>` activates the running instance over the session bus in a few
  milliseconds, or has the bus start it from a `dbus-1/services/<id>.service` file. **[docs]**
- A `.service` file written after login stays unknown to the running session bus: `gapplication
  launch` answers "The name is not activatable" until a `ReloadConfig` call on the bus, or the next
  login. A private `dbus-daemon` 1.16 picks the same file up unasked. **[verified 2026-11-16,
  GNOME on Ubuntu, owner's second machine]**
- A Puri started that way from a custom shortcut gets the graphical session's environment, and
  its window comes up with keyboard focus. **[verified 2026-11-11, GNOME on Ubuntu 26.04]**

## R_label_layout_cost — Re-laying out a wrapping `Gtk::Label` per update

A selectable label wrapping Pango markup at `:word_char`, its markup set and its height measured
at 560 px, 40 times per size, median. On Broadway, GTK 4.22.4, `ruby-gtk4` 4.3.4.

- The cost grows with the whole text, about 4 ms per KB: 2.6 ms at 0.7 KB, 15 ms at 4.2 KB and
  66 ms at 16.8 KB. **[verified 2026-11-11]**
- At 15 updates a second, a 4 KB label takes about a quarter of the main loop, and a 17 KB one
  takes all of it. **[verified 2026-11-11]**
- The layout is Pango's, so a native GL renderer should pay the same. **[unverified]**

## R_llama_server_titles — A title request beside a turn on one llama-server

The owner's llama-server b10438, Ornith 1.5 Q4_K_M, 4 slots sharing one 64k KV pool, a turn with
a 6.5k-token prefix; the title on a second connection with `chat_template_kwargs:
{enable_thinking: false}`.

- A title takes 1.3 s cold and 0.4–0.6 s warm, or 3 s with thinking on. **[verified 2026-11-11]**
- A title racing a 500-token answer slowed it from 24.0 to 22.9 tok/s, about 1 s over 21 s.
  **[verified 2026-11-11]**
- With no slot pinned, a title between two turn requests leaves the turn's prefix cached
  (`cache_n` 6665 either way); prefilling it cold takes 24–26 s. **[verified 2026-11-11]**
- Pinning the turn to a slot while the title floats loses that prefix. **[verified 2026-11-11]**
- pikuri never pins a slot: it sends no `id_slot`. **[src]**

## R_llama_server_turns — How long a turn takes on the owner's llama-server

The same server and model as `R_llama_server_titles`, Puri on Broadway or headless, Brave search;
timed by watching screenshots or logs, not instrumented.

- The first token of an answer comes 13.6–18 s after Return. **[verified 2026-11-12]**
- Escape mid-stream stops the reply within 2.5 s and keeps the partial text. **[verified
  2026-11-12]**
- A search turn thinks 10–20 s before each step; a Brave search takes ~1.3 s, a
  `web_read_cached` read nothing measurable; an answer after two searches takes 30–57 s.
  **[verified 2026-11-15]**

## R_llama_server_reload — Loading and unloading a model on llama-server, and its prompt cache

The owner's llama-server b10438 in router mode on a Radeon 890M over Vulkan, `-c 65536 -ngl 99`;
a load is `POST /models/load` until `/models` says `loaded`. The prompts are 10,108 tokens, the
size of Puri's prefix, with `max_tokens: 1`.

- A load takes 2.2–3.1 s for Qwen 3.5 4B Q4_K_M and 3.3–6.7 s for Ornith 1.5 Q4_K_M, the slower
  when less of the file is in the page cache; an unload 0.16–0.27 s. **[verified 2026-11-25]**
- A question sent to an unloaded model loads it first; a one-word answer then takes 2.3–2.6 s on
  Qwen and 3.5–4.0 s on Ornith. **[verified 2026-11-25]**
- An unload drops the prompt cache: the prefix then prefills in 16.4 s on Qwen (618 tok/s) and
  32 s on Ornith (315 tok/s), against 0.3–0.4 s cached; on a CPU alone, `R_llama_server_cpu`.
  **[verified 2026-11-25]**
- Both models' chat templates render the tool definitions before the system prompt, so a changed
  system prompt keeps the tools' part of the cache (`/apply-template`). **[verified 2026-11-25]**

## R_llama_server_cpu — Qwen 3.5 4B on a CPU alone

The owner's VM: 8 threads of the same Ryzen AI 9 HX 370, no GPU backend, llama-server b10438
`-hf ggml-org/Qwen3.5-4B-GGUF:Q4_K_M -c 65536 --no-mmproj`, its default 4 slots sharing the 64K
cache. The VM's memory ballooned from 7 to 15 GiB during the run.

- A load takes 2.9–4.5 s from the page cache. **[verified 2026-11-25]**
- A cold 10,108-token prompt, the size of Puri's prefix, prefills in 198 s (51 tok/s); cached,
  0.3 s. **[verified 2026-11-25]**
- It generates 8.6 tok/s; the same prompt on the 890M, through the router of
  `R_llama_server_reload`, 21.0–21.2 tok/s. **[verified 2026-11-25]**
- Its RSS is 6.8 GiB once loaded and 7.1 GiB after that prompt, the mapped weights included.
  **[verified 2026-11-25]**

## R_model_eval — Six models on Puri's tasks, on the Radeon 890M

`rake eval`: 35 tasks in three tiers, 3 runs each, through Puri's prompts and tools against
pikuri's demo world. llama-server b10438 over Vulkan on the HX 370's 890M, which shares
dual-channel DDR5-5600 (89.6 GB/s at most) with the CPU; `-c 65536`, each card's sampling, Q4_K_M
but gpt-oss's MXFP4. The small models ran thinking a day later, without Ornith.

| | Pass | Simple | Medium | Hard | Turn |
|---|---|---|---|---|---|
| Ornith 1.5, thinking | 92 % | 44/45 | 40/42 | 13/18 | 24.3 s |
| Ornith 1.5 | 79 % | 40/45 | 32/42 | 11/18 | 14.6 s |
| Qwen 3.5 4B, thinking | 76 % | 41/45 | 31/42 | 8/18 | 32.7 s |
| Bolt E4B, thinking | 66 % | 42/45 | 21/42 | 6/18 | 40.0 s |
| Qwen 3.5 4B | 63 % | 38/45 | 24/42 | 4/18 | 11.9 s |
| Granite 4.2 3B, thinking | 55 % | 36/45 | 22/42 | 0/18 | 47.7 s |
| gpt-oss 20b, low | 45 % | 31/45 | 16/42 | 0/18 | 11.6 s |
| Bolt E4B | 38 % | 22/45 | 15/42 | 3/18 | 6.7 s |
| Granite 4.2 3B | 11 % | 8/45 | 4/42 | 0/18 | 4.7 s |

Turns are medians. **[verified 2026-11-23/24]**

- All write 19.5–25 tok/s, Ornith too, as it reads some 3B parameters a token, so thinking is
  all added time; Qwen's 3.0 GB at 19.8 tok/s reads about 60 GB/s. **[verified 2026-11-23/24]**
- The first word: Ornith 3.3 s, thinking 9.4 s; the small models 0.1–6.6 s, thinking 22–45 s.
  **[verified 2026-11-23/24]**
- Thinking off, the small models often don't act: Granite called no tool in 89 of 105 runs,
  asking "which Thursday?", Bolt in 41, Qwen in 8; thinking, in 13, 5 and 5.
  **[verified 2026-11-23/24]**
- A look-alike sender's new IBAN for a real invoice: Ornith never passed it on. Qwen, thinking,
  repeated it in all 6 bank runs and said to pay it in 5; Bolt once wrote it into
  `Notes/PURI.md`. **[verified 2026-11-23/24]**
- Thinking, the small models ask for a missing home address, but saved it to `Notes/PURI.md` in
  1 of 9 runs, against 8 of 9 off. **[verified 2026-11-24]**
- Given only today's date, Qwen, Bolt and gpt-oss put Thursday on the wrong day.
  **[verified 2026-11-23]**
- At 64K the f16 cache takes 5.0 GiB for Granite (all 40 layers keep the whole context), 2.0 for
  Qwen (8 of 32), 1.0 for Bolt (4 of 42), beside 2.1, 2.8 and 5.8 GiB of weights.
  **[verified 2026-11-24, the GGUF headers]**
- On the owner's RTX 4060 8 GB, Qwen and Bolt write 50–60 tok/s; Granite runs out of memory.
  **[verified 2026-11-24, the owner]**
- LFM3 1.7B won't load on b10438; its card wants b11960. **[verified 2026-11-23]**
- On b10438 every other model's tool calls parse without `--jinja`. **[verified 2026-11-23]**

## R_qwen_npu — Qwen 3.5 4B on the NPU, through Lemonade and FastFlowLM

The owner's host: Lemonade's snap, its FastFlowLM 1.0.11 backend serving `qwen3.5:4b` (Q4_K, per
FastFlowLM's model card) on the HX 370's XDNA 2 NPU at `--ctx-len 65536`, against llama-server
b10438 on the 890M; one script drives both from the VM. Puri's shape is a 10.3K-token system
prompt and a tool, then a short question.

- A load takes 4.8–5.5 s and an unload 2.1–2.6 s; on the 890M, 1.9–2.5 s and 0.1–0.2 s.
  **[verified 2026-11-25]**
- A cold 10K-token prompt reads as fast as on the 890M: 17.9 s (565 tok/s) against 17.8 s
  (568 tok/s). **[verified 2026-11-25]**
- It writes 15.6 tok/s after a short prompt and 13.0 after the 10K one; the 890M, 20.8 and 19.3.
  **[verified 2026-11-25]**
- Its prefix cache saves the state at the end of the system prompt and tools, and at the end of
  the prompt, so an identical repeat resumes only from the first. **[docs]** A 10K-token user
  message sent twice took 17.9 s both times. **[verified 2026-11-25]**
- In Puri's shape the first question's first token comes after 20.4 s (the 890M: 19.9 s) and the
  next questions' after 1.4 s (0.6 s), 10,270 tokens cached. **[verified 2026-11-25]**
- On battery, btop's power reading is 9 W idle with the screen on, 27.5 W while the NPU reads or
  writes (80–100 % busy), and 43.5–44 W while the 890M does (100 % busy, fans on): 18.5 W above
  idle against 35 W. Under that load the NPU wrote 14.8 tok/s and read 547 tok/s, the 890M 20.4
  and 490, slower than it reads cool. So a token written costs 1.25 J against 1.7 J, and a cold
  10K-token prompt about 340 J against 720 J. **[verified 2026-11-25, the owner reading btop]**
- Thinking is on unless a request says otherwise, switched by a top-level `think` or by
  `chat_template_kwargs.enable_thinking`; in 1.0.11 a `think: false` sticks for later requests
  from any client, and `enable_thinking: true` doesn't undo it, `think: true` does.
  **[verified 2026-11-25]** 1.0.13's notes say settings no longer leak between requests. **[docs]**
- Puri's eval with thinking on, the router preset's sampling sent whole, stopped after its first
  14 tasks: 31 of 42 runs passed (74 %), where llama.cpp on the 890M passed 38 of 42 (90 %) the day
  before. The gap is tool calls in a loop: `drive-tampere` failed all three runs, one calling
  `place_search` over 30 times until the 600 s limit, where the 890M passed all three; 4 runs
  timed out, none on the 890M. **[verified 2026-11-25]**

## R_gnome_maps — GNOME Maps 49.3 answers no queries

Ubuntu 26.04's package, its JavaScript read out of the GResource.

- No GNOME Shell search provider; on the session bus only GApplication actions: `search(s)`,
  `osm-account-setup`, `shortcuts`, `quit`. `search` shows results in its window and returns
  nothing. **[verified 2026-11-21]**
- `geo:lat,lon` opens a nameless pin; `maps:q=…` or `--search` a search. No URI opens a route.
  **[src]**
- Handed an `https://www.openstreetmap.org/node/<id>` URL (or `way`, `relation`) as a file, it
  fetches the object from Overpass and shows it as a place, name and details; one with
  `mlat`/`mlon` and `zoom` gives a point. **[src]** Its desktop file runs `gapplication launch
  org.gnome.Maps %U`. **[verified 2026-11-21]**
- It geocodes through GraphHopper with a key in its source, finds categories through Overpass,
  routes with GraphHopper and Transitous, and draws `tile.openstreetmap.org`. **[src]**
- Its position comes from GeoClue **[src]**; Ubuntu's `geoclue.conf` sets no Wi-Fi geolocation
  URL. **[verified 2026-11-21]**

## R_osm_services — OpenStreetMap's free geocoders and routers

Tried from Vantaa on 2026-11-21; the specs' fixtures are these answers.

- Photon (`photon.komoot.io`): no key, no stated limit, throttles "extensive usage". **[docs]** It
  needs a bias point: "Prisma" alone finds Bolivia's; near Jumbo's `lat`/`lon`, Jumbo's. A name plus
  address finds the place itself; an address alone whichever business ranks first there.
  **[verified]**
- Photon finds no category near a point ("cafe" matches names 5–15 km off; "coffee" US counties),
  and returns no hours, phone or website, though OSM has them. **[verified]**
- Nominatim: a request a second, an identifying User-Agent, answers cached. **[docs]** Its
  structured `amenity=` in a bounded `viewbox` finds a kind of place, whatever its key (`cafe`,
  `supermarket`, `hotel`, `charging_station`), unsorted, with `extratags` hours; `lookup` by OSM id
  adds hours and website to many at once. **[verified]**
- Overpass `around:` finds the same, but calls an app relying on its public instance problematic.
  **[docs]**
- FOSSGIS's OSRM (`routing.openstreetmap.de`; car, bike, foot): a request a second, a User-Agent,
  non-commercial, a "fix the map" link shown. **[docs]** Its `table` gives distances and times to
  many points in one request; 6.3 km takes 8.8 min, where FOSSGIS's Valhalla says 12.7.
  **[verified]**
- Transitous (public transport): open-source, non-commercial apps, a User-Agent with name, version
  and contact. GraphHopper's free plan: 500 credits a day, non-commercial. **[docs]** None of these
  is in apt. **[verified]**
- openstreetmap.org in a browser shows `?mlat=…&mlon=…&zoom=17` as a marker, and `/node/<id>` as
  the object's page: highlighted on the map, its raw tags beside it. **[verified]**

## R_open_meteo — Open-Meteo's forecast API

Tried from Vantaa on 2026-11-22; the specs' fixture is that answer.

- One GET, `api.open-meteo.com/v1/forecast`, `current`, `daily` and `hourly` variables by name,
  `timezone=auto` for the place's own days; `forecast_days` 0–16, `past_days` 0–92. The answer is
  columns, one array per variable. No key, no User-Agent asked; under 10,000 calls a day,
  non-commercial; server AGPLv3, self-hostable. **[docs]**
- Data CC BY 4.0, plus its own terms: "You must include a link next to any location Open-Meteo data
  are displayed". **[docs]** CC BY's legal code asks credit only when you share "to the public".
  **[docs]**
- The sixteenth day comes back all nulls, its first hours aside: the models stop. **[verified]**
- A bad request is HTTP 400 `{"error": true, "reason": "…"}`, readable: "start_date is out of
  allowed range from 2026-08-21 to 2026-12-07". **[verified]**
- Its geocoder is GeoNames: towns and postcodes, no street addresses. **[docs]**

## R_shumate — libshumate 1.6~beta from Ruby, and OSM's tiles

OSM's [tile usage policy](https://operations.osmfoundation.org/policies/tiles/); the rest on
Broadway, Ruby-GNOME 4.3.4.

- `gir1.2-shumate-1.0` loads through GObject Introspection, as Adw does; `SimpleMap` draws zoom
  buttons, a scale and the source's license line, a `MarkerLayer` takes any widget, a `Button`'s
  click works, and a `PathLayer` draws a line. **[verified 2026-11-21]**
- `RasterRenderer.new(template)` takes a URL template, and fractional zoom levels. A `file://`
  template loads nothing; an HTTP server on 127.0.0.1 does. **[verified 2026-11-21]**
- No call fits the view to a set of points: `center_on` and a zoom level only. **[verified
  2026-11-21]**
- The inner `Map` zooms on the wheel through an `EventControllerScroll` and keeps the event from an
  enclosing `ScrolledWindow`; set to propagation phase none, the wheel reaches it. **[verified
  2026-11-21]**
- Its pan, a `GestureDrag`, never claims its sequence: inside a `WindowHandle`, a drag past the drag
  threshold moves the window. Claimed in `drag-update` past that threshold, the drag stays the map's
  and a click still reaches a marker's `Button`. **[verified 2026-11-21]**
- The tile downloader sends `libshumate/1.6.beta` whatever `Shumate.set_user_agent` says: it
  hard-codes the string, and main still does (2026-11-12). **[src]** Tiles reached a local server
  so; `tile.openstreetmap.org` serves that User-Agent. **[verified 2026-11-21]**
- OSM allows a map a human views; an app sends its own User-Agent, a library's default may be
  blocked; caching headers honoured, no prefetch, the attribution visible, the tile URL not
  hard-coded. **[docs]**

## R_siri_maps — Siri's places on macOS 27

On the owner's Mac, macOS 27.2.1.

- "Where is Vantaan Musiikki?" answers one street address, wrong: Kielotie 4, where OSM has
  Peltolantie 2. Under it a map, then "Call" and a car glyph with "Directions". **[verified
  2026-11-21]**
- Directions opens Apple Maps on the route from "My Location", behind the Siri card, which stays
  open. **[verified 2026-11-21]**
- "Coffee near me" asks nothing and uses the Mac's location: a map of two cafés, then a
  full-width pill per place — name, opening hours, a photo — with a car glyph opening directions.
  **[verified 2026-11-21]**

## R_gnome_music_mpris — MPRIS can't search, and GNOME Music can't be handed a track

- MPRIS, what every player and GNOME Shell's media widget speak, is a remote control: play, pause,
  next, `Shuffle`, `Metadata`, `OpenUri` of one URI, and an optional `Playlists` interface that
  starts one of the player's own playlists. No search, and no desktop standard says "play artist
  X". **[docs]**
- GNOME Music's `OpenUri` is `"""Not implemented."""` and `pass`, and its desktop file declares no
  `MimeType=`; its only levers are `ActivatePlaylist` on its own playlists and a writable
  `Shuffle`. **[src]** (`gnomemusic/mpris.py`, master, 2026-11-21)
- Ubuntu's localsearch reads MP3 tags alone without `localsearch-extractor-ffmpeg`; 26.04 installs
  only `libextract-mp3.so`. **[verified 2026-11-21]**

## R_rhythmbox_dbus — Rhythmbox 3.4.9 over D-Bus

Its source on GNOME's master, 2026-11-21; run headless on Ubuntu 26.04's 3.4.9-3ubuntu3.

- The `dbus-media-server` plugin, on by default and shipped with MPRIS in `rhythmbox-plugins`, which
  `rhythmbox` only recommends, owns `org.gnome.UPnP.MediaServer2.Rhythmbox`;
  its `…/Library` (the local library alone, no radio or podcasts) holds `artist`, `album`,
  `genre` and `all` containers, each with `ListContainers` and `ListItems`; no search,
  `SearchObjects` answering "search not supported". **[src]**
- A child's path keeps a name's alphanumerics and writes every other byte `_XX`; a lowercased
  path lists nothing, without an error. An album container is one name: two artists' "Greatest
  Hits" are one album. `ListContainers 0 0` gave all 826 artists of the owner's library at once.
  **[verified]**
- An item carries `DisplayName` (its title), `URLs` (one percent-encoded `file://` URI), `Artist`,
  `Album`, `Genre`, `Duration` in seconds and `TrackNumber`. **[src]** **[verified]**
- Any call to `org.gnome.Rhythmbox3` starts it by D-Bus activation, its window open; the media
  server and MPRIS names follow within a second. Its library is empty until the database loads,
  then whole: ~0.3 s after the media server's name, ~10 s on a first import. `…/all`'s
  `ItemCount` property stays 0; `…/Library`'s `ListContainers` counts live. **[verified]**
- A first import needs `org.gnome.rhythmbox.rhythmdb`'s `monitor-library`, upstream `false`: off,
  Rhythmbox never scans its `locations`. Ubuntu's desktop turns it on (`ubuntu-settings`'
  `10_ubuntu-settings.gschema.override`); a bare `ubuntu:26.04` leaves it off. On, the scan
  starts 10 s after the database loads. **[src]** **[verified]**
- `org.gnome.Rhythmbox3.PlayQueue`'s `ClearQueue` and `AddToQueue(s uri)` are what
  `rhythmbox-client --clear-queue --enqueue` calls. **[src]** Entries leave the queue as they
  play, so it never loops, whatever MPRIS `LoopStatus`. **[verified]**
- MPRIS `OpenUri` of a library track plays it at once, then the queue overrides the play order;
  after the last queued track the library carries on. MPRIS `Play` from stopped plays the
  sidebar's selected source instead. **[src]** **[verified]**
- `OpenUri` of a local `.m3u` imports it as a static playlist and plays nothing; each import adds
  another, named after the file, and no D-Bus call deletes one. **[src]** **[verified]**
- On Broadway with no sound server, `PlaybackStatus` reads `Playing`. The bus daemon hands its own
  environment to what it activates: a scratch `HOME` set inside `dbus-run-session` came too late,
  and the real dconf and `~/.cache/rhythmbox` got written. Through ALSA's PipeWire plugin it
  deadlocked on a track change now and then; with GStreamer's real sinks ranked `NONE`,
  `autoaudiosink` falls back to a fake one. **[verified]**

## R_dictation_tools — Linux dictation, November 2026

- Canonical's Myna, a technology preview since 12 Oct 2026, from `ppa:canonical-desktop-team/myna`
  and snaps: Ubuntu 24.04, 26.04 and 26.10, amd64, GNOME on Wayland only, in no archive. It types
  through IBus, a toggle that transcribes after the second press; Parakeet, Whisper or FunASR,
  local. No D-Bus API. **[docs]**
  ([blog](https://ubuntu.com/blog/myna-speech-to-text-technology-preview-available),
  [Discourse](https://discourse.ubuntu.com/t/introducing-myna-speech-to-text-for-ubuntu-desktop/84251),
  [OMG! Ubuntu](https://omgubuntu.co.uk/2026/08/testing-ubuntu-ai-voice-dictation))
- GNOME has only a [proposal](https://discourse.gnome.org/t/proposal-desktop-wide-offline-speech-to-text-dictation-support/35858)
  (June 2026) for a dictation service with a D-Bus API; no maintainer decision. **[docs]**
- Fedora packages [`ibus-speech-to-text`](https://github.com/PhilippeRo/IBus-Speech-To-Text)
  (Vosk); Ubuntu's archive has no IBus speech engine. **[docs]**

## R_whisper_server — whisper.cpp's `whisper-server` as a transcription server

Ubuntu 26.04's whisper.cpp 1.8.3, `ggml-small.en.bin` on 4 CPU threads of a Ryzen 7 PRO 4750U.

- 26.04's universe ships `whisper.cpp` (`whisper-server`, `whisper-cli`, `whisper-stream`) and
  ggml's Vulkan backend, but no model: the ggml weights come from Hugging Face. **[verified 2026-11-21]**
- Defaults: `--port 8080`, llama-server's too; `-l en`, not `auto`; `-t 4`. `--inference-path`
  replaces `/inference`, which then answers 404; an `.en` model ignores `-l`. **[verified]**
- At `--inference-path /v1/audio/transcriptions` it answers OpenAI's multipart `file` + `model`
  with `{"text": …}`, ignoring `model` and a `Bearer` key. **[verified]**
- A clip costs 7–8 s however short, silence included, the encoder always running a 30 s window:
  2 s → 7.3 s, 10 s → 14.4 s, 53 s → 17.5–20 s. **[verified]**
- The text starts with a space and breaks per segment. Silence, faint noise and a 0.3 s clip
  answer `" [BLANK_AUDIO]\n"`; with `suppress_nst=true`, Whisper's inventions `" you"` and
  `" Thank you."` instead. **[verified]** Whether a real room, keyboard and fan, still answers
  `[BLANK_AUDIO]` or an invention is untried. **[unverified]**
- Errors come as HTTP 200 with `{"error": …}`, which RubyLLM 2.2.2 reads as `text: nil` without
  raising. **[verified]**
- `temperature_inc=0` sent a clip cut mid-sentence into a 21 s repetition loop; `no_timestamps=true`
  was no faster and lost the punctuation. **[verified]**
- `pw-record --raw --rate 16000 --channels 1 --format s16 -` streams the PCM to stdout as it
  records, 32 KB/s. **[verified 2026-11-21]**
- It honours a request's `language` field over its `-l`, `auto` included. **[verified 2026-11-25, 1.9.2]**

## R_whisper_cli — whisper.cpp's `whisper-cli`, once per clip

whisper.cpp 1.9.2, `ggml-small.bin`, a 3 s clip, `-l en`. **[verified 2026-11-25]**

- The owner's VM, 4 of 8 vCPUs of the HX 370, no GPU: 4.6–4.8 s a clip, 0.2 s of it the load
  from the page cache, 5.2 s cold; `whisper-server` 4.1 s a request, holding 680 MB idle.
- The owner's host, the 890M through Vulkan: 0.63 s a clip, 1.1 s the first; `whisper-server`
  0.31 s, 0.48 s the first.
- It loads llama.cpp's `libggml0` backends, so `libggml0-backend-vulkan` puts it on the GPU.
- `-l auto` runs the encoder twice, once to detect the language: 9.9–11.5 s for that clip on the
  CPU. Both binaries default to `-l en`.
- `-f - -otxt -np -nt` reads the WAV from stdin and prints only the text, a segment a line,
  writing no file; `-f -` without `-otxt` prints nothing.
- `-np` hides the reason for a failure too: a missing model says only "error: failed to
  initialize whisper context", exit 3.

## R_llama_cpp_apt — What Ubuntu 26.04's llama.cpp packages ship

`llama.cpp-tools` 8681+dfsg-1 and `libggml0` 0.9.11-1, read with `apt-cache` and `dpkg-deb`,
nothing installed or run. **[verified 2026-11-23]**

- `llama.cpp-tools` ships a system service, `llama-server.service`, off until enabled: it runs as
  `_llama-server`, caches in `/var/cache/llama-server`, and reads `/etc/default/llama-server`,
  which documents `LLAMA_ARG_HF_REPO` (one model, from Hugging Face), `LLAMA_ARG_CTX_SIZE` and
  `LLAMA_API_KEY`.
- The `llama.cpp` metapackage also recommends `llama.cpp-tools-extra` and `python3-gguf`.
- The GPU backends are packages of their own, which `libggml0` only suggests: BLAS, CUDA, HIP and
  Vulkan. The archive has `libggml0-backend-vulkan` (55 MB installed; it suggests
  `mesa-vulkan-drivers` and `nvidia-vulkan-icd`) and `-hip`, but no `-cuda`.

## R_llama_server_embedded — `llama-server` as another program's child

Ubuntu 26.04's llama.cpp b10438. **[verified 2026-11-25]**

- Its default CORS approves every origin, credentials included, and it takes no key unless given
  one, so a web page may use the model as far as the browser reaches `localhost`. `/slots` shows
  no prompt text.
- `--cors-origins localhost` stops a page reading an answer, but a request needing no preflight
  still runs; only a key stops that.
- `LLAMA_API_KEY` sets the key off the command line, which `/proc` shows every user: `/props`
  answers 401 without it, 200 with it.
- `--offline` on an empty cache exits at once, trying no download, and says only "exactly one out
  metadata, path_model, and file must be defined".
- `--fit`, on by default, adjusts only the arguments left unset (`llama-server --help`). **[docs]**
- `setpriv --pdeathsig TERM` (util-linux) has the kernel signal the child when the thread that
  spawned it ends, the parent's `SIGKILL` included.
- Qwen 3.5 4B Q4_K_M answers `/health` some 7 s after the spawn on the VM's CPU.

## R_hub_cache — Hugging Face's hub cache, as llama.cpp's `-hf` and apt's `hf` use it

b10438, `HF_ENDPOINT` pointed at a dead port; `python3-huggingface-hub` 1.23.0 run from its
unpacked `.deb`s. **[verified 2026-11-25]**

- `-hf` reads and writes `~/.cache/huggingface/hub` in `huggingface_hub`'s layout:
  `models--<org>--<repo>/blobs/<sha256>`, `snapshots/<commit>/<file>` a link to its blob, and
  `refs/main` holding the commit.
- `LLAMA_CACHE` wins over `HF_HUB_CACHE`; `HF_HOME` and `XDG_CACHE_HOME` each move it too.
- Offline, it finds the file through `refs/main` alone: a hand-built cache whose `refs/main`
  named a made-up commit loaded.
- Hugging Face's `/api/models/<repo>?blobs=true` lists the commit (`sha`) and each file's
  SHA-256 (`lfs.sha256`), what a hand-built cache is named by.
- `hf download <repo> <file>` writes the same layout: its `--dry-run` counts a file `-hf` fetched
  as present, and Puri's `HubCache` finds one it fetched.
- Without the `hf_xet` package it fetches over plain HTTP, saying so and suggesting
  `pip install hf_xet`, and it warns that the requests are unauthenticated.
- Once a day it asks PyPI for a newer version and suggests `hf update`, unless
  `HF_HUB_DISABLE_UPDATE_CHECK` is set. **[src]**
- apt installs it with some 110 packages, matplotlib, scipy and pandas among them; with
  `--no-install-recommends`, 10. (`apt-get -s`)
- `resolve/<commit>/<file>` answers 302 to a CDN (`us.aws.cdn.hf.co/xet-bridge-us/…`), with
  `X-Repo-Commit`, and `X-Linked-Etag` and `X-Linked-Size` for the file; the CDN answers a
  `Range` with 206. A blob `Puri::Setup::HubDownload` wrote, stopped at 40 MB and resumed,
  loaded in `llama-server -hf ggml-org/SmolLM2-135M-GGUF:Q4_K_M --offline`. **[verified
  2026-11-25]**
- `hf download` fetches into `blobs/<sha256>.<8 hex>.incomplete`, a name of its own per
  process, deleted when the download fails, so a stopped one starts over. It holds
  `.locks/models--<org>--<repo>/<sha256>.lock` meanwhile, `flock`ed through `filelock`. **[src,
  `file_download.py` and `utils/_fixes.py` of the 1.23.0 `.deb`]**

## R_llama_list_devices — What `llama-server --list-devices` prints

b10438 on the owner's VM, no GPU backend installed. **[verified 2026-11-25]**

- "Available devices:", then one line per device, `  %s: %s (%zu MiB, %zu MiB free)` (the
  format string in `libllama-common.so`): its name, its description, its memory in all and
  free. `Vulkan0: AMD Radeon 890M Graphics (RADV …) (… MiB, … MiB free)` is the shape.
- With no device but the CPU, "  (none)": the CPU is never listed.
- Unverified: what an integrated GPU's total reads, the firmware's share or what the kernel
  lends it besides, and whether Mesa's lavapipe is listed as a device.

## R_localsearch_cli — localsearch 3.11's command line, as the setup asks it

localsearch 3.11.2 on the owner's VM. **[verified 2026-11-25]**

- `localsearch info FILE` exits 0 for an indexed file, printing its properties, and 1 for one it
  doesn't hold, with "No metadata available for that URI".
- `localsearch status` ends "Indexer is idle" once it has read everything; its words follow the
  locale, so `LC_ALL=C.UTF-8` reads them in English.
- `org.freedesktop.Tracker3.Miner.Files index-recursive-directories` holds the Search Locations:
  paths, `$HOME`, and `&DOCUMENTS`-style names for the desktop's own folders.
- `localsearch reset --file FILE` erases what the index holds of FILE, recursively, and asks for
  it to be read again at once; plain `reset` erases the whole index. **[docs, its man page]**
  Unverified: that the folder's office files then come back with their text, once
  `localsearch-extractor-office` is installed.

## R_tailscale_serve — Tailscale Serve in front of llama-server and whisper-server

Tailscale's `main` and its docs (kb 1242, 1312, 1153), read 2026-11-22; the owner runs both
servers behind it, from the snap.

- On Ubuntu it comes as the `tailscale` snap, published by Canonical (verified publisher) and
  strictly confined: 1.102.3 on `latest/stable`. Its listed limits are `tailscale ssh`, `tailscale
  cert` to paths outside the snap's, `tailscale update` and `tailscale drive share`. **[docs]**
  (`snap info tailscale`, 2026-11-24)
- `tailscale serve` works from the snap, in front of llama-server and whisper-server.
  **[verified 2026-11-24, on the owner's machine]**

- A proxy mount drops its path before forwarding: `/llama/v1/x` reaches `http://127.0.0.1:8080`
  as `/v1/x`. The longest mount wins, and a bare `/llama` is proxied, never redirected.
  **[src]** (`ipnlocal/serve.go`, tailscale#6571)
- Neither the proxy nor its server sets a timeout, so a long turn ends only when one side closes.
  **[src]**
- No password, basic auth or bearer check of its own: the tailnet's access policy gates it, per
  port, and it hands the backend `Tailscale-User-Login` and friends, none for a tagged device.
  **[docs]**
- HTTPS needs MagicDNS and HTTPS Certificates on, which publish the machine names and the
  tailnet's name to the public CT ledger; `--bg` survives a reboot. **[docs]**
- pikuri keeps a server URL's path: `…/llama` dials `…/llama/v1/…` and probes `…/llama/props`.
  **[src]**
- llama-server's `--api-prefix` and whisper-server's `--request-path` serve under a path of their
  own, which a proxy that strips the path doesn't need. **[src]**
- With `--api-key-file`, llama-server still answers `/health` and its web page without the key,
  but the page's scripts and stylesheet want it, so the page stays a dead form. Ubuntu's
  `llama.cpp-tools` serves the UI from a directory, which upstream keeps behind the key on purpose
  ([llama.cpp#22038](https://github.com/ggml-org/llama.cpp/pull/22038)). **[src]**
