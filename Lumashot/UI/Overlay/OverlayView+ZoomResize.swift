import AVFoundation
import Cocoa
import UniformTypeIdentifiers

extension OverlayView {
    // MARK: - Zoom (scroll wheel + trackpad pinch)

    /// Perform cursor-centered zoom on the enclosing scroll view.
    /// Uses NSScrollView's own setMagnification(_:centeredAt:) which handles all the
    /// coordinate math correctly, but we disable allowsMagnification so it doesn't
    /// apply its own elastic physics on top.
    func editorZoom(by factor: CGFloat, cursorInWindow: NSPoint, animated: Bool = false) {
        guard let sv = enclosingScrollView else { return }

        if animated {
            // Accumulate target and animate toward it
            if editorZoomAnimTimer == nil {
                editorZoomTarget = sv.magnification
            }
            editorZoomTarget = max(sv.minMagnification, min(sv.maxMagnification, editorZoomTarget * factor))
            editorZoomCursorDoc = convert(cursorInWindow, from: nil)

            if editorZoomAnimTimer == nil {
                editorZoomAnimTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
                    guard let self = self, let sv = self.enclosingScrollView else {
                        timer.invalidate()
                        return
                    }
                    let current = sv.magnification
                    let target = self.editorZoomTarget
                    let diff = target - current
                    if abs(diff) < 0.001 {
                        sv.setMagnification(target, centeredAt: self.editorZoomCursorDoc)
                        timer.invalidate()
                        self.editorZoomAnimTimer = nil
                        self.needsDisplay = true
                        if let topBar = sv.superview?.subviews.compactMap({ $0 as? EditorTopBarView }).first {
                            topBar.updateZoom(target)
                        }
                        return
                    }
                    // Ease toward target: move 25% of remaining distance per frame
                    let next = current + diff * 0.25
                    sv.setMagnification(next, centeredAt: self.editorZoomCursorDoc)
                    if let topBar = sv.superview?.subviews.compactMap({ $0 as? EditorTopBarView }).first {
                        topBar.updateZoom(next)
                    }
                }
            }
            return
        }

        let oldMag = sv.magnification
        let newMag = max(sv.minMagnification, min(sv.maxMagnification, oldMag * factor))
        guard newMag != oldMag else { return }

        // Convert cursor from window coords to document view (unscaled) coords
        let cursorInDoc = convert(cursorInWindow, from: nil)
        sv.setMagnification(newMag, centeredAt: cursorInDoc)

        // During active zooming, let the GPU-scaled layer handle the visual — it's instant.
        // Debounce the full-resolution redraw to when zooming stops (150ms idle).
        editorZoomRedrawTimer?.invalidate()
        editorZoomRedrawTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.needsDisplay = true
        }

        if let topBar = sv.superview?.subviews.compactMap({ $0 as? EditorTopBarView }).first {
            topBar.updateZoom(newMag)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        // Editor mode: all scroll handling is done by CenteringClipView
        if isInsideScrollView {
            enclosingScrollView?.scrollWheel(with: event)
            return
        }
        guard state == .selected else { return }
        let isTrackpadPhased = event.phase != [] || event.momentumPhase != []
        let isCommandScroll = event.modifierFlags.contains(.command)

        // Phase-based (trackpad) scroll without Cmd → pan only, never zoom
        // Suppress panning while actively drawing to prevent pan+draw conflict (Apple Pencil / Sidecar)
        if isTrackpadPhased && !isCommandScroll && currentAnnotation != nil { return }
        if isTrackpadPhased && !isCommandScroll {
            // Allow panning when zoomed OR when the image exceeds the view (tall/wide images in editor)
            let imageExceedsView =
                canPanAtOneX()
                || (isEditorMode
                    && (selectionRect.height > bounds.height || selectionRect.width > bounds.width))
            guard zoomLevel != 1.0 || imageExceedsView else { return }
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            zoomAnchorView.x += dx
            zoomAnchorView.y -= dy  // AppKit Y is flipped vs scroll direction
            clampZoomAnchor()
            needsDisplay = true
            return
        }

        // Cmd+scroll or plain mouse wheel (non-trackpad) → zoom
        guard isCommandScroll || !isTrackpadPhased else { return }
        let cursor = convert(event.locationInWindow, from: nil)
        let delta = event.deltaY
        let factor: CGFloat = 0.1
        setZoom(zoomLevel + delta * factor, cursorView: cursor)
    }

    override func magnify(with event: NSEvent) {
        if isInsideScrollView {
            editorZoom(by: 1.0 + event.magnification, cursorInWindow: event.locationInWindow)
            return
        }
        guard state == .selected else { return }
        let cursor = convert(event.locationInWindow, from: nil)
        setZoom(zoomLevel + event.magnification, cursorView: cursor)
    }

    // MARK: - Middle Mouse (toggle move mode)

    override func otherMouseDown(with event: NSEvent) {
        // Middle mouse: no action (previously toggled select tool)
    }

    // MARK: - Selection Resizing

    func resizeSelection(to point: NSPoint) {
        let minSize: CGFloat = 10
        let r = selectionRect
        var newRect = r

        switch resizeHandle {
        case .topLeft:
            let newX = min(point.x, r.maxX - minSize)
            let newMaxY = max(point.y, r.minY + minSize)
            newRect = NSRect(x: newX, y: r.minY, width: r.maxX - newX, height: newMaxY - r.minY)
        case .topRight:
            let newMaxX = max(point.x, r.minX + minSize)
            let newMaxY = max(point.y, r.minY + minSize)
            newRect = NSRect(
                x: r.minX, y: r.minY, width: newMaxX - r.minX, height: newMaxY - r.minY)
        case .bottomLeft:
            let newX = min(point.x, r.maxX - minSize)
            let newY = min(point.y, r.maxY - minSize)
            newRect = NSRect(x: newX, y: newY, width: r.maxX - newX, height: r.maxY - newY)
        case .bottomRight:
            let newMaxX = max(point.x, r.minX + minSize)
            let newY = min(point.y, r.maxY - minSize)
            newRect = NSRect(x: r.minX, y: newY, width: newMaxX - r.minX, height: r.maxY - newY)
        case .top:
            let newMaxY = max(point.y, r.minY + minSize)
            newRect = NSRect(x: r.minX, y: r.minY, width: r.width, height: newMaxY - r.minY)
        case .bottom:
            let newY = min(point.y, r.maxY - minSize)
            newRect = NSRect(x: r.minX, y: newY, width: r.width, height: r.maxY - newY)
        case .left:
            let newX = min(point.x, r.maxX - minSize)
            newRect = NSRect(x: newX, y: r.minY, width: r.maxX - newX, height: r.height)
        case .right:
            let newMaxX = max(point.x, r.minX + minSize)
            newRect = NSRect(x: r.minX, y: r.minY, width: newMaxX - r.minX, height: r.height)
        default:
            break
        }

        selectionRect = newRect
    }

}
