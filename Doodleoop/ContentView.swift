import SwiftUI

struct ContentView: View {
  @Environment(GameSession.self) private var session

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
    .drawingZoomLayer()
    .alert(
      session.alert?.title ?? "",
      isPresented: alertPresented
    ) {
      Button("OK", role: .cancel) {
        session.clearAlert()
      }
    } message: {
      Text(session.alert?.message ?? "")
    }
  }

  private var alertPresented: Binding<Bool> {
    Binding(
      get: { session.alert != nil },
      set: { if !$0 { session.clearAlert() } }
    )
  }

  /// Drives screen animation when role or phase changes.
  private var screenIdentity: String {
    switch session.role {
    case .idle:
      return "home"
    case .host, .joiner:
      if let phase = session.phase {
        return "\(String(describing: session.role))-\(phase.rawValue)"
      }
      return session.role == .joiner ? "joiner-lobby" : "host-empty"
    }
  }

  private var isLobbyPhase: Bool {
    // Prefer mirrored `phase` so pad syncs don't invalidate this shell.
    session.phase == .lobby || (session.role == .joiner && session.phase == nil)
  }

  /// Lobby, reveal and round-over own a 40pt leave band; drawing / guessing use overlay chrome.
  private var usesInlineLeave: Bool {
    guard !isLobbyPhase else { return true }
    return session.phase == .reveal || session.phase == .roundOver
  }

  @ViewBuilder
  private var gameFlow: some View {
    // Leave chrome sits outside the phase swap so it doesn't slide with the pad.
    // Switch on mirrored `phase` so pad submits don't rebuild this shell.
    ZStack {
      Group {
        switch session.phase {
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
        case nil:
          if session.role == .joiner {
            LobbyView()
              .transition(Self.crossfade)
          } else {
            HomeView()
              .transition(Self.crossfade)
          }
        }
      }

      if let banner = session.statusBanner {
        VStack {
          SessionStatusBanner(text: banner) {
            session.clearStatusBanner()
          }
          .padding(.top, Theme.Spacing.s3)
          Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(2)
      }
    }
    .animation(Theme.Motion.handoff, value: session.statusBanner)
    .leaveGameChrome(isEnabled: !usesInlineLeave)
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

/// Compact in-game notice for Multipeer departures and similar events.
struct SessionStatusBanner: View {
  let text: String
  var onDismiss: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: Theme.Spacing.s2) {
      Text(text)
        .themeText(.caption)
        .foregroundStyle(Theme.Text.primary)
        .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: onDismiss) {
        PhosphorIcon.x.image
          .resizable()
          .renderingMode(.template)
          .scaledToFit()
          .frame(width: Theme.Sizing.iconSm, height: Theme.Sizing.iconSm)
          .foregroundStyle(Theme.Text.secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Dismiss")
    }
    .padding(.horizontal, Theme.Spacing.s3)
    .padding(.vertical, Theme.Spacing.s2)
    .background(Theme.Paper.beige)
    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular))
    .overlay {
      RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular)
        .strokeBorder(Theme.Stroke.subtle, lineWidth: Theme.Borders.thin)
    }
    .pageHorizontalPadding()
  }
}

#Preview {
  ContentView()
    .environment(GameSession())
}
