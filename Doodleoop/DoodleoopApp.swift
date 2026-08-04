import SwiftUI

@main
struct DoodleoopApp: App {
  @StateObject private var historyStore: GameHistoryStore
  @StateObject private var session: GameSession
  @AppStorage(PaperStyle.storageKey) private var paperStyleRaw = PaperStyle.plain.rawValue

  init() {
    let history = GameHistoryStore()
    _historyStore = StateObject(wrappedValue: history)
    _session = StateObject(wrappedValue: GameSession(historyStore: history))
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(session)
        .environmentObject(historyStore)
        .environment(\.paperStyle, PaperStyle(rawValue: paperStyleRaw) ?? .plain)
    }
  }
}
