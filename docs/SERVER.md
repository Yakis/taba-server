# TABA server

The server is implemented for M1 step 5 and deployed in step 6 (see "Deployment" below). Linux release builds and a local Postgres/API benchmark using
recorded Edinburgh answers have passed. A live Edinburgh build through the API on 2025 dates with mock facts finished in about 10 minutes (research 3 min, plan 2, check with two repairs 2, write 1.5): structurally valid, no plan errors or warnings after repair, one copy flag, which was a checker false positive (now fixed).
Native x86-64 Linux verification also passed in an isolated, resource-limited VPS workspace, including
Postgres/API restart persistence. No production services or public ports were changed.
The deployment image is a static Linux binary; see "Deployment".

## Components

- `BuildKit`: source preparation shared with `taba build`.
- `PipelineKit`: research, initial plan, check/repair, copy, and assembly entry points with Codable checkpoints.
- `ServerHTTPKit`: bounded, cancellation-aware AsyncHTTPClient adapters for sources, OAuth and Responses.
  The client must disallow redirects; the executable sets that policy. Empty SSE lines are preserved.
- `ServerKit`: Hummingbird 2 router, PostgresNIO storage, postgres-migrations, swift-jobs/Postgres worker.
- `LivePipelineKit`: live runner and an explicitly selected offline recording replay runner.
- `taba-server`: configuration and service lifecycle. GuideKit remains Foundation-only.

## Local setup

Use Docker Desktop and the Swift toolchain required by `Package.swift`. No new host database installation is needed.

```sh
docker compose -f compose.local.yml up -d postgres
swift build --product taba-server
```

The disposable local database listens only on loopback port 15432. Its public development password is
not suitable for deployment. To run the native executable, supply `DB_PORT=15432` and an app token securely
in the process environment. Do not put real tokens in this repository or command literals/history.

### Configuration

| Variable | Default / requirement |
|---|---|
| `TABA_APP_TOKEN` | Required; at least 32 bytes. Generate a high-entropy random token and keep it private. |
| `HOST`, `PORT` | `127.0.0.1`, `8090`; Docker listens internally on `0.0.0.0`. |
| `DB_HOST`, `DB_PORT` | `localhost`, `5432` |
| `DB_USER`, `DB_NAME` | `taba`, `taba` |
| `DB_PASSWORD` | `taba-local-only` — local development only |
| `FOURSQUARE_API_KEY` | Required for live mode; obtain securely from Keychain. Only free fields are used. |
| `TABA_MODEL` | The default model for new trips; `gpt-6.1-sol` when unset (deployed: `gpt-6.1-terra`) |
| `ANTHROPIC_API_KEY` | Optional, paid per use. When set, Claude Opus 5.5 and Claude Sonnet 5.5 are offered. Never logged. |
| `DEEPSEEK_API_KEY` | Optional, paid per use. When set, DeepSeek V4 Pro and DeepSeek Flash are offered. Never logged. |
| `TABA_CHATGPT_CREDENTIALS` | Existing writable sign-in credentials file; otherwise the normal default path |
| `TABA_REPLAY_DIRECTORY` | Absent means live mode. Present means offline replay; empty or invalid paths fail startup. |

Database TLS is disabled because this configuration is for loopback or an internal Compose network. Do not
point it at an untrusted remote database. No OpenAI API-key fallback is implemented.

`compose.local.yml` optionally runs the Linux image on loopback port 18090. Set `TABA_UID=$(id -u)` and
`TABA_GID=$(id -g)` for access to the owner-only credentials bind mount, plus the real app token and source
key in the environment, before `docker compose -f compose.local.yml up --build server`. The **directory** is
mounted writable because token refresh atomically replaces the credentials file. Do not run a live build
without the owner's permission. No automatic guide build happens on startup. Allow 60 seconds for
container shutdown (`docker stop --timeout 60`); Compose sets that grace period because workers can
spend up to 30 seconds finishing work before cancellation. Docker's default 10 seconds can force-kill
an otherwise recoverable process.

## HTTP API

All trip endpoints require `Authorization: Bearer <app token>`. `/health` is an unauthenticated liveness
check. JSON responses and progress streams use `Cache-Control: no-store`; do not put a caching proxy in front.

| Method | Path | Result |
|---|---|---|
| GET | `/health` | `200`, `ok` |
| GET | `/models` | The AI models a trip may name, and the default (below) |
| POST | `/trips` | `202`, status containing the new UUID; `503` when four builds are active |
| GET | `/trips/:id` | State, current stage, `copyReviewRequired`, `model` |
| GET | `/trips/:id/guide` | The Guide after completion; `409` while unavailable |
| GET | `/trips/:id/review` | Preserved copy-review flags, including affected text and paths |
| GET | `/trips/:id/events` | SSE progress, resumable using `Last-Event-ID` |

