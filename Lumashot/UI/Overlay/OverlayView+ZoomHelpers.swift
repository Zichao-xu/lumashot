import AVFoundation
import Cocoa
import UniformTypeIdentifiers

extension OverlayView {
    // MARK: - Zoom helpers

    /// Convert a canvas-space point to view-space (reverse of viewToCanvas).
    func canvasToView(_ p: NSPoint) -> NSPoint {
        if isInsideScrollView { return p }
        var q = p
        // Apply zoom
        if zoomLevel != 1.0 || zoomAnchorCanvas != .zero || zoomAnchorView != .zero {
            q = NSPoint(
                x: zoomAnchorView.x + (p.x - zoomAnchorCanvas.x) * zoomLevel,
                y: zoomAnchorView.y + (p.y - zoomAnchorCanvas.y) * zoomLevel
            )
        }

        return q
    }

    /// Convert a point in view space to canvas (annotation) space by reversing the zoom transform.
    func viewToCanvas(_ p: NSPoint) -> NSPoint {
        if isInsideScrollView { return p }
        var q = adjustPointForEditor(p)
        if zoomLevel == 1.0 && zoomAnchorCanvas == .zero && zoomAnchorView == .zero { return q }
        guard zoomAnchorCanvas != .zero || zoomAnchorView != .zero else { return q }
        return NSPoint(
            x: zoomAnchorCanvas.x + (q.x - zoomAnchorView.x) / zoomLevel,
            y: zoomAnchorCanvas.y + (q.y - zoomAnchorView.y) / zoomLevel
        )
    }

    func applyZoomTransform(to context: NSGraphicsContext) {
        if isInsideScrollView { return }
        if zoomLevel == 1.0 && zoomAnchorCanvas == .zero && zoomAnchorView == .zero { return }
        guard zoomAnchorCanvas != .zero || zoomAnchorView != .zero else { return }
        let cgCtx = context.cgContext
        // screen = anchorView + (canvas - anchorCanvas) * zoom
        cgCtx.translateBy(
            x: zoomAnchorView.x - zoomAnchorCanvas.x * zoomLevel,
            y: zoomAnchorView.y - zoomAnchorCanvas.y * zoomLevel)
        cgCtx.scaleBy(x: zoomLevel, y: zoomLevel)
    }

    /// Apply editor canvas offset + zoom transform. Use this for all canvas-space drawing.
    func applyCanvasTransform(to context: NSGraphicsContext) {
        applyEditorTransform(to: context)
        applyZoomTransform(to: context)
    }

    /// Set zoom level, pinning the given view-space cursor point in place.
    func setZoom(_ level: CGFloat, cursorView: NSPoint) {
        // Canvas point currently under cursor (before zoom change)
        let canvasUnderCursor = viewToCanvas(cursorView)
        zoomLevel = max(zoomMin, min(zoomMax, level))

        // When zooming back to 1×, reset anchors to avoid floating-point drift
        // that causes visual misalignment between background and annotations.
        if abs(zoomLevel - 1.0) < 0.005 {
            zoomLevel = 1.0
            zoomAnchorCanvas = .zero
            zoomAnchorView = .zero
        } else {
            // After zoom change, pin that canvas point to the cursor's view position.
            // because applyZoomTransform runs after the editor translate.
            zoomAnchorCanvas = canvasUnderCursor
            zoomAnchorView = cursorView
            clampZoomAnchor()
        }
        showZoomLabel()
        needsDisplay = true
    }

    /// Reset zoom to 1× (no transform).
    func resetZoom() {
        zoomLevel = 1.0
        zoomAnchorCanvas = .zero
        zoomAnchorView = .zero
    }

