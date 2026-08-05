import SwiftUI

@main
struct DoodleoopApp: App {
  @State private var historyStore: GameHistoryStore
  @State private var session: GameSession
  @AppStorage(PaperStyle.storageKey) private var paperStyleRaw = PaperStyle.plain.rawValue

  init() {
    let history = GameHistoryStore()
    _historyStore = State(wrappedValue: history)
    _session = State(wrappedValue: GameSession(historyStore: history))
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(session)
        .environment(historyStore)
    }
    .environment(\.paperStyle, PaperStyle(rawValue: paperStyleRaw) ?? .plain)
  }
}
