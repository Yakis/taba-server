# Guide evaluation

A way to measure whether a change to the pipeline makes guides better, without asking a model to judge them.
Everything here is deterministic: `taba-score` reads a finished guide (JSON) and counts things about it.

- `Sources/GuideScoreKit` holds the scorer, the comparison and the build runner. `Sources/TabaScore` is the command.
- `Evaluation/scenarios` holds 11 fixed test trips. Each one builds a guide on a server.
- `Evaluation/runs/<label>` holds the guides from one set of builds. It is gitignored, because live guides are not committed.

## What the scorer measures

`swift run taba-score report <guide.json>` prints these, and `--json` gives every number:

- **Constraints:** contradictions between the words and the facts, whether the structure is valid, the plan
  checker's findings by severity and kind, stops before arrival or after departure, the stay and the base.
- **Interests:** each interest in rank order, with its main stops, meal stops, minutes and share of main-stop
  minutes, and its earliest start. Also whether higher-ranked interests got more minutes (`rankAgreement`), the
  largest share (`topShare`) and the interests no stop serves (`missed`). Stops serve an interest from the place's
  recorded `interests` when the guide has them, and from the place's kind otherwise.
- **Pace:** for each day, main stops, first main stop, walking minutes, rest stops, unplanned minutes, and whether the
  main-stop count and walking meet the pace table in the planning prompt. Arrival and departure days are not judged.
- **Spend:** the price level of each meal, drink and sight, against the ceiling for the daily spend (low 2,
  moderate 3, high none).
- **Feasibility:** stops with unknown opening hours, closed or outside-hours findings, stop lengths out of range, legs
  over 30 minutes, and when each day starts and ends.
- **Content:** generic tasting names, the number of facts and open questions, three-word phrases repeated across
  stop texts, long stop texts and empty notes.
- **Consistency:** pick-list and stop places that are missing, places in a pick list of the wrong kind, places nothing
  shows, and practical facts whose source is missing.

## Commands

```sh
swift run taba-score report <guide.json>            # one guide, as text
swift run taba-score report <guide.json> --json     # every number, as JSON
swift run taba-score compare <a.json> <b.json>      # overlap of the plans, and minutes per interest
swift run taba-score summary <folder>               # scores every guide in the folder into scores.json, and prints a table
```

The Edinburgh benchmark guide, which the tests also use, is at `GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-guide.json`.

## Building the scenarios

The build needs the owner's server address and the app token. Each build takes about 10 minutes of the AI model, and
the runner builds two trips at a time, so all 11 take about an hour. Set the token in the environment only; the
command never prints it:

```sh
export TABA_TOKEN='...'   # the app token
swift run taba-score build --server https://<server> --scenarios Evaluation/scenarios --out Evaluation/runs/<label>
```

The runner posts each scenario with its dates moved to `startInDays` after today, keeping the trip's length. It waits
while the server is busy, polls each trip every 15 seconds, and saves each finished guide as
`Evaluation/runs/<label>/<scenario>.json`.

The scenarios are:

| Name | What it tests |
|---|---|
| `one-day-train` | A one-day trip with a train and no stay |
| `two-nights-booked` | A named hotel for two nights |
| `three-days-no-stay` | Three days with no stay named |
| `food-markets`, `photography`, `low-spend`, `spread-out` | Interests and spend on their own |
| `relaxed`, `packed` | The same trip at two paces |
| `rank-a`, `rank-b` | The same trip with its interests in another order |

## Comparing two pipeline versions

1. Build the scenarios with the old version into `Evaluation/runs/before`, and with the new version into
   `Evaluation/runs/after`. Use the same server settings, so only the pipeline differs.
2. Score both folders: `swift run taba-score summary Evaluation/runs/before` and the same for `after`. Each
   folder gets a `scores.json`.
3. Compare the two `scores.json` files with `diff`, or read the two tables side by side.
4. For the rank test, run `swift run taba-score compare Evaluation/runs/<label>/rank-a.json Evaluation/runs/<label>/rank-b.json`.
   The plans should differ, and the minutes should move with the rank.

A single build is one sample. Judge a change on the numbers across all 11 scenarios, not on one guide.
