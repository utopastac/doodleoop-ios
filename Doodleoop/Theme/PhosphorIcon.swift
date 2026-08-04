import SwiftUI

/// Phosphor Icons — **regular** weight only.
///
/// Only the glyphs we actually use live in the asset catalog. Do not vend the
/// full Phosphor set; when a new icon is needed, pull that single regular SVG
/// from [phosphor-icons/core](https://github.com/phosphor-icons/core) (`assets/regular/`)
/// into `Assets.xcassets` as a template image.
enum PhosphorIcon: String {
  case penNib = "IconPenNib"
  case pencil = "IconPencil"
  case paintBrush = "IconPaintBrush"
  case eraser = "IconEraser"
  case undo = "IconUndo"
  case trash = "IconTrash"
  case x = "IconX"
  case signOut = "IconSignOut"
  case clockCounterClockwise = "IconClockCounterClockwise"

  var image: Image { Image(rawValue) }
}

extension DrawingTool {
  var phosphorIcon: PhosphorIcon {
    switch self {
    case .pen: .penNib
    case .pencil: .pencil
    case .highlighter: .paintBrush
    case .eraser: .eraser
    }
  }

  /// Toolbar order matches the drawing-page Figma (pen → pencil → brush → eraser).
  static var toolbarOrder: [DrawingTool] { [.pen, .pencil, .highlighter, .eraser] }
}