    /// Crop the screenshot to `viewRect` (view-space, within selectionRect),
    /// translate all annotations accordingly, and reset zoom.
    func commitCrop(viewRect: NSRect) {
        guard let originalImage = screenshotImage,
            let cgOriginal = originalImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        // viewRect is already in canvas space (cropDragRect uses canvas coords).
        let canvasRect = viewRect

        // Map canvas rect → CGImage pixel rect.
        // CGImage uses top-left origin; canvas uses bottom-left.
        let pointsW = originalImage.size.width
        let pointsH = originalImage.size.height
        let pixScale = CGFloat(cgOriginal.width) / pointsW

        let normX = (canvasRect.minX - selectionRect.minX) / selectionRect.width
        let normY = (canvasRect.minY - selectionRect.minY) / selectionRect.height
        let normW = canvasRect.width / selectionRect.width
        let normH = canvasRect.height / selectionRect.height

        let cgW = CGFloat(cgOriginal.width)
        let cgH = CGFloat(cgOriginal.height)
        let cgPixelRect = CGRect(
            x: max(0, normX * cgW),
            y: max(0, (1.0 - normY - normH) * cgH),  // flip Y for CGImage top-left origin
            width: min(normW * cgW, cgW - max(0, normX * cgW)),
            height: min(normH * cgH, cgH - max(0, (1.0 - normY - normH) * cgH))
        )

        guard cgPixelRect.width > 0, cgPixelRect.height > 0,
            let croppedCG = cgOriginal.cropping(to: cgPixelRect)
        else { return }

        // Save state for undo before modifying
        let prevImage = originalImage.copy() as! NSImage
        undoStack.append(.imageTransform(previousImage: prevImage, annotationOffsets: []))
        redoStack.removeAll()

        let dx = selectionRect.minX - canvasRect.minX
        let dy = selectionRect.minY - canvasRect.minY
        for ann in annotations { ann.move(dx: dx, dy: dy) }

        // Set NSImage size in points (not pixels) to preserve Retina scale
        let croppedPointSize = NSSize(
            width: CGFloat(croppedCG.width) / pixScale,
            height: CGFloat(croppedCG.height) / pixScale)
        screenshotImage = NSImage(cgImage: croppedCG, size: croppedPointSize)

        // Update selectionRect to match new image size
        selectionRect = NSRect(origin: .zero, size: croppedPointSize)

        cachedCompositedImage = nil

        // Resize view frame to match new image size (scroll view re-centers automatically)
        if isInsideScrollView {
            frame.size = croppedPointSize
            enclosingScrollView?.magnification = 1.0
            // Update top bar size label
            if let topBar = chromeParentView?.subviews.compactMap({ $0 as? EditorTopBarView }).first
            {
                topBar.updateSizeLabel(width: croppedCG.width, height: croppedCG.height)
                topBar.updateZoom(1.0)
            }
        } else {
            resetZoom()
        }
        currentTool = .arrow
        rebuildToolbarLayout()
        needsDisplay = true
    }

    /// Clamp zoomAnchorView.
    ///
    /// Transform: screenPos = zoomAnchorView + (canvasPos - zoomAnchorCanvas) * zoom
    ///
    /// zoom > 1×: keep all four image edges inside selectionRect (no empty border visible).
    /// zoom < 1×: allow free panning but keep at least `margin` screen-space pixels of the
    ///            image visible on each side, so the user never scrolls completely off canvas.
    func clampZoomAnchor() {
        // At 1x, no clamping needed (image fills the view exactly)
        if zoomLevel == 1.0 { return }
        let r = selectionRect
        let z = zoomLevel
        let ac = zoomAnchorCanvas
        var av = zoomAnchorView

        if z > 1.0 {
            // Overlay zoom-in: edges must stay covered.
            let maxAVx = r.minX - (r.minX - ac.x) * z
            let minAVx = r.maxX - (r.maxX - ac.x) * z
            av.x = max(minAVx, min(maxAVx, av.x))

            let maxAVy = r.minY - (r.minY - ac.y) * z
            let minAVy = r.maxY - (r.maxY - ac.y) * z
            av.y = max(minAVy, min(maxAVy, av.y))
        }

        zoomAnchorView = av
    }

    func showZoomLabel() {
        zoomLabelOpacity = 1.0
        zoomFadeTimer?.invalidate()
        zoomFadeTimer = nil
        if zoomLevel == 1.0 {
            // Back at 1× — fade out after a short pause
            zoomFadeTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) {
                [weak self] _ in
                self?.fadeOutZoomLabel()
            }
        }
        // While zoomed ≠ 1×: stay fully visible, no timer
    }

    func fadeOutZoomLabel() {
        // Don't fade if we're zoomed (either direction)
        guard zoomLevel == 1.0 else { return }
        zoomFadingOut = true
        let step: CGFloat = 0.08
        Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] t in
            guard let self = self else {
                t.invalidate()
                return
            }
            // Abort fade if user zoomed during the animation
            if self.zoomLevel != 1.0 {
                self.zoomLabelOpacity = 1.0
                self.zoomFadingOut = false
                t.invalidate()
                self.needsDisplay = true
                return
            }
            self.zoomLabelOpacity -= step
            if self.zoomLabelOpacity <= 0 {
                self.zoomLabelOpacity = 0
                self.zoomFadingOut = false
                t.invalidate()
            }
            self.needsDisplay = true
        }
    }

}
