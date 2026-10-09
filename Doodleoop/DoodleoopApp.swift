import SwiftUI

@main
struct DoodleoopApp: App {
  @State private var historyStore: GameHistoryStore
  @State private var session: GameSession
  @AppStorage(PaperStyle.storageKey) private var paperStyleRaw = PaperStyle.plain.rawValue

  init() {
    if UITesting.isEnabled {
      UITesting.preparePreferences()
    }
    let history = GameHistoryStore()
    if UITesting.isEnabled {
      UITesting.seedDemoHistory(into: history)
    }
    _historyStore = State(wrappedValue: history)
    _session = State(wrappedValue: GameSession(historyStore: history))
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(session)
        .environment(historyStore)
        .onAppear {
          guard UITesting.isEnabled, let preview = UITesting.viewPreview else { return }
          session.loadPreview(preview)
        }
    }
    .environment(\.paperStyle, PaperStyle(rawValue: paperStyleRaw) ?? .plain)
  }
}
