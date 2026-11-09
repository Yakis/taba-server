# TABA build plan

TABA ("There and Back Again") is a personal iOS app. You enter a destination, dates and a budget, and it builds
a walking field guide: a day-by-day plan of places to see, eat and drink, with opening hours, sun times,
weather and practical notes. The model is a hand-made Edinburgh guide; the mocked version of it in
`GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json` is the benchmark.

It is for one person and their family. There is no monetization and no App Store release: the app goes out
through TestFlight.

## Shape

- **iOS app** (SwiftUI, iOS 26, private repo `taba-ios`, created in Milestone 2). It reads, shows and shares
  guides, and asks the server to build new ones.
- **Server** (this repo). Swift + Hummingbird 2, with Postgres and swift-jobs for the pipeline steps. It runs
  as a Docker Compose service on a small self-hosted VPS and is reachable only over the owner's tailnet,
  over HTTPS.
- **GuideKit** (this repo). Shared Swift package: the guide model, plan checks, sun times, schemas and
  assembly. The app uses it by relative path. Foundation only, so it also runs on Linux.

## How a guide is built

The AI chooses and writes. Code measures and checks. Anything code can do, code does.

| # | Step | Who |
|---|---|---|
| 1 | Trip input, and ticket import (on the phone, Apple's on-device model, `Prompts/ticket.md`) | app |
| 2 | Destination basics: geocode, time zone, sun times, weather | code |
| 3 | Stay: the traveller's booking, or a shortlist with booking links | code |
| 4 | Place candidates: Foursquare sweep, OSM opening hours, area names, walk times | code |
| 5 | Research: time-bound facts for the exact dates, with sources (`research.md`, web search) | AI |
| 6 | Plan: choose and time stops from the candidates (`plan.md`, strict schema) | AI |
| 7 | Check with `PlanChecker`, send issues back for repair at most twice (`repair.md`) | code + AI |
| 8 | Write all words in the trip's voice from the given facts (`write.md`), then copy checks | AI + code |
| 9 | Assemble with `GuideAssembler`, save, notify the phone | code |

After a guide exists: re-check 3 days before the trip (hours, weather, closures), edit a single day, share.

## Providers (all free at personal volume)

| Need | Source | Notes |
|---|---|---|
| AI | OpenAI Responses API through the owner's ChatGPT plan ("Sign in with ChatGPT", open-source agent route) | `store:false`, `stream:true`, `instructions` not system items. No temperature, max_output_tokens, previous_response_id. Backup: an OpenAI API key on the same code path, never used automatically |
| Places | Foursquare Places API, free Pro fields | Free tier gives name, location, categories, website. No hours, rating or phone. Premium fields cost money: never call them without asking |
| Opening hours | OpenStreetMap `opening_hours` through Overpass | Often slow (about 45 s). Failure means "unknown hours", never a failed guide |
| Geocoding, area names | Nominatim | 1 request per second, real User-Agent |
| Weather | Open-Meteo forecast (within 16 days), else the archive for the same dates in the last 3 years | |
| Sun times | NOAA formulas in code (`SunTimes`) | |
| Walking times | Straight-line estimate now (`StraightLineWalkTimes`); Apple Maps Server API later | Apple Maps needs a key from the owner's developer account |
| Maps in the app | MapKit | |

## Sharing and family

- PDF and a self-contained HTML file, made on the phone from a GuideKit template.
- Family sharing through iCloud (CKShare with CKSyncEngine). Only the owner builds guides. Family can view,
  tick stops off and add notes. Family install through TestFlight as external testers.

## Milestones

| | Milestone | Status |
|---|---|---|
| M0 | GuideKit model, Edinburgh fixture, plan checks, sun times, prompts, Foursquare probe, ChatGPT sign-in and probe | done |
| M1 | Pipeline on the server (below) | in progress |
| M2 | App reads and shares guides (steps in the `taba-ios` repo, `docs/PLAN.md`): guide view, day timeline with walk legs, day map, place detail, offline cache, PDF and HTML export. Built against the Edinburgh fixture | |
| M3 | App makes guides: new-trip form, live progress, push notification. On the phone through TestFlight | |
| M4 | Family and a living guide: iCloud sharing, edit a day, ticket import, re-check before the trip, rain swaps | |
| M5 | Later: hotel shortlist within budget, spend totals, widget, Live Activity, illustrations | |

### M1 steps

Each step is reviewed, then committed on its own.

1. **Plan/copy split, schemas, assembler.** Done. `PlanDraft`, `GuideCopy`, `ResearchResult`, the strict
   `JSONSchema` builder (ids are enums, so the model can only pick given ids), `GuideAssembler`.
2. **Data sources (`SourcesKit`).** Done. HTTP seam, `PlaceMatcher` (best of N Foursquare hits), Foursquare
   sweep, OSM `OpeningHoursParser` and `OverpassHoursSource` (batches of 25, 90 s, one retry, never fatal),
   Open-Meteo weather (forecast, or the last 3 years for typical weather), Nominatim geocoder,
   `taba-sources-probe`. Live Edinburgh run: hours for 14 of 20 places in 45 s. Known weakness: reverse
   geocoding single places gives odd area names (an Old Town café came back as "Abbeyhill"). Step 3 should
   name a whole cluster, for example by the most common suburb or quarter among its places, at a zoom that
   gives Old Town / New Town / Stockbridge style names.
3. **Prompt wiring.** Done. `PipelineKit` depends on GuideKit, SourcesKit and ResponsesKit; the reviewed
   root `Prompts/` files are bundled without moving them. Plan and write prompts are version 2.
   - `PromptLibrary`: loads `Prompts/*.md` as package resources (move `Prompts/` into the target if SwiftPM
     needs it, and update paths in the docs), parses the front matter (id, version, role, output, effort,
     tools) and returns the body below it.
   - Areas: cluster candidates (about 500 m), name each cluster by the most common suburb or quarter among
     its places' reverse-geocoded names (see the weakness in step 2), and compute `areaWalkMinutes` between
     cluster centres with the WalkTimes.
   - Input builders that produce exactly the JSON each prompt describes, with sorted keys:
     - research input;
     - plan input: day windows from arrivals and departures, hours per date as periods or `closed` /
       `always` / `unknown`, third-party text under `external`;
     - repair message: `repair.md` text, then the issues and measured legs as JSON, sent with `plan.md` as
       the instructions;
     - write input: the assembled plan, places with facts, light, findings, stay, anchors, lists and open
       questions.
   - `CopyChecker`: ids present, banned phrases from `write.md`, emoji, more than one exclamation mark, word
     limits, and every time, date, price and number in the copy must appear in the input.

   Verified: Edinburgh research, plan, write, repair payload and full repair-message goldens reviewed against
   the prompts; every copy-check rule covered; all four checks pass (442 tests across the package suites).
   Learned for step 4: use stable cluster ids for area walks and preserve draft stop ids through writing;
   numeric copy checks are conservative lexical screening, not proof of a claim's truth.
4. **Whole guide from one command.** Done (reviewed, committed and live-verified). A `taba` executable: `taba build --destination ... --from ... --to ...
   [--stay ...] [--model ...]` on the Mac runs steps 2 to 9 with the live sources and the ChatGPT
   credentials. It writes `probe-output/runs/<timestamp>/guide.json` and `run.json`. The run record holds:
   prompt ids and versions, model, time per step, every AI answer, plan-check issues per round, repair
   rounds and copy-check results.

   Verified: the live Edinburgh mock run (23–25 Nov 2025) completed in about eight minutes using
   `gpt-6.1-sol`: three AI calls, no repairs or retries, structural validation passed, and zero initial or
   final plan-check issues. The run folder contains the guide, full evidence and a comparison with the
   mocked hand-made guide. All four repository checks pass (469 offline tests; new files also privacy-scanned).
   Seven conservative numeric-copy flags were reviewed: ordinary ordinals and times already present inside
   supplied hours/date-times. The original flags remain in the run record.

   Reproduce on the Mac after ChatGPT sign-in, with `FOURSQUARE_API_KEY` supplied securely:

   ```sh
   swift run taba build --destination Edinburgh --from 2025-11-23 --to 2025-11-25 \
     --facts GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json
   ```

   `--facts` reads a Guide as a facts scaffold (trip, stay, bookings, places, practical facts and sources),
   not as a prewritten plan or copy. Without it, `--stay` names the base; omitting the stay uses an explicitly
   approximate, unbooked destination-centre placeholder. Check-in/out and budget defaults are recorded as
   assumptions. `--model` overrides the provisional default; `--out` must name a new directory. Only the
   existing ChatGPT sign-in route is used. Source requests are capped, OSM remains nonfatal, research
   suggestions must resolve and be measured, and decode/copy retries and plan repairs are bounded.

   Learned for step 5: persist copy review flags separately from validation success and expose them to the
   reader. A historical benchmark uses current provider data plus mock facts, not verified historical hours;
   numerical screening and source-URL membership cannot prove factual truth. Unclassified boundary transport
   bookings fail before AI calls; resolve station/airport endpoints rather than silently dropping travel cutoffs.
5. **Server.** Done.
   Hummingbird 2 service:
   - one swift-jobs job per pipeline step, each saving its result and queuing the next;
   - Postgres via PostgresNIO and postgres-migrations;
   - a single app token (hummingbird-auth);
   - progress over SSE;
   - endpoints: create trip, trip status, get guide, progress stream.

   Use AsyncHTTPClient on the server, because `URLSession.bytes` does not exist on Linux: put it behind the
   `HTTPFetching` seam and the ResponsesKit transport.

   Verified locally: Linux release Docker build, Postgres migrations and durable seven-stage swift-jobs
   execution, bearer-token routes, authenticated resumable SSE, and an Edinburgh API build using recorded
   sources/answers. Replay returned a structurally valid guide with no plan errors and retained all seven
   numeric copy flags. Native x86-64 Linux verification also passed in an isolated VPS test setup;
   restarting both Postgres and the API preserved the guide, review flags and checkpoint/evidence counts,
   without public ports or changes to existing services. Postgres tests cover duplicates, restart
   checkpoints/outbox, admission bounds,
   backend termination/cancellation, recovery and stale-attempt evidence fencing. Fresh provider calls
   through the API have not been authorized or run. Setup and API details: `docs/SERVER.md`.

   Learned for deployment: exactly-once provider calls cannot be guaranteed across crashes; recover only
   the in-flight stage, fence evidence by attempt ID, and keep copy review distinct from completion.
   The local image uses a full Swift runtime; the small static-SDK deployment image is still step 6.
   Review fixes: an idle read timeout on the HTTP client (a request timeout only covers the response head,
   so a stalled AI stream could hold the single worker), and a short lock wait so a job pushed while the
   dispatcher still holds the lock is not skipped.

   Done when: the service builds for Linux in Docker, runs locally against a local Postgres, and builds the
   Edinburgh guide through the API. Passed with recorded answers and live.
   A live Edinburgh build through the API on 2025 dates with mock facts finished in about 10 minutes
   (research 3 min, plan 2, check with two repairs 2, write 1.5): structurally valid, no plan errors or
   warnings after repair, one copy flag, which was a checker false positive (now fixed).
   The flag was booking times written as `2025-11-25T18:52`, which grounded neither the date nor the time.
6. **Deploy.** Docker image: a static Linux SDK binary, on a base image with `tzdata` and `ca-certificates`.
   A Compose service plus Postgres on the VPS, listening on host port 18090. ChatGPT credentials moved over
   SSH. The tailnet-only HTTPS host already exists (see the private handoff).

   Done when: `https://travel.nanodev.uk` answers a health check over the tailnet, returns 403 publicly,
   and builds a guide through the API. The owner has to agree to the VPS change first.
   Done 2026-11-09: health 200 over the tailnet, 403 publicly, a wrong token 401, and a live Edinburgh build
   (2025 dates, mock facts) through the deployed API in 6 min 49 s (research 2, plan 2, check and write 3.5).
   The image is a static musl binary on Alpine (about 100 MB), cross-compiled on the Mac and copied over SSH;
   `Glibc` imports needed `Musl` branches. The server refreshed the ChatGPT sign-in file itself.
   Learned: CopyChecker flags the ordinal "first" as an ungrounded number (all four flags of the live run:
   "Market first.", "Breakfast first", "Your first evening's dinner"); words like first/second should not
   count as numbers.
7. **Model comparison.** On the Edinburgh trip, measure:
   - plan-check errors on the first answer, and repair rounds;
   - meals, daylight and the train buffer;
   - walking against the pace;
   - unsourced numbers in the copy, and banned phrases;
   - time per step;
   - a human read by the owner.

   Candidates: gpt-6.1-sol, gpt-6-astra, gpt-6-luna.

   Done when: a results table is in `docs/` and the default model and effort per step are set in config.

Follow-up from the iOS app (its M2 step 2): `Day.weather` (`DayOutlook`: summary, high and low in °C, rain
chance, forecast or typical) is in GuideKit, and the app shows it in each day's header. The pipeline already
fetches this weather in its sources step; it should copy it onto each day when it assembles the guide. Until
then it is nil and the app leaves the weather out. `GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-guide.json`
is the finished sample the app ships: the mock assembled by `GuideAssembler` with mocked hero, notes, open
questions and weather.

Follow-up from the iOS app (its M2 step 3): `Place.website` and `Place.phone` are in GuideKit (optional,
omitted when unknown), and the place sheet shows Website and Call buttons only when they are set. The
pipeline should fill them: Foursquare's free fields include the website (today it becomes a "Website: …"
fact instead), and OpenStreetMap tags often carry `website` and `phone` (or `contact:website`,
`contact:phone`). Foursquare's phone field is a paid Premium field: never call it without asking. The finished
sample sets websites on three places whose own site is already one of its sources.