Create body (14 calendar days maximum; names at most 120 UTF-8 bytes):

```json
{
  "destination": "Edinburgh",
  "from": "2025-11-23",
  "to": "2025-11-25",
  "stay": "Example lodging"
}
```

Optional preferences, each falling back to the old default when absent:

| Key | Values | Default |
|---|---|---|
| `pace` | `relaxed`, `unhurried`, `packed` | `unhurried` |
| `interests` | ranked strings, at most 10, each 1–60 UTF-8 bytes, no duplicates ignoring case | none |
| `dailySpend` | `low`, `moderate`, `high` | `moderate` |
| `adults`, `children` | 1–10, 0–10 | 1, 0 |
| `mobilityNotes` | at most 5 strings, each 1–120 bytes | none |
| `model` | an id from `/models`: `gpt-<version>-sol`, `-terra` or `-luna`, or a `claude-` or `deepseek-` id | the server default (`TABA_MODEL`) |

They fill the trip scaffold the pipeline plans and writes from (`Trip.pace`, `interests`, `budget.dailySpend`,
`party`). They are not accepted together with `facts`.

Optional `facts` is an inline Guide scaffold instead of `stay`. Only facts, not its existing plan or copy,
are used. The dates/destination must match. Unknown top-level fields, server file paths and caller-selected
provider configuration are not accepted, apart from picking one of the offered `model`s. Request bodies are limited to 1 MiB. An Edinburgh benchmark request
can embed `GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json` as `facts`.

Models: `GET /models` answers
`{"default":"gpt-6.1-sol","models":[{"id":"gpt-6.1-sol","name":"Sol","provider":"ChatGPT"},...]}`. Each option has a
`provider`: `ChatGPT`, `Claude` or `DeepSeek`.
The list is the newest Sol, Terra and Luna on the ChatGPT plan (from `GET https://api.openai.com/v1/models`), kept
for an hour; if the plan cannot be asked, the last good list, or only the default. The default is always first.
After the ChatGPT models come `claude-opus-5-5` and `claude-sonnet-5-5` when `ANTHROPIC_API_KEY` is set, then
`deepseek-v4-pro` and `deepseek-flash` when `DEEPSEEK_API_KEY` is set; these are fixed in code. A missing key means
that provider is not offered, and a `TABA_MODEL` whose provider has no key stops the server at startup. DeepSeek
Flash cannot search, so a Flash trip's research stage runs on DeepSeek V4 Pro; its other stages use Flash. Claude
requests use web search (`web_search_20260209`, up to 10 searches) and server-side fallbacks, and are retried
once without the JSON schema format if Anthropic refuses it together with search citations.
Offline replay offers only the default. A `model` the server does not currently offer gets `400`. The trip stores
the model it will use (the default is filled in at admission), `GET /trips/:id` and the progress events report it,
and the finished guide records it as `aiModel`. Trips from before this change have no model.

SSE sends durable increasing event IDs and safe status only—not the destination, bookings, provider output
or raw errors. It emits heartbeats, disables proxy buffering, observes disconnect/cancellation, and closes
at terminal state (also when reconnecting after the last event). Detailed evidence stays in Postgres.
A completed build is **not factual approval**: readers must fetch `/review` and inspect flags.

## Jobs, persistence and recovery

Every stage is a distinct swift-jobs record: `basics → candidates → research → plan → check → write → assemble`.
Each saves a checkpoint. Completion atomically advances the trip row to its successor; that row is the
**durable outbox**. A dispatcher enqueues pending stages and redelivers unacknowledged ones after 30 seconds.
A crash between enqueue and acknowledgment can duplicate delivery; the current stage is checked under a
Postgres advisory lock, so committed stages do not run again.

One queue worker and a cross-process advisory lock serialize all stage execution. A dedicated database
connection holds that lock throughout a stage; connection loss is monitored and cancels provider work.
Attempt IDs fence private evidence so an interrupted attempt cannot append after recovery. Four active
builds are admitted under a separate transaction lock. This is personal-volume infrastructure, not a
multi-tenant scheduler.

Ordinary provider/validation failures are terminal: the queue does not blindly retry AI work. A process
crash or lost lock can repeat the **in-flight stage**, up to three interrupted attempts, but not committed
stages. Exactly-once external provider calls are not possible across crashes; cancellation and network
failure detection are cooperative. Source caps are 5/100/45 per basics/candidates/research attempt (150 for
an uninterrupted build, up to 450 across the crash-recovery cap). Nominatim pacing is process-wide; Overpass
remains sequential and nonfatal. Plan repair and decode/copy retry bounds are unchanged.

