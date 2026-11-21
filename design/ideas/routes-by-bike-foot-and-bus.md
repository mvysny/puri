# Routes by bike, on foot and by bus

`route` drives, and only drives (`D_places`). Siri may answer "and by bus?" or "on foot?" as a
follow-up; whether it does is still to try.

## Open questions

- `Q_modes`: FOSSGIS runs bike and foot beside car (`routed-bike`, `routed-foot`), the same OSRM
  API, so a `mode` on `route` is cheap. Public transport would be Transitous, whose terms Puri
  (MIT, open source, non-commercial) meets: a User-Agent with name, version and contact, and over
  720 plans a day coordinated first (`R_osm_services`). Puri has no version yet.
- `Q_siri_maps`, still to try on the owner's Mac:
  - "How far is it by car from Jumbo Vantaa?" — distance, time, live traffic? A map of the route?
  - Follow-up "and by bus?", "on foot?".
  - Does "Where is …" ever ask when several places match?
  - Siri's map: does it pan and zoom, and what does a click on it do?
  - The popup card versus the Siri app: is the map the same in both?
