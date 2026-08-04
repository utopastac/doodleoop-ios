import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var session: GameSession

  var body: some View {
    ZStack {
      Group {
        switch session.role {
        case .idle:
          HomeView()
        case .host, .joiner:
          gameFlow
            // Lobby lays out leave in its own toolbar band; other phases overlay.
            .leaveGameChrome(isEnabled: !isLobbyPhase)
        }
      }

      if session.handoff != nil {
        HandoffOverlay()
      }
    }
    .environment(\.font, Theme.TextStyle.label.font)
  }

  private var isLobbyPhase: Bool {
    session.state?.phase == .lobby || (session.role == .joiner && session.state == nil)
  }

  @ViewBuilder
  private var gameFlow: some View {
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
    } else if session.role == .joiner {
      LobbyView()
    } else {
      HomeView()
    }
  }
}

#Preview {
  ContentView()
    .environmentObject(GameSession())
}
