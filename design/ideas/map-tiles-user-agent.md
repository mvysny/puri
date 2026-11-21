# The map's tiles under Puri's own User-Agent

OSM's tile policy asks an app to send its own User-Agent and says a library's default may be
blocked. Puri calls `Shumate.set_user_agent`, but libshumate 1.6's tile downloader hard-codes
`libshumate/1.6.beta` and never reads it, on main too (`R_shumate`). So Puri's tiles go out as
libshumate's, as GNOME Maps' do; `tile.openstreetmap.org` serves them today.

## Open questions

- `Q_tiles_ua`: which way out?
  - Report it upstream, or send the one-line patch (`shumate_get_user_agent ()` in place of the
    constant in `shumate-tile-downloader.c`); Puri's call then takes effect with the next
    libshumate in apt. Outward-facing: the owner's call.
  - A Ruby `Shumate::DataSource` that fetches tiles itself, under Puri's User-Agent and the tile
    policy's caching: a virtual function and async GTask from Ruby-GNOME, untried.
  - Leave it while OSM serves libshumate's User-Agent.
