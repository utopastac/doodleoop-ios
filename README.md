# Doodleoop (iOS)

Local multiplayer pictorial Chinese whispers — draw a category, pass left, guess, draw the guess, repeat until every pad has looped the table, then reveal.

## Architecture

Same shape as Empires:

**Views → GameSession intents → (host) GameEngine → syncState → joiners**

Shared local-play infrastructure lives in sibling [`party-play-kit`](https://github.com/utopastac/party-play-kit) (`../party-play-kit`): Multipeer transport, device identity, seat/handoff models. Empires uses the same package.

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
xcodebuild test -project Doodleoop.xcodeproj -scheme Doodleoop -destination 'platform=iOS Simulator,name=iPhone 17'
```

## PartyPlayKit

Shared with Empires via path `../party-play-kit` ([repo](https://github.com/utopastac/party-play-kit)).

| API | Role |
|-----|------|
| `MultipeerTransport` | Advertise / browse / send `Codable` or `Data` |
| `DeviceIdentity` | Persisted phone id |
| `SeatPlayer` / `SeatHandoff` | Multi-seat on one device |
