import SwiftUI

/// How a drawing arrives during the reveal (app setting).
enum RevealStyle: String, CaseIterable, Identifiable {
  /// The finished drawing fades and rises into place.
  case fade
  /// The drawing replays stroke by stroke, in the order it was made.
  case strokes

  static let storageKey = "appearance.revealStyle"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .fade: "Fade"
    case .strokes: "Draw"
    }
  }
}

struct RevealView: View {
  @EnvironmentObject private var session: GameSession
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage(RevealStyle.storageKey) private var revealStyleRaw = RevealStyle.fade.rawValue

  private let categoryScrollID = "reveal-category"

  /// Reduce Motion falls back to a plain fade — no replay, no rise.
  private var replaysStrokes: Bool {
    RevealStyle(rawValue: revealStyleRaw) == .strokes && !reduceMotion
  }

  var body: some View {
    let state = session.state
    let pad = state.flatMap { $0.pads.indices.contains($0.revealPadIndex) ? $0.pads[$0.revealPadIndex] : nil }
    let starter = pad.flatMap { state?.player(id: $0.id) }
    let padIndex = state?.revealPadIndex ?? 0
    let steps = RevealStep.list(state?.visibleRevealContributions ?? [], padIndex: padIndex)
    let finished = state?.isRevealFinished == true
    let category = state?.category.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    VStack(spacing: 0) {
      padHeader(starterName: starter?.name)

      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 0) {
            if !category.isEmpty {
              categoryBlock(category)
                .id(categoryScrollID)
              GridLine(axis: .horizontal)
            }

            ForEach(steps) { item in
              // Step and its rule animate as one block so the page grows in one move.
              VStack(spacing: 0) {
                stepBlock(item.step, state: state, isFirstContribution: item.index == 0 && !category.isEmpty)
                GridLine(axis: .horizontal)
              }
              .id(item.id)
              .transition(transition(for: item.step))
            }
          }
          .pageHorizontalPadding()
          .padding(.bottom, Theme.Spacing.s4)
          .animation(Theme.Motion.reveal, value: steps.map(\.id))
        }
        .onChange(of: RevealScrollTarget(padIndex: padIndex, count: steps.count)) { previous, current in
          guard current.count > 0 else { return }
          withAnimation(Theme.Motion.reveal) {
            if current.padIndex != previous.padIndex {
              proxy.scrollTo(
                category.isEmpty ? RevealStep.id(padIndex: current.padIndex, index: 0) : categoryScrollID,
                anchor: .top
              )
            } else {
              proxy.scrollTo(
                RevealStep.id(padIndex: current.padIndex, index: current.count - 1),
                anchor: .bottom
              )
            }
          }
        }
      }

      Button(DoodleLabel.bracketed(finished ? "Finish" : "Next")) {
        session.advanceReveal()
      }
      .doodleButton(.primary)
      .pageHorizontalPadding()
      .padding(.top, Theme.Spacing.s6)
      .padding(.bottom, Theme.Spacing.s3)
    }
    .paperBackground()
    .pageMargins()
  }

  /// Rises into place on insert; removals fade so a pad swap reads as a crossfade.
  /// A replayed drawing only fades its paper in — the ink supplies the motion.
  private func transition(for step: ChainStep) -> AnyTransition {
    guard !reduceMotion else { return .opacity }
    if case .drawing = step, replaysStrokes { return .opacity }
    return .asymmetric(
      insertion: .modifier(
        active: RevealStepEntry(hidden: true),
        identity: RevealStepEntry(hidden: false)
      ),
      removal: .opacity
    )
  }

  /// 40pt title band with leave control — matches Figma reveal header + Lobby leave layout.
  private func padHeader(starterName: String?) -> some View {
    let title = starterName.map { "\($0)’s Pad" } ?? "Pad"
    return LeaveToolbarBand(title: title)
      .contentTransition(.opacity)
      .animation(Theme.Motion.reveal, value: title)
      .gridBand()
  }

  private func categoryBlock(_ category: String) -> some View {
    Text(category)
      .themeText(.heading)
      .foregroundStyle(Theme.Text.primary)
      .frame(maxWidth: .infinity, minHeight: Theme.Spacing.s11, alignment: .leading)
      .padding(.horizontal, Theme.Spacing.s2)
  }

  @ViewBuilder
  private func stepBlock(
    _ step: ChainStep,
    state: GameState?,
    isFirstContribution: Bool
  ) -> some View {
    switch step {
    case .prompt(let text):
      categoryBlock(text)
    case .drawing(let playerId, let drawing):
      let name = state?.player(id: playerId)?.name ?? "Player"
      VStack(alignment: .leading, spacing: 0) {
        // First drawing after the category sits unlabeled (Figma Reveal pad).
        if !isFirstContribution {
          Text("\(name)’s Drawing")
            .modifier(RevealContributionLabel())
            .frame(maxWidth: .infinity, minHeight: Theme.Spacing.s8, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.s2)
        }
        RevealDrawing(drawing: drawing, replaysStrokes: replaysStrokes)
          .aspectRatio(1, contentMode: .fit)
          .frame(maxWidth: .infinity)
      }
    case .guess(let playerId, let text):
      let name = state?.player(id: playerId)?.name ?? "Player"
      VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
        Text("\(name)’s Guess")
          .modifier(RevealContributionLabel())
        Text(text)
          .themeText(.heading)
          .foregroundStyle(Theme.Text.primary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(Theme.Spacing.s2)
    }
  }
}

