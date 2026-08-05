import SwiftUI

struct GameHistoryView: View {
  @EnvironmentObject private var history: GameHistoryStore
  @Environment(\.dismiss) private var dismiss

  private let thumbnailSize: CGFloat = Theme.Spacing.s12 + Theme.Spacing.s2 // 104

  var body: some View {
    VStack(spacing: 0) {
      header
        .gridBand()

      if history.games.isEmpty {
        emptyState
      } else {
        listContent
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .paperBackground()
    .pageMargins()
    .toolbar(.hidden, for: .navigationBar)
  }

  /// Title + `[ DONE ]` in a 40pt band between horizontal rails (Figma).
  private var header: some View {
    HStack(spacing: Theme.Spacing.s2) {
      Text("History")
        .themeText(.body)
        .foregroundStyle(Theme.Text.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)

      Button {
        dismiss()
      } label: {
        Text(DoodleLabel.bracketed("Done"))
          .themeText(.button)
          .foregroundStyle(Theme.Paper.tan)
          .padding(.horizontal, Theme.Spacing.s5)
          .frame(height: Theme.Sizing.inputHeight)
          .background(Theme.Ink.deep)
          .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular))
      }
      .buttonStyle(.plain)
    }
    .pageHorizontalPadding()
    .frame(height: Theme.Sizing.inputHeight)
  }

  private var emptyState: some View {
    VStack(spacing: Theme.Spacing.s4) {
      Spacer()
      Text("No saved loops yet")
        .themeText(.heading)
        .foregroundStyle(Theme.Text.primary)
      Text("Finish a round and every drawing book will show up here.")
        .themeText(.label)
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.Text.secondary)
        .pageHorizontalPadding()
      Spacer()
    }
  }

  private var listContent: some View {
    List {
      ForEach(history.games) { game in
        ZStack(alignment: .leading) {
          NavigationLink {
            SavedGameDetailView(game: game)
          } label: {
            EmptyView()
          }
          .opacity(0)

          HistoryItemRow(game: game, thumbnailSize: thumbnailSize)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
          Button(role: .destructive) {
            history.delete(game)
          } label: {
            Label("Delete", systemImage: "trash")
          }
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .contentMargins(.top, Theme.Spacing.s6, for: .scrollContent)
  }
}

/// One history row: thumbnail + category / players / timestamp (Figma `history item`).
private struct HistoryItemRow: View {
  let game: SavedGame
  let thumbnailSize: CGFloat

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: Theme.Spacing.s2) {
        thumbnail
          .frame(width: thumbnailSize, height: thumbnailSize)

        VStack(alignment: .leading, spacing: 0) {
          VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
            Text(game.category.isEmpty ? "Untitled loop" : game.category)
              .textCase(.uppercase)
              .font(.custom(Theme.FontFamily.monoBold, size: Theme.FontSize.footnote))
              .tracking(Theme.FontSize.footnote * 0.07)
              .foregroundStyle(Theme.Text.primary)
              .lineLimit(2)

            Text(game.playerNamesSummary)
              .textCase(.uppercase)
              .themeText(.overline)
              .foregroundStyle(Theme.Ink.medium)
              .lineLimit(2)
          }

          Spacer(minLength: Theme.Spacing.s2)

          Text(game.historyTimestamp)
            .textCase(.uppercase)
            .themeText(.overline)
            .foregroundStyle(Theme.Text.tertiary)
        }
        .padding(.vertical, Theme.Spacing.s3)
        .frame(maxWidth: .infinity, minHeight: thumbnailSize, alignment: .leading)
      }
      .background(Theme.Paper.white)
      .pageHorizontalPadding()

      GridLine(axis: .horizontal)
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var thumbnail: some View {
    if let drawing = game.previewDrawing {
      ReadOnlyDrawingView(drawing: drawing, scalesStrokeWidth: true, showsPaper: false)
        .allowsHitTesting(false)
    } else {
      Theme.Paper.white
    }
  }
}

// MARK: - Shared chrome