Inputs, requests, answers, prompt versions, model, timing and checks are private database evidence. Copy
flags from unsuccessful or interrupted attempts are retained too; they may need to be compared with the
final guide. Evidence-write failure prevents checkpoint completion. Checkpoints are an internal format;
keep code, model configuration and prompt versions stable while resuming a build. Do not migrate to a new
pipeline format with unfinished jobs without an explicit compatibility plan.

## Verification

Default tests stay offline and do not need Docker:

```sh
swift build --build-tests
swift test
swiftlint lint --quiet --strict
scripts/privacy-scan.sh --all
```

Opt-in Postgres tests create **retained disposable databases** on local port 15432; no real database is
cleared. They cover admission, seven-stage persistence, duplicate delivery, outbox/worker execution,
reviews, failure privacy, backend termination, cancellation, recovery, and stale-evidence rejection:

```sh
TABA_TEST_POSTGRES=1 swift test --filter PostgresTripStoreTests
```

Linux release build (the same static image as deployment, for the Mac's own architecture):

```sh
docker build -t taba-local:static .
```

BuildKit keeps compilation in a reusable cache; check Docker's free space before a first build. Never prune
images, volumes or build cache without owner approval.

### Offline Edinburgh API replay

Use an existing private step-4 run directory containing `run.json` and `guide.json`. Explicitly set
`TABA_REPLAY_DIRECTORY` to that directory on the server (mount it read-only for Docker). Replay runs the
actual seven stages with recorded sources/answers, generates new evidence and checks, and refuses
incompatible input or malformed recordings. It never substitutes a live provider. The benchmark recording
is not committed, so this test requires that local artifact.

With the replay server running and the same app token supplied securely to the test process:

```sh
TABA_TEST_SERVER_URL=http://127.0.0.1:18090 swift test --filter ServerAPITests
TABA_REPLAY_TEST_DIRECTORY=/path/to/private/run swift test --filter replayRunsAllSevenStagesOffline
```

The API test checks authentication, admission, all 15 progress transitions, terminal reconnection, Guide
structure and plan checks, and the seven preserved benchmark copy flags. This is **offline replay**, not
fresh live-provider verification; the live run is described at the top.

An additional native x86-64 Linux run used a capped build container (2 CPUs, 4 GiB RAM), a separate
internal Docker network, and disposable Postgres/API containers with no published ports. Two API replays
passed. Restarting both Postgres and the API preserved the completed guide, seven review flags and the
unchanged counts of seven checkpoints, 15 progress events and 14 private evidence records for the first
build. Test containers were stopped afterwards; the seven pre-existing service containers retained their
identities and health. Real provider keys and sign-in credentials were not transferred.

## Deployment

The `Dockerfile` builds a fully static binary with the Swift Static Linux SDK (musl) and puts it on a small
Alpine image with `tzdata` and `ca-certificates` (about 100 MB, against 5 GB for the old full-runtime image).
The build stage runs on the builder's own architecture and cross-compiles, so an arm64 Mac builds the
x86-64 server image without emulation:

```sh
docker buildx build --platform linux/amd64 -t taba-server:<tag> --load .
```

The Static SDK version and checksum in the `Dockerfile` must match the Swift compiler of the build image
exactly (swift.org lists both). Code that imports `Glibc` needs a `Musl` branch too
(`#elseif canImport(Musl)`). The image has a health check (`wget` on `/health`, BusyBox is in the base).

Production runs as two Compose services next to the host's other apps:

- `taba-postgres` (`postgres:17-alpine`) on an internal-only network, data on a host folder;
- `taba-server` on that network plus an ordinary one for its outbound calls, published only on the host's
  loopback port `18090`, read-only root filesystem with a small `/tmp`, all capabilities dropped,
  `stop_grace_period: 60s` (workers get 30 seconds to finish a stage), memory capped at 1 GB.

The image is copied over SSH (`docker save | ssh <host> docker load`) and pinned by image ID; nothing is
pulled from a registry at start. Secrets (app token, Foursquare key, database password) live in root-only
env files on the host, written over SSH stdin. The ChatGPT sign-in file sits in a host folder owned by the
container user (65532), mounted writable because a token refresh replaces the file. A reverse proxy
terminates TLS for a tailnet-only host name and refuses public requests with 403. Backups take a `pg_dump`
of the database rather than its live files.

To update: build a new image, `docker save | docker load` it on the host, change the pinned image ID in the
host's Compose configuration, and apply it; only `taba-server` is recreated.
