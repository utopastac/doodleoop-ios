# Agent guide — Doodleoop iOS

## Where truth lives

| Concern | Edit here | Do not |
|---------|-----------|--------|
| Game rules / phases | `Doodleoop/Models/GameEngine.swift` | Put rules in views or session timers |
| Domain state | `Doodleoop/Models/GameModels.swift` | Mix networking enums into UI |
| Sync, seats, handoffs, Multipeer | `Doodleoop/Networking/GameSession.swift` (+ transport helpers) | Duplicate host/joiner apply paths |
| Wire protocol | `Doodleoop/Networking/NetworkMessage.swift` | Redefine messages in models |
| UI / screens | `Doodleoop/Views/*.swift` | Call Multipeer or mutate `GameState` directly |

Flow: **Views → GameSession intents → (host) GameEngine → syncState → joiners**.

## Multi-seat

Pass-and-play = multiple `Player` seats share one `deviceId`. Handoff overlay is local only.

## Round loop

1. Host sets a **category**
2. Everyone **draws** it (turn 0)
3. Pads pass **left**; everyone **guesses** the drawing in front of them
4. Pads pass left; everyone **draws** that guess
5. Alternate until each pad has `playerCount` contributions → **reveal** each pad’s chain

## IDs

- `deviceId` / `devicePlayerId` — phone identity (`DeviceIdentity`)
- `localPlayerId` — active seat on this phone
- `hostId` — lobby creator seat
- Pad `id` — starter seat for that chain
