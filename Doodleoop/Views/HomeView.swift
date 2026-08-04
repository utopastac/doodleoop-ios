import SwiftUI

struct HomeView: View {
  @EnvironmentObject private var session: GameSession
  @Namespace private var avatarZoomNamespace
  @State private var nameDraft = ""
  @State private var isEditingAvatar = false
  @State private var showRules = false
  @State private var showSettings = false
  @State private var showHistory = false
  @State private var showViewPreviews = false
  @State private var pendingPreview: ViewPreview?

  private static let avatarZoomID = "homeAvatar"

  var body: some View {
    NavigationStack {
      Group {
        if session.hasSavedAvatar {
          homeContent
            .navigationDestination(isPresented: $isEditingAvatar) {
              avatarEditor
            }
        } else {
          AvatarSetupView(
            initialDrawing: session.localAvatar,
            saveLabel: "That's me",
            onCancel: nil,
            onSave: { drawing in
              session.updateAvatar(drawing)
            }
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background {
        (session.hasSavedAvatar ? Theme.Background.broadsheet : Theme.Paper.tan)
          .ignoresSafeArea()
      }
      .sheet(isPresented: $showSettings) {
        AppSettingsView()
      }
      .sheet(isPresented: $showHistory) {
        GameHistoryView()
      }
      .sheet(isPresented: $showViewPreviews, onDismiss: {
        if let pendingPreview {
          session.loadPreview(pendingPreview)
          self.pendingPreview = nil
        }
      }) {
        ViewPreviewMenuView { preview in
          session.updateDisplayName(nameDraft.isEmpty ? session.localDisplayName : nameDraft)
          pendingPreview = preview
          showViewPreviews = false
        }
      }
    }
  }

  private var avatarEditor: some View {
    AvatarSetupView(
      initialDrawing: session.localAvatar,
      saveLabel: "Save",
      onCancel: { isEditingAvatar = false },
      onSave: { drawing in
        session.updateAvatar(drawing)
        isEditingAvatar = false
      }
    )
    .toolbar(.hidden, for: .navigationBar)
    .navigationTransition(.zoom(sourceID: Self.avatarZoomID, in: avatarZoomNamespace))
  }

  private var homeContent: some View {
    let margin = Theme.Layout.pageMargin
    let buttonHeight = DoodleButtonKind.primary.height
    let rulesHeight = DoodleButtonKind.tertiary.height

    return GeometryReader { geo in
      let contentWidth = geo.size.width - margin * 2

      VStack(spacing: 0) {
        Spacer(minLength: 0)

        // Brand title band — rails hug glyph ink, not the font box
        let brand = DoodleLabel.bracketed("Doodloop")
        Text(brand)
          .themeText(.body)
          .foregroundStyle(Theme.Text.primary)
          .frame(maxWidth: .infinity)
          .gridBand(crop: .glyphs(text: brand, style: .body))
          .onLongPressGesture {
            showViewPreviews = true
          }

        // Headline sits in the open field between title and hero bands
        Text("A drawing relay party game")
          .themeText(.display)
          .multilineTextAlignment(.center)
          .foregroundStyle(Theme.Text.primary)
          .frame(maxWidth: .infinity)
          .fixedSize(horizontal: false, vertical: true)
          .pageHorizontalPadding()
          .padding(.vertical, Theme.Spacing.s6)
          .onLongPressGesture {
            showViewPreviews = true
          }

        Spacer(minLength: Theme.Spacing.s2)

        // Avatar flush to the page margin rails (exact content width)
        HomeAvatarHero(
          drawing: session.localAvatar,
          zoomNamespace: avatarZoomNamespace,
          zoomID: Self.avatarZoomID
        ) {
          TextField("Your name", text: $nameDraft)
            .themeText(.subheading)
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.Text.primary)
            .onAppear { nameDraft = session.localDisplayName }
            .onSubmit { session.updateDisplayName(nameDraft) }
        } onDrawingTap: {
          isEditingAvatar = true
        }
        .frame(width: contentWidth, height: contentWidth)
        .frame(maxWidth: .infinity)
        .layoutPriority(1)
        .accessibilityElement(children: .contain)
        .gridBand()

        Spacer(minLength: Theme.Spacing.s6)

        // Create / Join — band height == button height
        HStack(spacing: 0) {
          Button(DoodleLabel.bracketed("Create game")) {
            session.updateDisplayName(nameDraft)
            session.hostGame()
          }
          .doodleButton(.primary)

          GridLine(axis: .vertical)
            .frame(maxHeight: .infinity)

          Button(DoodleLabel.bracketed("Join game")) {
            session.updateDisplayName(nameDraft)
            session.startBrowsing()
          }
          .doodleButton(.secondary)
        }
        .frame(height: buttonHeight)
        .pageHorizontalPadding()
        .gridBand()

        Spacer(minLength: Theme.Spacing.s5)

        // Rules + history + settings
        HStack(spacing: Theme.Spacing.s2) {
          Button(DoodleLabel.bracketed("The rules")) {
            showRules = true
          }
          .doodleButton(.tertiary)
          .frame(width: 153)

          Button {
            showHistory = true
          } label: {
            PhosphorIcon.clockCounterClockwise.image
              .resizable()
              .renderingMode(.template)
              .scaledToFit()
              .frame(width: Theme.Sizing.iconMd, height: Theme.Sizing.iconMd)
              .foregroundStyle(Theme.Text.primary)
              .frame(width: Theme.Sizing.inputHeight, height: Theme.Sizing.inputHeight)
              .background(Theme.Paper.white)
              .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("History")

          Button {
            showSettings = true
          } label: {
            Image(systemName: "slider.horizontal.3")
              .font(.system(size: Theme.Sizing.iconMd, weight: .semibold))
              .foregroundStyle(Theme.Text.primary)
              .frame(width: Theme.Sizing.inputHeight, height: Theme.Sizing.inputHeight)
              .background(Theme.Paper.white)
              .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Settings")
        }
        .frame(maxWidth: .infinity)
        .frame(height: rulesHeight)
        .gridBand()

        Spacer(minLength: Theme.Spacing.s7)
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
    .pageMargins()
    .alert("The rules", isPresented: $showRules) {
      Button("Got it", role: .cancel) {}
    } message: {
      Text("Draw the category, pass left, guess what’s in front of you, then draw that guess. Keep going until the loop comes back around.")
    }
  }
}

struct HomeAvatarHero<NameContent: View>: View {
  let drawing: Drawing
  var zoomNamespace: Namespace.ID
  var zoomID: String
  var onDrawingTap: (() -> Void)?
  @ViewBuilder var nameContent: () -> NameContent

  init(
    drawing: Drawing,
    zoomNamespace: Namespace.ID,
    zoomID: String,
    @ViewBuilder nameContent: @escaping () -> NameContent,
    onDrawingTap: (() -> Void)? = nil
  ) {
    self.drawing = drawing
    self.zoomNamespace = zoomNamespace
    self.zoomID = zoomID
    self.nameContent = nameContent
    self.onDrawingTap = onDrawingTap
  }

  var body: some View {
    VStack(spacing: Theme.Spacing.s5) {
      Group {
        if drawing.isEmpty {
          Image(systemName: "person.fill")
            .font(.system(size: 64, weight: .regular))
            .foregroundStyle(Theme.Text.tertiary)
        } else {
          Canvas { context, canvasSize in
            let scale = canvasSize.width / 280
            StrokeRenderer.drawDrawing(
              drawing,
              in: &context,
              size: canvasSize,
              widthScale: scale
            )
          }
        }
      }
      .frame(maxWidth: 160, maxHeight: 180)
      .contentShape(Rectangle())
      .onTapGesture { onDrawingTap?() }
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel("Edit avatar")

      nameContent()
        .frame(maxWidth: 200)
    }
    .padding(Theme.Spacing.s6)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .paperSurface(in: Circle())
    .matchedTransitionSource(id: zoomID, in: zoomNamespace)
  }
}

struct AvatarSetupView: View {
  var title: String = "Your avatar"
  let initialDrawing: Drawing
  let saveLabel: String
  var onCancel: (() -> Void)?
  let onSave: (Drawing) -> Void

  @State private var drawing = Drawing.empty
  @State private var undoStack = DrawingUndoStack()
  @State private var tool: DrawingTool = .pen
  @State private var colorHex = DrawingPalette.defaultHex
  @State private var widthByTool: [DrawingTool: Double] = Dictionary(
    uniqueKeysWithValues: DrawingTool.allCases.map { ($0, $0.defaultWidth) }
  )

  private var canSave: Bool { !drawing.isEmpty }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: Theme.Spacing.s2) {
        Text(title)
          .themeText(.body)
          .foregroundStyle(Theme.Text.primary)
          .frame(maxWidth: .infinity, minHeight: Theme.Sizing.inputHeight, alignment: .leading)

        if let onCancel {
          dismissButton(action: onCancel)
        }
      }
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
      .clipShape(Circle())
      .contentShape(Circle())
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

      saveButton
        .frame(height: Theme.Spacing.s10, alignment: .bottom)
        .pageHorizontalPadding()
        .padding(.bottom, Theme.Spacing.s3)
    }
    .paperBackground()
    .pageMargins()
    .onAppear {
      drawing = initialDrawing
      undoStack.reset()
    }
  }

  private var saveButton: some View {
    Button(DoodleLabel.bracketed(saveLabel)) {
      onSave(drawing)
    }
    .themeText(.button)
    .foregroundStyle(Theme.Paper.tan.opacity(canSave ? 1 : 0.5))
    .padding(.horizontal, Theme.Spacing.s5)
    .frame(maxWidth: .infinity)
    .frame(height: Theme.Sizing.inputHeight)
    .background(Theme.Ink.deep.opacity(canSave ? 1 : 0.35))
    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular))
    .disabled(!canSave)
  }

  private func dismissButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
      PhosphorIcon.x.image
        .resizable()
        .renderingMode(.template)
        .scaledToFit()
        .frame(width: Theme.Sizing.iconMd, height: Theme.Sizing.iconMd)
        .foregroundStyle(Theme.Text.primary)
        .frame(width: Theme.Sizing.inputHeight, height: Theme.Sizing.inputHeight)
        .background(Theme.Paper.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Cancel")
  }

  private var clearButton: some View {
    Button {
      undoStack.registerClear(before: drawing)
      drawing = .empty
    } label: {
      PhosphorIcon.trash.image
        .resizable()
        .renderingMode(.template)
        .scaledToFit()
        .frame(width: Theme.Sizing.iconMd, height: Theme.Sizing.iconMd)
        .foregroundStyle(Theme.Text.primary.opacity(drawing.isEmpty ? 0.35 : 1))
        .frame(width: Theme.Sizing.inputHeight, height: Theme.Sizing.inputHeight)
        .background(Theme.Paper.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular))
    }
    .buttonStyle(.plain)
    .disabled(drawing.isEmpty)
    .accessibilityLabel("Clear")
  }
}
