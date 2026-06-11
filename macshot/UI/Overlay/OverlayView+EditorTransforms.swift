import AVFoundation
import Cocoa
import UniformTypeIdentifiers

extension OverlayView {
    // MARK: - Editor Image Transforms

    func flipImageHorizontally() {
        guard let original = screenshotImage,
            let cgImage = original.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        // Save state for undo
        let prevImage = original.copy() as! NSImage
        undoStack.append(.imageTransform(previousImage: prevImage, annotationOffsets: []))
        redoStack.removeAll()

        let w = cgImage.width
        let h = cgImage.height
        // Preserve the source image's color space so colors stay correct.
        let cs = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard
            let ctx = CGContext(
                data: nil, width: w, height: h,
                bitsPerComponent: 8,
                bytesPerRow: 0, space: cs,
                bitmapInfo: bitmapInfo)
        else { return }
        ctx.translateBy(x: CGFloat(w), y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let flipped = ctx.makeImage() else { return }

        screenshotImage = NSImage(cgImage: flipped, size: original.size)

        // Mirror annotation X coordinates around the image center
        let imgW = original.size.width
        for ann in annotations {
            ann.startPoint.x = selectionRect.minX + (selectionRect.maxX - ann.startPoint.x)
            ann.endPoint.x = selectionRect.minX + (selectionRect.maxX - ann.endPoint.x)
            if let cp = ann.controlPoint {
                ann.controlPoint = NSPoint(
                    x: selectionRect.minX + (selectionRect.maxX - cp.x), y: cp.y)
            }
            // Mirror freeform points
            if let pts = ann.points {
                ann.points = pts.map {
                    NSPoint(x: selectionRect.minX + (selectionRect.maxX - $0.x), y: $0.y)
                }
            }
        }

        cachedCompositedImage = nil
        needsDisplay = true
    }

    func flipImageVertically() {
        guard let original = screenshotImage,
            let cgImage = original.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        let prevImage = original.copy() as! NSImage
        undoStack.append(.imageTransform(previousImage: prevImage, annotationOffsets: []))
        redoStack.removeAll()

        let w = cgImage.width
        let h = cgImage.height
        let cs = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard
            let ctx = CGContext(
                data: nil, width: w, height: h,
                bitsPerComponent: 8,
                bytesPerRow: 0, space: cs,
                bitmapInfo: bitmapInfo)
        else { return }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let flipped = ctx.makeImage() else { return }

        screenshotImage = NSImage(cgImage: flipped, size: original.size)

        // Mirror annotation Y coordinates around the image center
        for ann in annotations {
            ann.startPoint.y = selectionRect.minY + (selectionRect.maxY - ann.startPoint.y)
            ann.endPoint.y = selectionRect.minY + (selectionRect.maxY - ann.endPoint.y)
            if let cp = ann.controlPoint {
                ann.controlPoint = NSPoint(
                    x: cp.x, y: selectionRect.minY + (selectionRect.maxY - cp.y))
            }
            if let pts = ann.points {
                ann.points = pts.map {
                    NSPoint(x: $0.x, y: selectionRect.minY + (selectionRect.maxY - $0.y))
                }
            }
        }

        cachedCompositedImage = nil
        needsDisplay = true
    }

    /// Add a captured image as a draggable stamp annotation, placed below the current canvas.
    /// The canvas auto-expands to fit. Used by "Add Capture" in the editor.
    func addCaptureImage(_ newImage: NSImage) {
        let imgW = newImage.size.width
        let imgH = newImage.size.height

        // Place below the current canvas, left-aligned
        let placeY = -imgH  // just below origin (canvas will expand)

        let ann = Annotation(
            tool: .stamp,
            startPoint: NSPoint(x: 0, y: placeY),
            endPoint: NSPoint(x: imgW, y: placeY + imgH),
            color: NSColor.white.withAlphaComponent(0),
            strokeWidth: 0)
        ann.stampImage = newImage

        annotations.append(ann)
        undoStack.append(.added(ann))
        redoStack.removeAll()

        // Auto-select so user can move/resize immediately
        currentTool = .select
        selectedAnnotation = ann
        cachedCompositedImage = nil

        // Expand the canvas to fit the new annotation
        expandCanvasToFitAnnotations()
        rebuildToolbarLayout()
        needsDisplay = true
    }

    /// Resizes the canvas to tightly fit the original image content plus all annotations.
    /// Grows or shrinks as needed. Shifts everything so origin stays at (0,0).
    /// Only runs the expensive pixel scan when add-capture stamps are present.
    func expandCanvasToFitAnnotations() {
        guard isEditorMode, let original = screenshotImage,
              let oldCG = original.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        // Only resize canvas when there are add-capture image stamps that might be outside bounds.
        // Normal annotations (arrows, text, etc.) don't need canvas resizing.
        let hasImageStamps = annotations.contains { $0.tool == .stamp && $0.stampImage != nil }
        guard hasImageStamps else { return }

        let scale = CGFloat(oldCG.width) / original.size.width

        // Detect the non-transparent bounding box of the original image.
        let opaqueRect: NSRect
        if let cached = cachedOpaqueRect {
            opaqueRect = cached
        } else {
            opaqueRect = opaqueContentRect(of: oldCG, scale: scale)
            cachedOpaqueRect = opaqueRect
        }

        // Compute bounding box of opaque image content + all annotations
        var minX: CGFloat = opaqueRect.minX
        var minY: CGFloat = opaqueRect.minY
        var maxX: CGFloat = opaqueRect.maxX
        var maxY: CGFloat = opaqueRect.maxY

        for ann in annotations {
            let r = ann.boundingRect
            guard r.width > 0, r.height > 0 else { continue }
            minX = min(minX, r.minX)
            minY = min(minY, r.minY)
            maxX = max(maxX, r.maxX)
            maxY = max(maxY, r.maxY)
        }

        let targetRect = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        // If canvas already matches, nothing to do
        if abs(minX) < 1 && abs(minY) < 1
            && abs(maxX - selectionRect.width) < 1 && abs(maxY - selectionRect.height) < 1 {
            return
        }

        let newPtW = targetRect.width
        let newPtH = targetRect.height
        let newPxW = max(1, Int(newPtW * scale))
        let newPxH = max(1, Int(newPtH * scale))

        let cs = oldCG.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: newPxW, height: newPxH,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        // Draw old image offset so that targetRect.origin maps to (0,0)
        let drawX = -targetRect.origin.x * scale
        let drawY = -targetRect.origin.y * scale
        ctx.draw(oldCG, in: CGRect(x: drawX, y: drawY, width: CGFloat(oldCG.width), height: CGFloat(oldCG.height)))

        guard let newCG = ctx.makeImage() else { return }
        let prevImage = original.copy() as! NSImage
        let shiftDx = -targetRect.origin.x
        let shiftDy = -targetRect.origin.y
        let offsets = annotations.map { ($0, shiftDx, shiftDy) }
        undoStack.append(.imageTransform(previousImage: prevImage, annotationOffsets: offsets))

        screenshotImage = NSImage(cgImage: newCG, size: NSSize(width: newPtW, height: newPtH))
        cachedOpaqueRect = nil  // invalidate — image content changed

        // Shift all annotations so they align with the new origin
        if shiftDx != 0 || shiftDy != 0 {
            for ann in annotations {
                ann.move(dx: shiftDx, dy: shiftDy)
            }
        }

        selectionRect = NSRect(origin: .zero, size: NSSize(width: newPtW, height: newPtH))
        frame.size = NSSize(width: newPtW, height: newPtH)
        cachedCompositedImage = nil
    }

    /// Returns the bounding rect (in point coords) of non-transparent pixels in the image.
    /// Uses fast row/column scanning on the raw pixel data.
    func opaqueContentRect(of cgImage: CGImage, scale: CGFloat) -> NSRect {
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0,
              let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else {
            return NSRect(x: 0, y: 0, width: CGFloat(w) / scale, height: CGFloat(h) / scale)
        }

        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        guard bytesPerPixel >= 4 else {
            return NSRect(x: 0, y: 0, width: CGFloat(w) / scale, height: CGFloat(h) / scale)
        }

        // Alpha channel offset depends on bitmap info
        let alphaInfo = CGImageAlphaInfo(rawValue: cgImage.bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue)
        let alphaOffset: Int
        switch alphaInfo {
        case .premultipliedFirst, .first, .noneSkipFirst: alphaOffset = 0
        case .premultipliedLast, .last, .noneSkipLast: alphaOffset = 3
        default: alphaOffset = 3
        }

        var minRow = h, maxRow = 0, minCol = w, maxCol = 0

        for row in 0..<h {
            let rowBase = row * bytesPerRow
            for col in 0..<w {
                let alpha = ptr[rowBase + col * bytesPerPixel + alphaOffset]
                if alpha > 0 {
                    if row < minRow { minRow = row }
                    if row > maxRow { maxRow = row }
                    if col < minCol { minCol = col }
                    if col > maxCol { maxCol = col }
                }
            }
        }

        if minRow > maxRow {
            // Fully transparent — return full rect
            return NSRect(x: 0, y: 0, width: CGFloat(w) / scale, height: CGFloat(h) / scale)
        }

        // CGImage rows are top-to-bottom, convert to AppKit bottom-left origin
        let ptMinX = CGFloat(minCol) / scale
        let ptMinY = CGFloat(h - 1 - maxRow) / scale
        let ptMaxX = CGFloat(maxCol + 1) / scale
        let ptMaxY = CGFloat(h - minRow) / scale
        return NSRect(x: ptMinX, y: ptMinY, width: ptMaxX - ptMinX, height: ptMaxY - ptMinY)
    }

    func invertImageColors() {
        guard let original = screenshotImage,
            let cgImage = original.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        let prevImage = original.copy() as! NSImage
        undoStack.append(.imageTransform(previousImage: prevImage, annotationOffsets: []))
        redoStack.removeAll()

        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIColorInvert") else { return }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        guard let output = filter.outputImage else { return }

        let ciCtx = CIContext()
        guard let inverted = ciCtx.createCGImage(output, from: output.extent) else { return }

        screenshotImage = NSImage(cgImage: inverted, size: original.size)
        cachedCompositedImage = nil
        needsDisplay = true
    }

    // MARK: - Snap/Alignment Guides

    /// Collect all snap target X and Y values from the selection rect and existing annotations.
    func collectSnapTargets(excluding: Annotation? = nil) -> (xs: [CGFloat], ys: [CGFloat])
    {
        var xs: [CGFloat] = []
        var ys: [CGFloat] = []

        // Selection rect edges and center
        xs += [selectionRect.minX, selectionRect.midX, selectionRect.maxX]
        ys += [selectionRect.minY, selectionRect.midY, selectionRect.maxY]

        // Existing annotation bounding rects
        for ann in annotations where ann !== excluding {
            let r = ann.boundingRect
            guard r.width > 0 || r.height > 0 else { continue }
            xs += [r.minX, r.midX, r.maxX]
            ys += [r.minY, r.midY, r.maxY]
        }

        return (xs, ys)
    }

    /// Snap a point's X and Y to the nearest target within threshold. Returns snapped point and sets guide lines.
    func snapPoint(_ point: NSPoint, excluding: Annotation? = nil) -> NSPoint {
        guard snapGuidesEnabled else {
            snapGuideX = nil
            snapGuideY = nil
            return point
        }

        let (xs, ys) = collectSnapTargets(excluding: excluding)
        var result = point
        snapGuideX = nil
        snapGuideY = nil

        // Snap X
        var bestDx: CGFloat = snapThreshold + 1
        for tx in xs {
            let d = abs(point.x - tx)
            if d < bestDx {
                bestDx = d
                result.x = tx
                snapGuideX = tx
            }
        }
        if bestDx > snapThreshold {
            snapGuideX = nil
            result.x = point.x
        }

        // Snap Y
        var bestDy: CGFloat = snapThreshold + 1
        for ty in ys {
            let d = abs(point.y - ty)
            if d < bestDy {
                bestDy = d
                result.y = ty
                snapGuideY = ty
            }
        }
        if bestDy > snapThreshold {
            snapGuideY = nil
            result.y = point.y
        }

        return result
    }

    /// Snap a rect (for move operations) — checks all edges and center against targets.
    /// Returns the delta adjustment needed.
    func snapRectDelta(rect: NSRect, excluding: Annotation? = nil) -> (
        dx: CGFloat, dy: CGFloat
    ) {
        guard snapGuidesEnabled else {
            snapGuideX = nil
            snapGuideY = nil
            return (0, 0)
        }

        let (xs, ys) = collectSnapTargets(excluding: excluding)
        let edgesX = [rect.minX, rect.midX, rect.maxX]
        let edgesY = [rect.minY, rect.midY, rect.maxY]

        snapGuideX = nil
        snapGuideY = nil
        var bestDx: CGFloat = snapThreshold + 1
        var snapDx: CGFloat = 0
        var bestDy: CGFloat = snapThreshold + 1
        var snapDy: CGFloat = 0

        for ex in edgesX {
            for tx in xs {
                let d = abs(ex - tx)
                if d < bestDx {
                    bestDx = d
                    snapDx = tx - ex
                    snapGuideX = tx
                }
            }
        }
        if bestDx > snapThreshold {
            snapGuideX = nil
            snapDx = 0
        }

        for ey in edgesY {
            for ty in ys {
                let d = abs(ey - ty)
                if d < bestDy {
                    bestDy = d
                    snapDy = ty - ey
                    snapGuideY = ty
                }
            }
        }
        if bestDy > snapThreshold {
            snapGuideY = nil
            snapDy = 0
        }

        return (snapDx, snapDy)
    }

    /// Draw snap guide lines (called from draw after annotations, before toolbars).
    func drawSnapGuides() {
        guard snapGuidesEnabled else { return }

        let guideColor = NSColor.systemCyan.withAlphaComponent(0.6)
        guideColor.setStroke()

        if let gx = snapGuideX {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: gx, y: selectionRect.minY))
            line.line(to: NSPoint(x: gx, y: selectionRect.maxY))
            line.lineWidth = 0.5
            let pattern: [CGFloat] = [4, 3]
            line.setLineDash(pattern, count: 2, phase: 0)
            line.stroke()
        }

        if let gy = snapGuideY {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: selectionRect.minX, y: gy))
            line.line(to: NSPoint(x: selectionRect.maxX, y: gy))
            line.lineWidth = 0.5
            let pattern: [CGFloat] = [4, 3]
            line.setLineDash(pattern, count: 2, phase: 0)
            line.stroke()
        }
    }

}
