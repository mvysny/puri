# Autostart at login: opt-in now, default later?

`rake install` sets up D-Bus activation and the shortcut, and starts nothing at login;
`AUTOSTART=1` adds `~/.config/autostart/io.github.mvysny.Puri.desktop`, which runs
`exe/puri --gapplication-service` (no window) when the session starts. Opt-in because a resident
Puri gets in the way of development (below), and because some users would rather pay the first
press's start than keep a process around all day.

## What each choice costs

- **Without autostart:** the first shortcut press of a session waits for the bus to start Puri:
  ~1.2 s of Ruby, Bundler and GTK today (`desktop-popup-app/ui-toolkit.md`), plus whatever the
  real Core will add: pikuri's agent, the notes index (pikuri-rag), a warm local model. Once
  those land, the first press may take many seconds, not one.
- **With autostart:** ~116 MB (and later the model's memory, if Core keeps it loaded) for the
  whole session, used or not; every press is instant.

## The development trap

A resident Puri, whether autostarted or started once by the shortcut, owns
`io.github.mvysny.Puri` on the session bus. A later `exe/puri` from a terminal, Broadway
included, then only activates that process and exits: the developer sees the old code and
nothing says so. Today's workaround is `pkill -f exe/puri` before a dev run.

- `Q_dev_app_id`: give dev runs their own id (`io.github.mvysny.Puri.Devel`, as GNOME apps do for
  their development builds), so they never meet the installed one? Chosen how: an env var, a
  `--devel` flag, or "running from a checkout with uncommitted changes"? The installed one runs
  from the same checkout, so the id can't come from the install location alone.
- `Q_quit`: Puri has no Quit yet; `app.hold` keeps it alive with every window hidden. A
  `app.quit` action (a menu entry, Ctrl+Q) would end the trap without `pkill`.

## Open

- `Q_autostart_default`: once the real Core makes the first press slow, does `rake install`
  autostart by default, with `AUTOSTART=0` to opt out?
