# Launch: what's left before promoting Puri

Goal: Puri now does enough to promote (owner, 2026-11-23). Done: the page at
<https://puri-ai.de> (`docs/`, `D_domain`), live on GitHub Pages with HTTPS; the install guide
and the models page; the starter model (`D_starter_model`). No video (owner, 2026-11-25): the
page's replay is the demo. The install's untested steps are `quick-install.md`'s. Left here: the
free public services, then the open questions.

## Before launch: the free public services

One user is light use; a launch may bring hundreds, each hitting the same free services. Their
policies are already in `R_osm_services` and `R_open_meteo`; what a launch changes:

- **Nominatim and FOSSGIS's OSRM:** a request a second and an identifying User-Agent each. Does
  the limit count per install, or for every install behind Puri's one User-Agent? Not read yet;
  check before launch.
- **Photon:** throttles "extensive usage", with no number given.
- **OSM's tiles:** an identifying User-Agent. libshumate sends its own, and Puri's never reaches
  the wire (`Q_tiles_ua` in `map-tiles-user-agent.md`). Settle that first.
- **Open-Meteo:** under 10,000 calls a day, non-commercial. Fine per user.
- **Brave Search's free tier:** what it costs now. Check before the page says "free".

## Open questions

- `Q_startup_error`: started from the shortcut, Puri prints a config error to stderr and exits,
  so the press does nothing. *Easy, the Apple way* settles it: the error shows in the window
  (owner, 2026-11-25). Not built yet.
- `Q_packaging`: one day `apt install puri`? git clone and `bin/setup` do for the early adopters
  a launch reaches. Options: a Launchpad PPA, which builds from source with the gems vendored;
  Debian packages for pikuri's gems, slow; or Flatpak, whose sandbox would need holes for the
  Thunderbird profile, localsearch, podman and Rhythmbox's D-Bus.
- `Q_competitors`: Newelle, Moose and Alpaca, tried before the page compares? Everything in
  `design/competitors.md` comes from reading, none of it from running. Check there before the
  page claims that Puri is "the only" anything.
