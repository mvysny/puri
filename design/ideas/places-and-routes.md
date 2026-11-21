# Places and routes: where is it, how far, a map in the answer

Goal: answer what Siri answers with Apple Maps — where a place is, how far and how long from
somewhere, what's nearby — and draw the places on a map under the answer, as Siri does. GNOME
Maps answers no queries, so Puri asks the services Maps itself asks (*Research* below).

## The first cases

- "Where is Vantaan Musiikki, and how far is it by car from Jumbo Vantaa?" Two geocoder searches
  and one route, tested by hand: Peltolantie 2, 01300 Vantaa; 6.3 km, 9 to 13 minutes depending
  on the router. Straight line: 3.6 km.
- "Coffee near me": a category search around the home. Nominatim answers it and Photon doesn't:
  ten cafés within 1.1 km of the shop, most with opening hours, in one request.

## Decided (owner, 2026-11-21)

- Photon for names; Nominatim for categories, opening hours and websites; FOSSGIS's OSRM for car
  routes. The alternatives stay under *Research*.
- Built in Puri first, against the convention that a missing tool is a pikuri gap; its home is
  decided later, probably pikuri-workshop. Graduating needs a `D_` for the exception, or the move.
- Several matches: the model picks the likeliest or asks the user.
- `route` takes each end as a handle, an address or GPS coordinates, and resolves it itself; no
  `home` keyword (*The tools*).
- Where the user is: when `Notes/PURI.md` holds no home address, the agent asks and writes it
  there. No GeoClue, no config key.
