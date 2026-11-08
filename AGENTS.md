# AGENTS.md

Instructions for coding agents working on TABA. Read this, then `docs/PLAN.md` (what we are building, the
pipeline, milestones and the next steps) and `Prompts/README.md` (how the AI prompts work).

If `private/HANDOFF.md` exists, read it too. It holds the owner's infrastructure details and current state.
The `private/` folder is gitignored and must never be committed.

## The repo is public

This repo is public, because the ChatGPT plan route requires an open-source client. So:

- Never commit personal data: real names, emails, home paths, real trips, booking references, seats.
  Test data is mocked (the Edinburgh fixture uses 2025 dates and made-up stay and luggage places).
- Never commit secrets: API keys, tokens, credential files, `.env` files, private keys.
- The pre-commit hook runs `scripts/privacy-scan.sh --staged`. Enable it once per clone:
  `git config core.hooksPath scripts/hooks`. `--all` scans tracked files only, so new files are only
  checked once staged.
- A deliberate fake value that trips the scan gets `// privacy-scan:allow` at the end of its line. Prefer
  fakes that don't look real (`test-key-not-real`, `example.com`). Build test JWTs at run time, never as one
  literal (see `Tests/ResponsesKitTests/Support/JWTVector.swift`): GitGuardian flags them.
- macOS file systems are case-insensitive. A `.gitignore` folder rule like `credentials/` also matches
  `Sources/.../Credentials/`. Root-only rules start with `/`. After adding a folder, check
  `git check-ignore -v <path>`.

## Secrets and money

- Secrets live in the macOS Keychain or in `~/.config/taba/` (0600), never in files in this repo and never
  in output. Never print a key or token, not even partly.
- Foursquare key: Keychain service `foursquare-api-key`, passed as `FOURSQUARE_API_KEY`:
  `FOURSQUARE_API_KEY="$(security find-generic-password -s foursquare-api-key -a "$USER" -w)" swift run ...`
- ChatGPT credentials: `~/.config/taba/chatgpt.json`, written by `swift run taba-chatgpt sign-in` (the owner
  logs in in their browser). Never use an OpenAI API key automatically.
- Everything stays free. Never call paid APIs (Foursquare Premium fields, OpenAI API key billing, image
  generation) without the owner's explicit yes.
- Free APIs still get polite use: Nominatim at most 1 request per second with a real User-Agent; Overpass
  one query at a time.

## Layout

| Path | What |
|---|---|
| `Sources/GuideKit` | Shared model (`Guide`, places, plan, bookings, AI outputs), `PlanChecker`, `SunTimes`, `JSONSchema` builders, `GuideAssembler`. Foundation only, must build on Linux |
| `Sources/FoursquareKit`, `Sources/FoursquareProbe` | Foursquare wire types and mapping; `foursquare-probe` tool |
| `Sources/ResponsesKit`, `Sources/TabaChatGPT` | Sign in with ChatGPT (PKCE, ID-token verification), credentials, Responses API streaming client; `taba-chatgpt sign-in` and `taba-chatgpt probe --model <slug>` |
| `Sources/SourcesKit`, `Sources/SourcesProbe` | Data sources: place matching, OSM hours, weather, geocoding; `taba-sources-probe` |
| `Prompts/` | The AI prompts, versioned with front matter. See `Prompts/README.md` |
| `Tests/` | Swift Testing. `Tests/GuideKitTests/Fixtures/edinburgh-mock.json` is the benchmark trip |
| `scripts/` | `privacy-scan.sh`, `hooks/pre-commit` |
| `docs/PLAN.md` | The plan and roadmap |
| `probe-output/` | Probe reports and raw responses. Gitignored |

## Commands

```sh
swift build --build-tests
swift test
swiftlint lint --quiet          # must report 0 violations
scripts/privacy-scan.sh --all
```

All four must pass before a commit.

## How to work

- Swift 6.2 language mode, strict concurrency, Swift Testing (not XCTest). No new package dependencies
  without a reason in the commit message.
- Keep GuideKit Foundation-only. The server runs on Linux: no `URLSession.bytes` there (use AsyncHTTPClient
  on the server), no Apple-only frameworks outside `#if canImport(...)`.
- One step at a time, each committed on its own with a conventional message (`feat(guidekit): ...`,
  `fix: ...`, `docs(prompts): ...`). Commit and push only when the owner asks.
- Tests are offline, with hand-written JSON that follows the real API shapes. Live calls go in the probe
  tools, which the owner (or you, with permission) runs.
- The Edinburgh fixture must round-trip byte for byte. New model fields are optional, so nil is not
  encoded and the fixture doesn't change.
- Prompts: any wording change gets a new `version` in the front matter once guides have been built with
  it. Plan rules and `PlanChecker` use the same numbers; change both together.
- Use `rg` and `fd`, `uv run` for Python, `bun` for JavaScript.
- Explain results to the owner in plain language. Pick sensible defaults; ask only what is genuinely theirs
  to decide.

## Gotchas found so far

- `URLSession.AsyncBytes.lines` drops empty lines, and empty lines end server-sent events. Read the bytes and
  split them yourself (`StreamLines`).
- The ChatGPT plan route rejects `temperature`, `max_output_tokens`, `previous_response_id` and others (see
  `ResponsesRequest`). Web search needs `include: ["web_search_call.action.sources"]` to return sources.
  The models list is `GET https://api.openai.com/v1/models` with the access token (field `models[].slug`).
- Foursquare's top hit is often wrong (a road named like the venue). Use `PlaceMatcher` over all hits.
- Overpass can take about a minute. Never let it fail a guide.
- An empty id list makes an empty JSON Schema enum, which OpenAI rejects. The schema builders throw instead.

## Current state

See the M1 steps in `docs/PLAN.md`. M1 steps 1 and 2 are done. Next is step 3, prompt wiring.
