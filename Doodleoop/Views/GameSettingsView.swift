import SwiftUI

struct GameSettingsView: View {
  @EnvironmentObject private var session: GameSession
  @State private var drawSeconds: Double = Double(GameTimerDefaults.drawSeconds)
  @State private var guessSeconds: Double = Double(GameTimerDefaults.guessSeconds)
  @State private var isReady = false

  private var state: GameState { session.state ?? GameState() }

  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Drawing time")
            Spacer()
            Text("\(Int(drawSeconds))s")
              .font(Theme.Fonts.body)
              .foregroundStyle(Theme.coral)
          }
          if session.isHost {
            Slider(
              value: $drawSeconds,
              in: Double(GameTimerDefaults.minSeconds)...Double(GameTimerDefaults.maxSeconds),
              step: 5
            )
            .tint(Theme.coral)
          }
        }

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Guessing time")
            Spacer()
            Text("\(Int(guessSeconds))s")
              .font(Theme.Fonts.body)
              .foregroundStyle(Theme.teal)
          }
          if session.isHost {
            Slider(
              value: $guessSeconds,
              in: Double(GameTimerDefaults.minSeconds)...Double(GameTimerDefaults.maxSeconds),
              step: 5
            )
            .tint(Theme.teal)
          }
        }
      } header: {
        Text("Turn timers")
      } footer: {
        Text(
          session.isHost
            ? "Defaults are 60s to draw and 30s to guess. Changes apply to the next turns in this lobby."
            : "Only the host can change these."
        )
      }
    }
    .navigationTitle("Game settings")
    .navigationBarTitleDisplayMode(.inline)
    .scrollContentBackground(.hidden)
    .background(Theme.paper.ignoresSafeArea())
    .onAppear {
      drawSeconds = Double(state.drawTimeLimitSeconds)
      guessSeconds = Double(state.guessTimeLimitSeconds)
      isReady = true
    }
    .onChange(of: drawSeconds) { _, newValue in
      guard isReady else { return }
      pushSettings(draw: Int(newValue), guess: Int(guessSeconds))
    }
    .onChange(of: guessSeconds) { _, newValue in
      guard isReady else { return }
      pushSettings(draw: Int(drawSeconds), guess: Int(newValue))
    }
    .onChange(of: state.drawTimeLimitSeconds) { _, newValue in
      let value = Double(newValue)
      if Int(drawSeconds) != newValue { drawSeconds = value }
    }
    .onChange(of: state.guessTimeLimitSeconds) { _, newValue in
      let value = Double(newValue)
      if Int(guessSeconds) != newValue { guessSeconds = value }
    }
  }

  private func pushSettings(draw: Int, guess: Int) {
    guard session.isHost else { return }
    guard draw != state.drawTimeLimitSeconds || guess != state.guessTimeLimitSeconds else { return }
    session.updateGameSettings(drawSeconds: draw, guessSeconds: guess)
  }
}

/// Countdown synced to the host’s `phaseEndsAt`.
struct PhaseCountdown: View {
  let endsAt: Date?

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.25)) { context in
      let remaining = Self.remainingSeconds(until: endsAt, now: context.date)
      Text(Self.format(remaining))
        .font(Theme.Fonts.title3)
        .foregroundStyle(remaining <= 5 ? Theme.coral : Theme.ink.opacity(0.85))
        .accessibilityLabel("\(remaining) seconds remaining")
    }
  }

  static func remainingSeconds(until endsAt: Date?, now: Date = Date()) -> Int {
    guard let endsAt else { return 0 }
    return max(0, Int(ceil(endsAt.timeIntervalSince(now))))
  }

  static func format(_ totalSeconds: Int) -> String {
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}
