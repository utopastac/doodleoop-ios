import SwiftUI

struct GameHistoryView: View {
  @EnvironmentObject private var history: GameHistoryStore
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Group {
        if history.games.isEmpty {
          emptyState
        } else {
          listContent
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .paperBackground()
      .pageMargins()
      .navigationTitle("History")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
            .themeText(.label)
            .foregroundStyle(Theme.Accent.default)
        }
      }
    }
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
        NavigationLink {
          SavedGameDetailView(game: game)
        } label: {
          VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
            Text(game.category.isEmpty ? "Untitled loop" : game.category)
              .themeText(.bodyStrong)
              .foregroundStyle(Theme.Text.primary)
            Text(game.playerNamesSummary)
              .themeText(.caption)
              .foregroundStyle(Theme.Text.secondary)
              .lineLimit(1)
            Text(game.completedAt.formatted(date: .abbreviated, time: .shortened))
              .themeText(.caption)
              .foregroundStyle(Theme.Text.tertiary)
          }
          .padding(.vertical, Theme.Spacing.s1)
        }
        .listRowBackground(Theme.Paper.white)
      }
      .onDelete { offsets in
        for index in offsets {
          history.delete(history.games[index])
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
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
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.Spacing.s5) {
        header

        DoodleSegmentedControl(
          options: SavedGameBrowseMode.allCases,
          selection: $mode,
          title: \.title
        )

        switch mode {
        case .books:
          booksList
        case .gallery:
          DrawingGridView(items: game.allDrawings) { item in
            focusedDrawing = item
          }
        }
      }
      .pageHorizontalPadding()
      .padding(.top, Theme.Spacing.s4)
      .padding(.bottom, Theme.Spacing.s7)
    }
    .paperBackground()
    .pageMargins()
    .navigationTitle("Loop")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $focusedDrawing) { item in
      DrawingFocusSheet(game: game, item: item)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
      Text(game.category.isEmpty ? "Untitled loop" : game.category)
        .themeText(.heading)
        .foregroundStyle(Theme.Text.primary)
      Text(game.completedAt.formatted(date: .abbreviated, time: .shortened))
        .themeText(.caption)
        .foregroundStyle(Theme.Text.tertiary)
      Text(game.playerNamesSummary)
        .themeText(.label)
        .foregroundStyle(Theme.Text.secondary)
    }
  }

  private var booksList: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
      Text("Drawing books")
        .themeText(.overline)
        .foregroundStyle(Theme.Text.secondary)

      ForEach(game.pads) { pad in
        NavigationLink {
          SavedPadView(game: game, pad: pad)
        } label: {
          HStack(spacing: Theme.Spacing.s3) {
            if let starter = game.player(id: pad.id) {
              AvatarBadge(drawing: starter.avatar, size: Theme.Sizing.avatarMd)
              VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
                Text("\(starter.name)'s pad")
                  .themeText(.bodyStrong)
                  .foregroundStyle(Theme.Text.primary)
                Text("\(contributionCount(pad)) steps")
                  .themeText(.caption)
                  .foregroundStyle(Theme.Text.secondary)
              }
            } else {
              Text("Pad")
                .themeText(.bodyStrong)
                .foregroundStyle(Theme.Text.primary)
            }
            Spacer()
            Image(systemName: "chevron.right")
              .font(.system(size: Theme.Sizing.iconSm, weight: .semibold))
              .foregroundStyle(Theme.Text.tertiary)
          }
          .padding(Theme.Spacing.s4)
          .paperSurface(in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func contributionCount(_ pad: SketchPad) -> Int {
    pad.steps.filter {
      if case .prompt = $0 { return false }
      return true
    }.count
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
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.Spacing.s5) {
        if !game.category.isEmpty {
          labeled("Category", game.category)
        }

        DoodleSegmentedControl(
          options: PadBookLayout.allCases,
          selection: $layout,
          title: \.title
        )

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
      .padding(.top, Theme.Spacing.s4)
      .padding(.bottom, Theme.Spacing.s7)
    }
    .paperBackground()
    .pageMargins()
    .navigationTitle("\(starterName)'s pad")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $focusedDrawing) { item in
      DrawingFocusSheet(game: game, item: item)
    }
  }

  @ViewBuilder
  private var storyContent: some View {
    ForEach(Array(pad.steps.enumerated()), id: \.offset) { _, step in
      stepView(step)
    }
  }

  @ViewBuilder
  private func stepView(_ step: ChainStep) -> some View {
    switch step {
    case .prompt(let text):
      labeled("Category", text)
    case .drawing(let playerId, let drawing):
      VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
        Text(game.player(id: playerId)?.name ?? "Player")
          .themeText(.bodyStrong)
          .foregroundStyle(Theme.Text.primary)
        ReadOnlyDrawingView(drawing: drawing)
          .aspectRatio(1, contentMode: .fit)
      }
    case .guess(let playerId, let text):
      labeled(game.player(id: playerId)?.name ?? "Player", text)
    }
  }

  private func labeled(_ title: String, _ body: String) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
      Text(title)
        .themeText(.caption)
        .foregroundStyle(Theme.Accent.default)
      Text(body)
        .themeText(.subheading)
        .foregroundStyle(Theme.Text.primary)
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

private struct DrawingGridView: View {
  let items: [PadDrawingItem]
  var onSelect: (PadDrawingItem) -> Void

  private let columns = [
    GridItem(.flexible(), spacing: Theme.Spacing.s3),
    GridItem(.flexible(), spacing: Theme.Spacing.s3),
  ]

  var body: some View {
    if items.isEmpty {
      Text("No drawings in this loop.")
        .themeText(.label)
        .foregroundStyle(Theme.Text.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      LazyVGrid(columns: columns, spacing: Theme.Spacing.s3) {
        ForEach(items) { item in
          Button {
            onSelect(item)
          } label: {
            ReadOnlyDrawingView(drawing: item.drawing)
              .aspectRatio(1, contentMode: .fit)
              .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                  .strokeBorder(Theme.Stroke.subtle, lineWidth: Theme.Borders.thin)
              }
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Drawing")
        }
      }
    }
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

        ReadOnlyDrawingView(drawing: item.drawing)
          .aspectRatio(1, contentMode: .fit)

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
    .presentationDetents([.large])
  }
}
