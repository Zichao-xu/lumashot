import AVFoundation
import Cocoa
import UniformTypeIdentifiers

extension OverlayView {
    // MARK: - Auto Measure

    /// Update the auto-measure live preview based on cursor position.
    /// Called on keyDown repeat and mouseMoved while key is held.
    func updateAutoMeasurePreview() {
        let vertical = autoMeasureVertical
        autoMeasurePreview = computeAutoMeasure(vertical: vertical)
        needsDisplay = true
    }

    /// Compute an auto-measure annotation from the cursor position along a vertical or horizontal axis
    /// by scanning outward until the pixel color changes significantly.
    func computeAutoMeasure(vertical: Bool) -> Annotation? {
        guard let screenshot = screenshotImage,
            let cgImage = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        guard let window = window else { return nil }
        let windowPoint = window.mouseLocationOutsideOfEventStream
        let viewPoint = convert(windowPoint, from: nil)
        let canvasPoint = viewToCanvas(viewPoint)

        let drawRect = captureDrawRect
        let normX = (canvasPoint.x - drawRect.minX) / drawRect.width
        let normY = (canvasPoint.y - drawRect.minY) / drawRect.height

        let w = cgImage.width
        let h = cgImage.height

        let pixelX = Int(normX * CGFloat(w))
        let pixelY = Int((1.0 - normY) * CGFloat(h))

        guard pixelX >= 0, pixelX < w, pixelY >= 0, pixelY < h else {
            return nil
        }

        // Cache the bitmap context — only recreate if the image dimensions changed
        if autoMeasureBitmapCtx == nil || autoMeasureBitmapW != w || autoMeasureBitmapH != h {
            let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
            guard let ctx = CGContext(
                data: nil, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: srgb,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            autoMeasureBitmapCtx = ctx
            autoMeasureBitmapW = w
            autoMeasureBitmapH = h
        }

        guard let data = autoMeasureBitmapCtx?.data else { return nil }
        let ptr = data.assumingMemoryBound(to: UInt8.self)

        func pixelAt(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
            let offset = (y * w + x) * 4
            return (ptr[offset], ptr[offset + 1], ptr[offset + 2])
        }

        func colorDiff(_ a: (UInt8, UInt8, UInt8), _ b: (UInt8, UInt8, UInt8)) -> Int {
            abs(Int(a.0) - Int(b.0)) + abs(Int(a.1) - Int(b.1)) + abs(Int(a.2) - Int(b.2))
        }

        let refColor = pixelAt(pixelX, pixelY)
        let threshold = 30

        func toCanvas(px: Int, py: Int) -> NSPoint {
            let nx = CGFloat(px) / CGFloat(w)
            let ny = 1.0 - CGFloat(py) / CGFloat(h)
            return NSPoint(
                x: drawRect.minX + nx * drawRect.width,
                y: drawRect.minY + ny * drawRect.height)
        }

        var startPx: Int
        var endPx: Int

        if vertical {
            startPx = pixelY
            for py in stride(from: pixelY - 1, through: 0, by: -1) {
                if colorDiff(refColor, pixelAt(pixelX, py)) > threshold { break }
                startPx = py
            }
            endPx = pixelY
            for py in (pixelY + 1)..<h {
                if colorDiff(refColor, pixelAt(pixelX, py)) > threshold { break }
                endPx = py
            }
            let p1 = toCanvas(px: pixelX, py: startPx)
            let p2 = toCanvas(px: pixelX, py: endPx)
            let ann = Annotation(
                tool: .measure, startPoint: p1, endPoint: p2,
                color: annotationColor, strokeWidth: currentStrokeWidth)
            ann.measureInPoints = currentMeasureInPoints
            return ann
        } else {
            startPx = pixelX
            for px in stride(from: pixelX - 1, through: 0, by: -1) {
                if colorDiff(refColor, pixelAt(px, pixelY)) > threshold { break }
                startPx = px
            }
            endPx = pixelX
            for px in (pixelX + 1)..<w {
                if colorDiff(refColor, pixelAt(px, pixelY)) > threshold { break }
                endPx = px
            }
            let p1 = toCanvas(px: startPx, py: pixelY)
            let p2 = toCanvas(px: endPx, py: pixelY)
            let ann = Annotation(
                tool: .measure, startPoint: p1, endPoint: p2,
                color: annotationColor, strokeWidth: currentStrokeWidth)
            ann.measureInPoints = currentMeasureInPoints
            return ann
        }
    }

    // MARK: - Marker Cursor Preview

    func drawCropPreview() {
        let dimColor = NSColor.black.withAlphaComponent(0.4)
        dimColor.setFill()
        NSBezierPath(
            rect: NSRect(
                x: selectionRect.minX, y: cropDragRect.maxY,
                width: selectionRect.width, height: selectionRect.maxY - cropDragRect.maxY)
        ).fill()
        NSBezierPath(
            rect: NSRect(
                x: selectionRect.minX, y: selectionRect.minY,
                width: selectionRect.width, height: cropDragRect.minY - selectionRect.minY)
        ).fill()
        NSBezierPath(
            rect: NSRect(
                x: selectionRect.minX, y: cropDragRect.minY,
                width: cropDragRect.minX - selectionRect.minX, height: cropDragRect.height)
        ).fill()
        NSBezierPath(
            rect: NSRect(
                x: cropDragRect.maxX, y: cropDragRect.minY,
                width: selectionRect.maxX - cropDragRect.maxX, height: cropDragRect.height)
        ).fill()
    }

    /// Half-extent of the drawing cursor preview (used for dirty rect invalidation).
    var drawingCursorRadius: CGFloat {
        if currentTool == .marker {
            if smartMarkerEnabled {
                // Smart marker pill: height is the dominant dimension
                let h = smartMarkerLineHeight ?? (currentMarkerSize * 6)
                return h / 2
            }
            return (currentMarkerSize * 6) / 2
        } else {
            return max(currentStrokeWidth / 2, 2)
        }
    }

    func drawDrawingCursorPreview(at center: NSPoint) {
        if currentTool == .marker && smartMarkerEnabled {
            // Smart marker: vertical pill that scales to text line height
            let h = smartMarkerLineHeight ?? (currentMarkerSize * 6)
            let w: CGFloat = min(h * 0.55, 14)
            let pillRect = NSRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
            let pill = NSBezierPath(roundedRect: pillRect, xRadius: w / 2, yRadius: w / 2)
            currentColor.withAlphaComponent(0.45).setFill()
            pill.fill()
            currentColor.withAlphaComponent(0.8).setStroke()
            pill.lineWidth = 1.0
            pill.stroke()
        } else if currentTool == .marker {
            // Normal marker: circle at marker stroke size
            let radius = drawingCursorRadius
            let circleRect = NSRect(
                x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            let path = NSBezierPath(ovalIn: circleRect)
            currentColor.withAlphaComponent(0.35).setFill()
            path.fill()
            currentColor.withAlphaComponent(0.7).setStroke()
            path.lineWidth = 1.0
            path.stroke()
        } else {
            // Pencil: solid dot at stroke width (fixed size — don't scale by pressure
            // to avoid distracting size ripple while moving the cursor)
            let radius = max(drawingCursorRadius, 0.5)
            let circleRect = NSRect(
                x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            let path = NSBezierPath(ovalIn: circleRect)
            annotationColor.setFill()
            path.fill()
            let border = NSBezierPath(ovalIn: circleRect.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1.0
            NSColor.white.withAlphaComponent(0.6).setStroke()
            border.stroke()
            let inner = NSBezierPath(ovalIn: circleRect.insetBy(dx: 0.5, dy: 0.5))
            inner.lineWidth = 0.5
            NSColor.black.withAlphaComponent(0.3).setStroke()
            inner.stroke()
        }
    }

    // MARK: - Loupe Preview

    func drawLoupePreview(at center: NSPoint) {
        guard let screenshot = screenshotImage, let context = NSGraphicsContext.current else {
            return
        }
        let size = currentLoupeSize
        let squareRect = NSRect(
            x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        let magnification: CGFloat = 2.0

        context.saveGraphicsState()
        context.cgContext.setAlpha(0.75)

        // Clip to circle
        let path = NSBezierPath(ovalIn: squareRect)
        path.addClip()

        // Draw magnified region directly from screenshot (no intermediate image)
        let srcSize = size / magnification
        let srcRect = NSRect(
            x: center.x - srcSize / 2, y: center.y - srcSize / 2, width: srcSize, height: srcSize)
        let imgSize = screenshot.size
        let drawRect = captureDrawRect
        let scaleX = imgSize.width / drawRect.width
        let scaleY = imgSize.height / drawRect.height
        let fromRect = NSRect(
            x: (srcRect.origin.x - drawRect.origin.x) * scaleX,
            y: (srcRect.origin.y - drawRect.origin.y) * scaleY,
            width: srcRect.width * scaleX, height: srcRect.height * scaleY)
        screenshot.draw(in: squareRect, from: fromRect, operation: .copy, fraction: 1.0)

        // Simple border
        NSColor.white.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 3
        path.stroke()

        context.restoreGraphicsState()
    }

}