/// One visible contribution, identified per pad so steps never reuse identity across pads.
private struct RevealStep: Identifiable {
  let id: String
  let index: Int
  let step: ChainStep

  static func id(padIndex: Int, index: Int) -> String {
    "pad\(padIndex)-step\(index)"
  }

  static func list(_ contributions: [ChainStep], padIndex: Int) -> [RevealStep] {
    contributions.enumerated().map { index, step in
      RevealStep(id: id(padIndex: padIndex, index: index), index: index, step: step)
    }
  }
}

/// Distinguishes "one more step on this pad" from "moved to the next pad".
private struct RevealScrollTarget: Equatable {
  var padIndex: Int
  var count: Int
}

/// Replays its strokes once, when the step it belongs to is first shown.
private struct RevealDrawing: View {
  let drawing: Drawing
  let replaysStrokes: Bool

  @State private var progress: Double

  init(drawing: Drawing, replaysStrokes: Bool) {
    self.drawing = drawing
    self.replaysStrokes = replaysStrokes
    _progress = State(initialValue: replaysStrokes ? 0 : 1)
  }

  var body: some View {
    ZoomableDrawingView(drawing: drawing, progress: progress)
      .onAppear {
        guard replaysStrokes else { return }
        withAnimation(.linear(duration: StrokeRenderer.replayDuration(for: drawing))) {
          progress = 1
        }
      }
      // Flipping the setting mid-reveal completes what's on screen rather than redrawing it.
      .onChange(of: replaysStrokes) { _, _ in
        progress = 1
      }
  }
}

private struct RevealStepEntry: ViewModifier {
  var hidden: Bool

  func body(content: Content) -> some View {
    content
      .opacity(hidden ? 0 : 1)
      .scaleEffect(hidden ? 0.96 : 1, anchor: .top)
      .offset(y: hidden ? Theme.Spacing.s5 : 0)
  }
}

/// Footnote mono label — uppercase + 7% tracking (Figma Label Small).
private struct RevealContributionLabel: ViewModifier {
  func body(content: Content) -> some View {
    content
      .themeText(.labelSmall)
      .foregroundStyle(Theme.Text.primary)
      .textCase(.uppercase)
      .tracking(Theme.FontSize.footnote * 0.07)
  }
}

struct RoundOverView: View {
  @EnvironmentObject private var session: GameSession
  @State private var showCategorySheet = false

  var body: some View {
    let state = session.state

    VStack(spacing: 0) {
      header

      Text("Ready for another round?")
        .themeText(.heading)
        .foregroundStyle(Theme.Text.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.s2)
        .pageHorizontalPadding()

      DoodleCollage(
        drawings: drawings(in: state),
        seed: CollageSeed.value(for: state)
      )

      footer
    }
    .paperBackground()
    .pageMargins()
    .sheet(isPresented: $showCategorySheet) {
      CategoryPromptSheet(
        category: $session.draftCategory,
        startTitle: "Start round",
        onStart: {
          showCategorySheet = false
          session.startRound()
        },
        onCancel: { showCategorySheet = false }
      )
    }
  }

  /// 40pt title band with leave control — same layout as the reveal header.
  private var header: some View {
    LeaveToolbarBand(title: "Doodloop complete")
      .gridBand()
  }

