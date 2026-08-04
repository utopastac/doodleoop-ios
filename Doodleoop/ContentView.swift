import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var session: GameSession

  var body: some View {
    ZStack {
      Group {
        switch session.role {
        case .idle:
          HomeView()
            .transition(Self.crossfade)
        case .host, .joiner:
          gameFlow
            .transition(Self.crossfade)
        }
      }

      if session.handoff != nil {
        HandoffOverlay()
          .transition(.opacity)
          .zIndex(1)
      }
    }
    .animation(Theme.Motion.screen, value: screenIdentity)
    .animation(Theme.Motion.handoff, value: session.handoff != nil)
    .environment(\.font, Theme.TextStyle.label.font)
  }

  /// Drives screen animation when role or phase changes.
  private var screenIdentity: String {
    switch session.role {
    case .idle:
      return "home"
    case .host, .joiner:
      if let phase = session.state?.phase {
        return "\(String(describing: session.role))-\(phase.rawValue)"
      }
      return session.role == .joiner ? "joiner-lobby" : "host-empty"
    }
  }

  private var isLobbyPhase: Bool {
    session.state?.phase == .lobby || (session.role == .joiner && session.state == nil)
  }

  @ViewBuilder
  private var gameFlow: some View {
    // Leave chrome sits outside the phase swap so it doesn't slide with the pad.
    ZStack {
      Group {
        if let state = session.state {
          switch state.phase {
          case .lobby:
            LobbyView()
              .transition(Self.crossfade)
          case .drawing:
            DrawingView()
              .transition(Self.passLeft)
          case .guessing:
            GuessingView()
              .transition(Self.passLeft)
          case .reveal:
            RevealView()
              .transition(Self.crossfade)
          case .roundOver:
            RoundOverView()
              .transition(Self.crossfade)
          }
        } else if session.role == .joiner {
          LobbyView()
            .transition(Self.crossfade)
        } else {
          HomeView()
            .transition(Self.crossfade)
        }
      }
    }
    // Lobby lays out leave in its own toolbar band; other phases overlay.
    .leaveGameChrome(isEnabled: !isLobbyPhase)
  }

  /// Pads pass left: outgoing exits leading, incoming enters from trailing.
  private static let passLeft = AnyTransition.asymmetric(
    insertion: .move(edge: .trailing).combined(with: .opacity),
    removal: .move(edge: .leading).combined(with: .opacity)
  )

  private static let crossfade = AnyTransition.opacity.combined(
    with: .scale(scale: 0.985)
  )
}

#Preview {
  ContentView()
    .environmentObject(GameSession())
}
