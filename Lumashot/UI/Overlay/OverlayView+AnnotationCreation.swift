import AVFoundation
import Cocoa
import UniformTypeIdentifiers

extension OverlayView {
    // MARK: - Annotation Creation

    func startAnnotation(at point: NSPoint) {
        // No drawing in recording setup mode
        guard !isRecording else { return }

        // Click-to-select: if clicking on an existing annotation, select it instead of
        // starting a new annotation. Pencil and marker use long-press instead (so taps
        // and drags always draw, even single dots).
        let isPencilOrMarker = currentTool == .pencil || currentTool == .marker

        // Multi-select delete button — check before single-select controls
        if selectedAnnotations.count > 1 && multiSelectDeleteButtonRect.contains(point) {
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
            return
        }

        // Always check selected annotation controls (delete, resize, etc.) for all tools
        if currentTool != .colorSampler {
            if let selected = selectedAnnotation {
                if handleSelectedAnnotationClick(selected, at: point) { return }
            }
        }

        // Click-to-select body: Ctrl+click adds/removes from multi-selection
        // (consistent with Ctrl+drag for lasso). Shift is reserved for angle/shape
        // constraining during drawing.
        // For pencil/marker, only instant-select when Ctrl is held or a multi-selection
        // already exists (so the user can drag the group without a modifier).
        // Text tool: allow selecting annotations on click; only skip instant-select
        // when clicking empty space (where a new text box should be created).
        let ctrlHeld = NSEvent.modifierFlags.contains(.control)
        let pencilHasMultiSelection = isPencilOrMarker && selectedAnnotations.count > 1
        let textHitsAnnotation = currentTool == .text
            && annotations.reversed().contains(where: { $0.isMovable && $0.hitTest(point: point) })
        let useInstantSelect = currentTool != .colorSampler
            && (currentTool != .text || ctrlHeld || textHitsAnnotation)
            && (!isPencilOrMarker || ctrlHeld || pencilHasMultiSelection)
        if useInstantSelect {
            if let clicked = annotations.reversed().first(where: { $0.isMovable && $0.hitTest(point: point) }) {
                shiftClickPendingDeselect = nil
                if ctrlHeld {
                    if isSelected(clicked) {
                        // Defer deselect to mouseUp — allows dragging the full
                        // multi-selection even when ctrl+clicking a selected item.
                        shiftClickPendingDeselect = clicked
                    } else {
                        selectedAnnotations.append(clicked)
                    }
                } else if !isSelected(clicked) {
                    // Not Ctrl, not already selected: replace selection
                    selectedAnnotation = clicked
                }
                // If already selected without Ctrl: keep current selection (allows multi-drag)
                isDraggingAnnotation = true
                didMoveAnnotation = false
                annotationDragStart = point
                // Build cache of non-selected annotations for fast drag rendering
                cachedAnnotationLayerExcludingSelected = buildAnnotationLayer(excluding: Set(selectedAnnotations.map { ObjectIdentifier($0) }))
                NSCursor.closedHand.set()
                needsDisplay = true
                return
            }
        }

        // Ctrl+click on empty space — start lasso marquee selection
        if ctrlHeld {
            isLassoSelecting = true
            lassoStart = point
            lassoRect = .zero
            needsDisplay = true
            return
        }

        // Pencil/marker without Ctrl: start a long-press timer. If the user holds
        // still for 300ms on an annotation, select it. Otherwise drawing starts
        // normally (the timer is cancelled in mouseDragged when movement exceeds 3px).
        if isPencilOrMarker && !ctrlHeld {
            let hasAnnotationUnder = annotations.reversed().contains(where: { $0.isMovable && $0.hitTest(point: point) })
            if hasAnnotationUnder {
                longPressPoint = point
                longPressTriggered = false
                longPressTimer?.invalidate()
                longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    self.longPressTriggered = true
                    self.longPressTimer = nil
                    // Select the annotation under the long-press point
                    if let clicked = self.annotations.reversed().first(where: { $0.isMovable && $0.hitTest(point: point) }) {
                        self.shiftClickPendingDeselect = nil
                        if NSEvent.modifierFlags.contains(.control) {
                            if self.isSelected(clicked) {
                                self.shiftClickPendingDeselect = clicked
                            } else {
                                self.selectedAnnotations.append(clicked)
                            }
                        } else if !self.isSelected(clicked) {
                            self.selectedAnnotation = clicked
                        }
                        self.isDraggingAnnotation = true
                        self.didMoveAnnotation = false
                        self.annotationDragStart = point
                        // Build cache of non-selected annotations for fast drag rendering
                        self.cachedAnnotationLayerExcludingSelected = self.buildAnnotationLayer(excluding: Set(self.selectedAnnotations.map { ObjectIdentifier($0) }))
                        // Cancel any in-progress pencil stroke
                        self.currentAnnotation = nil
                        NSCursor.closedHand.set()
                        self.needsDisplay = true
                    }
                }
            }
        }

