import Photos
import SwiftUI

enum DrawingPhotoExporter {
  static let exportSize = CGSize(width: 1024, height: 1024)
  static let exportScale: CGFloat = 2

  enum ExportError: LocalizedError {
    case bakeFailed
    case accessDenied

    var errorDescription: String? {
      switch self {
      case .bakeFailed:
        return "Couldn't render this drawing."
      case .accessDenied:
        return "Allow Photos access in Settings to save drawings."
      }
    }
  }

  @MainActor
  static func saveToPhotos(_ drawing: Drawing, paperStyle: PaperStyle) async throws {
    guard let image = StrokeRenderer.bake(
      drawing,
      size: exportSize,
      scale: exportScale,
      paperStyle: paperStyle
    ) else {
      throw ExportError.bakeFailed
    }

    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard status == .authorized || status == .limited else {
      throw ExportError.accessDenied
    }

    try await PHPhotoLibrary.shared().performChanges {
      PHAssetChangeRequest.creationRequestForAsset(from: image)
    }
  }
}

/// Long-press context menu to rasterize a drawing and save it to Photos.
struct DrawingPhotoExportModifier: ViewModifier {
  let drawing: Drawing

  @Environment(\.paperStyle) private var paperStyle
  @State private var isSaving = false
  @State private var showSuccess = false
  @State private var errorMessage: String?

  func body(content: Content) -> some View {
    content
      .contextMenu {
        Button {
          Task { await save() }
        } label: {
          Text("Save to Photos")
        }
        .disabled(isSaving || drawing.isEmpty)
      }
      .alert("Saved to Photos", isPresented: $showSuccess) {
        Button("OK", role: .cancel) {}
      }
      .alert(
        "Couldn't Save",
        isPresented: Binding(
          get: { errorMessage != nil },
          set: { if !$0 { errorMessage = nil } }
        )
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage ?? "")
      }
  }

  @MainActor
  private func save() async {
    guard !isSaving else { return }
    isSaving = true
    defer { isSaving = false }

    do {
      try await DrawingPhotoExporter.saveToPhotos(drawing, paperStyle: paperStyle)
      showSuccess = true
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

extension View {
  func drawingPhotoExport(_ drawing: Drawing) -> some View {
    modifier(DrawingPhotoExportModifier(drawing: drawing))
  }
}
