import SwiftUI

struct GameSettingsView: View {
  @EnvironmentObject private var session: GameSession
  @State private var drawSeconds: Double = Double(GameTimerDefaults.drawSeconds)
  @State private var guessSeconds: Double = Double(GameTimerDefaults.guessSeconds)
  @State private var maxRounds: Double = Double(GameRoundDefaults.maxRounds)
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

        VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
          HStack {
            Text("Max rounds")
              .themeText(.label)
              .foregroundStyle(Theme.Text.primary)
            Spacer()
            Text("\(Int(maxRounds))")
              .themeText(.bodyStrong)
              .foregroundStyle(Theme.Text.primary)
          }
          if session.isHost {
            Slider(
              value: $maxRounds,
              in: Double(GameRoundDefaults.minRounds)...Double(GameRoundDefaults.absoluteMaxRounds),
              step: 1
            )
            .tint(Theme.Ink.deep)
          }
        }
      } header: {
        Text("Turn timers")
          .themeText(.overline)
      } footer: {
        Text(
          session.isHost
            ? "Defaults are 60s to draw, 30s to guess, and 8 rounds (capped by player count). Changes apply in this lobby."
            : "Only the host can change these."
        )
        .themeText(.caption)
      }
    }
    .navigationTitle("Game settings")
    .navigationBarTitleDisplayMode(.inline)
    .scrollContentBackground(.hidden)
    .paperBackground()
    .pageMargins()
    .onAppear {
      drawSeconds = Double(state.drawTimeLimitSeconds)
      guessSeconds = Double(state.guessTimeLimitSeconds)
      maxRounds = Double(state.maxRounds)
      isReady = true
    }
    .onChange(of: drawSeconds) { _, newValue in
      guard isReady else { return }
      pushSettings(draw: Int(newValue), guess: Int(guessSeconds), rounds: Int(maxRounds))
    }
    .onChange(of: guessSeconds) { _, newValue in
      guard isReady else { return }
      pushSettings(draw: Int(drawSeconds), guess: Int(newValue), rounds: Int(maxRounds))
    }
    .onChange(of: maxRounds) { _, newValue in
      guard isReady else { return }
      pushSettings(draw: Int(drawSeconds), guess: Int(guessSeconds), rounds: Int(newValue))
    }
    .onChange(of: state.drawTimeLimitSeconds) { _, newValue in
      let value = Double(newValue)
      if Int(drawSeconds) != newValue { drawSeconds = value }
    }
    .onChange(of: state.guessTimeLimitSeconds) { _, newValue in
      let value = Double(newValue)
      if Int(guessSeconds) != newValue { guessSeconds = value }
    }
    .onChange(of: state.maxRounds) { _, newValue in
      let value = Double(newValue)
      if Int(maxRounds) != newValue { maxRounds = value }
    }
  }

  private func pushSettings(draw: Int, guess: Int, rounds: Int) {
    guard session.isHost else { return }
    guard draw != state.drawTimeLimitSeconds
      || guess != state.guessTimeLimitSeconds
      || rounds != state.maxRounds else { return }
    session.updateGameSettings(drawSeconds: draw, guessSeconds: guess, maxRounds: rounds)
  }
}

/// Countdown synced to the host’s `phaseEndsAt`.
struct PhaseCountdown: View {
  let endsAt: Date?
  /// Drawing page uses a larger mono timer; other screens keep the default.
  var style: Theme.TextStyle = .subheading
  var urgentColor: Color = Theme.Accent.default
  var normalColor: Color = Theme.Text.primary

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.25)) { context in
      let remaining = Self.remainingSeconds(until: endsAt, now: context.date)
      Text(Self.format(remaining))
        .themeText(style)
        .foregroundStyle(remaining <= 5 ? urgentColor : normalColor)
        .accessibilityLabel("\(remaining) seconds remaining")
    }
  }

  static func remainingSeconds(until endsAt: Date?, now: Date = Date()) -> Int {
    guard let endsAt else { return 0 }
    return max(0, Int(ceil(endsAt.timeIntervalSince(now))))
  }

  /// `MM.SS` — matches Figma drawing-page timer (`00.45`).
  static func format(_ totalSeconds: Int) -> String {
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%02d.%02d", minutes, seconds)
  }
}
