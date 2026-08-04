import SwiftUI

struct LobbyView: View {
  @EnvironmentObject private var session: GameSession
  @State private var extraName = ""
  @State private var showCategorySheet = false

  private var state: GameState { session.state ?? GameState() }

  private var hostName: String {
    state.players.first { $0.id == state.hostId }?.name ?? session.localDisplayName
  }

  private var canStart: Bool {
    session.isHost && state.players.count >= 2 && state.phase == .lobby
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Leave sits in its own 40pt band between horizontal rails (Figma y 77–117).
      leaveToolbar
        .gridBand()

      // Title (80) + settings (64) share one block before the players rail.
      titleBlock
      settingsRow

      GridLine(axis: .horizontal)

      playerList
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

      if session.role == .joiner, session.state == nil || state.players.isEmpty {
        joinerBrowsing
          .padding(.bottom, Theme.Spacing.s4)
      }

      addPlayerRow
        .padding(.top, Theme.Spacing.s3)
        .padding(.bottom, Theme.Spacing.s3)

      if session.isHost {
        Button(DoodleLabel.bracketed("Start game")) {
          showCategorySheet = true
        }
        .doodleButton(.primary)
        .disabled(!canStart)
        .padding(.bottom, Theme.Spacing.s3)
      }
    }
    .pageHorizontalPadding()
    .paperBackground()
    .pageMargins()
    .sheet(isPresented: $showCategorySheet) {
      CategoryPromptSheet(
        category: $session.draftCategory,
        onStart: {
          showCategorySheet = false
          session.startRound()
        },
        onCancel: { showCategorySheet = false }
      )
      .presentationDetents([.medium])
    }
  }

  // MARK: - Header

  /// 40×40 sign-out, trailing flush to the page margin rail.
  private var leaveToolbar: some View {
    HStack(spacing: 0) {
      Spacer(minLength: 0)
      LeaveGameButton()
    }
    .frame(height: Theme.Spacing.s8)
  }

  private var titleBlock: some View {
    Text("\(hostName)’s game")
      .themeText(.heading)
      .foregroundStyle(Theme.Text.primary)
      // Figma title cell: 80pt tall, vertically centered.
      .frame(maxWidth: .infinity, minHeight: Theme.Spacing.s11, maxHeight: Theme.Spacing.s11, alignment: .leading)
      .accessibilityAddTraits(.isHeader)
  }

  // MARK: - Settings

  private var settingsRow: some View {
    HStack(alignment: .top, spacing: 0) {
      settingColumn(
        label: "Draw time",
        value: PhaseCountdown.format(state.drawTimeLimitSeconds)
      ) {
        timerMenu(
          selection: state.drawTimeLimitSeconds,
          around: GameTimerDefaults.drawSeconds,
          onSelect: { seconds in
            session.updateGameSettings(
              drawSeconds: seconds,
              guessSeconds: state.guessTimeLimitSeconds,
              maxRounds: state.maxRounds
            )
          }
        )
      }

      settingColumn(
        label: "Guess time",
        value: PhaseCountdown.format(state.guessTimeLimitSeconds)
      ) {
        timerMenu(
          selection: state.guessTimeLimitSeconds,
          around: GameTimerDefaults.guessSeconds,
          onSelect: { seconds in
            session.updateGameSettings(
              drawSeconds: state.drawTimeLimitSeconds,
              guessSeconds: seconds,
              maxRounds: state.maxRounds
            )
          }
        )
      }

      settingColumn(
        label: "Max rounds",
        value: "\(state.maxRounds)"
      ) {
        roundsMenu
      }
    }
    // Figma Frame 44: 64pt tall, metrics inset 2pt from top.
    .padding(.top, 2)
    .frame(height: Theme.Spacing.s10, alignment: .top)
  }

  private func settingColumn<MenuContent: View>(
    label: String,
    value: String,
    @ViewBuilder menu: () -> MenuContent
  ) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s0) {
      Text(label)
        .themeText(.caption)
        .foregroundStyle(Theme.Ink.medium)
        .textCase(.uppercase)
        .tracking(Theme.FontSize.caption1 * 0.05)

      if session.isHost {
        Menu {
          menu()
        } label: {
          Text(value)
            .themeText(.subheading)
            .foregroundStyle(Theme.Text.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        Text(value)
          .themeText(.subheading)
          .foregroundStyle(Theme.Text.primary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func timerMenu(
    selection: Int,
    around center: Int,
    onSelect: @escaping (Int) -> Void
  ) -> some View {
    ForEach(Self.timerOptions(around: center), id: \.self) { seconds in
      Button {
        onSelect(seconds)
      } label: {
        if seconds == selection {
          Label(PhaseCountdown.format(seconds), systemImage: "checkmark")
        } else {
          Text(PhaseCountdown.format(seconds))
        }
      }
    }
  }

  private var roundsMenu: some View {
    ForEach(GameRoundDefaults.minRounds...GameRoundDefaults.absoluteMaxRounds, id: \.self) { rounds in
      Button {
        session.updateGameSettings(
          drawSeconds: state.drawTimeLimitSeconds,
          guessSeconds: state.guessTimeLimitSeconds,
          maxRounds: rounds
        )
      } label: {
        if rounds == state.maxRounds {
          Label("\(rounds)", systemImage: "checkmark")
        } else {
          Text("\(rounds)")
        }
      }
    }
  }

  /// Five-second steps, six stops either side of the default (clamped to timer limits).
  private static func timerOptions(around center: Int) -> [Int] {
    let step = 5
    let stops = 6
    let values = (-stops...stops).map { center + $0 * step }
    return values.filter {
      $0 >= GameTimerDefaults.minSeconds && $0 <= GameTimerDefaults.maxSeconds
    }
  }

  // MARK: - Players

  private var playerList: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text("\(state.players.count) Players")
          .themeText(.bodyStrong)
          .foregroundStyle(Theme.Text.primary)
          .textCase(.uppercase)
          .tracking(Theme.FontSize.body * 0.05)
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(height: Theme.Spacing.s8, alignment: .center)
          .padding(.horizontal, Theme.Spacing.s2)

        ForEach(state.players) { player in
          playerRow(player)
        }
      }
    }
  }

  private func playerRow(_ player: Player) -> some View {
    HStack(spacing: Theme.Spacing.s3) {
      AvatarBadge(drawing: player.avatar, size: Theme.Spacing.s9)

      Text(player.name)
        .themeText(.body)
        .foregroundStyle(Theme.Text.primary)
        .lineLimit(1)

      Spacer(minLength: Theme.Spacing.s2)

      if player.id == state.hostId {
        Text("Host")
          .themeText(.labelSmall)
          .foregroundStyle(Theme.Accent.subtle)
          .textCase(.uppercase)
          .tracking(Theme.FontSize.footnote * 0.07)
      } else if session.isHost {
        Button {
          session.removeLobbyPlayer(player.id)
        } label: {
          PhosphorIcon.x.image
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: Theme.Sizing.iconSm, height: Theme.Sizing.iconSm)
            .foregroundStyle(Theme.Ink.deep)
            .frame(width: Theme.Spacing.s7, height: Theme.Spacing.s7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(player.name)")
      }
    }
    .padding(.horizontal, Theme.Spacing.s2)
    .padding(.vertical, Theme.Spacing.s1)
  }

  // MARK: - Add / join

  private var addPlayerRow: some View {
    HStack(spacing: Theme.Spacing.s2) {
      TextField("Player name", text: $extraName)
        .themeText(.label)
        .foregroundStyle(Theme.Text.primary)
        .padding(.horizontal, Theme.Spacing.s3)
        .padding(.vertical, Theme.Spacing.s2)
        .frame(maxWidth: .infinity)
        .frame(height: Theme.Spacing.s9)
        .background(Theme.Paper.white)
        .overlay(
          RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular)
            .stroke(Theme.Stroke.default, lineWidth: Theme.Borders.thick)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular))
        .onSubmit(addSeat)

      Button(DoodleLabel.bracketed("Add")) {
        addSeat()
      }
      .doodleButton(.secondary)
      .fixedSize(horizontal: true, vertical: false)
      .disabled(session.state == nil || state.phase != .lobby)
    }
  }

  private var joinerBrowsing: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
      if session.discoveredPeers.isEmpty {
        ProgressView("Looking for games…")
          .tint(Theme.Accent.default)
      } else {
        Text("Nearby games")
          .themeText(.bodyStrong)
          .foregroundStyle(Theme.Text.primary)
          .textCase(.uppercase)

        ForEach(session.discoveredPeers, id: \.displayName) { peer in
          Button(peer.displayName) {
            session.join(peer)
          }
          .doodleButton(.secondary)
        }
      }
    }
  }

  private func addSeat() {
    session.addLocalSeat(name: extraName)
    extraName = ""
  }
}

// MARK: - Category prompt (host starts round)

private struct CategoryPromptSheet: View {
  @Binding var category: String
  var onStart: () -> Void
  var onCancel: () -> Void

  private var trimmed: String {
    category.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: Theme.Spacing.s5) {
        Text("What are we drawing?")
          .themeText(.heading)
          .foregroundStyle(Theme.Text.primary)

        TextField("Category for this round", text: $category)
          .themeText(.label)
          .foregroundStyle(Theme.Text.primary)
          .padding(.horizontal, Theme.Spacing.s3)
          .padding(.vertical, Theme.Spacing.s2)
          .frame(height: Theme.Spacing.s9)
          .background(Theme.Paper.white)
          .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular)
              .stroke(Theme.Stroke.default, lineWidth: Theme.Borders.thick)
          )
          .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular))

        Spacer(minLength: 0)

        Button(DoodleLabel.bracketed("Start game")) {
          onStart()
        }
        .doodleButton(.primary)
        .disabled(trimmed.isEmpty)
      }
      .pageHorizontalPadding()
      .padding(.top, Theme.Spacing.s5)
      .padding(.bottom, Theme.Spacing.s4)
      .paperBackground()
      .pageMargins()
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
      }
    }
  }
}
