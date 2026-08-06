# Agent guide — Doodleoop iOS

## Where truth lives

| Concern | Edit here | Do not |
|---------|-----------|--------|
| Game rules / phases | `Doodleoop/Models/GameEngine.swift` | Put rules in views or session timers |
| Domain state | `Doodleoop/Models/GameModels.swift` | Mix networking enums into UI |
| Completed-round history | `Doodleoop/Models/SavedGame.swift` + `GameHistoryStore.swift` | Put file I/O in views |
| Sync, seats, handoffs, local network | `Doodleoop/Networking/GameSession.swift` (+ `NetworkPartyTransport`) | Duplicate host/joiner apply paths |
| Wire protocol | `Doodleoop/Networking/NetworkMessage.swift` | Redefine messages in models |
| UI / screens | `Doodleoop/Views/*.swift` | Call Network.framework or mutate `GameState` directly |

Flow: **Views → GameSession intents → (host) GameEngine → syncState → joiners**.

## Multi-seat

Pass-and-play = multiple `Player` seats share one `deviceId`. Handoff overlay is local only.

## Round loop

1. Host sets a **category**
2. Everyone **draws** it (turn 0)
3. Pads pass **left**; everyone **guesses** the drawing in front of them
4. Pads pass left; everyone **draws** that guess
5. Alternate draw / guess until each seat has **drawn on every pad** (capped by lobby draw cap) → **reveal** each pad’s journey one step at a time (synced on all phones), then the next pad

## IDs

- `deviceId` / `devicePlayerId` — phone identity (`DeviceIdentity`)
- `localPlayerId` — active seat on this phone
- `hostId` — lobby creator seat
- Pad `id` — starter seat for that chain

## Icons (Phosphor)

- Use **Phosphor Icons, regular weight only**.
- **Only add the glyphs we need** — do not vendor the full set.
- Catalog entries live under `Doodleoop/Assets.xcassets/Icon*.imageset` as template SVGs; names are mapped in `Doodleoop/Theme/PhosphorIcon.swift`.
- When a screen needs a new icon: pull that single regular SVG from [`phosphor-icons/core`](https://github.com/phosphor-icons/core) (`assets/regular/<name>.svg`), add an imageset with `template-rendering-intent`, and extend `PhosphorIcon`.

## Leaving a game

- In-game screens (host/joiner) show a global **leave** control via `.leaveGameChrome()` on `ContentView`’s game flow — Phosphor `sign-out`, top trailing. Lobby, reveal and round-over use `LeaveToolbarBand` for the same control in a 40pt toolbar band instead of the overlay.
- Confirm with the dialog in `LeaveGameButton` before calling `session.leaveGame()`.
- Top-row content that sits on the trailing edge (drawing / guessing / reveal) should pad with `Theme.Sizing.leaveButtonReserve` so it doesn’t collide with the chrome.
- Host leave broadcasts `.sessionEnded` before disconnect; joiners also exit if the host link drops for good.
- Mid-round disconnects mark the device `absentDeviceIds` and auto-fill empty submissions so the round can advance; seats are dropped on return to lobby.
- Failed joins stay on the browse lobby with `joinStatus` — don’t eject to home. Host-drop / session-ended show `SessionAlert` on home. Departures set `statusBanner` for the host.
- Brief link drops use a **~15s grace** before absent/leave. Host stays discoverable mid-round so known devices can reconnect (Bonjour + `.hello` with `deviceId`); returning devices clear `absentDeviceIds` and get a full sync. If the host never returns, remaining phones **elect a new network host** (`roomId` / `stateEpoch` / `networkHostDeviceId` on `GameState`), advertise, and continue. `ContentView` forwards `scenePhase` into `handleLifecycle` for reconnect + a stay-in-app tip. Joiners see `ReconnectOverlay` / `HostMigrationOverlay`; hosts see `ConnectionPresenceStrip` while someone is reconnecting or absent.
- **Simulator multi-instance testing**: Bonjour between Simulator apps is unreliable. `NetworkPartyTransport` uses a Mac-shared file bridge (`~/Library/Caches/doodleoop-sim-ports/`) and loopback TCP (`127.0.0.1`) when `targetEnvironment(simulator)`. Real devices keep Bonjour + `includePeerToPeer`.
- Info.plist must keep `NSLocalNetworkUsageDescription` and `NSBonjourServices` for `_doodleoop-game._tcp` / `._udp`.

## Sheets

- A sheet that draws its **own header bar** (title + `[ DONE ]` band, as on Settings) must inset it with `.sheetHeaderInset()` — at least 24pt, so the bar and its grid rail clear the sheet's rounded top edge.
- Sheets that use a system `NavigationStack` toolbar instead don't need it; the nav bar insets itself.

## Drawing canvas

- The in-game drawing surface stays a **square** (`aspectRatio(1)`). Do not stretch it to fill arbitrary aspect ratios.
- Read-only drawings use `ZoomableDrawingView` (guessing / reveal / history) — an Instagram-style **peek zoom**: pinch to magnify, release springs back to 100%. `ReadOnlyDrawingView` is the plain, non-interactive variant used for thumbnails.
- Peek zoom keeps everything in `@GestureState` so it resets itself when the fingers lift — don't reintroduce persistent zoom/pan `@State`.
- A pinch is mirrored into `DrawingZoomLayer` and drawn above the whole screen, so it escapes the scroll view's clip. Every screen root needs `.drawingZoomLayer()` — **including sheets**, which present outside their parent's view tree.
- Stroke replay (reveal `Draw` setting) is applied to the `GraphicsContext` inside `Canvas`, so a partly-drawn stroke tapers like a live one.

## Game history

- When a round hits `.roundOver`, each device saves the full pads + players locally via `GameHistoryStore` (Application Support JSON).
- Browse from **History** on `HomeView` — every seat’s drawing book is available offline on that phone.
- Dedupes by content fingerprint so repeated `syncState` of the same round does not create duplicates.