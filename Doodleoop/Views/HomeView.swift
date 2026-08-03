import SwiftUI

struct HomeView: View {
  @EnvironmentObject private var session: GameSession
  @State private var nameDraft = ""
  @State private var isEditingAvatar = false
  @State private var showRules = false
  @State private var showSettings = false
  @State private var showViewPreviews = false
  @State private var pendingPreview: ViewPreview?

  private var showingHome: Bool {
    session.hasSavedAvatar && !isEditingAvatar
  }

  var body: some View {
    NavigationStack {
      Group {
        if showingHome {
          homeContent
        } else {
          AvatarSetupView(
            title: session.hasSavedAvatar ? "Redraw your avatar" : "Draw your avatar",
            subtitle: session.hasSavedAvatar
              ? "This doodle shows up next to your name."
              : "One quick doodle — saved for every game.",
            initialDrawing: session.localAvatar,
            saveLabel: session.hasSavedAvatar ? "Save" : "That's me",
            onCancel: session.hasSavedAvatar ? { isEditingAvatar = false } : nil,
            onSave: { drawing in
              session.updateAvatar(drawing)
              isEditingAvatar = false
            }
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background {
        (showingHome ? Theme.Background.broadsheet : Theme.Paper.cream)
          .ignoresSafeArea()
      }
      .sheet(isPresented: $showSettings) {
        AppSettingsView()
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
          .pageHorizontalPadding()
          .padding(.vertical, Theme.Spacing.s6)
          .onLongPressGesture {
            showViewPreviews = true
          }

        Spacer(minLength: Theme.Spacing.s2)

        // Avatar flush to the page margin rails (exact content width)
        HomeAvatarHero(drawing: session.localAvatar) {
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

        // Rules + settings — centered row matching Figma
        HStack(spacing: Theme.Spacing.s2) {
          Button(DoodleLabel.bracketed("The rules")) {
            showRules = true
          }
          .doodleButton(.tertiary)
          .frame(width: 153)

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
  var onDrawingTap: (() -> Void)?
  @ViewBuilder var nameContent: () -> NameContent

  init(
    drawing: Drawing,
    @ViewBuilder nameContent: @escaping () -> NameContent,
    onDrawingTap: (() -> Void)? = nil
  ) {
    self.drawing = drawing
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
  }
}

struct AvatarSetupView: View {
  let title: String
  let subtitle: String
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

  var body: some View {
    VStack(spacing: Theme.Spacing.s3) {
      Text(title)
        .themeText(.heading)
        .foregroundStyle(Theme.Text.primary)
        .padding(.top, Theme.Spacing.s5)
        .frame(maxWidth: .infinity)
        .gridBand()

      Text(subtitle)
        .themeText(.label)
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.Text.secondary)
        .padding(.horizontal, Theme.Spacing.s7)

      DrawingCanvas(
        drawing: $drawing,
        tool: tool,
        colorHex: colorHex,
        lineWidth: widthByTool[tool] ?? tool.defaultWidth,
        onWillCommitStroke: { undoStack.registerStrokeAdded() }
      )
      .aspectRatio(1, contentMode: .fit)
      .clipShape(Circle())
      .overlay(Circle().stroke(Theme.Stroke.subtle, lineWidth: Theme.Borders.thick))
      .pageHorizontalPadding()
      .gridBand()

      DrawingToolbar(
        tool: $tool,
        colorHex: $colorHex,
        widthByTool: $widthByTool,
        canUndo: undoStack.canUndo,
        onUndo: { undoStack.undo(drawing: &drawing) }
      )
      .padding(.horizontal, Theme.Spacing.s5)

      HStack {
        if let onCancel {
          Button(DoodleLabel.bracketed("Cancel"), action: onCancel)
            .doodleButton(.tertiary)
        }
        Button(DoodleLabel.bracketed("Clear")) {
          undoStack.registerClear(before: drawing)
          drawing = .empty
        }
        .doodleButton(.tertiary)
        .disabled(drawing.isEmpty)
        Spacer()
        Button(DoodleLabel.bracketed(saveLabel)) { onSave(drawing) }
          .doodleButton(.primary)
          .frame(width: 160)
          .disabled(drawing.isEmpty)
      }
      .pageHorizontalPadding()
      .gridBand()
      .padding(.bottom, Theme.Spacing.s4)
    }
    .pageMargins()
    .onAppear {
      drawing = initialDrawing
      undoStack.reset()
    }
  }
}