  @ViewBuilder
  private var footer: some View {
    Group {
      if session.isHost {
        HStack(spacing: Theme.Spacing.s4) {
          Button(DoodleLabel.bracketed("Play again")) {
            session.draftCategory = ""
            showCategorySheet = true
          }
          .doodleButton(.primary)

          Button(DoodleLabel.bracketed("Lobby")) {
            session.returnToLobby()
          }
          .doodleButton(.secondary)
        }
        // Two bracketed labels sharing one row runs a few points over on
        // narrow phones; hold the single line rather than wrap to two.
        .lineLimit(1)
        .minimumScaleFactor(0.85)
      } else {
        Text("Waiting for the host to pick what's next.")
          .themeText(.label)
          .foregroundStyle(Theme.Text.secondary)
          .frame(maxWidth: .infinity, minHeight: Theme.Spacing.s9, alignment: .leading)
      }
    }
    .pageHorizontalPadding()
    .padding(.top, Theme.Spacing.s2)
    .padding(.bottom, Theme.Spacing.s3)
  }

  private func drawings(in state: GameState?) -> [Drawing] {
    guard let state else { return [] }
    return state.pads
      .flatMap { PadDrawingItem.items(from: $0) }
      .map(\.drawing)
      .filter { !$0.isEmpty }
  }
}

/// Every phone should show the same collage, and it shouldn't reshuffle
/// on re-render — so the layout is seeded from the round itself.
private enum CollageSeed {
  static func value(for state: GameState?) -> UInt64 {
    guard let state else { return 0 }
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in (state.category + state.pads.map(\.id).joined()).utf8 {
      hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3
    }
    return hash
  }
}

private struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

private struct CollageRow: Identifiable {
  let id: Int
  let drawing: Drawing
  let side: CGFloat
  let leading: CGFloat
}

/// A handful of the round's drawings, one per row, at random square sizes and
/// offsets — Figma "End of round". Rows divide the space between the title and
/// the buttons, so the stack always fills the page exactly.
private struct DoodleCollage: View {
  let drawings: [Drawing]
  let seed: UInt64

  /// Row side as a fraction of the content width.
  private static let sideRange: ClosedRange<CGFloat> = 0.27...0.55
  /// Average row side — decides how many rows the page fits.
  private static let targetSide: CGFloat = 0.41

  @State private var size: CGSize = .zero

  var body: some View {
    VStack(spacing: 0) {
      GridLine(axis: .horizontal)
      ForEach(rows) { row in
        VStack(spacing: 0) {
          ReadOnlyDrawingView(drawing: row.drawing)
            .frame(width: row.side, height: row.side)
            .padding(.leading, row.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
          GridLine(axis: .horizontal)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
    .pageHorizontalPadding()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Drawings from this loop")
  }

  private var rows: [CollageRow] {
    guard size.width > 0, size.height > 0, !drawings.isEmpty else { return [] }

    var rng = SeededGenerator(seed: seed)
    let count = max(1, Int((size.height / (size.width * Self.targetSide)).rounded()))
    // The rules between rows eat into the height the drawings can share.
    let available = max(0, size.height - CGFloat(count + 1) * Theme.Borders.thin)
    let fractions = (0..<count).map { _ in CGFloat.random(in: Self.sideRange, using: &rng) }
    let scale = available / (fractions.reduce(0, +) * size.width)
    let picks = picked(count, using: &rng)

    return picks.indices.map { index in
      let side = min(fractions[index] * size.width * scale, size.width)
      return CollageRow(
        id: index,
        drawing: picks[index],
        side: side,
        leading: (size.width - side) * CGFloat.random(in: 0...1, using: &rng)
      )
    }
  }

  /// Prefers distinct drawings, cycling through a fresh shuffle when the round
  /// has fewer drawings than there are rows to fill.
  private func picked(_ count: Int, using rng: inout SeededGenerator) -> [Drawing] {
    var pool = drawings.shuffled(using: &rng)
    var picks: [Drawing] = []
    while picks.count < count {
      if pool.isEmpty { pool = drawings.shuffled(using: &rng) }
      picks.append(pool.removeFirst())
    }
    return picks
  }
}

struct HandoffOverlay: View {
  @EnvironmentObject private var session: GameSession

  var body: some View {
    if let handoff = session.handoff,
       let player = session.state?.player(id: handoff.playerId) {
      ZStack {
        Theme.Ink.deep.opacity(0.94).ignoresSafeArea()
        VStack(spacing: Theme.Spacing.s5) {
          Text(handoff.title)
            .themeText(.heading)
            .foregroundStyle(Theme.Background.primary)
          Text(handoff.message)
            .themeText(.label)
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.Background.primary.opacity(0.85))
            .padding(.horizontal, Theme.Spacing.s7)
          AvatarBadge(drawing: player.avatar, size: 120)
          Text(player.name)
            .themeText(.display)
            .foregroundStyle(Theme.Accent.muted)
          Button(DoodleLabel.bracketed("I'm \(player.name)")) {
            session.confirmHandoff()
          }
          .doodleButton(.primary)
          .pageHorizontalPadding()
        }
      }
    }
  }
}
