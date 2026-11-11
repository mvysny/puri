# Research — Siri on macOS 27, the reference; GTK4 and its bindings, the stack

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

## R_gnome_activation — Starting and raising an app from a GNOME shortcut

- On Wayland no app can grab a global key; a custom keybinding in GNOME Settings runs a command
  (`org.gnome.settings-daemon.plugins.media-keys`), or the XDG `GlobalShortcuts` portal binds
  one. **[docs]**
- GNOME's input-source switcher sits on Super+Space (`org.gnome.desktop.wm.keybindings
  switch-input-source`). **[verified 2026-11-11, GNOME on Ubuntu 26.04]**
- `gapplication launch <id>` activates the running instance over the session bus in a few
  milliseconds, or has the bus start it from a `dbus-1/services/<id>.service` file. **[docs]**
- A Puri started that way from a custom shortcut gets the graphical session's environment, and
  its window comes up with keyboard focus. **[verified 2026-11-11, GNOME on Ubuntu 26.04]**