        // Clicking empty space — clear selection and start new annotation
        if !selectedAnnotations.isEmpty { selectedAnnotations = [] }

        // Dispatch to extracted tool handler if available
        if let handler = toolHandlers[currentTool] {
            if let annotation = handler.start(at: point, canvas: self) {
                // Apply outline color from settings for supported tools
                let outlineTools: [AnnotationTool] = [.arrow, .line, .rectangle, .ellipse, .number]
                if outlineTools.contains(currentTool) && UserDefaults.standard.bool(forKey: "annotationOutlineEnabled") {
                    annotation.outlineColor = ToolOptionsRowView.savedOutlineColor
                }
                currentAnnotation = annotation
                needsDisplay = true
            }
            return
        }

        // Color sampler: click sets the current drawing color, no annotation created.
        // Note: point is already in canvas space (converted by caller).
        if currentTool == .colorSampler {
            if let screenshot = screenshotImage,
                let result = sampleColor(from: screenshot, at: point)
            {
                currentColor = result.color
                currentColorOpacity = 1.0
                OverlayView.lastUsedOpacity = 1.0
                UserDefaults.standard.set(1.0, forKey: "lastUsedColorOpacity")
                // Also save to selected custom slot
                if selectedColorSlot >= 0 && selectedColorSlot < customColors.count {
                    customColors[selectedColorSlot] = result.color.withAlphaComponent(1.0)
                    saveCustomColors()
                    // Advance to next slot for rapid collection
                    let nextSlot = selectedColorSlot + 1
                    if nextSlot < customColors.count { selectedColorSlot = nextSlot }
                }
                showOverlayError(String(format: L("Set color %@"), result.hex))
                needsDisplay = true
            }
            return
        }

