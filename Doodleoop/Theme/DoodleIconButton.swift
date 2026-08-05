import SwiftUI

enum DoodleIconButtonVariant {
  /// White fill, ink glyph — secondary controls (back, clear, settings).
  case white
  /// Ink fill, tan glyph — primary icon actions (leave game).
  case ink
}

/// Square icon control — Figma 40×40 (32×32 when `size` is smaller).
struct DoodleIconButton: View {
  enum IconKind {
    case phosphor(PhosphorIcon)
    case symbol(String)
  }

  var icon: IconKind
  var variant: DoodleIconButtonVariant = .white
  var size: CGFloat = Theme.Spacing.s8
  var iconSize: CGFloat = Theme.Sizing.iconMd
  var isEnabled: Bool = true
  let accessibilityLabel: String
  let action: () -> Void

  init(
    phosphor: PhosphorIcon,
    variant: DoodleIconButtonVariant = .white,
    size: CGFloat = Theme.Spacing.s8,
    iconSize: CGFloat = Theme.Sizing.iconMd,
    isEnabled: Bool = true,
    accessibilityLabel: String,
    action: @escaping () -> Void
  ) {
    self.icon = .phosphor(phosphor)
    self.variant = variant
    self.size = size
    self.iconSize = iconSize
    self.isEnabled = isEnabled
    self.accessibilityLabel = accessibilityLabel
    self.action = action
  }

  init(
    symbol: String,
    variant: DoodleIconButtonVariant = .white,
    size: CGFloat = Theme.Spacing.s8,
    iconSize: CGFloat = Theme.Sizing.iconMd,
    isEnabled: Bool = true,
    accessibilityLabel: String,
    action: @escaping () -> Void
  ) {
    self.icon = .symbol(symbol)
    self.variant = variant
    self.size = size
    self.iconSize = iconSize
    self.isEnabled = isEnabled
    self.accessibilityLabel = accessibilityLabel
    self.action = action
  }

  private var foreground: Color {
    switch variant {
    case .white: Theme.Ink.deep
    case .ink: Theme.Paper.tan
    }
  }

  private var background: Color {
    switch variant {
    case .white: Theme.Paper.white
    case .ink: Theme.Ink.deep
    }
  }

  var body: some View {
    Button(action: action) {
      iconView
        .frame(width: iconSize, height: iconSize)
        .foregroundStyle(foreground.opacity(isEnabled ? 1 : 0.35))
        .frame(width: size, height: size)
        .background(background.opacity(isEnabled ? 1 : 0.35))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular))
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .accessibilityLabel(accessibilityLabel)
  }

  @ViewBuilder
  private var iconView: some View {
    switch icon {
    case .phosphor(let phosphor):
      phosphor.image
        .resizable()
        .renderingMode(.template)
        .scaledToFit()
    case .symbol(let name):
      Image(systemName: name)
        .font(.system(size: iconSize, weight: .semibold))
    }
  }
}
