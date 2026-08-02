import SwiftUI

@main
struct DoodleoopApp: App {
  @StateObject private var session = GameSession()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(session)
    }
  }
}
