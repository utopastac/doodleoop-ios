import SwiftUI

@main
struct DoodleoopApp: App {
  @StateObject private var session = GameSession()
  @AppStorage(PaperStyle.storageKey) private var paperStyleRaw = PaperStyle.plain.rawValue

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(session)
        .environment(\.paperStyle, PaperStyle(rawValue: paperStyleRaw) ?? .plain)
    }
  }
}
