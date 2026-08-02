import SwiftUI

struct HomeView: View {
  @EnvironmentObject private var session: GameSession
  @State private var nameDraft = ""
  @State private var isEditingAvatar = false

  var body: some View {
    NavigationStack {
      Group {
        if session.hasSavedAvatar && !isEditingAvatar {
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
      .background(Theme.paper.ignoresSafeArea())
    }
  }

  private var homeContent: some View {
    VStack(spacing: 28) {
      Spacer()

      Text("Doodleoop")
        .font(Theme.Fonts.permanentMarker(size: 48))
        .foregroundStyle(Theme.ink)

      Text("Draw, pass left, guess — pictorial Chinese whispers.")
        .font(Theme.Fonts.title3)
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.ink.opacity(0.7))
        .padding(.horizontal, 32)

      Button {
        isEditingAvatar = true
      } label: {
        AvatarBadge(drawing: session.localAvatar, size: 96)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Edit avatar")

      TextField("Your name", text: $nameDraft)
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal, 40)
        .onAppear { nameDraft = session.localDisplayName }
        .onSubmit { session.updateDisplayName(nameDraft) }

      VStack(spacing: 12) {
        Button("Create game") {
          session.updateDisplayName(nameDraft)
          session.hostGame()
        }
        .buttonStyle(PrimaryButtonStyle(color: Theme.coral))

        Button("Join game") {
          session.updateDisplayName(nameDraft)
          session.startBrowsing()
        }
        .buttonStyle(PrimaryButtonStyle(color: Theme.teal))
      }
      .padding(.horizontal, 40)

      Spacer()
    }
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
  @State private var tool: DrawingTool = .pen
  @State private var colorHex = DrawingPalette.defaultHex
  @State private var widthByTool: [DrawingTool: Double] = Dictionary(
    uniqueKeysWithValues: DrawingTool.allCases.map { ($0, $0.defaultWidth) }
  )

  var body: some View {
    VStack(spacing: 12) {
      Text(title)
        .font(Theme.Fonts.largeTitle)
        .foregroundStyle(Theme.ink)
        .padding(.top, 20)

      Text(subtitle)
        .font(Theme.Fonts.title3)
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.ink.opacity(0.7))
        .padding(.horizontal, 28)

      DrawingCanvas(
        drawing: $drawing,
        tool: tool,
        colorHex: colorHex,
        lineWidth: widthByTool[tool] ?? tool.defaultWidth
      )
      .aspectRatio(1, contentMode: .fit)
      .clipShape(Circle())
      .overlay(Circle().stroke(Theme.ink.opacity(0.12), lineWidth: 2))
      .padding(.horizontal, 36)
      .padding(.vertical, 4)

      DrawingToolbar(tool: $tool, colorHex: $colorHex, widthByTool: $widthByTool)
        .padding(.horizontal, 20)

      HStack {
        if let onCancel {
          Button("Cancel", action: onCancel)
        }
        Button("Clear") { drawing = .empty }
        Spacer()
        Button(saveLabel) { onSave(drawing) }
          .buttonStyle(PrimaryButtonStyle(color: Theme.coral))
          .frame(width: 150)
          .disabled(drawing.isEmpty)
      }
      .padding(.horizontal, 28)
      .padding(.bottom, 16)
    }
    .onAppear { drawing = initialDrawing }
  }
}

struct PrimaryButtonStyle: ButtonStyle {
  var color: Color

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(Theme.Fonts.headline)
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 14)
      .background(color.opacity(configuration.isPressed ? 0.8 : 1))
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}
