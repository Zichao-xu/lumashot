import AVFoundation
import Cocoa
import UniformTypeIdentifiers

extension OverlayView {
    // MARK: - Annotation layer cache

    /// Render all committed annotations into a transparent bitmap (canvas-space, no zoom).
    /// Reused across frames until annotations change, avoiding per-frame iteration.
    func annotationLayerImage() -> NSImage {
        if let cached = cachedAnnotationLayer { return cached }
        let image = renderAnnotationBitmap(annotations: annotations)
        cachedAnnotationLayer = image
        return image
    }

    var annotationLayerCache: NSImage? { cachedAnnotationLayer }

    /// Incrementally add a newly committed annotation onto a previous cache snapshot.
    /// Avoids a full rebuild which can cause a visible lag (cursor disappears for a frame).
    func appendToAnnotationCache(_ annotation: Annotation, previousCache: NSImage) {
        guard let existingCG = previousCache.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        let size = bounds.size
        let scale = window?.backingScaleFactor ?? 2.0
        let pxW = Int(ceil(size.width * scale))
        let pxH = Int(ceil(size.height * scale))
        let colorSpace = window?.screen?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cgCtx = CGContext(
            data: nil, width: pxW, height: pxH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        cgCtx.scaleBy(x: scale, y: scale)

        // Draw existing cache
        cgCtx.draw(existingCG, in: CGRect(origin: .zero, size: size))

        // Draw new annotation on top
        let nsCtx = NSGraphicsContext(cgContext: cgCtx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        annotation.draw(in: nsCtx)
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = cgCtx.makeImage() else { return }
        cachedAnnotationLayer = NSImage(cgImage: cgImage, size: size)
    }

    /// Build annotation layer excluding specific annotations (used during drag/resize).
    func buildAnnotationLayer(excluding: Set<ObjectIdentifier>) -> NSImage {
        let filtered = annotations.filter { !excluding.contains(ObjectIdentifier($0)) }
        return renderAnnotationBitmap(annotations: filtered)
    }

    /// Render annotations into a fixed bitmap at the current backing scale.
    /// Uses CGBitmapContext with the window's color space so colors match exactly.
    /// Returns an NSImage backed by a CGImage so AppKit never re-invokes a
    /// drawing handler when the image is drawn into a zoomed context.
    func renderAnnotationBitmap(annotations: [Annotation]) -> NSImage {
        let size = bounds.size
        let scale = window?.backingScaleFactor ?? 2.0
        let pxW = Int(ceil(size.width * scale))
        let pxH = Int(ceil(size.height * scale))
        let colorSpace = window?.screen?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cgCtx = CGContext(
            data: nil, width: pxW, height: pxH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return NSImage(size: size) }
        // Scale so drawing in points maps to pixels
        cgCtx.scaleBy(x: scale, y: scale)

        let nsCtx = NSGraphicsContext(cgContext: cgCtx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        for annotation in annotations where annotation.tool == .pixelate {
            annotation.draw(in: nsCtx)
        }
        for annotation in annotations where annotation.tool != .pixelate {
            annotation.draw(in: nsCtx)
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = cgCtx.makeImage() else { return NSImage(size: size) }
        return NSImage(cgImage: cgImage, size: size)
    }

    // MARK: - Output

    /// Render screenshot + all existing annotations into a full-size image.
    /// Used as source for pixelate/blur so they operate on the composited result.
    func compositedImage() -> NSImage? {
        if let cached = cachedCompositedImage { return cached }
        guard let screenshot = screenshotImage else { return nil }
        if annotations.isEmpty { return screenshot }

        let drawRect = captureDrawRect
        let annotationsCopy = annotations
        var success = false
        let image = NSImage(size: drawRect.size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current else {
                return true
            }
            screenshot.draw(
                in: NSRect(origin: .zero, size: drawRect.size), from: .zero, operation: .copy,
                fraction: 1.0)
            // Translate so annotations at selectionRect coords render correctly
            context.cgContext.translateBy(x: -drawRect.origin.x, y: -drawRect.origin.y)
            // Censor annotations render first so other annotations appear on top
            for annotation in annotationsCopy where annotation.tool == .pixelate {
                annotation.draw(in: context)
            }
            for annotation in annotationsCopy where annotation.tool != .pixelate {
                annotation.draw(in: context)
            }
            success = true
            return true
        }
        if !success {
            _ = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        if !success { return screenshot }
        cachedCompositedImage = image
        return image
    }
    func captureSelectedRegion() -> NSImage? {
        return renderSelectedRegion(includeAnnotations: true)
    }

    /// Capture the selected region WITHOUT annotations — just the raw screenshot.
    /// Used for editable history: the raw image is stored alongside annotation data.
    func captureSelectedRegionRaw() -> NSImage? {
        return renderSelectedRegion(includeAnnotations: false)
    }

    func renderSelectedRegion(includeAnnotations: Bool) -> NSImage? {
        guard selectionRect.width > 0, selectionRect.height > 0 else { return nil }

        // Determine the source image's actual pixel scale so we render at
        // native resolution instead of relying on lockFocus() which always
        // picks the highest backing scale of any connected display.  This
        // prevents interpolation-upscaling when a 1x external monitor is
        // captured while a Retina display is also connected.
        let scale: CGFloat
        if let screenshot = screenshotImage,
            let cg = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil)
        {
            scale = CGFloat(cg.width) / screenshot.size.width
        } else {
            scale = window?.backingScaleFactor ?? 2.0
        }

        // Snap selection rect to pixel boundaries to prevent sub-pixel
        // interpolation blur (especially visible on 1x non-Retina displays
        // where fractional mouse coordinates aren't absorbed by 2x scaling).
        let snappedRect = NSRect(
            x: round(selectionRect.origin.x * scale) / scale,
            y: round(selectionRect.origin.y * scale) / scale,
            width: round(selectionRect.width * scale) / scale,
            height: round(selectionRect.height * scale) / scale
        )

        let pixelW = Int(snappedRect.width * scale)
        let pixelH = Int(snappedRect.height * scale)
        guard pixelW > 0, pixelH > 0 else { return nil }
        // Use the source image's color space to avoid expensive color conversion on render.
        // Fall back to sRGB if unavailable.
        let cs: CGColorSpace
        if let screenshot = screenshotImage,
           let cg = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let srcCS = cg.colorSpace {
            cs = srcCS
        } else {
            cs = CGColorSpace(name: CGColorSpace.sRGB)!
        }
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard
            let cgCtx = CGContext(
                data: nil,
                width: pixelW, height: pixelH,
                bitsPerComponent: 8,
                bytesPerRow: pixelW * 4,
                space: cs,
                bitmapInfo: bitmapInfo
            )
        else { return nil }

        // Disable interpolation for pixel-perfect output — the screenshot
        // pixels should map 1:1 to the output without any filtering.
        cgCtx.interpolationQuality = .none
        // Scale the CG context so drawing in points maps to the correct pixels.
        cgCtx.scaleBy(x: scale, y: scale)
        cgCtx.translateBy(x: -snappedRect.origin.x, y: -snappedRect.origin.y)

        let nsContext = NSGraphicsContext(cgContext: cgCtx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        if let screenshot = screenshotImage {
            // In editor mode the image is at selectionRect (natural size);
            // in overlay mode it fills bounds (full screen).
            let drawRect = captureDrawRect
            screenshot.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)
        }

        if includeAnnotations {
            for annotation in annotations {
                annotation.draw(in: nsContext)
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = cgCtx.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: snappedRect.size)
    }

    /// Render ONLY the annotations for the current selection onto a transparent
    /// background, at native pixel scale and the same upright orientation as
    /// `renderSelectedRegion`. Used to burn annotations into the separately
    /// captured HDR image (which the HDR path grabs via ScreenCaptureKit and
    /// therefore never sees the overlay-drawn annotations).
    ///
    /// MUST be called while the overlay view is still alive — loupe / pixelate /
    /// censor annotations sample the live `screenshotImage`. Returns nil when
    /// there is nothing to draw, so the HDR path can skip compositing entirely.
    func renderAnnotationOverlayForHDR() -> CGImage? {
        guard selectionRect.width > 0, selectionRect.height > 0 else { return nil }
        guard !annotations.isEmpty else { return nil }

        // Mirror renderSelectedRegion's pixel-scale + snapping so the overlay
        // lines up 1:1 with the HDR capture of the same region.
        let scale: CGFloat
        if let screenshot = screenshotImage,
            let cg = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil)
        {
            scale = CGFloat(cg.width) / screenshot.size.width
        } else {
            scale = window?.backingScaleFactor ?? 2.0
        }

        let snappedRect = NSRect(
            x: round(selectionRect.origin.x * scale) / scale,
            y: round(selectionRect.origin.y * scale) / scale,
            width: round(selectionRect.width * scale) / scale,
            height: round(selectionRect.height * scale) / scale
        )

        let pixelW = Int(snappedRect.width * scale)
        let pixelH = Int(snappedRect.height * scale)
        guard pixelW > 0, pixelH > 0 else { return nil }

        // Annotations are SDR-range marks; an sRGB 8-bit transparent layer is
        // plenty. The HDR highlights live in the base image and are preserved by
        // source-over compositing where this layer's alpha is 0.
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard
            let cgCtx = CGContext(
                data: nil,
                width: pixelW, height: pixelH,
                bitsPerComponent: 8,
                bytesPerRow: pixelW * 4,
                space: cs,
                bitmapInfo: bitmapInfo
            )
        else { return nil }

        cgCtx.interpolationQuality = .none
        cgCtx.scaleBy(x: scale, y: scale)
        cgCtx.translateBy(x: -snappedRect.origin.x, y: -snappedRect.origin.y)

        let nsContext = NSGraphicsContext(cgContext: cgCtx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        for annotation in annotations {
            annotation.draw(in: nsContext)
        }
        NSGraphicsContext.restoreGraphicsState()

        return cgCtx.makeImage()
    }

    // MARK: - Cleanup

    /// Pre-set a selection (used by delay capture to restore the previous region)
    func snapshotEditorState() -> OverlayEditorState {
        return OverlayEditorState(
            screenshotImage: screenshotImage,
            selectionRect: selectionRect,
            annotations: annotations,
            undoStack: undoStack,
            redoStack: redoStack,
            currentTool: currentTool,
            currentColor: currentColor,
            currentStrokeWidth: currentStrokeWidth,
            currentMarkerSize: currentMarkerSize,
            currentNumberSize: currentNumberSize,
            numberCounter: numberCounter,
            beautifyEnabled: beautifyEnabled,
            beautifyStyleIndex: beautifyStyleIndex,
            effectsPreset: effectsPreset,
            effectsBrightness: effectsBrightness,
            effectsContrast: effectsContrast,
            effectsSaturation: effectsSaturation,
            effectsSharpness: effectsSharpness
        )
    }

    /// Restore editor state.
    /// Translates annotation coordinates by `offset` (the selection origin in the original view).
    func setAnnotations(_ anns: [Annotation]) {
        // Set sourceImage on loupe annotations so they can re-bake from the editor's image.
        // Also set it on pixelate/blur without a baked result (shouldn't happen, but defensive).
        if let img = screenshotImage {
            let bounds = captureDrawRect
            for ann in anns {
                if ann.tool == .loupe || ((ann.tool == .pixelate || ann.tool == .blur) && ann.bakedBlurNSImage == nil) {
                    ann.sourceImage = img
                    ann.sourceImageBounds = bounds
                    if ann.tool == .loupe { ann.bakeLoupe() }
                    if ann.tool == .pixelate { ann.bakePixelate() }
                }
            }
        }
        annotations = anns
        undoStack = anns.map { .added($0) }
        redoStack = []
        cachedCompositedImage = nil
        needsDisplay = true
    }

    func applySelection(_ rect: NSRect) {
        selectionRect = rect
        selectionStart = rect.origin
        state = .selected
        useMoveSelectionToolForNewOverlaySelection()
        showToolbars = true
        needsDisplay = true
    }

    func applyFullScreenSelection() {
        selectionRect = bounds
        selectionStart = bounds.origin
        state = .selected
        useMoveSelectionToolForNewOverlaySelection()
        showToolbars = true
        scheduleBarcodeDetection()
        overlayDelegate?.overlayViewDidFinishSelection(selectionRect)
        needsDisplay = true
    }

    func clearSelection() {
        state = .idle
        selectionRect = .zero
        remoteSelectionRect = .zero
        remoteSelectionFullRect = .zero
        showToolbars = false
        needsDisplay = true
    }

}
