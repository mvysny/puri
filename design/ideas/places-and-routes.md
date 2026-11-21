# Places and routes: where is it, how far, see it on a map

Goal: answer what Siri answers with Apple Maps — where a place is, how far and how long from
somewhere, what's nearby. GNOME Maps answers no queries (`R_gnome_maps`), so Puri asks the services
Maps itself asks, and hands the place to Maps for the human to look at.

## The first case

"Where is Vantaan Musiikki, and how far is it by car from Jumbo Vantaa?" Two geocoder searches and
one route answer it, tested by hand (`R_osm_services`): Peltolantie 2, 01300 Vantaa; 6.3 km, 9 to
13 minutes depending on the router. Straight line: 3.6 km.

The search for "Vantaan Musiikki" returns four places: the shop, two music schools and a memorial.
The shop comes first and its category (`shop=musical_instrument`) gives it away, but the model has
to pick (`Q_ambiguous`).

## Sketch

Two tools, upstream in pikuri, since a missing tool is a pikuri gap (`Q_pikuri_home`):

- `place_search(query, near:)` → per hit: name, category, address, coordinates, distance from
  `near`. Photon.
- `route(from, to, mode:)` → distance and duration; `mode` car, bike, foot, maybe transit.
  FOSSGIS's OSRM or Valhalla; Transitous for transit.

Both are the same class as `web_search`: a fixed host, the payload unreviewed
(`egress_destination: :tool_vouched`), and the results `untrusted: :hard`, since anyone can edit
OSM and a shop's name can carry an injection.

Puri's side: a line in the system prompt (use the tools, never guess an address), the tool-line
wording, and the hand-off to a map.

### See it on a map (owner, 2026-11-21; details later)

A button next to the reply, placed like a confirmation's: "See Vantaan Musiikki on a map". A click
opens GNOME Maps centred on the spot (`geo:lat,lon`, the `x-scheme-handler/geo` default once Maps
is installed), or the browser on openstreetmap.org where nothing handles `geo:`. The human clicks,
as with a mail draft, so the map's own tile fetches are the human's, not the agent's.

Unlike a confirmation, nothing waits on it: the button stays after the turn ends, and the
conversation goes on. Still to brainstorm:

- Which tool result makes a button: every hit of `place_search`, or only the place the answer
  ends up naming? Several places, several buttons?
- Core words the button (Desktop only draws); who launches the URI, Desktop or Core?
- Does the button survive a replay of an old conversation from the history?
- A route: Maps takes no route URI (`R_gnome_maps`), so "See the route" can open only the
  destination, or openstreetmap.org's directions page, which does take both ends.

## What Siri does — `Q_siri_maps`

To try on the Mac, macOS 27.3; the answers become `R_siri_maps`:

- "Where is Vantaan Musiikki?" — an address in text, a map in the card, a place card with Call,
  Website and Directions? Does it ask when several places match?
- "How far is it by car from Jumbo Vantaa?" — distance, time, with live traffic? Does it open
  Apple Maps on the route, or only offer to?
- Follow-up "and by bus?", "on foot?".
- "Coffee near me" — does it use the Mac's location, ask permission first, list or map the results?
- "How long to my next meeting?", "When do I have to leave?" — does it join Calendar's location to
  Maps unasked?
- Opening hours, phone number, ratings: does the answer carry them, and from where?
- The popup card versus the Siri app: does either show a map inline?

## Open questions

- `Q_ambiguous`: several hits — the model picks the likeliest and says so, or lists them and asks?
  Siri's behaviour decides.
- `Q_route_args`: does `route` take names and geocode them inside (one call), or coordinates from
  `place_search` (two calls, the pick visible in the transcript)?
- `Q_providers`: Photon or Nominatim; OSRM or Valhalla, whose times differ by 45 % on the test.
  All are keyless, so v1 needs no config; a setting only if one stops answering. Attribution:
  OSM's ODbL and FOSSGIS's "fix the map" link — a source line under the answer, like Siri's chip?
- `Q_where_am_i`: "near me" needs a position. GeoClue is off on the owner's machine, and Ubuntu
  gives it no Wi-Fi source (`R_gnome_maps`). A home place in `config.toml`? The user's own address
  from their contact card in Thunderbird? GeoClue where it works, which needs `X-Geoclue-Reason` in
  our `.desktop` and the Shell's consent?
- `Q_leave_by`: the Siri-shaped case — the next event's location from the calendar, a route to it,
  "leave at 13:40". Needs only the two tools plus the calendar tools already built.
- `Q_local_geo`: self-hosted Photon and OSRM or Valhalla for Finland would keep even the query
  local, but none is in apt, and they cost gigabytes and a server process.
- `Q_inline_map`: a map drawn inside the reply (libshumate, `gir1.2-shumate-1.0` 1.6~beta in apt)?
  Its tiles would be fetched for coordinates the model chose, an agent's egress, where the button
  is the human's. Likely never, given the button.
- `Q_pikuri_home`: a new pikuri gem (`pikuri-places`?), or beside `web_search` in pikuri-web?
  Does pikuri-tui want it too?