- A map in the answer, drawn by libshumate; a click on a pin opens that place in GNOME Maps, or on
  openstreetmap.org in the browser when Maps isn't installed. The wheel scrolls the answer, never
  zooms the map. No rows under it and no buttons: no Call (Linux can't call), no Website, and no Directions, since a
  route from home asked of the model costs half a minute a click.
- A `[maps]` table in `config.toml` holds the tile URL. Without it Puri starts, with no place
  tools and no map, as `[search]` without a key leaves no web tools. At graduation the *Search,
  never fetch* promise ("talks only to the configured search engines") grows to name the map
  services.
- Every request carries Puri's own User-Agent, the GitHub repository as contact:
  `Puri (+https://github.com/mvysny/puri)`. Transitous would want a version in it too.
- Not doing: leave-by times from the calendar; a self-hosted geocoder or router.
- The owner drives Siri on the Mac for `Q_siri_maps`.

## v1 (owner, 2026-11-21)

- `place_search(query:, near:)` finds a place by name, through Photon. One Nominatim `lookup` adds
  the hits' opening hours and websites, so "is it open now?" needs no third tool; several ids in
  one `lookup` is untested.
- `place_search(category:, near:)` finds what's nearby, through Nominatim. `category` is one of
  about twenty OSM types — café, restaurant, pharmacy, supermarket, fuel, charging station, ATM —
  and the model maps "coffee" or "kahvila" to `cafe`. Hits within 1–2 km of `near`, sorted by our
  own distance.
- Each hit's distance from `near` is by car, with the time: one OSRM `table` request for all the
  hits.
- `route(from:, to:)`, car only, through OSRM; its ends as in *How `route` takes its ends*.
- The home address: the agent asks when `Notes/PURI.md` holds none, and saves it there. Prompt
  text only.
- A map under the answer, from the turn's last place tool: a search's hits as pins numbered like
  their handles; a route's two ends and its line, the view fitted to both.
- A click on a pin opens that place in GNOME Maps, or in the browser without Maps (*The map in
  the answer*).
- The wheel scrolls the answer, never zooms the map; a drag pans it, its buttons zoom (`Q_map`).
- An old conversation redraws its map from the data stored with the answer.
- Attribution: the map's OSM licence line; under a route, a "Fix the map" link, as FOSSGIS asks.
- At most one request a second to Nominatim and to OSRM, and a small cache of their answers.
- Specs draw local tiles from `dev/`, never OSM's.
- `gir1.2-shumate-1.0` is required, like `gir1.2-adw-1`: in the README's apt line and CI's image.

Later: bike, foot and public transport (`Q_modes`); photos.

## The tools

Both are the same class as `web_search`: a fixed host, the payload unreviewed
(`egress_destination: :tool_vouched`), the results `untrusted: :hard`, since anyone can edit OSM
and a shop's name can carry an injection.

- `place_search(query: or category:, near:)` → per hit: its handle, name, category, address,
  distance and time by car from `near`, opening hours where known: `[3] Musiikki Silfverberg Oy Vantaan Musiikki
  (musical instrument shop), Peltolantie 2, 01300 Vantaa`. "Where is X" by `query`, "what's near
  Y" by `category`. `near` takes the same three forms as a route's end.
- `route(from:, to:)` → what each end resolved to, the distance, the duration. Car only, to start.

### How `route` takes its ends (owner, 2026-11-21)

Each end is one of three, and `route` resolves it to coordinates itself before it calls OSRM:

- **A handle**, the number a `place_search` hit carries (`3`): the usual case, once the user has
  searched and perhaps said which place they meant. Numbers count up through the whole
  conversation, never restarting per search, so after two searches `3` still means one place. A
  table in memory, per conversation, maps each number to the hit's coordinates and OSM id. After a
  restart the table is gone: an unknown handle answers "pass the address instead", and the model
  copies it from the hit's line in the transcript — one more step, only then.
  - Why not OSM's own id (`N9444805490`), which needs no table and survives a restart: ten digits
    to copy in every call, where a small model slips, and the echo below catches a slip only after
    the wrong place was routed to. Anthropic's tool-writing post found the same: a simple numbered
    scheme in place of long ids raised precision and cut hallucinations.
- **An address**, as text, geocoded inside — a cold "from my home to Cafe XYZ". A text end is
  looked up near the other end.
- **GPS coordinates**, `60.2931,25.0307` — what the user or a mail gives.

No `home` keyword: the model passes the address it saved in `Notes/PURI.md`, which it may well
word differently from one save to the next.

The result names what each end turned out to be, "name (category), address", GPS ends as the
nearest address, so a wrong match or a miscopied handle or number shows, and the model can ask.

Why not one form alone — prior art, read 2026-11-21:

- MCP's archived Google Maps server: `maps_directions(origin, destination, mode)`, both strings,
  "address or coordinates", geocoded by Google.
- Google's current Maps agent tools: `compute_routes` takes per waypoint an `address`, a
  `place_id` or a `lat_lng`, mixed freely, and a `location_bias` that steers how text resolves.
- An OpenStreetMap MCP server: `get_route_directions(from_latitude, from_longitude, to_latitude,
  to_longitude)`; the model copies the numbers out of `geocode_address`.
- Anthropic's "Writing effective tools for agents": agents do "significantly more successfully"
  with natural-language names than with cryptic identifiers, and one tool may fold a frequently
  chained task into one call.

Google's mix is the closest. Our own findings behind the three forms:

- Coordinates alone make the model copy four long numbers, and a miscopied digit moves a point by
  kilometres unseen; a handle alone makes even a cold question two steps, search then route, each
  costing 10–20 s of thinking on the owner's server (`R_llama_server_turns`). Text alone picks the
  geocoder's first match unseen.
- A text end needs a bias point, or "Prisma" lands in Bolivia (*Research*).
- An address alone finds the building but whichever business there ranks first: "Peltolantie 2"
  echoes as a grill (*Research*). So an address end echoes as the address, a business's name only
  when the text named it.

## The map in the answer

Siri draws a map under a place answer, and so does Puri. libshumate, the widget GNOME Maps draws
with, loads from Ruby the way Adw does; a scratch prototype (2026-11-21) showed Vantaan Musiikki on
OSM's tiles with a pin, zoom buttons, a scale and the licence line (*Research*).

How it fits:

- Core decides when an answer gets a map and what is on it — pins with labels, a route's line —
  and sends it as JSON data in the `Reply`; Desktop draws a `Shumate::SimpleMap` from it, so
  Desktop still only draws. `exe/puri` loads Shumate beside Adw.
- No rows under the map, unlike Siri's pills: the answer already lists the places, and each pin
  carries its handle. No photo either: OSM rarely has one, and an image URL from OSM's data is a
  stranger's URL to fetch.
- A car button per place was dropped (owner, 2026-11-21): a route from home has to go through
  the model, which reads the home address from `Notes/PURI.md`, and a turn with one tool call
  takes half a minute or so on the owner's server (`R_llama_server_turns`). Siri's opens Apple
  Maps at once.
- A click on a pin opens the place by its openstreetmap.org URL: a hit's object,
  `https://www.openstreetmap.org/node/9444805490`, or a GPS end's point,
  `https://www.openstreetmap.org/?mlat=60.2931&mlon=25.0307&zoom=17`. With GNOME Maps installed,
  the URL goes to Maps' desktop file, and Maps shows the place with its name and details. Without
  Maps it goes to the default browser (owner, 2026-11-21), where a hit opens OSM's object page:
  the place highlighted on the map, its raw tags beside it, address and opening hours among them
  (*Research*). The click is the human's, so the agent still opens no URL.
- The map fetches its own tiles when drawn: egress with no click, to `tile.openstreetmap.org`, for
  the area a tool found — never a URL the model wrote. The same class as the geocoder's query
  (`:tool_vouched`); the tile server learns which area the user looked at.
- OSM's terms: Puri's own User-Agent, the licence line on the map, the cache honoured, the tile
  URL from `[maps]` rather than hard-coded.
- `gir1.2-shumate-1.0` joins the README's apt line and CI's image.

`Q_map`, unchecked for v1:

- A route's view fitted to both ends and OSRM's line (`overview=full`): does libshumate fit a view
  to a bounding box, or do we do the Mercator maths?
- The wheel scrolls the answer (owner): can libshumate's map pass it on rather than zoom?
- A replayed map's tiles come from `~/.cache/shumate` or the network.

## What Siri does — `Q_siri_maps`

Seen on the owner's Mac, macOS 27.2.1, 2026-11-21:

- "Where is Vantaan Musiikki?": one street address, and a wrong one — Kielotie 4, where the shop
  is at Peltolantie 2. Under the answer a map; under the map "Call", and a car glyph with
  "Directions".
- Directions opens Apple Maps on the route from "My Location" to the place, behind the Siri card,
  which stays open.
- "Coffee near me": asks nothing first and uses the Mac's location. A map with two cafés, then one
  full-width pill per place — name, opening hours, a photo and the like — with a car glyph on the
  right that opens driving directions in Apple Maps.

Siri got the address wrong where OSM had it right, so naming what was matched — name, category,
address — is worth keeping.

Still to try:

- Does "Where is …" ever ask when several places match?
- Siri's map: does it pan and zoom, and what does a click on it do?
- "How far is it by car from Jumbo Vantaa?" — distance, time, with live traffic? A map with the
  route?
- Follow-up "and by bus?", "on foot?".
- The popup card versus the Siri app: is the map the same in both?

## Open questions

- `Q_map`: above.
- `Q_modes`, after v1: bike and foot are FOSSGIS's too (`routed-bike`, `routed-foot`); public
  transport would be Transitous, whose open-source, non-commercial terms Puri (MIT) meets. If
  Siri does them.

## Research (2026-11-21)

Markers as in `design/research.md`: **[verified]** tried here, **[src]** read in the source,
**[docs]** the service's own page, **[unverified]** a hypothesis. When the idea graduates, what
still matters moves to `design/research.md`.

### GNOME Maps 49.3 answers no queries

Ubuntu 26.04's package, its JavaScript read out of the GResource.

- It ships no GNOME Shell search provider. **[verified]**
- On the session bus it exports only GApplication actions: `search(s)`, `osm-account-setup`,
  `shortcuts`, `quit`. `search` shows the results in its window and returns nothing.
  **[verified]**
- `geo:lat,lon` opens it on a point; `maps:q=…`, `geo:0,0?q=…` or `--search` on a search. A
  `maps:` URI takes `q=` alone, so no URI opens a route. **[src]**
- Installed, it is the `x-scheme-handler/geo` default. **[verified]**
- `geo:lat,lon` gives a nameless pin. An `https://www.openstreetmap.org/node/<id>` URL (or `way`,
  `relation`) passed to it as a file makes it fetch that object from Overpass and select it as a
  place, with its name and details; one with `mlat`/`mlon` and `zoom`, or `#map=`, gives a point.
  **[src]**
- Its desktop file launches it with `gapplication launch org.gnome.Maps %U`. **[verified]**
- It searches GraphHopper's geocoding API with a key written in its source, finds places by
  category through Overpass (`around:`), routes with GraphHopper and Transitous, and draws
  `tile.openstreetmap.org`. **[src]**
- Its own position comes from GeoClue **[src]**; Ubuntu's `geoclue.conf` sets no Wi-Fi
  geolocation URL. **[verified]**

### Finding places: Photon, Nominatim, Overpass

- Photon (`photon.komoot.io`): no key, no stated limit, "extensive usage will be throttled", no
  availability promised. **[docs]**
- Photon's first hits are Vantaan Musiikki (`shop=musical_instrument`, Peltolantie 2, 01300
  Vantaa) and Jumbo (`shop=mall`, Vantaanportinkatu 3); three other "Vantaan musiikki…" places
  follow the first. **[verified]**
