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

- Photon for places, FOSSGIS's OSRM for car distance; the alternatives stay under *Research*.
  "Coffee near me" reopens the first half (`Q_providers`).
- Built in Puri first, against the convention that a missing tool is a pikuri gap; its home is
  decided later, probably pikuri-workshop. Graduating needs a `D_` for the exception, or the move.
- Several matches: the model picks the likeliest or asks the user.
- Where the user is: when `Notes/PURI.md` holds no home address, the agent asks and writes it
  there. No GeoClue, no config key.
- A map in the answer, drawn by libshumate. No buttons: no Call (Linux can't call), no Directions,
  no Website.
- Not doing: leave-by times from the calendar; a self-hosted geocoder or router.
- The owner drives Siri on the Mac for `Q_siri_maps`.

## The tools

Both are the same class as `web_search`: a fixed host, the payload unreviewed
(`egress_destination: :tool_vouched`), the results `untrusted: :hard`, since anyone can edit OSM
and a shop's name can carry an injection.

- `place_search(query:, near:)` → per hit: name, category, address, distance from `near`,
  opening hours where known. For "where is X" and "what's near Y" (`Q_categories`).
- `route(from:, to:, near:)` → what each end resolved to, the distance, the duration. Car only,
  to start.

### `Q_route_args`: text, coordinates or handles — recommendation, for the owner

Prior art splits three ways (read 2026-11-21):

- MCP's archived Google Maps server: `maps_directions(origin, destination, mode)`, both strings,
  "address or coordinates", geocoded by Google.
- Google's current Maps agent tools: `compute_routes` takes per waypoint an `address`, a
  `place_id` or a `lat_lng`, mixed freely, and a `location_bias` that steers how text resolves.
- An OpenStreetMap MCP server: `get_route_directions(from_latitude, from_longitude, to_latitude,
  to_longitude)`; the model copies the numbers out of `geocode_address`.
- Anthropic's "Writing effective tools for agents": agents do "significantly more successfully"
  with natural-language names than with cryptic identifiers, and one tool may fold a frequently
  chained task into one call.

Our own findings:

- Photon needs a bias point, or "Prisma" lands in Bolivia (*Research*).
- Name plus address finds the exact place again; an address alone finds another business at the
  same building (*Research*).
- Each step costs 10–20 s of thinking on the owner's server (`R_llama_server_turns`). With
  coordinates the first case takes two steps (both searches, then the route); with text, one.

Recommendation: **text in, resolved places out.**

- `route` takes each end as text and geocodes it inside: `from` near `near`, `to` near `from`.
  `near` is the area the question names, else the home from memory.
- Its result names each end as "name (category), address", and the runner-up matches beside it:
  "Musiikki Silfverberg Oy Vantaan Musiikki (musical instrument shop), Peltolantie 2, 01300 Vantaa;
  also matched: Vantaan musiikkiopisto (music school), Lummetie 4". One call answers both "where"
  and "how far", and a wrong pick shows; the model then asks, or calls again with the runner-up's
  line.
- A hit's line from `place_search`, name plus address, is the exact reference to pass on — no
  handle store to evict, nothing that breaks when an old conversation is replayed.
- No coordinates in: no numbers for a model to copy. Handles (Google's `place_id`) only if a
  name-plus-address line ever fails to come back as itself.

## The map in the answer

Siri draws a map under a place answer, and so does Puri. libshumate, the widget GNOME Maps draws
with, loads from Ruby the way Adw does; a scratch prototype (2026-11-21) showed Vantaan Musiikki on
OSM's tiles with a pin, zoom buttons, a scale and the licence line (*Research*).

How it fits:

- Core decides when an answer gets a map and what is on it — pins with labels, a route's line —
  and sends it as JSON data in the `Reply`; Desktop draws a `Shumate::SimpleMap` from it, so
  Desktop still only draws. `exe/puri` loads Shumate beside Adw.
- Under the map, one row per place, as Siri's pills: name, category, distance, opening hours.
  No photo: OSM rarely has one, and an image URL from OSM's data is a stranger's URL to fetch.
  Siri's car glyph per place went with the buttons.
- The map fetches its own tiles when drawn: egress with no click, to `tile.openstreetmap.org`, for
  the area a tool found — never a URL the model wrote. The same class as the geocoder's query
  (`:tool_vouched`); the tile server learns which area the user looked at.
- OSM's terms: Puri's own User-Agent, the licence line on the map, the cache honoured, the tile
  URL a setting rather than hard-coded.
- `gir1.2-shumate-1.0` joins the README's apt line and CI's image.

`Q_map`, still to brainstorm:

- Which result gets a map: the place the answer names, or every hit as pins, numbered like the
  rows? A route: both ends and OSRM's line (`overview=full`), the view fitted to both — whether
  libshumate fits a view to a bounding box, or we do the Mercator maths, is unchecked.
- Inside a scrolling answer, does the wheel scroll the answer or zoom the map?
- Does a click on the map open GNOME Maps on the spot (`geo:`), the way Siri's Directions opens
  Apple Maps behind the card?
- An old conversation replayed from the history: the map redraws from its stored data, the tiles
  from the cache or the network.
- Specs fetch no real tiles: a local tile source for `Puri::Dummy`, under `dev/`.
- Without `gir1.2-shumate-1.0` the answer stays text?

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

- `Q_route_args`: the recommendation above.
- `Q_map`: above.
- `Q_providers`: Photon finds no category near a point; Nominatim does, and finds the names too,
  but its `viewbox` is a box to prefer, not a ranking by distance ("Prisma" gave three Helsinki
  Prismas, not Jumbo's). Photon for names and Nominatim for categories and details, or Nominatim
  alone, with a tight box around `near` and our own sort by distance?
- `Q_categories`: how do "coffee", "kahvila" or "pharmacy" become `amenity=cafe` or
  `amenity=pharmacy` — a list of categories the model picks from, or Nominatim's special phrases
  ("cafe near …", untested)?
- `Q_details`: website and opening hours for a name search — Photon drops them, Nominatim's
  `lookup` by the hit's OSM id returns them, one more request per place. Fetch them inside
  `place_search` for the top hit, or a third tool `place_details`? Opening hours would answer
  "is it open now?".
- `Q_modes`: bike and foot are FOSSGIS's too (`routed-bike`, `routed-foot`); public transport
  would be Transitous, whose open-source, non-commercial terms Puri (MIT) meets. After car, if
  Siri does them.
- `Q_attribution`: the map carries OSM's licence line; FOSSGIS's routes ask for a "fix the map"
  link too — under the answer, like Siri's source chip?

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
