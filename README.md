# TABA ("There and Back Again")

TABA turns a destination, dates and a budget into a walking field guide: a day-by-day plan of places to see, eat and drink, with opening hours, sun times and practical notes.

This is a personal project. It is not a product, and it is not accepting contributions.

## Layout

- `Sources/GuideKit`: the shared data model and plan checks. Uses only Foundation APIs that also exist on Linux, so the backend can run it.
- `Tests/GuideKitTests`: Swift Testing tests.

## Requirements

- Xcode with Swift 6.2 or later (developed with Swift 6.4)
- macOS 26 or later for the Apple platform targets

## Build and test

```sh
swift build
swift test
swiftlint lint --quiet
```

API keys and tokens are read from environment variables at runtime. They are never stored in this repository.

## Privacy

This repository is public, so secrets and personal trip data never go in it. After cloning, enable the pre-commit scan:

```sh
git config core.hooksPath scripts/hooks
```

`scripts/privacy-scan.sh --staged` runs on every commit. Run `scripts/privacy-scan.sh --all` before pushing.