/// Paper-white 40×40 back control (Figma `Icon Button`, secondary).
private struct HistoryBackButton: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Button {
      dismiss()
    } label: {
      PhosphorIcon.arrowLeft.image
        .resizable()
        .renderingMode(.template)
        .scaledToFit()
        .frame(width: Theme.Sizing.iconMd, height: Theme.Sizing.iconMd)
        .foregroundStyle(Theme.Ink.deep)
        .frame(width: Theme.Sizing.inputHeight, height: Theme.Sizing.inputHeight)
        .background(Theme.Paper.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Back")
  }
}

/// Back control (+ optional title) in a 40pt band between horizontal rails.
private struct HistoryTopBar: View {
  var title: String?

  var body: some View {
    HStack(spacing: Theme.Spacing.s3) {
      HistoryBackButton()

      if let title {
        Text(title)
          .themeText(.body)
          .foregroundStyle(Theme.Text.primary)
          .lineLimit(1)
          .accessibilityAddTraits(.isHeader)
      }

      Spacer(minLength: 0)
    }
    .pageHorizontalPadding()
    .frame(height: Theme.Sizing.inputHeight)
    .gridBand()
  }
}

// MARK: - Loop detail (books list ↔ all-drawings gallery)

private enum SavedGameBrowseMode: String, CaseIterable, Identifiable {
  case books
  case gallery

  var id: String { rawValue }

  var title: String {
    switch self {
    case .books: "Books"
    case .gallery: "Gallery"
    }
  }
}

struct SavedGameDetailView: View {
  let game: SavedGame
  @State private var mode: SavedGameBrowseMode = .books
  @State private var focusedDrawing: PadDrawingItem?

  var body: some View {
    VStack(spacing: 0) {
      HistoryTopBar()

      header
        .pageHorizontalPadding()

      GridLine(axis: .horizontal)

      DoodleSegmentedControl(
        options: SavedGameBrowseMode.allCases,
        selection: $mode,
        title: \.title
      )
      .pageHorizontalPadding()

      ScrollView {
        switch mode {
        case .books:
          VStack(spacing: 0) {
            ForEach(game.pads) { pad in
              NavigationLink {
                SavedPadView(game: game, pad: pad)
              } label: {
                HistoryPadRow(game: game, pad: pad)
              }
              .buttonStyle(.plain)
            }
          }
        case .gallery:
          DrawingGridView(items: game.allDrawings) { item in
            focusedDrawing = item
          }
          .pageHorizontalPadding()
        }
      }
      .contentMargins(.top, Theme.Spacing.s6, for: .scrollContent)
      .contentMargins(.bottom, Theme.Spacing.s7, for: .scrollContent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .paperBackground()
    .pageMargins()
    .toolbar(.hidden, for: .navigationBar)
    .sheet(item: $focusedDrawing) { item in
      DrawingFocusSheet(game: game, item: item)
    }
  }

  /// Category over timestamp — Figma gives the title an 80pt cell.
  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(game.category.isEmpty ? "Untitled loop" : game.category)
        .themeText(.heading)
        .foregroundStyle(Theme.Text.primary)
        .frame(maxWidth: .infinity, minHeight: Theme.Spacing.s11, alignment: .leading)

      Text(game.historyTimestamp)
        .textCase(.uppercase)
        .themeText(.caption)
        .foregroundStyle(Theme.Ink.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Theme.Spacing.s4)
    }
  }
}

/// One pad row: starter avatar + name, with a 2×2 peek of the pad's drawings.
private struct HistoryPadRow: View {
  let game: SavedGame
  let pad: SketchPad

  private let rowHeight: CGFloat = Theme.Spacing.s12 + Theme.Spacing.s2 // 104
  private let avatarSize: CGFloat = Theme.Spacing.s10 // 64
  private let peekSize: CGFloat = (Theme.Spacing.s12 + Theme.Spacing.s2) / 2 // 52

  private var starter: Player? { game.player(id: pad.id) }

