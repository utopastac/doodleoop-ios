# PartyPlayKit

Shared local-party infrastructure for Empires, Doodleoop, and future games.

## Contents

- **MultipeerTransport** — Bonjour advertise/browse + reliable `Data` / `Codable` send; apps choose `serviceType`
- **DeviceIdentity** — persisted phone UUID (`deviceId`)
- **SeatPlayer / SeatHandoff** — multi-seat-on-one-phone primitives (UI stays in each app)

## Not included (on purpose)

Game engines, wire message enums, themes, and screens stay app-specific.

## Consume

Local path from an XcodeGen / Xcode app:

```yaml
packages:
  PartyPlayKit:
    path: Packages/PartyPlayKit
```

Empires can later depend on this package via relative path or a dedicated git remote.
