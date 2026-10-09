# Doodleoop (iOS)

Local multiplayer pictorial Chinese whispers — draw a category, pass left, guess, draw the guess, repeat until every pad has looped the table, then reveal.

## Architecture

Same shape as Empires:

**Views → GameSession intents → (host) GameEngine → syncState → joiners**

Multipeer transport and seat handoff helpers live in `Doodleoop/Networking/` (not a shared package — keeps Xcode simple while the games diverge).

## Requirements

- iOS 18+
- Xcode 16+
- Physical devices on the same Wi‑Fi / Personal Hotspot work best

## Open & run

```bash
cd doodleoop-ios
xcodegen generate   # if project.yml changed
open Doodleoop.xcodeproj
```

## Tests

```bash
xcodebuild test -project Doodleoop.xcodeproj -scheme Doodleoop \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# Crash smoke (UI process survival)
xcodebuild test -project Doodleoop.xcodeproj -scheme Doodleoop \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:DoodleoopUITests/CrashSmokeUITests

# App Store screenshots
fastlane screenshots
```

UI crash smoke lives in `DoodleoopUITests/CrashSmokeUITests` (seeded `-UITesting` scenes).
Launch args `-UITesting` / `-UITScene` seed `ViewPreview` fixtures (lobby, drawing,
guessing, reveal, round-over). See [`docs/TESTING.md`](docs/TESTING.md).

## Release

Ship checklist, ASC metadata, and review notes: [`docs/RELEASE.md`](docs/RELEASE.md).
