import SwiftUI

struct DrawingView: View {
  @Environment(GameSession.self) private var session
  @State private var drawing = Drawing.empty
  @State private var undoStack = DrawingUndoStack()
  @State private var tool: DrawingTool = .pen
  @State private var colorHex = DrawingPalette.defaultHex
  @State private var widthByTool: [DrawingTool: Double] = Dictionary(
    uniqueKeysWithValues: DrawingTool.allCases.map { ($0, $0.defaultWidth) }
  )
  /// Optimistic submit so joiners see the wait UI before `syncState` lands.
  @State private var locallySubmittedForPlayerId: String?

  var body: some View {
    let state = session.state
    let hasSubmitted = locallySubmittedForPlayerId == session.localPlayerId
      || (state?.submittedPlayerIds.contains(session.localPlayerId) ?? false)
    let prompt: String = {
      guard let state,
            let pad = state.pad(inFrontOf: session.localPlayerId),
            let last = pad.steps.last else { return session.state?.category ?? "" }
      switch last {
      case .prompt(let text):
        return text
      case .guess(_, let text):
        return text
      case .drawing:
        return state.category
      }
    }()
    let canSubmit = !drawing.isEmpty && !hasSubmitted

    Group {
      if hasSubmitted {
        waitingContent(endsAt: state?.phaseEndsAt)
      } else {
        drawingContent(prompt: prompt, canSubmit: canSubmit, endsAt: state?.phaseEndsAt)
      }
    }
    .paperBackground()
    .pageMargins()
    .task(id: state?.phaseEndsAt) {
      await autoSubmitWhenTimerExpires(endsAt: state?.phaseEndsAt)
    }
  }

  private func drawingContent(prompt: String, canSubmit: Bool, endsAt: Date?) -> some View {
    VStack(spacing: 0) {
      Text(prompt)
        .themeText(.body)
        .multilineTextAlignment(.leading)
        .foregroundStyle(Theme.Text.primary)
        .frame(maxWidth: .infinity, minHeight: Theme.Sizing.inputHeight, alignment: .leading)
        .padding(.trailing, Theme.Sizing.leaveButtonReserve)
        .pageHorizontalPadding()
        .padding(.top, Theme.Spacing.s3)

      Spacer(minLength: Theme.Spacing.s2)

      DrawingCanvas(
        drawing: $drawing,
        tool: tool,
        colorHex: colorHex,
        lineWidth: widthByTool[tool] ?? tool.defaultWidth,
        onWillCommitStroke: { undoStack.registerStrokeAdded() }
      )
      .aspectRatio(1, contentMode: .fit)
      .frame(maxWidth: .infinity)
      .overlay(alignment: .topTrailing) {
        clearButton
      }
      .pageHorizontalPadding()

      Spacer(minLength: Theme.Spacing.s4)

      DrawingToolbar(
        tool: $tool,
        colorHex: $colorHex,
        widthByTool: $widthByTool,
        canUndo: undoStack.canUndo,
        onUndo: { undoStack.undo(drawing: &drawing) }
      )
      .pageHorizontalPadding()

      HStack(alignment: .bottom, spacing: Theme.Spacing.s2) {
        PhaseCountdown(endsAt: endsAt, style: .timer)
          .frame(maxWidth: .infinity, minHeight: Theme.Sizing.inputHeight, alignment: .leading)

        saveButton(canSubmit: canSubmit)
          .frame(maxWidth: .infinity)
      }
      .frame(height: Theme.Spacing.s10, alignment: .bottom)
      .pageHorizontalPadding()
      .padding(.bottom, Theme.Spacing.s3)
    }
  }

  private func waitingContent(endsAt: Date?) -> some View {
    VStack(spacing: 0) {
      Spacer(minLength: Theme.Spacing.s3)

      Text("Waiting for other players")
        .themeText(.body)
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.Text.secondary)
        .frame(maxWidth: .infinity)
        .padding(.trailing, Theme.Sizing.leaveButtonReserve)
        .pageHorizontalPadding()

      Spacer(minLength: Theme.Spacing.s4)

      PhaseCountdown(endsAt: endsAt, style: .timer)
        .frame(maxWidth: .infinity, minHeight: Theme.Sizing.inputHeight, alignment: .leading)
        .frame(height: Theme.Spacing.s10, alignment: .bottom)
        .pageHorizontalPadding()
        .padding(.bottom, Theme.Spacing.s3)
    }
  }

  private var clearButton: some View {
    DoodleIconButton(
      phosphor: .trash,
      isEnabled: !drawing.isEmpty,
      accessibilityLabel: "Clear"
    ) {
      undoStack.registerClear(before: drawing)
      drawing = .empty
    }
  }

  private func saveButton(canSubmit: Bool) -> some View {
    DoodlePrimarySaveButton(title: "Save", isEnabled: canSubmit) {
      commitDrawing()
    }
  }

  private func commitDrawing() {
    locallySubmittedForPlayerId = session.localPlayerId
    session.submitDrawing(drawing)
    drawing = .empty
    undoStack.reset()
  }

  /// Submit whatever is on the canvas when time runs out so work isn’t lost to expireTurn.
  private func autoSubmitWhenTimerExpires(endsAt: Date?) async {
    guard await PhaseTimer.waitForExpiry(endsAt: endsAt) else { return }
    guard let state = session.state,
          state.phase == .drawing,
          locallySubmittedForPlayerId != session.localPlayerId,
          !state.submittedPlayerIds.contains(session.localPlayerId),
          !drawing.isEmpty else { return }
    commitDrawing()
  }
}