- Photon needs a bias point: "Prisma" alone finds shops in Bolivia; with Jumbo's `lat`/`lon`, the
  Jumbo Prisma comes first. **[verified]**
- An address alone finds the building but whichever business there ranks first ("Peltolantie 2"
  is a grill); name plus address finds the place itself, telling two same-named music schools
  apart. **[verified]**
- Photon finds no category near a point: "cafe", "kahvila" and "coffee" match names 5–15 km away
  despite the bias point, "coffee" finds US counties, and an `osm_tag` filter plus a `bbox` leaves
  only the two cafés named "Cafe…". **[verified]**
- A Photon hit carries its OSM id but no phone, website or opening hours, though OSM has all three
  for the shop. **[verified]**
- Nominatim: one request a second per application, an identifying User-Agent, results cached, no
  autocomplete. **[docs]**
- Nominatim's `lookup` by an OSM id with `extratags=1` returns phone, website and opening hours.
  **[verified]**
- Nominatim's `amenity=cafe` inside a bounded `viewbox`, with `extratags=1`, returns ten cafés
  within 1.1 km, most with opening hours, unsorted by distance, in one request. **[verified]**
- Nominatim's free text finds Vantaan Musiikki and Jumbo first. "Prisma" with a regional `viewbox`
  gives three Helsinki Prismas, not Jumbo's; without one, a Czech peak and Bogotá. **[verified]**
