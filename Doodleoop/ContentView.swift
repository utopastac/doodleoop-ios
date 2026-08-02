import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var session: GameSession

  var body: some View {
    ZStack {
      Group {
        if let state = session.state {
          switch state.phase {
          case .lobby:
            LobbyView()
          case .drawing:
            DrawingView()
          case .guessing:
            GuessingView()
          case .reveal:
            RevealView()
          case .roundOver:
            RoundOverView()
          }
        } else {
          HomeView()
        }
      }

      if session.handoff != nil {
        HandoffOverlay()
      }
    }
  }
}

#Preview {
  ContentView()
    .environmentObject(GameSession())
}
