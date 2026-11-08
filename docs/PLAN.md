# TABA build plan

TABA ("There and Back Again") is a personal iOS app. You enter a destination, dates and a budget, and it builds
a walking field guide: a day-by-day plan of places to see, eat and drink, with opening hours, sun times,
weather and practical notes. The model is a hand-made Edinburgh guide; the mocked version of it in
`Tests/GuideKitTests/Fixtures/edinburgh-mock.json` is the benchmark.

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
| M2 | App reads and shares guides: guide view, day timeline with walk legs, day map, place detail, offline cache, PDF and HTML export. Built against the Edinburgh fixture | |
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
3. **Prompt wiring.** A new library target `PipelineKit` (depends on GuideKit, SourcesKit, ResponsesKit).
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

   Done when: golden-file tests show the plan, write and repair inputs for the Edinburgh fixture (reviewed
   by hand against the prompts), `CopyChecker` tests cover each rule, and the four checks pass.
4. **Whole guide from one command.** A `taba` executable: `taba build --destination ... --from ... --to ...
   [--stay ...] [--model ...]` on the Mac runs steps 2 to 9 with the live sources and the ChatGPT
   credentials. It writes `probe-output/runs/<timestamp>/guide.json` and `run.json`. The run record holds:
   prompt ids and versions, model, time per step, every AI answer, plan-check issues per round, repair
   rounds and copy-check results.

   Done when: one real Edinburgh run (23–25 Nov 2025 dates, mock stay) finishes, the guide passes
   `validateStructure`, there are no plan-check errors after repair, and a short comparison with the
   hand-made guide is written to the run folder for the owner to read.
5. **Server.** Hummingbird 2 service:
   - one swift-jobs job per pipeline step, each saving its result and queuing the next;
   - Postgres via PostgresNIO and postgres-migrations;
   - a single app token (hummingbird-auth);
   - progress over SSE;
   - endpoints: create trip, trip status, get guide, progress stream.

   Use AsyncHTTPClient on the server, because `URLSession.bytes` does not exist on Linux: put it behind the
   `HTTPFetching` seam and the ResponsesKit transport.

   Done when: the service builds for Linux in Docker, runs locally against a local Postgres, and builds the
   Edinburgh guide through the API.
6. **Deploy.** Docker image: a static Linux SDK binary, on a base image with `tzdata` and `ca-certificates`.
   A Compose service plus Postgres on the VPS, listening on host port 18090. ChatGPT credentials moved over
   SSH. The tailnet-only HTTPS host already exists (see the private handoff).

   Done when: `https://travel.nanodev.uk` answers a health check over the tailnet, returns 403 publicly,
   and builds a guide through the API. The owner has to agree to the VPS change first.
7. **Model comparison.** On the Edinburgh trip, measure:
   - plan-check errors on the first answer, and repair rounds;
   - meals, daylight and the train buffer;
   - walking against the pace;
   - unsourced numbers in the copy, and banned phrases;
   - time per step;
   - a human read by the owner.

   Candidates: gpt-6.1-sol, gpt-6-astra, gpt-6-luna.

   Done when: a results table is in `docs/` and the default model and effort per step are set in config.

## Decisions already made

- Swift + Hummingbird, not TypeScript, Vapor or Rust.
- OpenAI through the ChatGPT plan, which requires this repo to be public. Code only: secrets and trips stay
  on the server.
- Photos (provider and Wikimedia, with credits) in v1. Illustrations later.
- Everything stays on free tiers. Ask the owner before anything that costs money.
