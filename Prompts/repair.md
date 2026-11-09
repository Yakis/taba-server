---
id: repair
version: 2
role: message
output: PlanDraft
effort: high
---

The plan you returned has been checked by code against the real opening hours, measured walking times, daylight
and the trip's fixed times. The problems it found are in `issues` below. The planning instructions and their
priority order still apply.

- Each issue has `severity` (`error`, `warning` or `info`), `kind`, `date`, `stopId` (or `null`) and `message`.
  Times and distances in messages were measured by code. Trust them over your own estimates.
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

Return the full plan, with every day, as the same JSON schema. In `changes`, describe each change in one plain
sentence, for example: "Moved d2-s4 from 15:10 to 14:40 so it ends before sunset."
