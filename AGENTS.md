# AGENTS.md

Instructions for coding agents working on TABA.

## Start of every session

1. Read this file.
2. Read `private/HANDOFF.md` if it exists (gitignored, never commit `private/`): *Now* and *Next*. Do the task
   under *Next* unless the owner says otherwise.
3. Run `git status` and `git log --oneline -5`; if they disagree with *Now*, fix the handoff first.

Then read nothing else up front. Use "Where to look" below. For any doc over 3,000 words, list its headings
first (`rg -n '^#' <file>`) and read one section (`docs/PLAN.md` is over that). Never read `docs/history/`
unless asked about a past decision.

## Where to look

| Task touches | Read |
|---|---|
| What TABA is, the pipeline, providers | `docs/PLAN.md` "Shape", "How a guide is built", "Providers" |
| Anything AI-related (prompts, schemas, versions) | `Prompts/README.md`, before touching it |
| A guide-quality step (Q1-Q23 and next) | `docs/PLAN.md` "Guide quality fixes", that row only |
| An M1 step or a past decision on the plan | `docs/PLAN.md` "M1 steps", "Decisions already made" |
| The HTTP API, configuration, jobs, deploy | `docs/SERVER.md`, the matching section |
| Scoring guides, evaluation runs | `Evaluation/README.md` |
| The iOS app (plan and design) | The private `taba-ios` repo next to this one: `../taba-ios/AGENTS.md`. GuideKit stays here |
| Past decisions only | `docs/history/README.md` |

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
- ChatGPT credentials: `~/.config/taba/chatgpt.json`, written by `swift run taba-chatgpt sign-in` (the owner
  logs in in their browser). Never use an OpenAI API key automatically.
- Everything stays free. Never call paid APIs (paid place data, OpenAI API key billing, image
  generation) without the owner's explicit yes.
- Ask the owner before any batch of test builds: they cost no money but count toward the ChatGPT plan's usage
  limits.
- Deploy a new image to the VPS only with the owner's yes.
- Free APIs still get polite use: Nominatim at most 1 request per second with a real User-Agent; Overpass
  one query at a time.

## Layout

| Path | What |
|---|---|
| `GuideKit/` | Nested package: shared model (`Guide`, places, plan, bookings, AI outputs), `PlanChecker`, `SunTimes`, `JSONSchema` builders, `GuideAssembler`. Foundation only, must build on Linux; the iOS app depends on it by path |
| `Sources/ResponsesKit`, `Sources/TabaChatGPT` | Sign in with ChatGPT (PKCE, ID-token verification), credentials, Responses API streaming client; `taba-chatgpt sign-in` and `taba-chatgpt probe --model <slug>` |
| `Sources/SourcesKit`, `Sources/SourcesProbe` | Data sources: place matching, OSM hours, weather, geocoding; `taba-sources-probe` |
| `Prompts/` | The AI prompts, versioned with front matter. See `Prompts/README.md` |
| `Tests/` | Swift Testing. `GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json` is the benchmark trip |
| `scripts/` | `privacy-scan.sh`, `hooks/pre-commit` |
| `Evaluation/` | Test scenarios and the gitignored runs; see `Evaluation/README.md` |
| `docs/PLAN.md` | The plan and roadmap |
| `docs/SERVER.md` | The server: API, configuration, jobs, deploy |
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
- A name search's top hit is often wrong (a road named like the venue). Compare names with `NameTokens` over all hits.
- Overpass can take about a minute. Never let it fail a guide.
- An empty id list makes an empty JSON Schema enum, which OpenAI rejects. The schema builders throw instead.

## Handoff routine (do this without being asked)

Work may move between agents and tools at any time: Claude Code, Pi, or another session. The handoff keeps
the next agent from starting cold. Update it at every one of these moments, without waiting to be asked:

- when a step from `docs/PLAN.md` is finished and committed;
- before you stop for any reason: the owner ends the session, your context or budget is running low, or you
  are blocked on the owner;
- after any change outside this repo, such as the VPS, DNS, Keychain or credentials.

What to update:

1. **`docs/PLAN.md`:** mark the step done and add one line on anything learned that changes later steps.
   Public, so no personal or infrastructure details.
2. **`AGENTS.md`, "Current state" below:** at most 3 lines: the live image, the default model and pointers.
   History goes to the handoff Log. Public, so no personal or infrastructure details.
3. **`private/HANDOFF.md`** (gitignored, never committed). Keep it within its caps: `Now` at most 8 bullets,
   `Next` at most 5, `Log` the 10 newest entries of at most 3 lines, at most 1,500 words. Older entries go to
   `private/history/handoff-log.md`. Infrastructure details live in `private/INFRA.md`.
   - `Now`: what is finished, what is in progress, and the exact state of the working tree (uncommitted
     files, branches, worktrees, local commits not yet pushed).
   - `Next`: the next step from the plan, the first concrete actions, and anything to check first.
   - `Waiting on the owner`: questions or actions only the owner can take.
   - `Log`: add a dated entry (newest first): what was done, commit hashes, and decisions with the reason.
4. Commit the public doc changes, `docs: update handoff after <step>`. Never commit `private/`.

A handoff is good when a new agent can read `AGENTS.md` and the handoff's *Now* and *Next* and continue.

## Current state

Live image `taba-server:q23b` (2026-11-19), default model `gpt-6.2-sol`. Guide-quality fixes Q1-Q20 and Q23
are deployed; Q21 and Q22 are planned (rows in `docs/PLAN.md` "Guide quality fixes"). Next steps: the handoff's
*Next*. Older deploy history: `docs/history/2026-11-28-agents-current-state.md`.
