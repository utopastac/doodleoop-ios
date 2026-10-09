import CoreGraphics
import SwiftUI
import UIKit
import XCTest
@testable import Doodleoop

final class DrawingToolsTests: XCTestCase {

  // MARK: - DrawingTool

  func testEveryToolHasStableDisplayNameAndRawValue() {
    XCTAssertEqual(DrawingTool.pencil.displayName, "Pencil")
    XCTAssertEqual(DrawingTool.pen.displayName, "Pen")
    XCTAssertEqual(DrawingTool.highlighter.displayName, "Highlighter")
    XCTAssertEqual(DrawingTool.eraser.displayName, "Eraser")

    XCTAssertEqual(DrawingTool.pencil.rawValue, "pencil")
    XCTAssertEqual(DrawingTool.pen.rawValue, "pen")
    XCTAssertEqual(DrawingTool.highlighter.rawValue, "highlighter")
    XCTAssertEqual(DrawingTool.eraser.rawValue, "eraser")
  }

  func testToolOpacitiesMatchBrushCharacter() {
    XCTAssertEqual(DrawingTool.pencil.opacity, 0.72, accuracy: 0.0001)
    XCTAssertEqual(DrawingTool.pen.opacity, 1.0, accuracy: 0.0001)
    XCTAssertEqual(DrawingTool.highlighter.opacity, 0.38, accuracy: 0.0001)
    XCTAssertEqual(DrawingTool.eraser.opacity, 1.0, accuracy: 0.0001)
  }

  func testDefaultWidthIsOneOfAvailableWidths() {
    for tool in DrawingTool.allCases {
      XCTAssertTrue(
        tool.availableWidths.contains(tool.defaultWidth),
        "\(tool.displayName) defaultWidth \(tool.defaultWidth) missing from \(tool.availableWidths)"
      )
      XCTAssertEqual(tool.availableWidths.count, 4, "\(tool.displayName) should expose four nibs")
      XCTAssertEqual(
        tool.availableWidths,
        tool.availableWidths.sorted(),
        "\(tool.displayName) nibs should increase left → right"
      )
    }
  }

  func testToolNibSets() {
    XCTAssertEqual(DrawingTool.pencil.availableWidths, [3, 8, 16, 28])
    XCTAssertEqual(DrawingTool.pen.availableWidths, [4, 10, 18, 32])
    XCTAssertEqual(DrawingTool.highlighter.availableWidths, [14, 24, 40, 56])
    XCTAssertEqual(DrawingTool.eraser.availableWidths, [12, 24, 40, 64])
  }

  func testTipAndEraserFlags() {
    XCTAssertTrue(DrawingTool.highlighter.usesFlatTip)
    XCTAssertFalse(DrawingTool.pen.usesFlatTip)
    XCTAssertFalse(DrawingTool.pencil.usesFlatTip)
    XCTAssertFalse(DrawingTool.eraser.usesFlatTip)

    XCTAssertTrue(DrawingTool.eraser.isEraser)
    for tool in DrawingTool.allCases where tool != .eraser {
      XCTAssertFalse(tool.isEraser)
    }
  }

  func testToolbarOrderAndIcons() {
    XCTAssertEqual(
      DrawingTool.toolbarOrder,
      [.pen, .pencil, .highlighter, .eraser]
    )
    XCTAssertEqual(Set(DrawingTool.toolbarOrder), Set(DrawingTool.allCases))

    XCTAssertEqual(DrawingTool.pen.phosphorIcon, .penNib)
    XCTAssertEqual(DrawingTool.pencil.phosphorIcon, .pencil)
    XCTAssertEqual(DrawingTool.highlighter.phosphorIcon, .paintBrush)
    XCTAssertEqual(DrawingTool.eraser.phosphorIcon, .eraser)
  }

  func testDrawingToolCodableRoundTrip() throws {
    for tool in DrawingTool.allCases {
      let data = try JSONEncoder().encode(tool)
      let decoded = try JSONDecoder().decode(DrawingTool.self, from: data)
      XCTAssertEqual(decoded, tool)
    }
  }

  // MARK: - DrawingPalette

