# TABA iOS app plan

The app is how the owner and their family use TABA: read a guide on the walk, share it, and (for the owner)
ask the server for a new one. This plan covers milestones M2 to M4 from `docs/PLAN.md` in buildable steps.
Each step has a "Done when" and is committed on its own, with a handoff after it (see `AGENTS.md`).

## Principles

- **The guide is the product.** Reading it on a phone while walking has to be calm, fast and offline.
  Building guides is a small, occasional flow next to it.
- **The model is GuideKit.** The app renders `Guide` exactly as the server produces it. No second model
  and no app-only copy of the data. Anything the app needs that the guide lacks is added to GuideKit.
- **Only the owner's phone talks to the server.** The server is reachable only over the owner's tailnet.
  Family get guides through iCloud sharing, so they need no Tailscale, no token and no server.
- **Free.** Apple frameworks only, plus GuideKit. No third-party SDKs, analytics or paid services.
- **Shown carefully.** A guide carries open questions, unknown hours and copy-review flags. The app shows
  them plainly instead of hiding them. "Check before you go" beats a confident mistake.

## Look

The hand-made guide is the reference: a field guide on paper. Warm paper and cream backgrounds, deep ink
text, wine, brick and gold accents, serif display type for titles, a clean sans for body text. In the app
that becomes:

- an asset-catalog palette with light and dark variants (dark mode is ink paper, not plain black);
- the system serif design (New York) for titles and the system font for body, so Dynamic Type works;
- Liquid Glass only where iOS puts it (tab bar, toolbars, sheets), not on content cards;
- SF Symbols for stop kinds (meal, sight, view, rest, logistics) and for walk legs.

## Shape

- Repo `taba-ios`, private, next to `taba-server` in `~/Desktop/Swift`. Xcode project, iOS 26, Swift 6.2
  language mode, strict concurrency, Swift Testing, SwiftUI with `@Observable` models.
- GuideKit by local path. Before M2 starts, GuideKit moves into its own package folder inside
  `taba-server` (`GuideKit/Package.swift`), and the server package depends on it by path. Otherwise the
  app would resolve the whole server dependency tree (Hummingbird, Postgres, NIO) just to read guides.
- Storage: each guide is its JSON file in Application Support, decoded with GuideKit. Personal state
  (ticked stops, notes) lives in a small separate store keyed by guide and stop id. No SwiftData:
  SwiftData's CloudKit sync can't share records, and M4 needs `CKShare`. `CKSyncEngine` takes over the
  state store in M4, so its records are designed for that from the start.
- Navigation: a library of trips, then a guide opens to tabs: **Days**, **Map**, **Lists**, **Notes**.

## M2: read and share guides

Built and tested against the Edinburgh fixture, bundled as sample data. No server needed.

1. **GuideKit as its own package, and the app skeleton.** Move GuideKit, keep the server building, and
   create the Xcode project with the palette, fonts, the sample guide, and the library screen listing
   stored guides (plus import of a `.json` guide file through the Files app).
   Done when: the server's four checks pass after the move, and the app runs in the simulator showing the
   sample trip in the library.
2. **Guide overview and days.** Hero (title, subtitle, dates, weather and light for the trip), then a day
   view: the day's title and summary, sunrise and sunset, and a timeline of stops with start times, how
   long each lasts, and the walk leg to the next stop. Flexible stops and rain alternatives are marked.
   A "today" mode during the trip scrolls to the next stop.
   Done when: every day of the sample reads correctly in the simulator, with Dynamic Type at the largest
   accessibility size and VoiceOver labels on every stop.
3. **Place detail.** Name, kind, tag and blurb, address, hours on the trip dates (with "unknown, check"
   shown plainly), price level, booking needed, facts with their sources, photo with its credit when
   there is one, and buttons for directions in Apple Maps, website and phone.
   Done when: every place in the sample opens and every source link resolves to its URL.
4. **Day map.** MapKit map of a day's stops in order, with the walking route between them from
   `MKDirections` (on device, free), the stay marked, and the selected stop linked to its timeline row.
   Real walking times from the map replace the straight-line estimates on screen, and a leg much longer
   than planned is flagged.
   Done when: each sample day shows a route, and tapping a pin and a timeline row select the same stop.
5. **Lists, tasting and notes.** The pick lists (eat, drink, photos, groceries), tasting items, practical
   notes, weather, light, backup plan, "rules of the trip", open questions and copy-review flags.
   Done when: nothing in the sample guide is unreachable from the app (a test walks the model and checks
   each section has a view).
6. **Offline and personal state.** Guides open with no network. Tick stops off and add a note per stop
   or place, stored in the state store. Map tiles need a connection; Apple Maps offline areas cover that,
   and the app says so once.
   Done when: the sample guide works in airplane mode in the simulator, and ticks and notes survive a
   relaunch.
7. **Export.** A self-contained HTML guide rendered by a template in GuideKit (Foundation-only, so the
   server can render the same file later) in the paper style, and a PDF made from that HTML on the phone.
   Both go out through the share sheet.
   Done when: the exported PDF and HTML of the sample open on a Mac and show every day, place and list.

## M3: make guides from the phone

Needs the server deployed (M1 step 6).

1. **Server connection.** Settings screen for the server address (default `https://travel.nanodev.uk`)
   and the app token, stored in the Keychain. A health check that explains the usual failure ("Is Tailscale
   on?"). A small API client in the app over URLSession, using the server's JSON types from GuideKit.
   Done when: the app reaches the deployed server over the tailnet, and a wrong token or Tailscale off each
   give a clear message.
2. **New trip form.** Destination, dates (at most 14 days), optional stay, pace, interests, daily spend,
   party and mobility notes. Validation matches the server's `TripBuildInput`, so a bad form never
   reaches it. (The server input grows to accept pace, interests and the rest. That's a server change done
   in the same step.)
   Done when: a submitted trip appears on the server and in the app's library as "building".
3. **Live progress.** The server's SSE stream drives a progress view of the seven stages, resumes after
   the app is backgrounded or the network drops, and shows the finished guide with its review flags.
   Done when: a real build can be followed from start to finish, including one interruption.
4. **Done notification.** A local notification when the app sees the build finish. Remote push needs an
   APNs key from the owner's developer account and a server change, so it comes only if local
   notifications prove not to be enough.
   Done when: backgrounding the app during a build still ends with a notification.
5. **TestFlight.** Archive, upload and install on the owner's phone.
   Done when: the owner builds a real guide on their phone through TestFlight.

## M4: family and a living guide

1. **Family sharing.** The owner shares a trip through iCloud (`CKShare`, `CKSyncEngine`). Family see the
   guide and share ticks and notes. Only the owner can rebuild it.
2. **Edit a day.** Swap, move or drop a stop, then re-check it with `PlanChecker` on the phone. Rewriting
   the words goes to the server.
3. **Ticket import.** Train, flight and booking confirmations read on the phone with Apple's on-device
   model (`Prompts/ticket.md`) to fill the trip's anchors.
4. **Re-check before the trip.** Three days before, the server re-checks hours, weather and closures and
   flags what changed.
5. **Rain swaps.** On a rainy day, offer each outdoor stop's rain alternative in one tap.

## Not planned

Accounts, App Store release, ads, analytics, Android, and a web app.
