import SwiftUI

struct AvatarBadge: View {
  let drawing: Drawing
  var size: CGFloat = Theme.Sizing.avatarMd

  var body: some View {
    Group {
      if drawing.isEmpty {
        Circle()
          .fill(Theme.Background.tertiary)
          .overlay {
            Image(systemName: "person.fill")
              .font(.system(size: size * 0.4))
              .foregroundStyle(Theme.Text.tertiary)
          }
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
        .paperSurface(in: Circle())
      }
    }
    .frame(width: size, height: size)
    .overlay(Circle().stroke(Theme.Stroke.subtle, lineWidth: Theme.Borders.thin))
  }
}
