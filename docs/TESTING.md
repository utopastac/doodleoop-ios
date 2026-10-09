# Testing

## Running tests

```sh
xcodebuild -project Doodleoop.xcodeproj -scheme Doodleoop \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Or in Xcode: select the `Doodleoop` scheme, open the Test navigator (⌘6), and run
`DoodleoopTests` / `DoodleoopUITests`.

CI runs unit tests plus `CrashSmokeUITests` on every push and pull request to `main`
via [`.github/workflows/ci.yml`](../.github/workflows/ci.yml).

## Crash smoke (UI)

`DoodleoopUITests/CrashSmokeUITests.swift` launches the seeded `-UITesting` scenes and
taps the main crash surfaces (rules, settings, history, host game, lobby add/start/leave,
reveal advance, drawing leave). It asserts the process stays running — not pixel-perfect UI.

```sh
xcodebuild -project Doodleoop.xcodeproj -scheme Doodleoop \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:DoodleoopUITests/CrashSmokeUITests test
```

Or: `fastlane ui_smoke`

Screenshot capture (`ScreenshotTests` / `fastlane screenshots`) stays separate and is
not part of CI.

## App Store screenshots

Launch args `-UITesting` / `-UITScene` load deterministic `ViewPreview` fixtures via
`GameSession.loadPreview`, then flip an accessibility probe to `screenshot-ready`.

```sh
fastlane screenshots          # capture + frameit
fastlane frame                # re-frame existing captures
SKIP_FRAME=1 fastlane screenshots
fastlane sync_marketing       # → sibling doodloop-website/assets/screenshots
```

Scenes: `01-home`, `02-lobby`, `03-drawing`, `04-guessing`, `05-reveal`,
`06-round-over`.

## What's covered

`DoodleoopTests/` covers engine rules, session sync/leave/reconnect, history store, and
wire-protocol Codable — the code that determines *what the game should do*, independent
of SwiftUI layout.

## What's intentionally not covered

- **SwiftUI visual/layout fidelity** — crash smoke covers process survival; App Store
  screenshots cover marketing frames.
- **Live Bonjour peer networking** — preview / `-UITesting` paths use
  `PreviewStateFactory` fixtures without opening Network.framework sessions.