  func testPaletteHasEightSwatchesAndBlackDefault() {
    XCTAssertEqual(DrawingPalette.hexes.count, 8)
    XCTAssertEqual(DrawingPalette.defaultHex, "#000000")
    XCTAssertEqual(DrawingPalette.hexes[1], DrawingPalette.defaultHex)
    XCTAssertTrue(DrawingPalette.hexes.contains("#FFFFFF"))
    XCTAssertEqual(Set(DrawingPalette.hexes).count, DrawingPalette.hexes.count)
  }

  func testPaletteIsLightHexDetectsWhiteVariants() {
    XCTAssertTrue(DrawingPalette.isLightHex("#FFFFFF"))
    XCTAssertTrue(DrawingPalette.isLightHex("#ffffffff"))
    XCTAssertTrue(DrawingPalette.isLightHex("FFFFFF"))
    XCTAssertFalse(DrawingPalette.isLightHex("#000000"))
    XCTAssertFalse(DrawingPalette.isLightHex("#6176FF"))
    XCTAssertFalse(DrawingPalette.isLightHex("#EEDB4D"))
  }

  func testDrawingHexColorParsesRGBAndRGBA() {
    let black = UIColor(Color(drawingHex: "#000000"))
    var r: CGFloat = -1, g: CGFloat = -1, b: CGFloat = -1, a: CGFloat = -1
    XCTAssertTrue(black.getRed(&r, green: &g, blue: &b, alpha: &a))
    XCTAssertEqual(r, 0, accuracy: 0.001)
    XCTAssertEqual(g, 0, accuracy: 0.001)
    XCTAssertEqual(b, 0, accuracy: 0.001)
    XCTAssertEqual(a, 1, accuracy: 0.001)

    let blue = UIColor(Color(drawingHex: "#6176FF"))
    XCTAssertTrue(blue.getRed(&r, green: &g, blue: &b, alpha: &a))
    XCTAssertEqual(r, 0x61 / 255, accuracy: 0.001)
    XCTAssertEqual(g, 0x76 / 255, accuracy: 0.001)
    XCTAssertEqual(b, 0xFF / 255, accuracy: 0.001)

    let translucent = UIColor(Color(drawingHex: "#80FF0000"))
    XCTAssertTrue(translucent.getRed(&r, green: &g, blue: &b, alpha: &a))
    XCTAssertEqual(a, 0x80 / 255, accuracy: 0.001)
    XCTAssertEqual(r, 1, accuracy: 0.001)
    XCTAssertEqual(g, 0, accuracy: 0.001)
    XCTAssertEqual(b, 0, accuracy: 0.001)
  }

  // MARK: - DrawPoint / Stroke / Drawing

  func testDrawPointCodableRoundTripsNilLineWidth() throws {
    let point = DrawPoint(x: 0.25, y: 0.75)
    let data = try JSONEncoder().encode(point)
    let decoded = try JSONDecoder().decode(DrawPoint.self, from: data)
    XCTAssertEqual(decoded, point)
    XCTAssertNil(decoded.lineWidth)
  }

  func testDrawPointCodableKeepsPerPointWidth() throws {
    let point = DrawPoint(x: 0.1, y: 0.2, lineWidth: 12.5)
    let data = try JSONEncoder().encode(point)
    let decoded = try JSONDecoder().decode(DrawPoint.self, from: data)
    XCTAssertEqual(try XCTUnwrap(decoded.lineWidth), 12.5, accuracy: 0.0001)
  }

  func testStrokeDefaultsAndEquatable() {
    let a = Stroke(points: [DrawPoint(x: 0, y: 0)])
    XCTAssertEqual(a.lineWidth, DrawingTool.pen.defaultWidth)
    XCTAssertEqual(a.tool, .pen)
    XCTAssertEqual(a.colorHex, DrawingPalette.defaultHex)

    let b = Stroke(
      id: a.id,
      points: a.points,
      lineWidth: a.lineWidth,
      tool: a.tool,
      colorHex: a.colorHex
    )
    XCTAssertEqual(a, b)
  }

  func testStrokeCodableFillsMissingOptionalFields() throws {
    let id = UUID()
    let json = """
    {
      "id": "\(id.uuidString)",
      "points": [{"x": 0.5, "y": 0.5}]
    }
    """.data(using: .utf8)!

    let stroke = try JSONDecoder().decode(Stroke.self, from: json)
    XCTAssertEqual(stroke.id, id)
    XCTAssertEqual(stroke.points.count, 1)
    XCTAssertEqual(stroke.lineWidth, DrawingTool.pen.defaultWidth)
    XCTAssertEqual(stroke.tool, .pen)
    XCTAssertEqual(stroke.colorHex, DrawingPalette.defaultHex)
  }

