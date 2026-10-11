import AVFoundation
import Cocoa
import UniformTypeIdentifiers

extension OverlayView {
    // MARK: - Tool options API (used by ToolOptionsRowView)

    func activeStrokeWidthForTool(_ tool: AnnotationTool) -> CGFloat {
        switch tool {
        case .number: return currentNumberSize
        case .marker: return currentMarkerSize
        case .loupe: return currentLoupeSize
        default: return currentStrokeWidth
        }
    }

    func setActiveStrokeWidth(_ value: CGFloat, for tool: AnnotationTool) {
        switch tool {
        case .number:
            currentNumberSize = value
            UserDefaults.standard.set(Double(value), forKey: "numberStrokeWidth")
        case .marker:
            currentMarkerSize = value
            UserDefaults.standard.set(Double(value), forKey: "markerStrokeWidth")
        case .loupe:
            currentLoupeSize = value
            UserDefaults.standard.set(Double(value), forKey: "loupeSize")
        default:
            currentStrokeWidth = value
            UserDefaults.standard.set(Double(value), forKey: "currentStrokeWidth")
        }
        needsDisplay = true
    }


    func showColorPickerPopover(target: ColorPickerTarget, anchorView: NSView? = nil, anchorRect: NSRect = .zero) {
        colorPickerTarget = target
        let picker = ColorPickerView()
        let initialColor: NSColor
        switch target {
        case .drawColor: initialColor = currentColor
        case .textBg: initialColor = textEditor.bgColor
        case .textOutline: initialColor = textEditor.outlineColor
        case .textGlyphStroke: initialColor = textEditor.glyphStrokeColor
        case .annotationOutline:
            if let data = UserDefaults.standard.data(forKey: "annotationOutlineColor"),
               let c = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
                initialColor = c
            } else {
                initialColor = .white
            }
        }
        picker.setColor(initialColor, opacity: currentColorOpacity)
        picker.customColors = customColors
        picker.selectedColorSlot = selectedColorSlot

        picker.onColorChanged = { [weak self] color in
            guard let self = self else { return }
            self.applyPickedColor(color)
            picker.saveToSelectedSlot(color)
            // Update toolbar color swatches without rebuilding (which destroys the popover anchor)
            self.toolOptionsRowView?.updateSwatchColors()
            self.needsDisplay = true
        }
        picker.onOpacityChanged = { [weak self] opacity in
            guard let self = self else { return }
            self.currentColorOpacity = opacity
            OverlayView.lastUsedOpacity = opacity
            UserDefaults.standard.set(Double(opacity), forKey: "lastUsedColorOpacity")
            self.applyColorToSelectedAnnotation()
            self.needsDisplay = true
        }
        picker.onCustomSlotSelected = { [weak self] idx in
            self?.selectedColorSlot = idx
        }
        picker.onCustomColorsChanged = { [weak self] colors in
            self?.customColors = colors
            self?.saveCustomColors()
        }

        let size = picker.preferredSize
        if let anchor = anchorView {
            PopoverHelper.show(picker, size: size, relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        } else if anchorRect != .zero {
            PopoverHelper.showAtPoint(picker, size: size, at: NSPoint(x: anchorRect.midX, y: anchorRect.midY), in: self, preferredEdge: .minY)
        } else {
            PopoverHelper.showAtPoint(picker, size: size, at: NSPoint(x: bounds.midX, y: bounds.midY), in: self, preferredEdge: .minY)
        }
    }

    func applyPickedColor(_ color: NSColor) {
        switch colorPickerTarget {
        case .drawColor:
            currentColor = color
            applyColorToTextIfEditing()
            applyColorToSelectedAnnotation()
        case .textBg:
            textEditor.bgColor = color
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
                UserDefaults.standard.set(data, forKey: "textBgColor")
            }
        case .textOutline:
            textEditor.outlineColor = color
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
                UserDefaults.standard.set(data, forKey: "textOutlineColor")
            }
        case .textGlyphStroke:
            textEditor.glyphStrokeColor = color
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
                UserDefaults.standard.set(data, forKey: "textGlyphStrokeColor")
            }
            applyGlyphStrokeToLiveTextView()
            applyTextBgOutlineToSelectedAnnotations()
        case .annotationOutline:
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
                UserDefaults.standard.set(data, forKey: "annotationOutlineColor")
            }
            // Apply to selected annotations
            for ann in selectedAnnotations {
                ann.outlineColor = color
            }
            cachedCompositedImage = nil
        }
        needsDisplay = true
    }

    func reset() {
        state = .idle
        selectionRect = .zero
        selectionIsWindowSnap = false
        snappedWindowID = nil
        snappedWindowImage = nil
        remoteSelectionRect = .zero
        remoteSelectionFullRect = .zero
        annotations.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        currentAnnotation = nil
        numberCounter = 0
        showToolbars = false
        bottomStripView?.isHidden = true
        rightStripView?.isHidden = true
        toolOptionsRowView?.isHidden = true
        PopoverHelper.dismiss()
        editorTooltipView?.removeFromSuperview()
        editorTooltipView = nil
        isTranslating = false
        translateEnabled = false
        autoMeasurePreview = nil
        autoMeasureKeyHeld = false
        autoMeasureBitmapCtx = nil
        selectedAnnotation = nil
        isDraggingAnnotation = false
        hoveredAnnotationClearTimer?.invalidate()
        hoveredAnnotationClearTimer = nil
        hoveredAnnotation = nil
        colorWheel.dismiss()
        beautifyEnabled = UserDefaults.standard.bool(forKey: "beautifyEnabled")
        beautifyStyleIndex = UserDefaults.standard.integer(forKey: "beautifyStyleIndex")
        beautifyMode =
            BeautifyMode(rawValue: UserDefaults.standard.integer(forKey: "beautifyMode")) ?? .window
        beautifyPadding = CGFloat(
            UserDefaults.standard.object(forKey: "beautifyPadding") as? Double ?? 48)
        beautifyCornerRadius = CGFloat(
            UserDefaults.standard.object(forKey: "beautifyCornerRadius") as? Double ?? 10)
        beautifyShadowRadius = CGFloat(
            UserDefaults.standard.object(forKey: "beautifyShadowRadius") as? Double ?? 20)
        beautifyBgRadius = CGFloat(
            UserDefaults.standard.object(forKey: "beautifyBgRadius") as? Double ?? 8)
        currentLineStyle =
            LineStyle(rawValue: UserDefaults.standard.integer(forKey: "currentLineStyle")) ?? .solid
        currentArrowStyle =
            ArrowStyle(rawValue: UserDefaults.standard.integer(forKey: "currentArrowStyle"))
            ?? .single
        currentRectFillStyle =
            RectFillStyle(rawValue: UserDefaults.standard.integer(forKey: "currentRectFillStyle"))
            ?? .stroke
        currentRectCornerRadius = CGFloat(
            UserDefaults.standard.object(forKey: "currentRectCornerRadius") as? Double ?? 0)
        textEditor.dismiss()
        sizeInputField?.removeFromSuperview()
        sizeInputField = nil
        isResizingAnnotation = false
        loupeCursorPoint = .zero
        colorSamplerPoint = .zero
        colorSamplerBitmap = nil
        overlayErrorTimer?.invalidate()
        overlayErrorTimer = nil
        overlayErrorMessage = nil
        barcodeDetector.cancel()
        hoveredWindowRect = nil
        isRecording = false
        needsDisplay = true
    }
}