  private var peekDrawings: [PadDrawingItem] {
    Array(PadDrawingItem.items(from: pad).prefix(4))
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: Theme.Spacing.s2) {
        HStack(spacing: Theme.Spacing.s3) {
          AvatarBadge(drawing: starter?.avatar ?? .empty, size: avatarSize)

          Text(starter?.name ?? "Pad")
            .themeText(.body)
            .foregroundStyle(Theme.Text.primary)
            .lineLimit(1)
        }
        .padding(.vertical, Theme.Spacing.s3)

        Spacer(minLength: Theme.Spacing.s2)

        peekGrid
      }
      .frame(height: rowHeight)
      .background(Theme.Paper.white)
      .pageHorizontalPadding()

      GridLine(axis: .horizontal)
    }
    .accessibilityElement(children: .combine)
  }

  /// 2×2 block of 52pt thumbnails, flush to the trailing rail.
  private var peekGrid: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        peekTile(0)
        peekTile(1)
      }
      HStack(spacing: 0) {
        peekTile(2)
        peekTile(3)
      }
    }
    .frame(width: peekSize * 2, height: peekSize * 2)
  }

  @ViewBuilder
  private func peekTile(_ index: Int) -> some View {
    if index < peekDrawings.count {
      ReadOnlyDrawingView(
        drawing: peekDrawings[index].drawing,
        scalesStrokeWidth: true,
        showsPaper: false
      )
      .frame(width: peekSize, height: peekSize)
      .allowsHitTesting(false)
    } else {
      Theme.Paper.white
        .frame(width: peekSize, height: peekSize)
    }
  }
}

// MARK: - Single pad (story ↔ grid)

private enum PadBookLayout: String, CaseIterable, Identifiable {
  case story
  case grid

  var id: String { rawValue }

  var title: String {
    switch self {
    case .story: "Story"
    case .grid: "Grid"
    }
  }
}

struct SavedPadView: View {
  let game: SavedGame
  let pad: SketchPad
  @State private var layout: PadBookLayout = .story
  @State private var focusedDrawing: PadDrawingItem?

  private var starterName: String {
    game.player(id: pad.id)?.name ?? "Player"
  }

  private var drawings: [PadDrawingItem] {
    PadDrawingItem.items(from: pad)
  }

