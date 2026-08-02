import SwiftUI

struct RevealView: View {
  @EnvironmentObject private var session: GameSession

  var body: some View {
    let state = session.state
    let pad = state.flatMap { $0.pads.indices.contains($0.revealPadIndex) ? $0.pads[$0.revealPadIndex] : nil }
    let starter = pad.flatMap { state?.player(id: $0.id) }

    VStack(spacing: 16) {
      Text("Reveal")
        .font(.largeTitle.weight(.black))
      if let starter {
        Text("Started by \(starter.name)")
          .foregroundStyle(.secondary)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if let pad {
            ForEach(Array(pad.steps.enumerated()), id: \.offset) { _, step in
              switch step {
              case .prompt(let text):
                labeled("Category", text)
              case .drawing(let playerId, let drawing):
                VStack(alignment: .leading, spacing: 8) {
                  Text(state?.player(id: playerId)?.name ?? "Player")
                    .font(.headline)
                  ReadOnlyDrawingView(drawing: drawing)
                    .frame(height: 220)
                }
              case .guess(let playerId, let text):
                labeled(state?.player(id: playerId)?.name ?? "Player", text)
              }
            }
          }
        }
        .padding(.horizontal, 20)
      }

      if session.isHost {
        Button(state.map { $0.revealPadIndex + 1 >= $0.pads.count } == true ? "Finish" : "Next pad") {
          session.advanceReveal()
        }
        .buttonStyle(PrimaryButtonStyle(color: Theme.coral))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
      } else {
        Text("Host is revealing…")
          .foregroundStyle(.secondary)
          .padding(.bottom, 12)
      }
    }
    .padding(.top, 20)
    .background(Theme.paper.ignoresSafeArea())
  }

  private func labeled(_ title: String, _ body: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption.weight(.bold))
        .foregroundStyle(Theme.teal)
      Text(body)
        .font(.title3.weight(.semibold))
    }
  }
}

struct RoundOverView: View {
  @EnvironmentObject private var session: GameSession

  var body: some View {
    VStack(spacing: 24) {
      Spacer()
      Text("Loop complete")
        .font(.largeTitle.weight(.black))
      Text("Ready for another category?")
        .foregroundStyle(.secondary)
      if session.isHost {
        Button("Back to lobby") {
          session.returnToLobby()
        }
        .buttonStyle(PrimaryButtonStyle(color: Theme.coral))
        .padding(.horizontal, 40)
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.paper.ignoresSafeArea())
  }
}

struct HandoffOverlay: View {
  @EnvironmentObject private var session: GameSession

  var body: some View {
    if let handoff = session.handoff,
       let player = session.state?.player(id: handoff.playerId) {
      ZStack {
        Theme.ink.opacity(0.94).ignoresSafeArea()
        VStack(spacing: 20) {
          Text(handoff.title)
            .font(.largeTitle.weight(.black))
            .foregroundStyle(.white)
          Text(handoff.message)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 28)
          Text(player.name)
            .font(.system(size: 40, weight: .black, design: .rounded))
            .foregroundStyle(Theme.mustard)
          Button("I'm \(player.name)") {
            session.confirmHandoff()
          }
          .buttonStyle(PrimaryButtonStyle(color: Theme.coral))
          .padding(.horizontal, 40)
        }
      }
    }
  }
}
