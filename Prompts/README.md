# TABA prompts

These are the instructions TABA gives the AI when it builds a guide. They shape the result more than any other
text in the project, so they are versioned, reviewed like code and measured against the Edinburgh test trip.

## Where each prompt runs

| Pipeline step | File | Runs on | The AI's job | Returns |
|---|---|---|---|---|
| 1. Read a ticket | `ticket.md` | iPhone, on device | Pull the journey or stay out of ticket text | `TicketBooking` list |
| 5. Look up what's on | `research.md` | server | Find time-bound facts for the exact dates, with sources | `ResearchResult` |
| 6. Plan the days | `plan.md` | server | Choose and time stops from the candidate list | `PlanDraft` |
| 7. Fix the plan | `repair.md` | server | Fix what the code checks found, changing as little as possible | `PlanDraft` |
| 8. Write it up | `write.md` | server | Write every word, in the trip's voice, from the facts given | `GuideCopy` |

Everything else is code: places, walking times, sun times, weather, checks, assembly.

## Design rules

0. **The trip's facts outrank the words.** What the traveller arranged (dates, times, how they travel, whether
   and where they stay, their bags) is a typed fact that code sets once and passes in as `anchors`. Missing
   information stays unknown: code never invents a stay, a station, check-in times or opening hours to fill a
   gap, and checks every answer, including the finished guide, against the facts.

1. **The AI chooses and writes. Code measures and checks.** The AI never works out walking times, sunsets,
   totals or opening hours. Code works them out first, passes them in, and checks the answer. If code can do
   it, code does it.
2. **The AI only picks from what it is given.** Plans use candidate place ids. Copy uses only the facts
   provided. New places come back from research as suggestions, which code looks up before anything can use
   them.
3. **Planning and writing are separate calls.** The plan has no prose, only a short `reason` for each stop.
   The writer gets the checked plan and writes everything. A repair never rewrites prose, and a change of voice
   never moves a stop. `PlanDraft` holds the plan and `GuideCopy` holds the prose.
4. **Instructions are fixed. Trip data goes in the input.** Each file's text is sent unchanged as the request's
   `instructions`, with no trip data in it, so the provider can cache it. Everything about the trip is one JSON
   object in the input message.
5. **Third-party text is fenced off.** Anything written by websites, reviewers or providers sits under a key
   named `external`, and every prompt says it is information, never instructions.
6. **Strict outputs.** Every server call returns JSON matching a strict schema: every key required, `null`
   where a value doesn't apply, no extra keys.
7. **Hard rules first.** Rules are ordered: hard constraints, then quality, then taste. When rules conflict,
   the earlier one wins and the AI says what it gave up in `openQuestions`.

## Packaging and pipeline wiring

The reviewed files remain in the root `Prompts/` directory. SwiftPM copies that directory as a `PipelineKit`
resource, and `PromptLibrary` loads the bundled files rather than maintaining separate copies. `PipelineKit`
provides prompt loading, area clustering, input builders, request construction and copy checks; the complete
server pipeline is still in progress.

## Request shape (Responses API, ChatGPT plan route)

- `instructions`: the file's text below its front matter.
- `input`: one user message holding the step's JSON input.
- `text.format`: a strict JSON schema for the output.
- `store: false` and `stream: true`. No `temperature`, `max_output_tokens` or `prompt_cache_retention`, which
  the plan route rejects. Effort comes from the front matter.
- Research also sends the `web_search` tool, and asks for the search sources in the response. No other step
  sends tools.
- A repair keeps `plan.md` as its instructions, so the cached prefix stays the same. The input grows to: the
  original user message, the previous plan as an assistant message, then a user message made of `repair.md`'s
  text followed by the issues JSON. Repair requests default to the repair prompt's effort; initial plan
  requests use the plan prompt's effort. There are at most two repair rounds.

## What code checks on every answer

The prompts ask for good behaviour. Code makes sure of it:

| Answer | Check | On failure |
|---|---|---|
| Any | Decodes against the schema | Retry once, then fail the step |
| Research | Each finding's URL is among the search sources the response reports | Drop the finding |
| Research | Suggested places resolve through the places provider | Drop the suggestion |
| Plan | Every place id is a candidate | Treated as an error and sent to repair |
| Plan | `PlanChecker`: hours, gaps, walks, meals, daylight, logistics, pace | Errors and warnings sent to repair |
| Plan | Stops and open questions against what the traveller arranged (`Guide.contradictions`): no hotel, check-in or accommodation talk without a booked stay, no check-in or check-out on a one-day trip | Error, sent to repair |
| Plan | Pick-list places fit their list (`eat`, `drink`, `photos`, `groceries`) | Warning, sent to repair |
| Copy | Every day, stop, place and list id is present, and no others | Retry once |
| Copy | Every time, date, price and number in the text appears in the input | Flag the sentence for review |
| Copy | Banned phrases, emoji, exclamation marks, word limits | Retry the affected items once |
| Copy | Opening hours and walk minutes in stop bodies, day summaries and blurbs; plan talk; station, train, flight or airport words without a matching booking or travel mode | Retry the affected sentences once, then flag them for review |
| Copy | Every word the guide shows against what the traveller arranged (`Guide.contradictions`) | Retry once, then fail the step: facts win over prose |
| Finished guide | `Guide.contradictions` again, after assembly | Fail the build |

## Versions

Each file starts with front matter: `id`, `version`, `role` (`instructions` or `message`), `output` and
`effort`. The server config picks the model. The backend stores each prompt's id and version with every guide
it builds, so a bad guide can be traced to the prompts that made it. Any change to the wording means a new
version.

## How prompts are judged

The Edinburgh test trip (`GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json`) is the benchmark. For each
prompt version and model, the Milestone 1 bake-off records:

- plan-check errors and warnings on the first answer, and after repair;
- repair rounds needed (the target is none; the limit is two);
- meals covered, daylight kept, buffer before the train, rain alternatives present;
- walking per day against the pace;
- for copy: unsourced numbers (target zero), banned phrases and broken limits;
- a human read: does it sound like the Edinburgh guide, and would you follow it?
