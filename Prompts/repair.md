---
id: repair
version: 4
role: message
output: PlanDraft
effort: high
---

The plan you returned has been checked by code against the real opening hours, measured walking times, daylight
and the trip's fixed times. The problems it found are in `issues` below. The planning instructions and their
priority order still apply.

- Each issue has `severity` (`error`, `warning` or `info`), `kind`, `date`, `stopId` (or `null`) and `message`.
  Times and distances in messages were measured by code. Trust them over your own estimates.
- An issue of kind `stayContradiction` means a stop or an open question contradicts what the traveller arranged
  in `anchors`, such as a hotel on a trip with no stay. Remove that stop or question; don't reword it.
- `legs` gives the measured minutes and the mode (`walk`, or `transit` for a bus or taxi ride) between consecutive
  stops in your plan. Use them instead of `areaTravelMinutes` for stops that stay where they are.

What to do:

1. Fix every `error`.
2. Fix each `warning` you can without causing an error.
3. Leave `info` alone unless fixing it costs nothing.
4. Change as little as you can. A day with no issues comes back exactly as it was.
5. Keep every stop's id. A new stop gets the next unused number on its day, even if that puts ids out of
   time order. Code renumbers them later.
6. Move a stop in time before you replace its place. Replace a place only when no move fixes the issue.
7. If an issue can't be fixed without breaking a stronger rule, leave it and explain it in `openQuestions`.

Preference issues come from the interests, pace and spend rules. `topInterestOutweighed` means a lower-ranked
interest has more main-stop time than the top one: swap one stop of that lower interest for a nearby candidate
that serves the top interest. `interestDominates` means one interest takes over half the main-stop time: swap one
stop of it for a nearby candidate serving the next interest. `drinkHeavyDay` means more than two drink stops: turn
the extra drink into a sight nearby, or drop it. `mainStopsOverPace` means too many main stops: drop the weakest
main stop rather than squeezing the times. `startsBeforePace` means the first main stop is too early: move it
later. `restMissing` means a full day has no rest of 45 minutes: add one in the afternoon. `overSpend` means a
meal or drink above the ceiling: swap it for a candidate within the ceiling, and keep it only if none fits, saying
so in `openQuestions`. Fix each of these without breaking an error, a booked time or the opening hours. A
`mainStopsUnderPace` issue is info: leave it alone.

Return the full plan, with every day, as the same JSON schema. In `changes`, describe each change in one plain
sentence, for example: "Moved d2-s4 from 15:10 to 14:40 so it ends before sunset."
