# Siri parity: what Siri on macOS 27.2 does that Puri doesn't

Goal: the list of what's left for feature parity with Siri on macOS 27.2, Reminders aside
(`Q_reminders_backend` in `trifecta-and-tools.md`). Brainstormed 2026-11-22 from Apple's Mac
User Guide and three reviews (sources at the end); none of it tried on the owner's Mac yet, so
every Siri claim is [docs] or [unverified]. Each item graduates on its own: picked up, it moves
into an idea file of its own or straight into code, and its section here is deleted.

**At parity, roughly:** web answers, notes and documents, memory, mail read and draft, calendar
read and create, contacts, places and car routes, playing music, dictation, the calculator.

## Cheap: Siri does it, Linux has it, no promise at stake

### Weather

"What's the weather like in San Francisco?" [docs]; Siri passed it in the 27.2 test of 62
tasks [unverified]. Today Puri can only web-search it.

- Open-Meteo (free, no key) or MET Norway, which GNOME Weather reads through libgweather
  (its `met-no` provider, in apt's libgweather-4). The place leaves like a Photon query does,
  the home address from `Notes/PURI.md` included.
- A small card under the answer, as the map is (`D_place_map`)?
- `Q_weather_home`: a tool goes upstream, to pikuri-workshop, unless it's another `D_places`
  exception.
- `Q_weather_service`: Open-Meteo or MET Norway? MET's terms want an identifying User-Agent,
  the same snag as Transitous (`routes-by-bike-foot-and-bus.md`): Puri has no version yet.

### Time zones and unit conversions

"What time is it in London?", "How many centimetres are in an inch?", "What's 18 per cent of
225?" [docs]. pikuri's calculator does the last and neither of the others; tzdata is local, so
both are offline. Upstream, beside `Pikuri::Tool::CALCULATOR`.

### Open an app, a settings panel, a document

"Open Photos.", "Open System Information." [docs]; the pill's Return already guesses "Safari –
Open" before any model runs (`R_siri_popup`). Two halves:

- **The pill, without the model:** match the typed text against `Gio::AppInfo.all` and GNOME
  Settings' panels (`gnome-control-center <panel>`) as you type; Return launches. This is the
  half of Cmd-Space that is Spotlight, and the one people use most.
- **An `open` tool:** a file the agent found under `[documents]`, in its default app.
- `Q_open_gate`: a local file isn't a URL, but an HTML file opens in the browser, which loads
  whatever it links. Refuse browser handlers, or confirm each open?
- `Q_pill_matching`: is the app list Core's (it orders and words things) with Desktop only
  drawing rows, as `D_ruby_gtk4` says?

### Timers and alarms

"Set the timer for 3 minutes.", "Set an alarm for 7 am." [docs]. Puri stays resident, so a
timer is `Gio::Notification` plus a sound when it fires.

- The same "fire at due time" machinery as the own-store option of `Q_reminders_backend`, so a
  timer is the cheap probe of it before Reminders.
- Dies with Puri: a reason to revisit `autostart-at-login.md`.
- GNOME Clocks (installed, 50.0) has timers and alarms; whether anything outside it can set one
  is unchecked. [unverified]
- `Q_timer_ui`: a running timer shown where? Only the notification, or a line in the
  conversation that counts down?

### Browser history

27.2 lets Siri draw on Safari history [unverified]. Firefox keeps it in `places.sqlite`, locked
while it runs; copy it as pikuri-thunderbird's `DatabaseSnapshot` copies Thunderbird's.

- Titles and URLs only, never fetched; a URL shows as text or as a link the human clicks
  (`Q_link_rendering` in `trifecta-and-tools.md`).
- Private, and untrusted: a page's title is the attacker's.
- Snap or apt Firefox, found on its own like the Thunderbird profile.
- Upstream: a pikuri-firefox beside pikuri-thunderbird.

### Changing a calendar event

Siri changes an event after a grey Cancel and a red Update (`R_siri_popup`). `exe/puri --dummy`
already walks that row (`reschedule`), but pikuri-thunderbird has only `calendar_create`.

- `Q_calendar_update`: how to change a Thunderbird event? Writing its sqlite under a running
  Thunderbird is out. An ICS with the same `UID` and a higher `SEQUENCE` through the import
  wizard may update or may duplicate. [unverified] Research in pikuri-thunderbird.

## Medium: what's on the screen

### Ask about the selection, a file, a window

Siri's headline in 27: Control-click → Ask Siri, Shift-Cmd-Space for the active window,
Shift-Cmd-6 for an area [docs]. Apple's example: select two reports in Finder, "Which quarterly
report grew faster?" [docs]. Reviews find it works better from the popup than from the app
[unverified].

- **Selected text.** The popup takes the focus when it opens, so it can read the primary
  selection then and offer it as a removable chip: "with your selection". [unverified on Mutter]
- **Files.** A Nautilus script, `~/.local/share/nautilus/scripts/Ask Puri`, set up by
  `rake install`, hands the selected paths to the resident Puri over D-Bus; the extractors read
  them (`D_extractors`). Files outside `[documents]`: the user picked them, so that's consent?
- **A window or an area.** The xdg-desktop-portal Screenshot asks the user what to capture. It
  needs a model that takes images; Puri sends none today (`Config::Llm#transport` skips
  pikuri's `with_detected_modalities`). Waits for `local-model.md`'s v2.
- `Q_selection_chip`: always offer the selection, or only when the question says "this"?

### Attachments

The Siri app's `+` adds photos or files [docs]. A `+` or a file dropped on the conversation,
read through the same extractors as the Nautilus script; images wait for a model that takes
them.

### Copy a reply out

"Proofread this.", "Condense these meeting notes to give me key points." [docs]. The model
already writes; what's missing is getting the text out of Puri. A **Copy** button on a reply,
and on a code block or a table. Siri writes back into the app; on Wayland that needs the
RemoteDesktop portal, not worth it.

### Past conversations

27.2's headline: "ask Siri about something it told you before" [docs]; asked, it summarized
yesterday's conversations (`R_siri_app`). Already the Memory section of `trifecta-and-tools.md`:
pikuri-rag over the saved conversations, later.

- `Q_conversation_search`: or a plain `conversation_search` over titles and text, in
  pikuri-conversations, before any vectors?

### Music beyond play

"What's playing?", "Favourite this song.", "Add this song to my Workout playlist.", "Skip ahead
three minutes.", "Play the latest episode of … podcast." [docs]. Puri only plays; the rest is
`Q_music_control` in `music-beyond-rhythmbox.md`, left to the media keys for now. Podcasts:
Rhythmbox has them.

## Bigger, or the owner's call

### System toggles

"Turn on VoiceOver.", "Increase my screen's brightness." [docs]; "adjusting system settings"
passed the 27.2 test [unverified]. `trifecta-and-tools.md` decided: no `bash`, the machine is
`pikuri-tui-computer`'s.

- But a closed set of typed, reversible toggles isn't `bash`: dark mode, Do Not Disturb and text
  size are gsettings keys; brightness gnome-settings-daemon's D-Bus; volume `wpctl`; Wi-Fi
  NetworkManager; the screen reader Orca's gsettings key. No passive-command detector needed.
- An injected mail at worst switches Wi-Fi off; that one perhaps asks.
- Home: pikuri-os in the workshop, which already "operates the host OS".
- `Q_toggles`: reopen the hand-off for a closed set like this? Owner's call.

### Photos

"Find photos from my trip to Lisbon", "Show me the photos of the cat with the yellow collar
within the last month." [docs, unverified].

- Date and place: localsearch's image metadata, with a reverse geocode for "Lisbon". How much
  EXIF localsearch keeps is unchecked. [unverified]
- What's *in* the photo needs image embeddings over the whole library: big, and the model that
  makes them.
- Either way the answer shows local thumbnails, a new kind of reply part; never a remote image
  (`trifecta-and-tools.md`, "Links in the reply").
- `Q_photos_store`: localsearch alone, or Shotwell's database where Shotwell is used?

### OS help

"How do I take a screenshot?" [docs]. GNOME's help is offline: 327 Mallard pages in
`/usr/share/help/C/gnome-help`, more beside it. Answerable without a web search; pikuri-os's.

### Spoken answers

Siri's setting: responses Spoken or Silent [docs]; the mic's orb answers aloud.
speech-dispatcher is installed and espeak-ng is in apt, both robotic; apt's `piper` is the mouse
configurator, not the Piper voice, so a good voice waits on the owner. A wake word: no.

## Not pursued

- **Messages, FaceTime, Tapbacks:** Linux has no system messenger.
- **Smart home:** Home Assistant's REST API, only if the owner runs one.
- **Suggestions before asking** (an invitation in Mail → add to Calendar [docs]): another
  product.
- **Image Search** on the web [docs]: uploads a local image.
- **Renaming, moving, compressing files:** Siri fails them too [unverified], and Puri writes
  only in `Notes/` (`D_documents`).
- **Translation, spelling, sports scores, general knowledge:** the model and `web_search`;
  testing, not building.

## Multi-step requests: a test list, not a build

The tools should already compose these; try each before building anything.

- "What time should I leave to pick up Antonio?" [docs]: mail or calendar, then `route`.
- "Email the participants that I'll be 10 minutes late" [unverified]: `calendar_read` lists
  attendees, then `mail_compose`.
- "Summarize the details in a note" [unverified]: a read, then `write` in `Notes/`.
- "What tasks do I have today?" [unverified]: the calendar, until Reminders exist.

## Proposed order (not decided)

Weather; the pill's Open; ask about the selection; timers; changing an event. Each is cheap or
closes a gap the UI already shows, and together they cover the most of what Cmd-Space gets used
for.

## Sources (fetched 2026-11-22)

- Apple's Mac User Guide, macOS 27:
  [Get started with Siri AI](https://support.apple.com/en-au/guide/mac-help/mac88e1mkh19/mac),
  [Find information and get things done](https://support.apple.com/en-au/guide/mac-help/mchl6b029310/27/mac/27),
  [What's on your screen](https://support.apple.com/en-au/guide/mac-help/iphmk4p88mkuky/27/mac/27),
  [Write with Siri](https://support.apple.com/en-au/guide/mac-help/ipho54eqrx4ms3j/27/mac/27),
  [The Siri app](https://support.apple.com/en-au/guide/mac-help/q7ny3g54v9lk/27/mac/27),
  [What's new in the updates](https://support.apple.com/en-us/127257).
- [MacStories, macOS 27 review](https://www.macstories.net/stories/macos-27-the-macstories-review/6/)
  and [its next page](https://www.macstories.net/stories/macos-27-the-macstories-review/7/);
  [iOS 27, Siri as a General Assistant](https://www.macstories.net/stories/ios-and-ipados-27-review/6/).
- [9to5Mac, macOS 27 Siri AI top features](https://9to5mac.com/2026/09/17/macos-27-golden-gate-siri-ai-top-features-apples-assistant-finally-comes-to-life-video/),
  [9to5Mac, macOS 27.2](https://9to5mac.com/2026/10/26/macos-27-2-golden-gate-now-available-heres-everything-new/).
- [Geeky Gadgets, 34 of 62 tasks on 27.2](https://www.geeky-gadgets.com/siri-ai-mac-test/):
  categories only, no per-task list.