  func testStrokeCodableRoundTripPreservesToolAndColor() throws {
    let stroke = Stroke(
      points: [DrawPoint(x: 0.1, y: 0.2, lineWidth: 9), DrawPoint(x: 0.3, y: 0.4)],
      lineWidth: 24,
      tool: .highlighter,
      colorHex: "#EF68C8"
    )
    let data = try JSONEncoder().encode(stroke)
    let decoded = try JSONDecoder().decode(Stroke.self, from: data)
    XCTAssertEqual(decoded, stroke)
  }

  func testDrawingIsEmptyAndCapped() {
    XCTAssertTrue(Drawing.empty.isEmpty)
    XCTAssertTrue(Drawing(strokes: [Stroke(points: [])]).isEmpty)

    let points = (0..<20).map { DrawPoint(x: Double($0) / 20, y: 0.5) }
    let strokes = (0..<5).map { _ in
      Stroke(points: points, tool: .pencil, colorHex: "#6176FF")
    }
    let drawing = Drawing(strokes: strokes)
    XCTAssertFalse(drawing.isEmpty)

    let capped = drawing.capped(maxStrokes: 2, maxPointsPerStroke: 3)
    XCTAssertEqual(capped.strokes.count, 2)
    XCTAssertTrue(capped.strokes.allSatisfy { $0.points.count == 3 })
  }

  func testDrawingCodableRoundTrip() throws {
    let drawing = Drawing(strokes: [
      Stroke(points: [DrawPoint(x: 0, y: 0)], tool: .eraser, colorHex: "#FFFFFF"),
      Stroke(points: [DrawPoint(x: 1, y: 1)], tool: .pen, colorHex: "#000000"),
    ])
    let data = try JSONEncoder().encode(drawing)
    let decoded = try JSONDecoder().decode(Drawing.self, from: data)
    XCTAssertEqual(decoded, drawing)
  }

  // MARK: - DrawingUndoStack

  func testUndoRemovesCommittedStroke() {
    var stack = DrawingUndoStack()
    var drawing = Drawing.empty
    XCTAssertFalse(stack.canUndo)

    drawing.strokes.append(Stroke(points: [DrawPoint(x: 0.1, y: 0.1)]))
    stack.registerStrokeAdded()
    drawing.strokes.append(Stroke(points: [DrawPoint(x: 0.9, y: 0.9)]))
    stack.registerStrokeAdded()
    XCTAssertTrue(stack.canUndo)
    XCTAssertEqual(drawing.strokes.count, 2)

    stack.undo(drawing: &drawing)
    XCTAssertEqual(drawing.strokes.count, 1)
    XCTAssertEqual(drawing.strokes[0].points[0].x, 0.1, accuracy: 0.0001)

    stack.undo(drawing: &drawing)
    XCTAssertTrue(drawing.isEmpty)
    XCTAssertFalse(stack.canUndo)

    stack.undo(drawing: &drawing)
    XCTAssertTrue(drawing.isEmpty)
  }

  func testUndoRestoresClear() {
    var stack = DrawingUndoStack()
    var drawing = Drawing(strokes: [
      Stroke(points: [DrawPoint(x: 0.2, y: 0.3)]),
      Stroke(points: [DrawPoint(x: 0.4, y: 0.5)]),
    ])
    let snapshot = drawing

    stack.registerClear(before: drawing)
    drawing = .empty
    XCTAssertTrue(stack.canUndo)

    stack.undo(drawing: &drawing)
    XCTAssertEqual(drawing, snapshot)
    XCTAssertFalse(stack.canUndo)
  }

  func testRegisterClearIgnoresEmptyDrawing() {
    var stack = DrawingUndoStack()
    stack.registerClear(before: .empty)
    XCTAssertFalse(stack.canUndo)

    stack.registerClear(before: Drawing(strokes: [Stroke(points: [])]))
    XCTAssertFalse(stack.canUndo)
  }

