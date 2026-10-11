import AVFoundation
import Cocoa
import UniformTypeIdentifiers

extension OverlayView {
    // MARK: - Context Menu Actions

    /// Add an anchor point to a line/arrow annotation at the position closest to `canvasPoint`.
    /// Inserts the point between the two nearest existing waypoints.
    func addAnchorPoint(to annotation: Annotation, at canvasPoint: NSPoint) {
        var pts = annotation.waypoints

        // Find which segment the point is closest to, and insert there
        var bestIdx = 1
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in 1..<pts.count {
            let d = distanceToSegment(point: canvasPoint, from: pts[i - 1], to: pts[i])
            if d < bestDist {
                bestDist = d
                bestIdx = i
            }
        }

        // Project the point onto the segment for exact placement
        let a = pts[bestIdx - 1]
        let b = pts[bestIdx]
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        let t: CGFloat =
            lenSq < 0.001
            ? 0.5
            : max(
                0.05, min(0.95, ((canvasPoint.x - a.x) * dx + (canvasPoint.y - a.y) * dy) / lenSq))
        let projected = NSPoint(x: a.x + t * dx, y: a.y + t * dy)

        pts.insert(projected, at: bestIdx)

        // Store as anchorPoints, update startPoint/endPoint to match
        annotation.anchorPoints = pts
        annotation.startPoint = pts.first!
        annotation.endPoint = pts.last!
        // Clear legacy controlPoint since we're using anchorPoints now
        annotation.controlPoint = nil
    }

    func distanceToSegment(point: NSPoint, from a: NSPoint, to b: NSPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq < 0.001 { return hypot(point.x - a.x, point.y - a.y) }
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq
        t = max(0, min(1, t))
        let proj = NSPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(point.x - proj.x, point.y - proj.y)
    }

    @objc func saveAsMenuAction() {
        overlayDelegate?.overlayViewDidRequestSave()
    }

    // MARK: - Keyboard

    override func flagsChanged(with event: NSEvent) {
        // Re-apply shift constraint immediately when Shift is pressed/released during annotation drag
        if currentAnnotation != nil, let lastPoint = lastDragPoint {
            let shiftHeld = event.modifierFlags.contains(.shift)
            updateAnnotation(at: lastPoint, shiftHeld: shiftHeld)
            needsDisplay = true
        }
    }

