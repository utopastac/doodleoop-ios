import SwiftUI

enum Theme {
  static let ink = Color(red: 0.12, green: 0.14, blue: 0.18)
  static let paper = Color(red: 0.98, green: 0.96, blue: 0.92)
  static let coral = Color(red: 0.93, green: 0.35, blue: 0.32)
  static let teal = Color(red: 0.12, green: 0.55, blue: 0.52)
  static let mustard = Color(red: 0.90, green: 0.68, blue: 0.18)

  enum Fonts {
    /// PostScript name of Permanent Marker Regular.
    static let permanentMarkerName = "PermanentMarker-Regular"

    static func permanentMarker(size: CGFloat) -> Font {
      .custom(permanentMarkerName, size: size)
    }

    static let largeTitle = permanentMarker(size: 34)
    static let title = permanentMarker(size: 28)
    static let title2 = permanentMarker(size: 22)
    static let title3 = permanentMarker(size: 20)
    static let headline = permanentMarker(size: 17)
    static let body = permanentMarker(size: 17)
    static let subheadline = permanentMarker(size: 15)
    static let caption = permanentMarker(size: 12)
  }
}

extension Color {
  init(drawingHex hex: String) {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var value: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&value)
    let hasAlpha = cleaned.count == 8
    let a = hasAlpha ? Double((value & 0xFF00_0000) >> 24) / 255 : 1
    let r = Double((value & 0x00FF_0000) >> 16) / 255
    let g = Double((value & 0x0000_FF00) >> 8) / 255
    let b = Double(value & 0x0000_00FF) / 255
    self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
  }
}