- Overpass (`overpass-api.de`) `around:1000` returns the same cafés with all their tags.
  **[verified]** About 10,000 requests and 1 GB a day, but it calls "an app for more than just
  OSM mappers" relying on its public instance problematic. **[docs]**

### Routes: OSRM, Valhalla, Transitous, GraphHopper

- FOSSGIS's OSRM (`routing.openstreetmap.de`; car, bike, foot): one request a second, a valid
  User-Agent, "reasonable, non-commercial use-cases", requests logged, a "fix the map" link shown.
  **[docs]**
- FOSSGIS's Valhalla (`valhalla1.openstreetmap.de`) answers without a key; its terms are unread,
  as FOSSGIS's policy page turns bots away. **[verified]**
- For the same 6.3 km by car, OSRM says 8.8 min and Valhalla 12.7 min. **[verified]**
- FOSSGIS's OSRM answers the `table` service: one request gave car distances and times from the
  shop to three points, 1.1 to 6.9 km. **[verified]**
- Transitous (public transport): open-source, non-commercial apps only, a User-Agent naming the
  app, its version and a contact; over 720 plans a day, coordinate first. **[docs]**
- GraphHopper's free plan: 500 credits a day, non-commercial only. **[docs]**
- None of these servers, nor Photon or Nominatim, is in Ubuntu 26.04's apt. **[verified]**

### A map from Ruby: libshumate, and OSM's tiles

libshumate 1.6~beta from apt, a 560 × 330 map on Broadway; OSM's
[tile usage policy](https://operations.osmfoundation.org/policies/tiles/).

- `gir1.2-shumate-1.0` comes in with `gnome-maps`; Ruby loads it through GObject Introspection,
  as it does Adw. **[verified]**
- `Shumate::SimpleMap` draws OSM's tiles with zoom buttons, a scale and the source's licence line;
  a `MarkerLayer` takes any widget as a pin. **[verified]**
- The typelib also has a `PathLayer`, for a line such as a route. **[verified]**
- Ruby-GNOME folds alternative constructors into `new`: `MapSourceRegistry.new_with_defaults` is
  missing; `new`, then `populate_defaults`, works. **[verified]**
- One view at zoom 16 left 26 tiles, 700 KB, in `~/.cache/shumate`. **[verified]**
- `Shumate.set_user_agent` sets the tile requests' User-Agent. **[unverified]**
- OSM allows a map a human is viewing, and blocks a library's default User-Agent: an app sends its
  own, distinct and stable. **[docs]**
- Tiles honour the server's caching headers, or are kept at least 7 days; no prefetch, no offline
  use; the attribution stays visible on the map. **[docs]**
- OSM asks apps not to hard-code the tile URL, so it can be switched without an update. **[docs]**
- openstreetmap.org in a browser opens `?mlat=…&mlon=…&zoom=17` as a marker on that point, and
  `/node/<id>` as the object's page: highlighted on the map, its tags beside it. **[verified]**