### Guide quality fixes (from the first trip built from the app)

The first guide built through the app had sound picks but serious gaps. Each fix is its own commit.

| # | Fix | Done when | Status |
|---|---|---|---|
| Q1 | Opening hours survive a busy Overpass: retry timeouts, lost connections and 429/502/503/504 four times with doubling waits, rotate to a backup server, record the error in the evidence | Tests cover each retry case; a live run records `found` above 0 or an `error` | done |
| Q2 | Weather on each day: `GuideAssembler` copies the fetched `DayWeather` onto `Day.weather` (see the follow-up above) | Assembled guides carry `weather` on every day the forecast or archive covers; the fixture still round-trips | done |
| Q3 | Bus or taxi for long legs: a leg over a set walking time becomes `transit` with an estimated ride time; the pace check counts walking only; the plan input and `plan.md` say how to reach a far-out stay | A stay 10 km out gives ride legs of minutes, not walks of hours, and no pace warning from them | done |
| Q4 | Interests steer the search: each interest adds Foursquare categories (music venues, markets, …); research findings with a venue are resolved as places so the plan can schedule them | A date-specific event with a venue can appear as a stop | |
| Q5 | Less repeated copy: `write.md` says unknown hours once in the notes, and on a stop only when it matters | Fewer than a third of stop bodies mention checking hours on a trip with mostly unknown hours | |
| Q6 | Rebuild the same trip and compare | The owner judges it good | |

Learned in Q1: overpass-api.de often answers 502 when full, and the public mirrors are slow or broken at times,
so retries with waits matter more than more mirrors. A batch can now take about 8.5 minutes at worst.
Q2: the assemble stage loads the candidates checkpoint for the weather; `GuideAssembler.assemble` takes an optional
weather-by-date map, so older callers and the fixture are unchanged.
Q3: `Travel` in GuideKit is the one rule (walk up to 30 minutes, else a ride of 10 min + road distance at 30 km/h). AI
inputs renamed: `fromStay`, `areaTravelMinutes`, `fromPrevious`; plan v3, repair v2, write v3. In Edinburgh one area
pair (36 walk minutes) became a 16-minute ride.

Later, if the AI turns out to be the weak link: a second AI provider with its own key, switchable from the app's
settings. A paid key needs the owner's yes.

## Decisions already made

- Swift + Hummingbird, not TypeScript, Vapor or Rust.
- OpenAI through the ChatGPT plan, which requires this repo to be public. Code only: secrets and trips stay
  on the server.
- Photos (provider and Wikimedia, with credits) in v1. Illustrations later.
- Everything stays on free tiers. Ask the owner before anything that costs money.