    /// Called by the Character Palette when the user selects an emoji.
    override func insertText(_ insertString: Any) {
        guard currentTool == .stamp, let str = insertString as? String, !str.isEmpty else { return }
        currentStampImage = StampEmojis.renderEmoji(str)
        currentStampEmoji = str
        needsDisplay = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Forward Cmd shortcuts to the text view when editing — the main menu
        // intercepts these before keyDown reaches the overlay window.
        // Use keyCode (hardware-based) instead of charactersIgnoringModifiers
        // so shortcuts work regardless of keyboard layout (e.g. Russian, Arabic).
        if event.modifierFlags.contains(.command) {
            let key = event.keyCode
            // Text editing: forward to NSTextView (only when text is actively selected)
            if let tv = textEditView {
                switch key {
                case 8:  // C
                    if tv.selectedRange().length > 0 {
                        tv.copy(nil)
                    } else {
                        // No text selected — commit, copy annotation, then deselect
                        // so the purple selection chrome doesn't flash
                        commitTextFieldIfNeeded()
                        if selectedAnnotations.isEmpty, let last = annotations.last, last.tool == .text {
                            selectedAnnotation = last
                        }
                        copySelectedAnnotations()
                        selectedAnnotations = []
                        needsDisplay = true
                    }
                    return true
                case 9:  // V
                    if NSPasteboard.general.data(forType: Self.annotationPasteboardType) != nil {
                        commitTextFieldIfNeeded()
                        pasteAnnotations()
                        selectedAnnotations = []
                        needsDisplay = true
                    } else {
                        tv.paste(nil)
                    }
                    return true
                case 7: tv.cut(nil); return true  // X
                case 0: tv.selectAll(nil); return true  // A
                case 6:  // Z
                    if event.modifierFlags.contains(.shift) { tv.undoManager?.redo() }
                    else { tv.undoManager?.undo() }
                    return true
                default: break
                }
            }

            // Annotation copy/paste (no text editing active)
            if state == .selected {
                switch key {
                case 8:  // C
                    if !selectedAnnotations.isEmpty {
                        copySelectedAnnotations()
                    } else {
                        overlayDelegate?.overlayViewDidConfirm()
                    }
                    return true
                case 9:  // V
                    if NSPasteboard.general.data(forType: Self.annotationPasteboardType) != nil {
                        pasteAnnotations()
                        return true
                    }
                default: break
                }
            }

            // Canvas undo/redo — intercept before main menu consumes the event
            if state == .selected {
                switch key {
                case 6:  // Z
                    if event.modifierFlags.contains(.shift) { redo() }
                    else { undo() }
                    return true
                case 16:  // Y
                    redo()
                    return true
                default: break
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // In recording mode, only allow Escape (to exit recording mode)
        if isRecording {
            if event.keyCode == 53 { // Escape
                handleToolbarAction(.stopRecord)
            }
            return
        }

        // Space: reposition shape/selection mid-drag (design tool convention)
        if event.keyCode == 49 {
            // Swallow all repeats while repositioning to prevent system beep
            if spaceRepositioning { return }

            if !event.isARepeat {
                let isDraggingAnnotation =
                    currentAnnotation != nil && currentAnnotation!.tool != .pencil
                    && currentAnnotation!.tool != .marker
                let isDraggingNewSelection = state == .selecting

                if isDraggingAnnotation || isDraggingNewSelection {
                    spaceRepositioning = true
                    if isDraggingAnnotation {
                        spaceRepositionLast = lastDragPoint ?? .zero
                    } else if let windowPoint = window?.mouseLocationOutsideOfEventStream {
                        spaceRepositionLast = convert(windowPoint, from: nil)
                    }
                    return
                }
            }
        }

        switch event.keyCode {
        case 53:  // Escape
            if isScrollCapturing {
                overlayDelegate?.overlayViewDidRequestStopScrollCapture()
                return
            }
            if isAnchoredSelecting {
                cancelAnchoredSelection()
                return
            }
            if colorWheel.isVisible && colorWheel.isSticky {
                colorWheel.dismiss()
                needsDisplay = true
            } else if textEditView != nil {
                cancelTextEditing()
            } else if PopoverHelper.isVisible {
                PopoverHelper.dismiss()
            } else if !selectedAnnotations.isEmpty {
                selectedAnnotations = []
                needsDisplay = true
            } else {
                overlayDelegate?.overlayViewDidCancel()
            }
        case 48:  // Tab
            if state == .idle {
                // Toggle window snapping in idle state
                windowSnapEnabled = !windowSnapEnabled
                hoveredWindowRect = nil
                needsDisplay = true
                // Notify other overlays to redraw (for multi-monitor setups)
                overlayDelegate?.overlayViewDidChangeWindowSnapState()
            }
        case 3:  // F — full screen capture (only in idle state with snap on)
            if state == .idle && windowSnapEnabled {
                selectionRect = bounds
                state = .selected
                hoveredWindowRect = nil
                if autoQuickSaveMode {
                    autoQuickSaveMode = false
                    overlayDelegate?.overlayViewDidRequestQuickSave()
                } else {
                    showToolbars = true
                    scheduleBarcodeDetection()
                    overlayDelegate?.overlayViewDidFinishSelection(selectionRect)
                    needsDisplay = true
                }
            }
        case 36:  // Return/Enter — same as Done
            if textEditView == nil, state == .selected {
                overlayDelegate?.overlayViewDidConfirm()
            }
        case 51:  // Backspace/Delete — remove selected annotation(s)
            guard textEditView == nil, state == .selected, !selectedAnnotations.isEmpty else { break }
            for ann in selectedAnnotations {
                if let idx = annotations.firstIndex(where: { $0 === ann }) {
                    annotations.remove(at: idx)
                    undoStack.append(.deleted(ann, idx))
                }
            }
            redoStack.removeAll()
            selectedAnnotations = []
            cachedCompositedImage = nil
            needsDisplay = true
        default:
            // Auto-measure: hold "1" = vertical preview, hold "2" = horizontal preview
            if state == .selected && currentTool == .measure && textEditView == nil
                && !event.modifierFlags.contains(.command)
            {
                if let char = event.charactersIgnoringModifiers {
                    if char == "1" || char == "2" {
                        autoMeasureVertical = (char == "1")
                        if !autoMeasureKeyHeld {
                            autoMeasureKeyHeld = true
                            updateAutoMeasurePreview()
                        }
                        return
                    }
                }
            }
            // Single-key tool shortcuts (only when selected, not editing text, no modifiers)
            if state == .selected && textEditView == nil && !event.modifierFlags.contains(.command)
                && !event.modifierFlags.contains(.option) && !event.modifierFlags.contains(.control)
            {
                if let char = event.charactersIgnoringModifiers?.lowercased(),
                   let action = ToolShortcutManager.lookupAction(for: char) {
                    switch action {
                    case .detach:
                        if shouldAllowDetach() { handleToolbarAction(.detach) }
                    case .pin, .scrollCapture:
                        if !isEditorMode { handleToolbarAction(action) }
                    default:
                        handleToolbarAction(action)
                    }
                    return
                }
            }
            if event.modifierFlags.contains(.command) {
                // Cmd+C, Cmd+V, Cmd+X, Cmd+A, Cmd+Z are handled in performKeyEquivalent.
                // Only Cmd+S and zoom shortcuts remain here.
                // Use keyCode for letters so shortcuts work with any keyboard layout.
                if event.keyCode == 1 {  // S
                    if state == .selected {
                        overlayDelegate?.overlayViewDidRequestSave()
                    }
                    return
                }
                if event.charactersIgnoringModifiers == "0" {
                    if isInsideScrollView, let sv = enclosingScrollView {
                        sv.magnification = 1.0
                        findTopBar()?.updateZoom(1.0)
                    } else if state == .selected && zoomLevel != 1.0 {
                        resetZoom()
                        showZoomLabel()
                        needsDisplay = true
                    }
                    return
                }
                if isInsideScrollView {
                    if event.charactersIgnoringModifiers == "=" || event.charactersIgnoringModifiers == "+" {
                        if let sv = enclosingScrollView, let doc = sv.documentView {
                            let newMag = min(sv.maxMagnification, sv.magnification * 1.25)
                            sv.setMagnification(newMag, centeredAt: NSPoint(x: doc.bounds.midX, y: doc.bounds.midY))
                            findTopBar()?.updateZoom(newMag)
                        }
                        return
                    }
                    if event.charactersIgnoringModifiers == "-" {
                        if let sv = enclosingScrollView, let doc = sv.documentView {
                            let newMag = max(sv.minMagnification, sv.magnification / 1.25)
                            sv.setMagnification(newMag, centeredAt: NSPoint(x: doc.bounds.midX, y: doc.bounds.midY))
                            findTopBar()?.updateZoom(newMag)
                        }
                        return
                    }
                    if event.charactersIgnoringModifiers == "1" {
                        if let sv = enclosingScrollView, let doc = sv.documentView {
                            let unscaledW = doc.frame.width / sv.magnification
                            let unscaledH = doc.frame.height / sv.magnification
                            guard unscaledW > 0, unscaledH > 0 else { return }
                            let clipSize = sv.contentView.bounds.size
                            let fitMag = min(clipSize.width / unscaledW, clipSize.height / unscaledH)
                            let clamped = max(sv.minMagnification, min(sv.maxMagnification, fitMag))
                            sv.magnification = clamped
                            findTopBar()?.updateZoom(clamped)
                        }
                        return
                    }
                }
            }
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 && spaceRepositioning {
            spaceRepositioning = false
            return
        }
        // Clear auto-measure preview on key release (click to commit instead)
        if let char = event.charactersIgnoringModifiers, char == "1" || char == "2" {
            if autoMeasureKeyHeld {
                autoMeasureKeyHeld = false
                autoMeasurePreview = nil
                autoMeasureBitmapCtx = nil  // free cached bitmap
                needsDisplay = true
                return
            }
        }
        super.keyUp(with: event)
    }

    // MARK: - Annotation Copy/Paste

    static let annotationPasteboardType = NSPasteboard.PasteboardType("com.sw33tlie.macshot.annotations")

    /// Copy selected annotations to the pasteboard.
    func copySelectedAnnotations() {
        let toCopy = selectedAnnotations.isEmpty ? [] : selectedAnnotations
        guard !toCopy.isEmpty else { return }
        guard let data = AnnotationSerializer.encode(toCopy) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: Self.annotationPasteboardType)
    }

    /// Paste annotations from the pasteboard, offset slightly so they're visible.
    func pasteAnnotations() {
        let pb = NSPasteboard.general
        guard let data = pb.data(forType: Self.annotationPasteboardType),
              let pasted = AnnotationSerializer.decode(data) else { return }
        selectedAnnotations = []
        var newAnnotations: [Annotation] = []
        for ann in pasted {
            let copy = ann.clone()
            copy.move(dx: 15, dy: -15)
            annotations.append(copy)
            undoStack.append(.added(copy))
            newAnnotations.append(copy)
        }
        redoStack.removeAll()
        selectedAnnotations = newAnnotations
        cachedCompositedImage = nil
        needsDisplay = true
    }

    // MARK: - Undo/Redo

    func undo() {
        guard let entry = undoStack.last else { return }
        undoStack.removeLast()
        switch entry {
        case .added(let ann):
            // Undo an addition — handle batch (groupID) or single
            if let groupID = ann.groupID {
                var batch: [UndoEntry] = [.added(ann)]
                while let prev = undoStack.last, prev.annotation.groupID == groupID {
                    undoStack.removeLast()
                    batch.append(prev)
                }
                for e in batch { annotations.removeAll { $0 === e.annotation } }
                if ann.tool == .number { numberCounter = max(0, numberCounter - batch.count) }
                if ann.tool == .translateOverlay { translateEnabled = false; rebuildToolbarLayout() }
                redoStack.append(contentsOf: batch)
                clearHoverIfNeeded(batch.map { $0.annotation })
            } else {
                annotations.removeAll { $0 === ann }
                if ann.tool == .number { numberCounter = max(0, numberCounter - 1) }
                if ann.tool == .translateOverlay { translateEnabled = false; rebuildToolbarLayout() }
                redoStack.append(.added(ann))
                clearHoverIfNeeded([ann])
            }
        case .deleted(let ann, let idx):
            // Undo a deletion — re-insert at original position
            let safeIdx = min(idx, annotations.count)
            annotations.insert(ann, at: safeIdx)
            if ann.tool == .number { numberCounter += 1 }
            redoStack.append(.deleted(ann, idx))
        case .propertyChange(let ann, let snapshot):
            // Undo property change — swap current state with snapshot
            let currentSnapshot = ann.clone()
            ann.copyProperties(from: snapshot)
            redoStack.append(.propertyChange(annotation: ann, snapshot: currentSnapshot))
            cachedCompositedImage = nil
        case .imageTransform(let previousImage, _):
            // Undo crop/flip — swap the current image with the saved one
            let currentImage = screenshotImage?.copy() as? NSImage ?? previousImage
            redoStack.append(.imageTransform(previousImage: currentImage, annotationOffsets: []))
            screenshotImage = previousImage
            // Update selectionRect to match restored image size
            if isEditorMode {
                selectionRect = NSRect(origin: .zero, size: previousImage.size)
                if isInsideScrollView { frame.size = previousImage.size }
            }
            cachedCompositedImage = nil
            resetZoom()
        }
        needsDisplay = true
    }

    func clearHoverIfNeeded(_ removed: [Annotation]) {
        var changed = false
        if let h = hoveredAnnotation, removed.contains(where: { $0 === h }) {
            hoveredAnnotationClearTimer?.invalidate()
            hoveredAnnotationClearTimer = nil
            hoveredAnnotation = nil
            changed = true
        }
        let beforeCount = selectedAnnotations.count
        selectedAnnotations.removeAll { ann in removed.contains(where: { $0 === ann }) }
        if selectedAnnotations.count != beforeCount {
            changed = true
        }
    }

    func redo() {
        guard let entry = redoStack.last else { return }
        redoStack.removeLast()
        switch entry {
        case .added(let ann):
            if let groupID = ann.groupID {
                var batch: [UndoEntry] = [.added(ann)]
                while let next = redoStack.last, next.annotation.groupID == groupID {
                    redoStack.removeLast()
                    batch.append(next)
                }
                for e in batch { annotations.append(e.annotation) }
                if ann.tool == .number { numberCounter += batch.count }
                undoStack.append(contentsOf: batch)
            } else {
                annotations.append(ann)
                if ann.tool == .number { numberCounter += 1 }
                undoStack.append(.added(ann))
            }
        case .deleted(let ann, let idx):
            // Redo a deletion — remove again
            annotations.removeAll { $0 === ann }
            if ann.tool == .number { numberCounter = max(0, numberCounter - 1) }
            undoStack.append(.deleted(ann, idx))
        case .propertyChange(let ann, let snapshot):
            // Redo property change — swap again
            let currentSnapshot = ann.clone()
            ann.copyProperties(from: snapshot)
            undoStack.append(.propertyChange(annotation: ann, snapshot: currentSnapshot))
            cachedCompositedImage = nil
        case .imageTransform(let redoImage, _):
            // Redo crop/flip — swap back
            let currentImage = screenshotImage?.copy() as? NSImage ?? redoImage
            undoStack.append(.imageTransform(previousImage: currentImage, annotationOffsets: []))
            screenshotImage = redoImage
            if isEditorMode {
                selectionRect = NSRect(origin: .zero, size: redoImage.size)
                if isInsideScrollView { frame.size = redoImage.size }
            }
            cachedCompositedImage = nil
            if !isInsideScrollView { resetZoom() }
        }
        needsDisplay = true
    }

}
