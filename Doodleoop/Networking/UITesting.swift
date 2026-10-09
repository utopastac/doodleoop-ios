import Foundation

/// Launch-argument helpers for UI tests and App Store screenshot capture.
///
/// Enable with `-UITesting`. Optionally pass `-UITScene <name>` to open a
/// marketing frame without flaky UI navigation:
/// - `01-home` — branded home (seeded avatar)
/// - `02-lobby` — host lobby with nearby seats
/// - `03-drawing` — first draw turn (category)
/// - `04-guessing` — guess the drawing in front of you
/// - `05-reveal` — pad reveal journey
/// - `06-round-over` — loop complete
/// - `07-reconnect` — joiner reconnect overlay
/// - `08-host-migration` — host-migration overlay
/// - `09-handoff` — pass-the-phone handoff overlay
/// - `10-history` — history list with a seeded loop
enum UITesting {
  static let argument = "-UITesting"
  static let sceneArgument = "-UITScene"

  static var isEnabled: Bool {
    isEnabled(arguments: ProcessInfo.processInfo.arguments)
  }

  /// Screenshot / UI-test scene name, if provided after `-UITScene`.
  static var scene: String? {
    scene(from: ProcessInfo.processInfo.arguments)
  }

  static var parsedScene: Scene? {
    parsedScene(from: ProcessInfo.processInfo.arguments)
  }

  enum Scene: String, CaseIterable {
    case home = "01-home"
    case lobby = "02-lobby"
    case drawing = "03-drawing"
    case guessing = "04-guessing"
    case reveal = "05-reveal"
    case roundOver = "06-round-over"
    case reconnect = "07-reconnect"
    case hostMigration = "08-host-migration"
    case handoff = "09-handoff"
    case history = "10-history"
  }

  static func isEnabled(arguments: [String]) -> Bool {
    arguments.contains(argument)
  }

  static func scene(from arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: sceneArgument),
          arguments.index(after: index) < arguments.endIndex
    else { return nil }
    let value = arguments[arguments.index(after: index)]
    return value.hasPrefix("-") ? nil : value
  }

  static func parsedScene(from arguments: [String]) -> Scene? {
    scene(from: arguments).flatMap(Scene.init(rawValue:))
  }

  /// Maps a UIT scene to the existing `ViewPreview` fixture, if any.
  /// Home / history stay on idle home (history opens its own sheet).
  static var viewPreview: ViewPreview? {
    viewPreview(for: parsedScene)
  }

  static func viewPreview(for scene: Scene?) -> ViewPreview? {
    switch scene {
    case .home, .history, .none:
      nil
    case .lobby:
      .lobbyNearbyHost
    case .drawing:
      .drawing
    case .guessing:
      .guessing
    case .reveal:
      .reveal
    case .roundOver:
      .roundOver
    case .reconnect:
      .reconnecting
    case .hostMigration:
      .hostMigration
    case .handoff:
      .handoffOverlay
    }
  }

  /// Quiet prefs + a deterministic avatar/name before `GameSession` init.
  /// Uses the same UserDefaults keys as `GameSession` (string literals so this
  /// stays callable from `App.init` without hopping onto the main actor).
  static func preparePreferences() {
    guard isEnabled else { return }

    let defaults = UserDefaults.standard
    defaults.set("Blake", forKey: "displayName")
    defaults.set(PaperStyle.plain.rawValue, forKey: PaperStyle.storageKey)
    defaults.set(RevealStyle.fade.rawValue, forKey: RevealStyle.storageKey)

    let avatar = PreviewStateFactory.demoDrawing(seed: 7)
    if let data = try? JSONEncoder().encode(avatar) {
      defaults.set(data, forKey: "doodleoop.avatar")
    }
  }

  /// Seeds one finished loop so history UI tests aren't empty.
  @MainActor
  static func seedDemoHistory(into store: GameHistoryStore) {
    guard isEnabled, parsedScene == .history else { return }
    guard store.games.isEmpty else { return }

    let deviceId = DeviceIdentity.current()
    let avatar = PreviewStateFactory.demoDrawing(seed: 7)
    let state = PreviewStateFactory.roundOverState(
      devicePlayerId: deviceId,
      displayName: "Blake",
      avatar: avatar,
      now: Date(timeIntervalSince1970: 1_775_577_600) // fixed for stable timestamps
    )
    _ = store.saveIfNeeded(from: state, completedAt: Date(timeIntervalSince1970: 1_775_577_600))
  }
}
