import AVFoundation
import Cocoa
import UniformTypeIdentifiers

extension OverlayView {
    // MARK: - Overlay Error

    func showOverlayError(_ message: String) {
        overlayErrorTimer?.invalidate()
        overlayErrorMessage = message
        needsDisplay = true
        overlayErrorTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) {
            [weak self] _ in
            self?.overlayErrorMessage = nil
            self?.needsDisplay = true
        }
    }


    // MARK: - Barcode / QR Detection

    func scheduleBarcodeDetection() {
        barcodeDetector.cancel()
        needsDisplay = true
        guard state == .selected, let screenshot = screenshotImage else { return }
        barcodeDetector.scan(
            image: screenshot, selectionRect: selectionRect, captureDrawRect: captureDrawRect
        ) { [weak self] in
            self?.needsDisplay = true
        }
    }


    // MARK: - Toolbar Layout

    /// Rebuild toolbar button content. Call when tool, color, or state changes — NOT on every draw.
    func rebuildToolbarLayout() {
        // Clear tooltip before rebuilding — old button views are about to be destroyed
        hoveredTooltip = nil
        hoveredTooltipButtonView = nil

        let movableAnnotations = annotations.contains { $0.isMovable }
        bottomButtons = ToolbarLayout.bottomButtons(
            selectedTool: currentTool, selectedColor: currentColor,
            beautifyEnabled: beautifyEnabled, beautifyStyleIndex: beautifyStyleIndex,
            hasAnnotations: movableAnnotations, isRecording: isRecording,
            effectsActive: effectsActive, translateEnabled: translateEnabled,
            isEditorMode: isEditorMode, hdrEnabled: isHDRCaptureMode
        )
        if showBeautifyInOptionsRow {
            for i in bottomButtons.indices {
                if case .tool = bottomButtons[i].action {
                    bottomButtons[i].isSelected = false
                } else if case .beautify = bottomButtons[i].action {
                    bottomButtons[i].isSelected = true
                }
            }
        }
        rightButtons = ToolbarLayout.rightButtons(
            beautifyEnabled: beautifyEnabled, beautifyStyleIndex: beautifyStyleIndex,
            hasAnnotations: movableAnnotations, translateEnabled: translateEnabled,
            isRecording: isRecording,
            isEditorMode: isEditorMode)

        // Create strip views if needed — add to chrome parent (window content) when in scroll view
        let parent = chromeParentView ?? self
        if bottomStripView == nil {
            let strip = ToolbarStripView(orientation: .horizontal)
            parent.addSubview(strip)
            bottomStripView = strip
        }
        if rightStripView == nil {
            let strip = ToolbarStripView(orientation: .vertical)
            parent.addSubview(strip)
            rightStripView = strip
        }
        // Update existing buttons if count matches, rebuild only if structure changed
        if bottomStripView?.buttonViews.count == bottomButtons.count && bottomStripView?.buttonViews.count ?? 0 > 0 {
            bottomStripView?.updateState(from: bottomButtons)
        } else {
            bottomStripView?.setButtons(bottomButtons)
            bottomStripView?.onClick = { [weak self] action in self?.handleToolbarAction(action) }
            bottomStripView?.onRightClick = { [weak self] action, view in
                self?.handleToolbarButtonRightClick(action, anchorView: view)
            }
            bottomStripView?.onHover = { [weak self] action, hovered in
                self?.handleToolbarButtonHover(action, hovered: hovered, strip: self?.bottomStripView)
            }
        }
        if rightStripView?.buttonViews.count == rightButtons.count && rightStripView?.buttonViews.count ?? 0 > 0 {
            rightStripView?.updateState(from: rightButtons)
        } else {
            rightStripView?.setButtons(rightButtons)
            rightStripView?.onClick = { [weak self] action in self?.handleToolbarAction(action) }
            rightStripView?.onRightClick = { [weak self] action, view in
                self?.handleToolbarButtonRightClick(action, anchorView: view)
            }
            rightStripView?.onHover = { [weak self] action, hovered in
                self?.handleToolbarButtonHover(action, hovered: hovered, strip: self?.rightStripView)
            }
        }
        // Move button needs onMouseDown for press-and-drag (synchronous tracking loop)
        for bv in rightStripView?.buttonViews ?? [] {
            if case .moveSelection = bv.action, bv.onMouseDown == nil {
                bv.onMouseDown = { [weak self] _ in self?.handleToolbarAction(.moveSelection) }
            }
        }

        // Rebuild options row content
        if toolHasOptionsRow {
            if toolOptionsRowView == nil {
                let row = ToolOptionsRowView()
                row.overlayView = self
                parent.addSubview(row)
                toolOptionsRowView = row
            }
            // Don't overwrite annotation-specific options when editing a selected annotation
            if let ann = selectedAnnotation, toolOptionsRowView?.editingAnnotation === ann {
                // Already showing this annotation's options — skip rebuild
            } else {
                toolOptionsRowView?.rebuild(for: currentTool)
            }
        }

        repositionToolbars()

    }

    /// Reposition toolbar strips based on current selection/bounds. Cheap — safe to call from draw().
    func repositionToolbars() {
        guard let bottomStrip = bottomStripView, let rightStrip = rightStripView else { return }

        // In editor mode, let toolbar gap clicks pass through to the image beneath
        bottomStrip.passesThrough = isEditorMode
        rightStrip.passesThrough = isEditorMode

        let visible = showToolbars && state == .selected && !isScrollCapturing
        let bottomHasButtons = bottomStrip.buttonViews.count > 0
        bottomStrip.isHidden = !visible || !bottomHasButtons
        let rightHasButtons = rightStrip.buttonViews.count > 0
        rightStrip.isHidden = !visible || !rightHasButtons
        let optionsShouldBeVisible = visible && toolHasOptionsRow && bottomHasButtons
        if !optionsShouldBeVisible {
            toolOptionsRowView?.setToolbarVisible(false, animated: toolOptionsRowView?.window != nil)
        }
        guard visible else { return }

        // Anchor rect: beautify-expanded when active, selection otherwise
        let config = beautifyConfig
        let bPad = config.padding
        let titleBarH: CGFloat = config.mode == .window ? 28 : 0
        let expandedAnchor = NSRect(
            x: selectionRect.minX - bPad, y: selectionRect.minY - bPad,
            width: selectionRect.width + bPad * 2,
            height: selectionRect.height + titleBarH + bPad * 2)
        let anchorRect: NSRect
        if beautifyToolbarAnimProgress < 1.0 {
            let t = beautifyToolbarAnimProgress
            let eased = 1.0 - (1.0 - t) * (1.0 - t)
            let fromRect = beautifyToolbarAnimTarget ? selectionRect : expandedAnchor
            let toRect = beautifyToolbarAnimTarget ? expandedAnchor : selectionRect
            anchorRect = NSRect(
                x: fromRect.minX + (toRect.minX - fromRect.minX) * eased,
                y: fromRect.minY + (toRect.minY - fromRect.minY) * eased,
                width: fromRect.width + (toRect.width - fromRect.width) * eased,
                height: fromRect.height + (toRect.height - fromRect.height) * eased
            )
        } else if beautifyEnabled && !isScrollCapturing && !isRecording {
            anchorRect = expandedAnchor
        } else {
            anchorRect = selectionRect
        }

        let rightSize = rightStrip.frame.size

        let bottomSize = bottomStrip.frame.size

        if isEditorMode {
            let cb = chromeParentView?.bounds ?? bounds
            bottomStrip.frame.origin = NSPoint(x: cb.midX - bottomSize.width / 2, y: 20)
            bottomStrip.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
            rightStrip.frame.origin = NSPoint(
                x: cb.maxX - rightSize.width - 20, y: cb.maxY - rightSize.height - 36)
            rightStrip.autoresizingMask = [.minXMargin, .minYMargin]
        } else {
            let optRowH: CGFloat = 38  // options row height + gap

            // ── 1. Position right bar (anchored to selection edge) ──
            let rightMargin: CGFloat = 50
            let rightFitsRight = anchorRect.maxX < bounds.maxX - rightMargin
            let rightFitsLeft = anchorRect.minX > bounds.minX + rightMargin

            // For very narrow selections, put the right bar below instead of to the side
            let selectionTooNarrow = !rightFitsRight && !rightFitsLeft
                && anchorRect.width < bounds.width * 0.5

            var rx: CGFloat
            var ry: CGFloat

            if selectionTooNarrow {
                // Place right bar below the selection, right-aligned
                rx = anchorRect.maxX - rightSize.width
                rx = max(bounds.minX + 4, min(rx, bounds.maxX - rightSize.width - 4))
                ry = anchorRect.minY - rightSize.height - 6
                ry = max(bounds.minY + 4, min(ry, bounds.maxY - rightSize.height - 4))
            } else {
                if rightFitsRight {
                    rx = anchorRect.maxX + 6
                } else if rightFitsLeft {
                    rx = anchorRect.minX - rightSize.width - 6
                } else {
                    rx = selectionRect.maxX - rightSize.width - 6
                }
                rx = max(bounds.minX + 4, min(rx, bounds.maxX - rightSize.width - 4))

                ry = anchorRect.maxY - rightSize.height
                ry = max(bounds.minY + 4, min(ry, bounds.maxY - rightSize.height - 4))
            }

            // ── 2. Choose bottom bar Y, preferring positions that don't overlap right bar ──
            let belowY = anchorRect.minY - bottomSize.height - 6
            let belowFits = (belowY - optRowH) >= bounds.minY + 4
            let aboveY = anchorRect.maxY + optRowH + 6
            let aboveFits = (aboveY + bottomSize.height) <= bounds.maxY - 4

            // Helper: does a bottom bar at candidate Y (centered) overlap the right bar?
            let centeredBx = anchorRect.midX - bottomSize.width / 2
            let clampedCenteredBx = max(bounds.minX + 4, min(centeredBx, bounds.maxX - bottomSize.width - 4))
            func wouldOverlapRight(candidateY: CGFloat) -> Bool {
                let bMinY = candidateY - optRowH
                let bMaxY = candidateY + bottomSize.height
                guard bMaxY > ry && bMinY < ry + rightSize.height else { return false }
                let bMaxX = clampedCenteredBx + bottomSize.width
                let bMinX = clampedCenteredBx
                return bMaxX > rx && bMinX < rx + rightSize.width
            }

            var by: CGFloat
            if belowFits && !wouldOverlapRight(candidateY: belowY) {
                by = belowY
            } else if aboveFits && !wouldOverlapRight(candidateY: aboveY) {
                by = aboveY
            } else if belowFits {
                by = belowY  // overlaps but at least fits vertically
            } else if aboveFits {
                by = aboveY
            } else {
                by = selectionRect.minY + optRowH + 6
                by = max(bounds.minY + optRowH + 4, min(by, bounds.maxY - bottomSize.height - 4))
            }

            // ── 3. Position bottom bar X, avoiding right bar if they overlap vertically ──
            var bx = clampedCenteredBx
            let bottomMinY = by - optRowH
            let bottomMaxY = by + bottomSize.height
            let overlapsVertically = bottomMaxY > ry && bottomMinY < ry + rightSize.height

            if overlapsVertically {
                // Check if centered bottom bar already clears the right bar horizontally
                if bx + bottomSize.width <= rx - 4 || bx >= rx + rightSize.width + 4 {
                    // No overlap — keep both as-is
                } else {
                    // Overlap: move the RIGHT bar out of the way, keep bottom bar centered.
                    // Try pushing right bar further right (past bottom bar's right edge).
                    let pushRight = bx + bottomSize.width + 4
                    // Try pushing right bar to the left (before bottom bar's left edge).
                    let pushLeft = bx - rightSize.width - 4

                    if pushRight + rightSize.width <= bounds.maxX - 4 {
                        rx = pushRight
                    } else if pushLeft >= bounds.minX + 4 {
                        rx = pushLeft
                    } else {
                        // Right bar can't dodge horizontally — push it vertically.
                        // Try below the bottom bar + options row zone.
                        let rightPushDown = by - optRowH - rightSize.height - 4
                        if rightPushDown >= bounds.minY + 4 {
                            ry = rightPushDown
                        } else {
                            // Try above the bottom bar
                            let rightPushUp = by + bottomSize.height + 4
                            if rightPushUp + rightSize.height <= bounds.maxY - 4 {
                                ry = rightPushUp
                            }
                            // else: truly no room, accept overlap
                        }
                    }
                }
            }
            bx = max(bounds.minX + 4, min(bx, bounds.maxX - bottomSize.width - 4))

            bottomStrip.frame.origin = NSPoint(x: bx, y: by)
            rightStrip.frame.origin = NSPoint(x: rx, y: ry)
        }

        bottomBarRect = bottomStrip.frame
        rightBarRect = rightStrip.frame

        // Position options row — above bottom bar in editor, below in overlay
        if let row = toolOptionsRowView, optionsShouldBeVisible {
            // Keep the secondary row left-aligned, but let it shrink to its real controls.
            let availableW = (isEditorMode ? (chromeParentView?.bounds.width ?? bounds.width) : bounds.width) - 8
            let rowW = min(row.contentWidth, max(0, availableW))
            row.frame.size.width = rowW
            let rowY: CGFloat
            if isEditorMode {
                // In editor mode, keep the options row pinned to the toolbar's left edge.
                let cb = chromeParentView?.bounds ?? bounds
                let rowX = max(4, min(bottomBarRect.minX, cb.maxX - rowW - 4))
                row.frame.origin = NSPoint(x: rowX, y: bottomBarRect.maxY + 2)
                row.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
            } else {
                // Align the options row to the toolbar's left edge, clamped to view bounds.
                var rowX = bottomBarRect.minX
                rowX = max(4, min(rowX, bounds.maxX - rowW - 4))
                rowY = bottomBarRect.minY - row.frame.height - 2
                row.frame.origin = NSPoint(x: rowX, y: rowY)
            }
            row.setToolbarVisible(true, animated: row.window != nil)
        }

    }

    // MARK: - Handle hit testing

    func allHandleRects() -> [(ResizeHandle, NSRect)] {
        let r = selectionRect
        let s = handleSize
        return [
            (.topLeft, NSRect(x: r.minX - s / 2, y: r.maxY - s / 2, width: s, height: s)),
            (.topRight, NSRect(x: r.maxX - s / 2, y: r.maxY - s / 2, width: s, height: s)),
            (.bottomLeft, NSRect(x: r.minX - s / 2, y: r.minY - s / 2, width: s, height: s)),
            (.bottomRight, NSRect(x: r.maxX - s / 2, y: r.minY - s / 2, width: s, height: s)),
            (.top, NSRect(x: r.midX - s / 2, y: r.maxY - s / 2, width: s, height: s)),
            (.bottom, NSRect(x: r.midX - s / 2, y: r.minY - s / 2, width: s, height: s)),
            (.left, NSRect(x: r.minX - s / 2, y: r.midY - s / 2, width: s, height: s)),
            (.right, NSRect(x: r.maxX - s / 2, y: r.midY - s / 2, width: s, height: s)),
        ]
    }

    func hitTestHandle(at point: NSPoint) -> ResizeHandle {
        // Use the same hit area as resizeHandleCursor so cursor and click zones match
        let hitPad: CGFloat = 2  // handle rect is already handleSize; expand by 2 to match cursor zone
        // Check corner handles first (they take priority over edges)
        for (handle, rect) in allHandleRects() {
            switch handle {
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                if rect.insetBy(dx: -hitPad, dy: -hitPad).contains(point) {
                    return handle
                }
            default:
                break
            }
        }

        // Check full edges/borders (not just the handle dots)
        let edgeThickness: CGFloat = 6  // match resizeHandleCursor's edgeT
        let r = selectionRect
        // Top edge
        if NSRect(x: r.minX, y: r.maxY - edgeThickness / 2, width: r.width, height: edgeThickness)
            .contains(point)
        {
            return .top
        }
        // Bottom edge
        if NSRect(x: r.minX, y: r.minY - edgeThickness / 2, width: r.width, height: edgeThickness)
            .contains(point)
        {
            return .bottom
        }
        // Left edge
        if NSRect(x: r.minX - edgeThickness / 2, y: r.minY, width: edgeThickness, height: r.height)
            .contains(point)
        {
            return .left
        }
        // Right edge
        if NSRect(x: r.maxX - edgeThickness / 2, y: r.minY, width: edgeThickness, height: r.height)
            .contains(point)
        {
            return .right
        }

        return .none
    }

    func handleRectsForRect(_ r: NSRect) -> [(ResizeHandle, NSRect)] {
        let s = handleSize
        return [
            (.topLeft, NSRect(x: r.minX - s / 2, y: r.maxY - s / 2, width: s, height: s)),
            (.topRight, NSRect(x: r.maxX - s / 2, y: r.maxY - s / 2, width: s, height: s)),
            (.bottomLeft, NSRect(x: r.minX - s / 2, y: r.minY - s / 2, width: s, height: s)),
            (.bottomRight, NSRect(x: r.maxX - s / 2, y: r.minY - s / 2, width: s, height: s)),
            (.top, NSRect(x: r.midX - s / 2, y: r.maxY - s / 2, width: s, height: s)),
            (.bottom, NSRect(x: r.midX - s / 2, y: r.minY - s / 2, width: s, height: s)),
            (.left, NSRect(x: r.minX - s / 2, y: r.midY - s / 2, width: s, height: s)),
            (.right, NSRect(x: r.maxX - s / 2, y: r.midY - s / 2, width: s, height: s)),
        ]
    }

    func hitTestRemoteHandle(at point: NSPoint) -> ResizeHandle {
        let r = remoteSelectionRect
        guard r.width >= 1, r.height >= 1 else { return .none }
        let hitPad: CGFloat = 2
        for (handle, rect) in handleRectsForRect(r) {
            switch handle {
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                if rect.insetBy(dx: -hitPad, dy: -hitPad).contains(point) { return handle }
            default: break
            }
        }
        let edgeThickness: CGFloat = 6
        if NSRect(x: r.minX, y: r.maxY - edgeThickness / 2, width: r.width, height: edgeThickness).contains(point) { return .top }
        if NSRect(x: r.minX, y: r.minY - edgeThickness / 2, width: r.width, height: edgeThickness).contains(point) { return .bottom }
        if NSRect(x: r.minX - edgeThickness / 2, y: r.minY, width: edgeThickness, height: r.height).contains(point) { return .left }
        if NSRect(x: r.maxX - edgeThickness / 2, y: r.minY, width: edgeThickness, height: r.height).contains(point) { return .right }
        return .none
    }

    func drawRemoteResizeHandles() {
        for (_, rect) in handleRectsForRect(remoteSelectionRect) {
            ToolbarLayout.handleColor.setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
    }

    /// Returns the anchor point (fixed corner) for a given resize handle on a rect.
    func anchorForHandle(_ handle: ResizeHandle, in r: NSRect) -> NSPoint {
        switch handle {
        case .topLeft:     return NSPoint(x: r.maxX, y: r.minY)
        case .topRight:    return NSPoint(x: r.minX, y: r.minY)
        case .bottomLeft:  return NSPoint(x: r.maxX, y: r.maxY)
        case .bottomRight: return NSPoint(x: r.minX, y: r.maxY)
        case .top:         return NSPoint(x: r.midX, y: r.minY)
        case .bottom:      return NSPoint(x: r.midX, y: r.maxY)
        case .left:        return NSPoint(x: r.maxX, y: r.midY)
        case .right:       return NSPoint(x: r.minX, y: r.midY)
        case .none, .move:  return .zero
        }
    }

}