        if currentTool == .text {
            // Click on existing text annotation → select it (double-click enters edit via handleSelectedAnnotationClick)
            if let existingAnn = annotations.reversed().first(where: {
                $0.tool == .text && $0.hitTest(point: point)
            }) {
                selectedAnnotation = existingAnn
                needsDisplay = true
                // If double-click, immediately enter edit mode
                if let event = NSApp.currentEvent, event.clickCount >= 2 {
                    textEditor.editingAnnotation = existingAnn
                    textEditor.restoreState(from: existingAnn)
                    if let idx = annotations.firstIndex(where: { $0 === existingAnn }) {
                        annotations.remove(at: idx)
                        selectedAnnotation = nil
                    }
                    showTextField(
                        at: existingAnn.textDrawRect.origin,
                        existingText: existingAnn.attributedText,
                        existingFrame: existingAnn.textDrawRect)
                    cachedCompositedImage = nil
                }
            } else {
                // Click on empty space → new text annotation, immediately enter edit
                showTextField(at: point)
            }
        }
    }

    func updateAnnotation(at point: NSPoint, shiftHeld: Bool = false) {
        guard let annotation = currentAnnotation else { return }
        if let handler = toolHandlers[annotation.tool] {
            handler.update(to: point, shiftHeld: shiftHeld, canvas: self)
        }
    }

    func finishAnnotation(_ annotation: Annotation) {
        if let handler = toolHandlers[annotation.tool] {
            handler.finish(canvas: self)
        }
    }

    /// Handle click on the selected annotation's controls (resize handles, rotation, delete).
    /// Returns true if the click was consumed. Does NOT check the annotation body — that's
    /// handled by the caller's hit-test loop.
    func handleSelectedAnnotationClick(_ selected: Annotation, at point: NSPoint) -> Bool {
        // Unrotate point for resize handle hit test
        let handleTestPoint: NSPoint
        if selected.rotation != 0 && selected.supportsRotation {
            let center = NSPoint(x: selected.boundingRect.midX, y: selected.boundingRect.midY)
            let cos_r = cos(-selected.rotation)
            let sin_r = sin(-selected.rotation)
            let dx = point.x - center.x
            let dy = point.y - center.y
            handleTestPoint = NSPoint(
                x: center.x + dx * cos_r - dy * sin_r,
                y: center.y + dx * sin_r + dy * cos_r)
        } else {
            handleTestPoint = point
        }
        // Check resize handles (populated by drawAnnotationControls)
        for (handleIdx, handleEntry) in annotationResizeHandleRects.enumerated() {
            let (handle, rect) = handleEntry
            if rect.insetBy(dx: -4, dy: -4).contains(handleTestPoint) {
                isResizingAnnotation = true
                // Build cache of non-selected annotations for fast resize rendering
                cachedAnnotationLayerExcludingSelected = buildAnnotationLayer(excluding: Set(selectedAnnotations.map { ObjectIdentifier($0) }))
                annotationResizeHandle = handle
                annotationResizeOrigStart = selected.startPoint
                annotationResizeOrigEnd = selected.endPoint
                annotationResizeOrigTextOrigin = selected.textDrawRect.origin
                annotationResizeMouseStart = point
                annotationResizeAnchorIndex = -1
                if let anchors = selected.anchorPoints, anchors.count >= 3, handleIdx >= 2 {
                    let anchorIdx = handleIdx - 2 + 1
                    if anchorIdx > 0 && anchorIdx < anchors.count - 1 {
                        annotationResizeAnchorIndex = anchorIdx
                        annotationResizeOrigControlPoint = anchors[anchorIdx]
                    }
                } else if handle == .none || (handle != .bottomLeft && handle != .topRight) {
                    if annotationResizeAnchorIndex < 0 {
                        annotationResizeOrigControlPoint =
                            selected.controlPoint
                            ?? NSPoint(
                                x: (selected.startPoint.x + selected.endPoint.x) / 2,
                                y: (selected.startPoint.y + selected.endPoint.y) / 2
                            )
                    }
                }
                NSCursor.closedHand.set()
                needsDisplay = true
                return true
            }
        }
        // Check rotation handle
        if annotationRotateHandleRect != .zero
            && annotationRotateHandleRect.insetBy(dx: -6, dy: -6).contains(point)
        {
            isRotatingAnnotation = true
            cachedAnnotationLayerExcludingSelected = buildAnnotationLayer(excluding: Set(selectedAnnotations.map { ObjectIdentifier($0) }))
            let center = NSPoint(x: selected.boundingRect.midX, y: selected.boundingRect.midY)
            rotationStartAngle = atan2(point.x - center.x, point.y - center.y)
            rotationOriginal = selected.rotation
            NSCursor.closedHand.set()
            needsDisplay = true
            return true
        }
        // Check edit button (text annotations only)
        if selected.tool == .text && annotationEditButtonRect != .zero && annotationEditButtonRect.contains(point) {
            textEditor.restoreState(from: selected)
            if let idx = annotations.firstIndex(where: { $0 === selected }) {
                annotations.remove(at: idx)
                selectedAnnotation = nil
            }
            showTextField(
                at: selected.textDrawRect.origin, existingText: selected.attributedText,
                existingFrame: selected.textDrawRect)
            needsDisplay = true
            return true
        }
        // Check delete button
        if annotationDeleteButtonRect.contains(point) {
            if let idx = annotations.firstIndex(where: { $0 === selected }) {
                annotations.remove(at: idx)
                undoStack.append(.deleted(selected, idx))
                redoStack.removeAll()
            }
            selectedAnnotation = nil
            needsDisplay = true
            return true
        }
        // Double-click on text annotation — enter edit mode
        if selected.tool == .text && selected.hitTest(point: point) {
            if let event = NSApp.currentEvent, event.clickCount >= 2 {
                textEditor.editingAnnotation = selected
                textEditor.restoreState(from: selected)
                if let idx = annotations.firstIndex(where: { $0 === selected }) {
                    annotations.remove(at: idx)
                    selectedAnnotation = nil
                }
                showTextField(
                    at: selected.textDrawRect.origin, existingText: selected.attributedText,
                    existingFrame: selected.textDrawRect)
                cachedCompositedImage = nil
                return true
            }
        }
        // Click on the annotation body — start drag (annotation already selected)
        if selected.hitTest(point: point) {
            isDraggingAnnotation = true
            didMoveAnnotation = false
            annotationDragStart = point
            cachedAnnotationLayerExcludingSelected = buildAnnotationLayer(excluding: Set(selectedAnnotations.map { ObjectIdentifier($0) }))
            NSCursor.closedHand.set()
            needsDisplay = true
            return true
        }
        return false
    }

    // MARK: - Text Field

    func showTextField(
        at point: NSPoint, existingText: NSAttributedString? = nil, existingFrame: NSRect = .zero
    ) {
        textEditor.show(
            in: self, at: point, color: currentColor,
            existingText: existingText, existingFrame: existingFrame,
            canvas: self)
        textEditor.textView?.delegate = self
        rebuildToolbarLayout()
        needsDisplay = true
    }

    func cancelTextEditing() {
        textEditor.cancel(canvas: self)
        window?.makeFirstResponder(self)
        rebuildToolbarLayout()
        needsDisplay = true
    }

    func toggleKeystrokeOverlay() {
        let current = UserDefaults.standard.bool(forKey: "recordKeystroke")
        if current {
            UserDefaults.standard.set(false, forKey: "recordKeystroke")
            rebuildToolbarLayout()
            return
        }
        // Requires Input Monitoring permission for CGEvent tap
        if KeystrokeOverlay.hasInputMonitoringPermission {
            UserDefaults.standard.set(true, forKey: "recordKeystroke")
            rebuildToolbarLayout()
        } else {
            overlayDelegate?.overlayViewDidRequestInputMonitoringPermission()
        }
    }

    func commitTextFieldIfNeeded() {
        guard textEditor.isEditing else { return }
        textEditor.commit(canvas: self)
        window?.makeFirstResponder(self)
        rebuildToolbarLayout()
        needsDisplay = true
    }

}
