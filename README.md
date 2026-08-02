# Doodleoop (iOS)

Local multiplayer pictorial Chinese whispers — draw a category, pass left, guess, draw the guess, repeat until every pad has looped the table, then reveal.

## Architecture

Same shape as Empires:

**Views → GameSession intents → (host) GameEngine → syncState → joiners**

Shared local-play infrastructure lives in [`Packages/PartyPlayKit`](Packages/PartyPlayKit): Multipeer transport, device identity, seat/handoff models.

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

Reusable by Empires and Doodleoop. Path dependency today; can become its own repo later.

| API | Role |
|-----|------|
| `MultipeerTransport` | Advertise / browse / send `Codable` or `Data` |
| `DeviceIdentity` | Persisted phone id |
| `SeatPlayer` / `SeatHandoff` | Multi-seat on one device |
