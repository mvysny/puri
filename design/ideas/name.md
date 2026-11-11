# A name better than "pikuri-seci"

"seci" is short for *secretary*, picked in pikuri-tui because *secretarius* is "the one entrusted
with secrets", which was the shell's security story. Good etymology, uninspiring word, and "seci"
reads as nothing. Decide before the first D-Bus API, the `.desktop` file and the GNOME shortcut:
the GApplication id (reverse-DNS) and the state folder (`~/.local/state/<name>/`) carry the name,
and renaming them later strands users' shortcuts and saved conversations.

## Constraints

- **The pikuri family.** Siblings are `pikuri-tui`, `pikuri-web`; the repo may stay `pikuri-*`
  while the app's own name (window title, binary, what you'd say aloud) differs.
- **Sayable.** You'll call it by name ("ask X"), like Siri.
- **Not Siri.** A pun is fine; anything that reads as Apple's trademark isn't.
- **The mascot.** pikuri's mascot is Kuri, a pika: gathers grass all summer into a haypile under a
  rock, lives in rockslides, whistles at anything that comes close, never leaves its mountain.

## Candidates

- **Kuri.** The mascot's name, and it rhymes with Siri. "Ask Kuri." Repo `pikuri-kuri` (silly) or
  plain `kuri`; binary `kuri`. Cons: it makes the mascot a product; *kuri* is Japanese for
  chestnut; Kuri was also a 2017 home robot (Mayfield Robotics, discontinued). No apt package or
  command of that name here (checked 2026-11-11).
- **Pikuri Desktop.** Descriptive and safe, and the owner's fallback. Cons: sounds like a desktop
  environment, or like *the* desktop build of all of pikuri; nobody says "ask Pikuri Desktop".
- **Haypile.** The pika's winter store: notes, reminders and memory gathered for later. Lovely
  metaphor for the notes half, says nothing about the asking half.
- **Whistle.** A pika whistles; you whistle (the hotkey) and it comes. Sayable, a verb. Cons:
  generic, and collides with lots of software named Whistle.
- **Talus.** The rockslide pikas live in. Nice-sounding, opaque.
- **Secretary / Seci.** Keep it. Cons: as above.

Leaning: **Kuri** for the app, in a repo named `kuri` whose README opens "on pikuri" —
`pikuri-kuri` stutters. See `Q_repo_name`.

## Open questions

- `Q_app_name`: Kuri, Pikuri Desktop, or another?
- `Q_repo_name`: `pikuri-<name>` for the family, or the bare name?
- `Q_app_id`: the reverse-DNS GApplication id — a domain the owner controls
  (`io.github.mvysny.*`? `org.codeberg.mvysny.*`?), which also names the D-Bus service.
