# AGENTS.md "Current state", as of 2026-11-28

This is the section as it stood on 2026-11-28. It may not match the code today.

## Current state

M1 is done and the server is deployed (static Linux image, tailnet-only HTTPS). Guide-quality fixes Q1–Q14 in
`docs/PLAN.md` are deployed (`taba-server:q14`, 2026-11-13). Q14: the trip's typed facts
outrank the prose: stay arrangement, trip travel and the guide's base; no invented stay; a contradiction check on
all copy; pick lists keep fitting kinds; plan.md v8, write.md v8, repair.md v3. Default model: Sol.
Q15 (2026-11-14, deployed as `taba-server:q15`): named tasting items, a trip-only Good to know, a later last stop
before a known departure. Deploying: `docs/SERVER.md`, "Deployment".
Q16-Q18 (2026-11-14): `taba-score` and 11 evaluation scenarios; rank, pace and spend checks; and an OpenStreetMap fallback when Foursquare gives nothing (Foursquare credits ran out). Q19 adds Nominatim as a second fallback. Deployed as `taba-server:q19`. Apple Maps data cannot be stored in guides (Apple's terms); see the server `docs/PLAN.md` notes.
Q20 (2026-11-14, deployed as `taba-server:q20`): research names up to 20 places (research.md v6), each looked up on OpenStreetMap by name with a shorter-name retry; the sweep only fills gaps (Nominatim, then Overpass); research picks are marked and plan.md v11 prefers them; the build no longer uses Foursquare or its key. The six-trip run passed (83 of 87 picks found). The Foursquare code is deleted (2026-11-14, not deployed: no behaviour change). Fixes for the two weaknesses it showed (picks of kind `other`, picks with unknown hours; plan.md v12) and a fix that records why a ChatGPT request failed are deployed as `taba-server:q20c`; a Leeds rebuild passed. Next: stop the unfixable `mealMissing` warning burning repair rounds, then Q21 (OSM credit) and Q22 (live MapKit walks).
