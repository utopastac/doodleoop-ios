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
        VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
          HStack {
            Text("Drawing time")
              .themeText(.label)
              .foregroundStyle(Theme.Text.primary)
            Spacer()
            Text("\(Int(drawSeconds))s")
              .themeText(.bodyStrong)
              .foregroundStyle(Theme.Accent.default)
          }
          if session.isHost {
            Slider(
              value: $drawSeconds,
              in: Double(GameTimerDefaults.minSeconds)...Double(GameTimerDefaults.maxSeconds),
              step: 5
            )
            .tint(Theme.Accent.default)
          }
        }

        VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
          HStack {
            Text("Guessing time")
              .themeText(.label)
              .foregroundStyle(Theme.Text.primary)
            Spacer()
            Text("\(Int(guessSeconds))s")
              .themeText(.bodyStrong)
              .foregroundStyle(Theme.Accent.hover)
          }
          if session.isHost {
            Slider(
              value: $guessSeconds,
              in: Double(GameTimerDefaults.minSeconds)...Double(GameTimerDefaults.maxSeconds),
              step: 5
            )
            .tint(Theme.Accent.hover)
          }
        }
      } header: {
        Text("Turn timers")
          .themeText(.overline)
      } footer: {
        Text(
          session.isHost
            ? "Defaults are 60s to draw and 30s to guess. Changes apply to the next turns in this lobby."
            : "Only the host can change these."
        )
        .themeText(.caption)
      }
    }
    .navigationTitle("Game settings")
    .navigationBarTitleDisplayMode(.inline)
    .scrollContentBackground(.hidden)
    .paperBackground(.plain)
    .pageMargins()
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
        .themeText(.subheading)
        .foregroundStyle(remaining <= 5 ? Theme.Accent.default : Theme.Text.secondary)
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
