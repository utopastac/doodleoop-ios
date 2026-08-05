import SwiftUI

struct DrawingToolbar: View {
  @Binding var tool: DrawingTool
  @Binding var colorHex: String
  @Binding var widthByTool: [DrawingTool: Double]
  var canUndo: Bool = false
  var onUndo: (() -> Void)?

  private var selectedWidth: Double {
    widthByTool[tool] ?? tool.defaultWidth
  }

  /// Preview dot diameters for the four nib slots (Figma brush-size row).
  private let nibPreviewSizes: [CGFloat] = [12, 20, 28, 36]

  var body: some View {
    VStack(spacing: Theme.Spacing.s0) {
      toolsRow
      sizesRow
      swatchesRow
    }
    .gridBand()
  }

  private var toolsRow: some View {
    HStack(spacing: 0) {
      ForEach(Array(DrawingTool.toolbarOrder.enumerated()), id: \.element) { index, option in
        if index > 0 { Spacer(minLength: 0) }
        toolButton(option)
      }
      Spacer(minLength: 0)
      undoButton
    }
    .padding(.horizontal, Theme.Spacing.s2)
    .padding(.vertical, Theme.Spacing.s1)
    .frame(height: 56)
  }

  private var sizesRow: some View {
    HStack(spacing: Theme.Spacing.s1) {
      ForEach(Array(tool.availableWidths.enumerated()), id: \.offset) { index, width in
        Button {
          widthByTool[tool] = width
        } label: {
          let preview = nibPreviewSizes[min(index, nibPreviewSizes.count - 1)]
          ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular)
              .strokeBorder(
                selectedWidth == width ? Theme.Ink.deep : Color.clear,
                lineWidth: Theme.Borders.heavy
              )
            Circle()
              .fill(tool.isEraser ? Theme.Ink.deep : Color(drawingHex: colorHex))
              .frame(width: preview, height: preview)
              .overlay {
                if colorHex.uppercased() == "#FFFFFF" || colorHex.uppercased() == "#FFFFFFFF" {
                  Circle().strokeBorder(Theme.Stroke.subtle, lineWidth: Theme.Borders.thin)
                }
              }
          }
          .frame(maxWidth: .infinity)
          .frame(height: 48)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Nib \(Int(width))")
      }
    }
    .padding(.horizontal, Theme.Spacing.s2)
    .padding(.vertical, Theme.Spacing.s1)
  }

  private var swatchesRow: some View {
    HStack {
      ForEach(DrawingPalette.hexes, id: \.self) { hex in
        let selected = colorHex.caseInsensitiveCompare(hex) == .orderedSame
        Button {
          colorHex = hex
        } label: {
          Circle()
            .fill(Color(drawingHex: hex))
            .frame(width: selected ? 40 : 28, height: selected ? 40 : 28)
            .overlay {
              Circle()
                .strokeBorder(
                  selected ? Theme.Ink.deep : swatchEdge(for: hex),
                  lineWidth: selected ? Theme.Borders.heavy : Theme.Borders.thin
                )
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Color \(hex)")
      }
    }
    .padding(.horizontal, Theme.Spacing.s2)
    .padding(.vertical, Theme.Spacing.s1)
    .frame(height: 56)
  }

  private func toolButton(_ option: DrawingTool) -> some View {
    let selected = tool == option
    return Button {
      tool = option
    } label: {
      option.phosphorIcon.image
        .resizable()
        .renderingMode(.template)
        .scaledToFit()
        .frame(width: Theme.Sizing.iconLg + 8, height: Theme.Sizing.iconLg + 8)
        .foregroundStyle(selected ? Theme.Paper.tan : Theme.Ink.deep)
        .frame(width: 48, height: 48)
        .background(selected ? Theme.Ink.deep : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(option.displayName)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var undoButton: some View {
    Button {
      onUndo?()
    } label: {
      PhosphorIcon.undo.image
        .resizable()
        .renderingMode(.template)
        .scaledToFit()
        .frame(width: Theme.Sizing.iconLg + 8, height: Theme.Sizing.iconLg + 8)
        .foregroundStyle(canUndo ? Theme.Ink.deep : Theme.Text.placeholder)
        .frame(width: 48, height: 48)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!canUndo)
    .accessibilityLabel("Undo")
  }

  private func hexIsLight(_ hex: String) -> Bool {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
    return cleaned == "FFFFFF" || cleaned == "FFFFFFFF"
  }

  private func swatchEdge(for hex: String) -> Color {
    if hexIsLight(hex) {
      return Theme.Ink.deep.opacity(0.25)
    }
    return Color(drawingHex: hex).opacity(0.55)
  }
}
