import SwiftUI

enum ViewPreview: String, CaseIterable, Identifiable {
  case lobbyPassAndPlay
  case lobbyNearbyHost
  case lobbyNearbyJoiner
  case lobbyNearbyGameFound
  case drawing
  case drawingFromGuess
  case guessing
  case reveal
  case roundOver
  case handoffOverlay
  case avatarSetup
  case paperStyles

  enum Section: String, CaseIterable, Identifiable {
    case gamePhases = "Game Phases"
    case standalone = "Standalone Screens"
    case overlays = "Overlays"

    var id: String { rawValue }
  }

  var id: String { rawValue }

  var section: Section {
    switch self {
    case .avatarSetup, .paperStyles:
      return .standalone
    case .handoffOverlay:
      return .overlays
    default:
      return .gamePhases
    }
  }

  var title: String {
    switch self {
    case .lobbyPassAndPlay: return "Lobby — Multi-seat"
    case .lobbyNearbyHost: return "Lobby — Host"
    case .lobbyNearbyJoiner: return "Lobby — Joiner"
    case .lobbyNearbyGameFound: return "Lobby — Game Found"
    case .drawing: return "Drawing — Category"
    case .drawingFromGuess: return "Drawing — From guess"
    case .guessing: return "Guessing"
    case .reveal: return "Reveal"
    case .roundOver: return "Round Over"
    case .handoffOverlay: return "Pass-the-Phone Handoff"
    case .avatarSetup: return "Avatar Setup"
    case .paperStyles: return "Paper Styles"
    }
  }

  var subtitle: String {
    switch self {
    case .lobbyPassAndPlay: return "Host lobby with several seats on one phone"
    case .lobbyNearbyHost: return "Host lobby with players on separate phones"
    case .lobbyNearbyJoiner: return "Searching for nearby games"
    case .lobbyNearbyGameFound: return "Tap a nearby host to join"
    case .drawing: return "First turn — draw the shared category"
    case .drawingFromGuess: return "Later turn — draw someone else's guess"
    case .guessing: return "What is this a drawing of?"
    case .reveal: return "Reveal each pad one step at a time"
    case .roundOver: return "Loop complete celebration"
    case .handoffOverlay: return "Full-screen seat handoff gate"
    case .avatarSetup: return "First-run doodle avatar"
    case .paperStyles: return "Plain, dots, crosses, rules, parchment, textured"
    }
  }

  var isSheetPreview: Bool {
    switch self {
    case .avatarSetup, .paperStyles:
      return true
    default:
      return false
    }
  }
}

struct ViewPreviewMenuView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var session: GameSession
  var onSelectGamePreview: (ViewPreview) -> Void

  @State private var sheetPreview: ViewPreview?

  var body: some View {
    NavigationStack {
      ZStack {
        PaperFill(style: .plain)
          .ignoresSafeArea()

        List {
          ForEach(ViewPreview.Section.allCases) { section in
            Section(section.rawValue) {
              ForEach(ViewPreview.allCases.filter { $0.section == section }) { preview in
                Button {
                  open(preview)
                } label: {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(preview.title)
                      .themeText(.bodyStrong)
                      .foregroundStyle(Theme.Text.primary)

                    Text(preview.subtitle)
                      .themeText(.caption)
                      .foregroundStyle(Theme.Text.secondary)
                  }
                  .padding(.vertical, 2)
                }
              }
            }
          }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
      }
      .navigationTitle("View Previews")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(item: $sheetPreview) { preview in
        switch preview {
        case .avatarSetup:
          AvatarSetupView(
            title: "Draw your avatar",
            subtitle: "One quick doodle — saved for every game.",
            initialDrawing: .empty,
            saveLabel: "That's me",
            onCancel: { sheetPreview = nil },
            onSave: { drawing in
              session.updateAvatar(drawing)
              sheetPreview = nil
            }
          )
          .paperBackground()
        case .paperStyles:
          PaperStylesPreviewView()
        default:
          EmptyView()
        }
      }
    }
  }

  private func open(_ preview: ViewPreview) {
    if preview.isSheetPreview {
      sheetPreview = preview
    } else {
      onSelectGamePreview(preview)
    }
  }
}

struct PaperStylesPreviewView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Theme.Spacing.s5) {
          ForEach(PaperStyle.allCases) { style in
            paperSwatch(title: style.displayName, style: style)
          }
        }
        .padding(Theme.Spacing.s5)
      }
      .paperBackground()
      .navigationTitle("Paper Styles")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private func paperSwatch(title: String, style: PaperStyle) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
      Text(title)
        .themeText(.bodyStrong)
        .foregroundStyle(Theme.Text.primary)

      PaperFill(style: style)
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
            .stroke(Theme.Stroke.subtle, lineWidth: Theme.Borders.thin)
        )
    }
  }
}