  var body: some View {
    VStack(spacing: 0) {
      HistoryTopBar(title: "\(starterName)’s pad")

      DoodleSegmentedControl(
        options: PadBookLayout.allCases,
        selection: $layout,
        title: \.title
      )
      .pageHorizontalPadding()
      .padding(.top, Theme.Spacing.s4)

      GridLine(axis: .horizontal)

      ScrollView {
        switch layout {
        case .story:
          storyContent
        case .grid:
          DrawingGridView(items: drawings) { item in
            focusedDrawing = item
          }
        }
      }
      .pageHorizontalPadding()
      .contentMargins(.top, Theme.Spacing.s4, for: .scrollContent)
      .contentMargins(.bottom, Theme.Spacing.s7, for: .scrollContent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .paperBackground()
    .pageMargins()
    .toolbar(.hidden, for: .navigationBar)
    .sheet(item: $focusedDrawing) { item in
      DrawingFocusSheet(game: game, item: item)
    }
  }

  @ViewBuilder
  private var storyContent: some View {
    // The category heads the loop screen; skip the pad's prompt step here.
    let contributions = pad.steps.filter {
      if case .prompt = $0 { return false }
      return true
    }
    VStack(spacing: 0) {
      ForEach(Array(contributions.enumerated()), id: \.offset) { index, step in
        // First drawing after the category sits unlabeled (same as live reveal).
        stepView(step, showDrawingLabel: index > 0)
        GridLine(axis: .horizontal)
      }
    }
  }

  @ViewBuilder
  private func stepView(_ step: ChainStep, showDrawingLabel: Bool) -> some View {
    switch step {
    case .prompt(let text):
      Text(text)
        .themeText(.heading)
        .foregroundStyle(Theme.Text.primary)
        .frame(maxWidth: .infinity, minHeight: Theme.Spacing.s11, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.s2)
    case .drawing(let playerId, let drawing):
      let name = game.player(id: playerId)?.name ?? "Player"
      VStack(alignment: .leading, spacing: 0) {
        if showDrawingLabel {
          Text("\(name)’s Drawing")
            .textCase(.uppercase)
            .themeText(.labelSmall)
            .foregroundStyle(Theme.Text.primary)
            .tracking(Theme.FontSize.footnote * 0.07)
            .frame(maxWidth: .infinity, minHeight: Theme.Spacing.s8, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.s2)
        }
        ZoomableDrawingView(drawing: drawing)
          .aspectRatio(1, contentMode: .fit)
          .drawingPhotoExport(drawing)
      }
    case .guess(let playerId, let text):
      let name = game.player(id: playerId)?.name ?? "Player"
      VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
        Text("\(name)’s Guess")
          .textCase(.uppercase)
          .themeText(.labelSmall)
          .foregroundStyle(Theme.Text.primary)
          .tracking(Theme.FontSize.footnote * 0.07)
        Text(text)
          .themeText(.heading)
          .foregroundStyle(Theme.Text.primary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(Theme.Spacing.s2)
    }
  }
}

// MARK: - Drawing grid + focus

struct PadDrawingItem: Identifiable {
  let id: String
  let padId: String
  let playerId: String
  let drawing: Drawing
  let order: Int

  static func items(from pad: SketchPad) -> [PadDrawingItem] {
    var result: [PadDrawingItem] = []
    var order = 0
    for step in pad.steps {
      if case .drawing(let playerId, let drawing) = step {
        result.append(
          PadDrawingItem(
            id: "\(pad.id)-\(order)",
            padId: pad.id,
            playerId: playerId,
            drawing: drawing,
            order: order
          )
        )
        order += 1
      }
    }
    return result
  }
}

extension SavedGame {
  var allDrawings: [PadDrawingItem] {
    pads.flatMap { PadDrawingItem.items(from: $0) }
  }
}

/// Two flush columns of square drawings, divided by grid lines (Figma pad grid).
private struct DrawingGridView: View {
  let items: [PadDrawingItem]
  var onSelect: (PadDrawingItem) -> Void

  private var rows: [[PadDrawingItem]] {
    stride(from: 0, to: items.count, by: 2).map { start in
      Array(items[start..<min(start + 2, items.count)])
    }
  }

  var body: some View {
    if items.isEmpty {
      Text("No drawings in this loop.")
        .themeText(.label)
        .foregroundStyle(Theme.Text.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      VStack(spacing: 0) {
        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
          HStack(spacing: 0) {
            tile(row.first)
            GridLine(axis: .vertical)
            tile(row.count > 1 ? row[1] : nil)
          }

          if index < rows.count - 1 {
            GridLine(axis: .horizontal)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func tile(_ item: PadDrawingItem?) -> some View {
    Group {
      if let item {
        Button {
          onSelect(item)
        } label: {
          ReadOnlyDrawingView(drawing: item.drawing, scalesStrokeWidth: true)
        }
        .buttonStyle(.plain)
        .drawingPhotoExport(item.drawing)
        .accessibilityLabel("Drawing")
      } else {
        Theme.Paper.white
      }
    }
    .frame(maxWidth: .infinity)
    .aspectRatio(1, contentMode: .fit)
  }
}

private struct DrawingFocusSheet: View {
  let game: SavedGame
  let item: PadDrawingItem
  @Environment(\.dismiss) private var dismiss

  private var artistName: String {
    game.player(id: item.playerId)?.name ?? "Player"
  }

  private var padOwnerName: String {
    game.player(id: item.padId)?.name ?? "Player"
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
        VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
          Text(artistName)
            .themeText(.heading)
            .foregroundStyle(Theme.Text.primary)
          Text("On \(padOwnerName)'s pad")
            .themeText(.caption)
            .foregroundStyle(Theme.Text.secondary)
        }

        ZoomableDrawingView(drawing: item.drawing)
          .aspectRatio(1, contentMode: .fit)
          .drawingPhotoExport(item.drawing)

        Spacer(minLength: 0)
      }
      .pageHorizontalPadding()
      .padding(.top, Theme.Spacing.s4)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .paperBackground()
      .pageMargins()
      .navigationTitle("Drawing")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
            .themeText(.label)
            .foregroundStyle(Theme.Accent.default)
        }
      }
    }
    // Sheets present outside the app's view tree, so they need their own layer.
    .drawingZoomLayer()
    .presentationDetents([.large])
  }
}