  func testUndoStackTrimsToTenSteps() {
    var stack = DrawingUndoStack()
    var drawing = Drawing.empty

    for i in 0..<12 {
      drawing.strokes.append(Stroke(points: [DrawPoint(x: Double(i), y: 0)]))
      stack.registerStrokeAdded()
    }
    XCTAssertTrue(stack.canUndo)

    for _ in 0..<10 {
      stack.undo(drawing: &drawing)
    }
    XCTAssertFalse(stack.canUndo)
    // Oldest two stroke-adds were trimmed — only 2 strokes remain after 10 undos from 12.
    XCTAssertEqual(drawing.strokes.count, 2)
  }

  func testUndoStackResetClearsHistory() {
    var stack = DrawingUndoStack()
    var drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0, y: 0)])])
    stack.registerStrokeAdded()
    stack.reset()
    XCTAssertFalse(stack.canUndo)
    stack.undo(drawing: &drawing)
    XCTAssertEqual(drawing.strokes.count, 1)
  }

  func testStrokeThenClearUndoOrder() {
    var stack = DrawingUndoStack()
    var drawing = Drawing.empty

    drawing.strokes.append(Stroke(points: [DrawPoint(x: 0.1, y: 0.1)]))
    stack.registerStrokeAdded()
    drawing.strokes.append(Stroke(points: [DrawPoint(x: 0.2, y: 0.2)]))
    stack.registerStrokeAdded()

    let beforeClear = drawing
    stack.registerClear(before: drawing)
    drawing = .empty

    stack.undo(drawing: &drawing)
    XCTAssertEqual(drawing, beforeClear)

    stack.undo(drawing: &drawing)
    XCTAssertEqual(drawing.strokes.count, 1)
  }

  // MARK: - LiveStrokeSession

  private let canvasSize = CGSize(width: 390, height: 390)

  func testLiveStrokeStartsWithNormalizedPointAndToolSettings() throws {
    var session = LiveStrokeSession()
    session.appendSample(
      at: CGPoint(x: 39, y: 78),
      timestamp: 1,
      in: canvasSize,
      tool: .pencil,
      colorHex: "#EC6363",
      lineWidth: 16
    )

    let stroke = try XCTUnwrap(session.currentStroke)
    XCTAssertEqual(stroke.tool, .pencil)
    XCTAssertEqual(stroke.colorHex, "#EC6363")
    XCTAssertEqual(stroke.lineWidth, 16)
    XCTAssertEqual(stroke.points.count, 1)
    XCTAssertEqual(stroke.points[0].x, 0.1, accuracy: 0.0001)
    XCTAssertEqual(stroke.points[0].y, 0.2, accuracy: 0.0001)
    XCTAssertNil(stroke.points[0].lineWidth)
    XCTAssertFalse(session.isLiveErasing)
  }

  func testLiveStrokePenFirstSampleUsesBoostedWidth() throws {
    var session = LiveStrokeSession()
    session.appendSample(
      at: CGPoint(x: 10, y: 10),
      timestamp: 0,
      in: canvasSize,
      tool: .pen,
      colorHex: DrawingPalette.defaultHex,
      lineWidth: 10
    )

    let width = try XCTUnwrap(session.currentStroke?.points.first?.lineWidth)
    XCTAssertEqual(width, 10 * 1.15, accuracy: 0.0001)
  }

  func testLiveStrokeDropsSamplesCloserThanMinSpacing() {
    var session = LiveStrokeSession()
    session.appendSample(
      at: .zero,
      timestamp: 0,
      in: canvasSize,
      tool: .highlighter,
      colorHex: "#EEDB4D",
      lineWidth: 24
    )
    // 0.5pt move < minSpacing (0.7)
    session.appendSample(
      at: CGPoint(x: 0.5, y: 0),
      timestamp: 0.01,
      in: canvasSize,
      tool: .highlighter,
      colorHex: "#EEDB4D",
      lineWidth: 24
    )
    XCTAssertEqual(session.currentStroke?.points.count, 1)

    session.appendSample(
      at: CGPoint(x: 8, y: 0),
      timestamp: 0.02,
      in: canvasSize,
      tool: .highlighter,
      colorHex: "#EEDB4D",
      lineWidth: 24
    )
    XCTAssertEqual(session.currentStroke?.points.count, 2)
  }

  func testLiveStrokePenUpdatesWidthWhenSampleIsTooClose() throws {
    var session = LiveStrokeSession()
    session.appendSample(
      at: .zero,
      timestamp: 0,
      in: canvasSize,
      tool: .pen,
      colorHex: DrawingPalette.defaultHex,
      lineWidth: 10
    )
    let firstWidth = try XCTUnwrap(session.currentStroke?.points.first?.lineWidth)

    // Fast tiny move: spacing rejects append, but pen tip width still refreshes.
    session.appendSample(
      at: CGPoint(x: 0.4, y: 0),
      timestamp: 0.001,
      in: canvasSize,
      tool: .pen,
      colorHex: DrawingPalette.defaultHex,
      lineWidth: 10
    )
    XCTAssertEqual(session.currentStroke?.points.count, 1)
    let updated = try XCTUnwrap(session.currentStroke?.points.first?.lineWidth)
    XCTAssertGreaterThan(abs(updated - firstWidth), 0.0001)
  }

  func testLiveStrokePenWidthThinsWhenFingerMovesFast() throws {
    var session = LiveStrokeSession()
    session.appendSample(
      at: .zero,
      timestamp: 0,
      in: canvasSize,
      tool: .pen,
      colorHex: DrawingPalette.defaultHex,
      lineWidth: 10
    )
    let startWidth = try XCTUnwrap(session.currentStroke?.points.first?.lineWidth)

    session.appendSample(
      at: CGPoint(x: 120, y: 0),
      timestamp: 0.01,
      in: canvasSize,
      tool: .pen,
      colorHex: DrawingPalette.defaultHex,
      lineWidth: 10
    )
    let fastWidth = try XCTUnwrap(session.currentStroke?.points.last?.lineWidth)
    XCTAssertLessThan(fastWidth, startWidth)
  }

  func testLiveStrokeFinishMergesNearDuplicateEndPoint() throws {
    var session = LiveStrokeSession()
    session.appendSample(
      at: CGPoint(x: 100, y: 100),
      timestamp: 0,
      in: canvasSize,
      tool: .pen,
      colorHex: DrawingPalette.defaultHex,
      lineWidth: 10
    )
    session.appendSample(
      at: CGPoint(x: 140, y: 100),
      timestamp: 0.05,
      in: canvasSize,
      tool: .pen,
      colorHex: DrawingPalette.defaultHex,
      lineWidth: 10
    )

    let finished = try XCTUnwrap(
      session.finish(
        at: CGPoint(x: 140.05, y: 100),
        in: canvasSize,
        tool: .pen,
        lineWidth: 10
      )
    )
    XCTAssertEqual(finished.points.count, 2)
    XCTAssertNotNil(finished.points.last?.lineWidth)
    XCTAssertNil(session.currentStroke)
  }

  func testLiveStrokeFinishAppendsDistinctEndPoint() throws {
    var session = LiveStrokeSession()
    session.appendSample(
      at: .zero,
      timestamp: 0,
      in: canvasSize,
      tool: .eraser,
      colorHex: "#000000",
      lineWidth: 24
    )
    XCTAssertTrue(session.isLiveErasing)

    let finished = try XCTUnwrap(
      session.finish(
        at: CGPoint(x: 50, y: 60),
        in: canvasSize,
        tool: .eraser,
        lineWidth: 24
      )
    )
    XCTAssertEqual(finished.points.count, 2)
    XCTAssertEqual(finished.tool, .eraser)
    XCTAssertNil(finished.points.last?.lineWidth)
    XCTAssertFalse(session.isLiveErasing)
  }

  func testLiveStrokeFinishWithNoSamplesReturnsNil() {
    var session = LiveStrokeSession()
    XCTAssertNil(
      session.finish(
        at: .zero,
        in: canvasSize,
        tool: .pen,
        lineWidth: 10
      )
    )
  }

  func testLiveStrokeGuardsAgainstZeroCanvasSize() throws {
    var session = LiveStrokeSession()
    session.appendSample(
      at: CGPoint(x: 0.5, y: 0.5),
      timestamp: 0,
      in: .zero,
      tool: .pen,
      colorHex: DrawingPalette.defaultHex,
      lineWidth: 10
    )
    let stroke = try XCTUnwrap(session.currentStroke)
    XCTAssertEqual(stroke.points[0].x, 0.5, accuracy: 0.0001)
    XCTAssertEqual(stroke.points[0].y, 0.5, accuracy: 0.0001)
  }

  // MARK: - StrokeRenderer

  func testCanvasPointsScaleNormalizedCoordinates() {
    let stroke = Stroke(points: [
      DrawPoint(x: 0, y: 0),
      DrawPoint(x: 0.5, y: 1),
      DrawPoint(x: 1, y: 0.25),
    ])
    let points = StrokeRenderer.canvasPoints(for: stroke, size: CGSize(width: 200, height: 400))
    XCTAssertEqual(points.count, 3)
    XCTAssertEqual(points[0], .zero)
    XCTAssertEqual(points[1].x, 100, accuracy: 0.001)
    XCTAssertEqual(points[1].y, 400, accuracy: 0.001)
    XCTAssertEqual(points[2].x, 200, accuracy: 0.001)
    XCTAssertEqual(points[2].y, 100, accuracy: 0.001)
  }

  func testPenWidthSlowsThickerFasterThinner() {
    let base = 10.0
    let slow = StrokeRenderer.penWidth(base: base, speedPointsPerSecond: 0)
    let mid = StrokeRenderer.penWidth(base: base, speedPointsPerSecond: 800)
    let fast = StrokeRenderer.penWidth(base: base, speedPointsPerSecond: 1600)
    let clamped = StrokeRenderer.penWidth(base: base, speedPointsPerSecond: 10_000)
    let negative = StrokeRenderer.penWidth(base: base, speedPointsPerSecond: -50)

    XCTAssertGreaterThan(slow, mid)
    XCTAssertGreaterThan(mid, fast)
    XCTAssertEqual(fast, clamped, accuracy: 0.0001)
    XCTAssertEqual(slow, negative, accuracy: 0.0001)
    XCTAssertEqual(slow, base * 1.65, accuracy: 0.0001)
    XCTAssertEqual(fast, max(0.6, base * 0.32), accuracy: 0.0001)
    XCTAssertGreaterThanOrEqual(StrokeRenderer.penWidth(base: 0.1, speedPointsPerSecond: 1600), 0.6)
  }

  func testSmoothPathHandlesEmptyOneTwoAndManyPoints() {
    XCTAssertTrue(StrokeRenderer.smoothPath(from: []).isEmpty)

    let single = StrokeRenderer.smoothPath(from: [CGPoint(x: 10, y: 20)])
    XCTAssertFalse(single.isEmpty)

    let pair = StrokeRenderer.smoothPath(from: [
      CGPoint(x: 0, y: 0),
      CGPoint(x: 40, y: 0),
    ])
    XCTAssertFalse(pair.isEmpty)
    XCTAssertEqual(pair.boundingRect.width, 40, accuracy: 0.001)

    let curve = StrokeRenderer.smoothPath(from: [
      CGPoint(x: 0, y: 0),
      CGPoint(x: 20, y: 40),
      CGPoint(x: 40, y: 0),
      CGPoint(x: 60, y: 40),
    ])
    XCTAssertFalse(curve.isEmpty)
    XCTAssertGreaterThan(curve.boundingRect.width, 0)
  }

  func testSampleCountAndReplayDuration() {
    XCTAssertEqual(StrokeRenderer.sampleCount(of: .empty), 0)
    XCTAssertEqual(StrokeRenderer.replayDuration(for: .empty), 0.45, accuracy: 0.0001)

    let short = Drawing(strokes: [
      Stroke(points: (0..<10).map { DrawPoint(x: Double($0), y: 0) }),
    ])
    XCTAssertEqual(StrokeRenderer.sampleCount(of: short), 10)
    XCTAssertEqual(StrokeRenderer.replayDuration(for: short), 0.45, accuracy: 0.0001)

    let long = Drawing(strokes: [
      Stroke(points: (0..<1_000).map { DrawPoint(x: Double($0), y: 0) }),
    ])
    XCTAssertEqual(StrokeRenderer.sampleCount(of: long), 1_000)
    XCTAssertEqual(
      StrokeRenderer.replayDuration(for: long),
      min(2.6, Double(1_000) / 260),
      accuracy: 0.0001
    )

    let epic = Drawing(strokes: [
      Stroke(points: (0..<5_000).map { DrawPoint(x: Double($0), y: 0) }),
    ])
    XCTAssertEqual(StrokeRenderer.replayDuration(for: epic), 2.6, accuracy: 0.0001)
  }

  @MainActor
  func testBakeReturnsImageForValidSizeAndNilForTiny() {
    let drawing = Drawing(strokes: [
      Stroke(
        points: [
          DrawPoint(x: 0.1, y: 0.1, lineWidth: 12),
          DrawPoint(x: 0.5, y: 0.6, lineWidth: 8),
          DrawPoint(x: 0.9, y: 0.2, lineWidth: 10),
        ],
        tool: .pen,
        colorHex: "#000000"
      ),
      Stroke(
        points: [DrawPoint(x: 0.2, y: 0.8), DrawPoint(x: 0.8, y: 0.8)],
        lineWidth: 16,
        tool: .pencil,
        colorHex: "#6176FF"
      ),
      Stroke(
        points: [DrawPoint(x: 0.3, y: 0.3), DrawPoint(x: 0.7, y: 0.7)],
        lineWidth: 24,
        tool: .highlighter,
        colorHex: "#EEDB4D"
      ),
      Stroke(
        points: [DrawPoint(x: 0.4, y: 0.4), DrawPoint(x: 0.6, y: 0.5)],
        lineWidth: 24,
        tool: .eraser,
        colorHex: "#000000"
      ),
    ])

    let image = StrokeRenderer.bake(
      drawing,
      size: CGSize(width: 120, height: 120),
      scale: 2
    )
    XCTAssertNotNil(image)
    XCTAssertEqual(image?.size.width ?? 0, 120, accuracy: 0.5)
    XCTAssertEqual(image?.size.height ?? 0, 120, accuracy: 0.5)

    XCTAssertNil(
      StrokeRenderer.bake(drawing, size: CGSize(width: 1, height: 100), scale: 1)
    )
    XCTAssertNil(
      StrokeRenderer.bake(.empty, size: .zero, scale: 1)
    )
  }

  @MainActor
  func testBakeSucceedsForEachToolAlone() {
    for tool in DrawingTool.allCases {
      let drawing = Drawing(strokes: [
        Stroke(
          points: [
            DrawPoint(x: 0.2, y: 0.2, lineWidth: tool == .pen ? 14 : nil),
            DrawPoint(x: 0.5, y: 0.55, lineWidth: tool == .pen ? 8 : nil),
            DrawPoint(x: 0.8, y: 0.3, lineWidth: tool == .pen ? 11 : nil),
          ],
          lineWidth: tool.defaultWidth,
          tool: tool,
          colorHex: DrawingPalette.defaultHex
        ),
      ])
      let image = StrokeRenderer.bake(
        drawing,
        size: CGSize(width: 80, height: 80),
        scale: 1
      )
      XCTAssertNotNil(image, "bake failed for \(tool.displayName)")
    }
  }

  @MainActor
  func testBakeSucceedsForEachPaperStyle() {
    let drawing = Drawing(strokes: [
      Stroke(
        points: [DrawPoint(x: 0.2, y: 0.2), DrawPoint(x: 0.8, y: 0.8)],
        tool: .pen,
        colorHex: "#000000"
      ),
    ])
    for style in PaperStyle.allCases {
      let image = StrokeRenderer.bake(
        drawing,
        size: CGSize(width: 64, height: 64),
        scale: 1,
        paperStyle: style
      )
      XCTAssertNotNil(image, "bake failed for paper \(style.rawValue)")
    }
  }
}

final class DrawPromptGateTests: XCTestCase {
  func testSingleWordPromptOpensCover() {
    XCTAssertEqual(DrawPromptGate.word(in: "cat"), "cat")
    XCTAssertEqual(DrawPromptGate.word(in: "  Pets  "), "Pets")
    XCTAssertEqual(DrawPromptGate.headline(for: "cat"), "Draw a cat")
    XCTAssertEqual(DrawPromptGate.headline(for: "Pets"), "Draw a Pets")
  }

  func testPhraseAndBlankPromptsAreNotWords() {
    XCTAssertNil(DrawPromptGate.word(in: "Farm animals"))
    XCTAssertNil(DrawPromptGate.word(in: "hot dog"))
    XCTAssertNil(DrawPromptGate.word(in: ""))
    XCTAssertNil(DrawPromptGate.word(in: "   "))
  }
}
