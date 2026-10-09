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
enum UITesting {
  static let argument = "-UITesting"
  static let sceneArgument = "-UITScene"

  static var isEnabled: Bool {
    ProcessInfo.processInfo.arguments.contains(argument)
  }

  /// Screenshot / UI-test scene name, if provided after `-UITScene`.
  static var scene: String? {
    let args = ProcessInfo.processInfo.arguments
    guard let index = args.firstIndex(of: sceneArgument),
          args.index(after: index) < args.endIndex
    else { return nil }
    let value = args[args.index(after: index)]
    return value.hasPrefix("-") ? nil : value
  }

  static var parsedScene: Scene? {
    scene.flatMap(Scene.init(rawValue:))
  }

  enum Scene: String {
    case home = "01-home"
    case lobby = "02-lobby"
    case drawing = "03-drawing"
    case guessing = "04-guessing"
    case reveal = "05-reveal"
    case roundOver = "06-round-over"
  }

  /// Maps a UIT scene to the existing `ViewPreview` fixture, if any.
  /// Home stays on the idle `HomeView` (no preview load).
  static var viewPreview: ViewPreview? {
    switch parsedScene {
    case .home, .none:
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
}
