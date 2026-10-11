import AVFoundation
import Cocoa
import UniformTypeIdentifiers

extension OverlayView {
    // MARK: - Recording Permission Pre-checks

    /// Sequentially request mic and camera permissions so system dialogs don't overlap behind the overlay.
    func preCheckRecordingPermissions() {
        checkMicPermission { [weak self] in
            self?.checkCameraPermission()
        }
    }

    func checkMicPermission(then next: @escaping () -> Void) {
        guard UserDefaults.standard.bool(forKey: "recordMicAudio") else { next(); return }
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .authorized {
            startMicLevelMonitor()
            next()
        } else if status == .notDetermined {
            let savedLevel = window?.level
            window?.level = .normal
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if let saved = savedLevel { self?.window?.level = saved }
                    if granted {
                        self?.startMicLevelMonitor()
                    } else {
                        UserDefaults.standard.set(false, forKey: "recordMicAudio")
                        self?.rebuildToolbarLayout()
                    }
                    next()
                }
            }
        } else {
            UserDefaults.standard.set(false, forKey: "recordMicAudio")
            rebuildToolbarLayout()
            showMicPermissionAlert()
            next()
        }
    }

    func checkCameraPermission() {
        guard UserDefaults.standard.bool(forKey: "recordWebcam") else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            showWebcamSetupPreview()
        } else if status == .notDetermined {
            let savedLevel = window?.level
            window?.level = .normal
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if let saved = savedLevel { self?.window?.level = saved }
                    if granted {
                        self?.showWebcamSetupPreview()
                    } else {
                        UserDefaults.standard.set(false, forKey: "recordWebcam")
                        self?.rebuildToolbarLayout()
                    }
                }
            }
        } else {
            UserDefaults.standard.set(false, forKey: "recordWebcam")
            rebuildToolbarLayout()
        }
    }

    // MARK: - Webcam Toggle & Device Menu

    func toggleWebcamOverlay() {
        let current = UserDefaults.standard.bool(forKey: "recordWebcam")
        if current {
            UserDefaults.standard.set(false, forKey: "recordWebcam")
            dismissWebcamSetupPreview()
            rebuildToolbarLayout()
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            UserDefaults.standard.set(true, forKey: "recordWebcam")
            rebuildToolbarLayout()
            showWebcamSetupPreview()
        case .notDetermined:
            let savedLevel = window?.level
            window?.level = .normal
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if let saved = savedLevel { self?.window?.level = saved }
                    if granted {
                        UserDefaults.standard.set(true, forKey: "recordWebcam")
                        self?.showWebcamSetupPreview()
                    }
                    self?.rebuildToolbarLayout()
                }
            }
        case .denied, .restricted:
            showCameraPermissionAlert()
        @unknown default:
            break
        }
    }

    func showWebcamSetupPreview() {
        guard webcamSetupPreview == nil else { return }
        guard let screen = window?.screen ?? NSScreen.main else { return }

        let overlay = WebcamOverlay(screen: screen)
        let position = WebcamPosition(rawValue: UserDefaults.standard.string(forKey: "webcamPosition") ?? "bottomRight") ?? .bottomRight
        let size = WebcamSize(rawValue: UserDefaults.standard.string(forKey: "webcamSize") ?? "medium") ?? .medium
        let shape = WebcamShape(rawValue: UserDefaults.standard.string(forKey: "webcamShape") ?? "circle") ?? .circle

        let screenOrigin = screen.frame.origin
        let screenRect = NSRect(
            x: selectionRect.origin.x + screenOrigin.x,
            y: selectionRect.origin.y + screenOrigin.y,
            width: selectionRect.width,
            height: selectionRect.height)

        overlay.configure(position: position, size: size, shape: shape, recordingRect: screenRect)
        overlay.startPreview(deviceUID: UserDefaults.standard.string(forKey: "selectedCameraDeviceUID"))
        overlay.setDraggable(true)
        overlay.orderFront(nil)
        webcamSetupPreview = overlay
    }

    func dismissWebcamSetupPreview() {
        webcamSetupPreview?.stopPreview()
        webcamSetupPreview?.close()
        webcamSetupPreview = nil
    }

    /// Detach the setup preview so it can be reused during recording (avoids camera restart).
    func detachWebcamSetupPreview() -> WebcamOverlay? {
        let overlay = webcamSetupPreview
        webcamSetupPreview = nil
        return overlay
    }

    func updateWebcamSetupPreview() {
        guard webcamSetupPreview != nil else { return }
        dismissWebcamSetupPreview()
        if UserDefaults.standard.bool(forKey: "recordWebcam") {
            showWebcamSetupPreview()
        }
    }

    /// Reposition the webcam preview to follow the current selection without restarting the camera.
    func repositionWebcamSetupPreview() {
        guard let overlay = webcamSetupPreview,
              let screen = window?.screen ?? NSScreen.main else { return }
        let position = WebcamPosition(rawValue: UserDefaults.standard.string(forKey: "webcamPosition") ?? "bottomRight") ?? .bottomRight
        let size = WebcamSize(rawValue: UserDefaults.standard.string(forKey: "webcamSize") ?? "medium") ?? .medium
        let shape = WebcamShape(rawValue: UserDefaults.standard.string(forKey: "webcamShape") ?? "circle") ?? .circle
        let screenOrigin = screen.frame.origin
        let screenRect = NSRect(
            x: selectionRect.origin.x + screenOrigin.x,
            y: selectionRect.origin.y + screenOrigin.y,
            width: selectionRect.width,
            height: selectionRect.height)
        overlay.configure(position: position, size: size, shape: shape, recordingRect: screenRect)
    }

    func showCameraPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = L("Camera Access Required")
        alert.informativeText = L("Lumashot needs camera permission for the webcam overlay. Open System Settings to grant access.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Open Settings"))
        alert.addButton(withTitle: L("Cancel"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func showWebcamDeviceMenu(anchorView: NSView) {
        let menu = NSMenu()
        let savedUID = UserDefaults.standard.string(forKey: "selectedCameraDeviceUID")
        let webcamOn = UserDefaults.standard.bool(forKey: "recordWebcam")

        let noneItem = NSMenuItem(title: L("None"), action: #selector(webcamMenuNone), keyEquivalent: "")
        noneItem.target = self
        if !webcamOn { noneItem.state = .on }
        menu.addItem(noneItem)
        menu.addItem(NSMenuItem.separator())

        let devices = WebcamOverlay.availableCameras
        for device in devices {
            let item = NSMenuItem(title: device.localizedName, action: #selector(webcamMenuSelectDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uniqueID
            if webcamOn && (savedUID == device.uniqueID || (savedUID == nil && device == AVCaptureDevice.default(for: .video))) {
                item.state = .on
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchorView.bounds.height), in: anchorView)
    }

    @objc func webcamMenuNone() {
        UserDefaults.standard.set(false, forKey: "recordWebcam")
        dismissWebcamSetupPreview()
        rebuildToolbarLayout()
    }

    @objc func webcamMenuSelectDevice(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        UserDefaults.standard.set(uid, forKey: "selectedCameraDeviceUID")
        UserDefaults.standard.set(true, forKey: "recordWebcam")
        rebuildToolbarLayout()
        updateWebcamSetupPreview()
    }

    /// Update the color swatch on the main toolbar's color button without a full rebuild.
    func updateToolbarColorSwatch() {
        if let idx = bottomButtons.firstIndex(where: { if case .color = $0.action { return true } else { return false } }) {
            bottomButtons[idx].bgColor = currentColor
            bottomStripView?.updateState(from: bottomButtons)
            // Schedule button redraw on next run loop iteration so it happens after
            // the overlay's own draw pass (which can paint over button subviews).
            if idx < (bottomStripView?.buttonViews.count ?? 0) {
                let buttonView = bottomStripView?.buttonViews[idx]
                DispatchQueue.main.async {
                    buttonView?.needsDisplay = true
                }
            }
        }
    }

    func handleToolbarAction(_ action: ToolbarButtonAction, mousePoint: NSPoint = .zero) {
        switch action {
        case .tool(let tool):
            commitTextFieldIfNeeded()
            showBeautifyInOptionsRow = false  // switch back to tool options
            currentTool = tool
            // Auto-select first emoji when switching to stamp tool with nothing selected
            if tool == .stamp && currentStampImage == nil {
                currentStampImage = StampEmojis.renderEmoji(StampEmojis.common[0])
                currentStampEmoji = StampEmojis.common[0]
            }
            needsDisplay = true
        case .loupe:
            currentTool = .loupe
            needsDisplay = true
        case .color:
            if PopoverHelper.isVisible { PopoverHelper.dismiss(); break }
            let colorBtn = bottomStripView?.buttonViews.first { if case .color = $0.action { return true }; return false }
            showColorPickerPopover(target: .drawColor, anchorView: colorBtn)
        case .more:
            let moreBtn = bottomStripView?.buttonViews.first { if case .more = $0.action { return true }; return false }
            showMoreActionsPopover(anchorView: moreBtn)
        case .sizeDisplay:
            break
        case .moveSelection:
            guard let win = window else { break }
            // Moving breaks window snap — revert to normal beautify mode
            if selectionIsWindowSnap {
                selectionIsWindowSnap = false
                snappedWindowID = nil
                snappedWindowImage = nil
                rebuildToolbarLayout()
            }
            // Show drag hint tooltip
            hoveredTooltip = L("Drag to reposition")
            needsDisplay = true
            displayIfNeeded()
            // Synchronous drag loop: tracks mouse from button press until release
            let startPoint = convert(win.mouseLocationOutsideOfEventStream, from: nil)
            let offset = NSPoint(x: startPoint.x - selectionRect.origin.x, y: startPoint.y - selectionRect.origin.y)
            let hasWebcam = webcamSetupPreview != nil
            while true {
                guard let event = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
                let point = convert(event.locationInWindow, from: nil)
                selectionRect.origin = NSPoint(x: point.x - offset.x, y: point.y - offset.y)
                if hasWebcam { repositionWebcamSetupPreview() }
                needsDisplay = true
                displayIfNeeded()
                if event.type == .leftMouseUp { break }
            }
            // Restore original tooltip and reset button pressed state
            hoveredTooltip = hoveredTooltipButtonView?.tooltipText
            if let moveBtn = rightStripView?.buttonViews.first(where: { if case .moveSelection = $0.action { return true }; return false }) {
                moveBtn.isPressed = false
                moveBtn.needsDisplay = true
            }
            scheduleBarcodeDetection()
            needsDisplay = true
        case .undo:
            undo()
        case .redo:
            redo()
        case .copy:
            overlayDelegate?.overlayViewDidConfirm()
        case .save:
            overlayDelegate?.overlayViewDidRequestSave()
        case .upload:
            let confirmEnabled = UserDefaults.standard.bool(forKey: "uploadConfirmEnabled")
            if confirmEnabled {
                let provider = UserDefaults.standard.string(forKey: "uploadProvider") ?? "imgbb"
                let title: String
                switch provider {
                case "gdrive": title = L("Upload to Google Drive?")
                case "s3": title = L("Upload to S3?")
                default: title = L("Upload to imgbb.com?")
                }
                let alert = NSAlert()
                alert.messageText = title
                alert.informativeText = L("Your screenshot will be uploaded.")
                alert.addButton(withTitle: L("Upload"))
                alert.addButton(withTitle: L("Cancel"))
                alert.alertStyle = .informational
                // Temporarily lower window level so the alert is visible
                let originalLevel = window?.level ?? .statusBar
                window?.level = .normal
                let response = alert.runModal()
                window?.level = originalLevel
                if response == .alertFirstButtonReturn {
                    overlayDelegate?.overlayViewDidRequestUpload()
                }
            } else {
                overlayDelegate?.overlayViewDidRequestUpload()
            }
        case .share:
            // Show share picker anchored to the share button, then dismiss on selection
            let shareBtn = toolbarButtonView(for: .share)
            overlayDelegate?.overlayViewDidRequestShare(anchorView: shareBtn)
        case .hdrToggle:
            isHDRCaptureMode.toggle()
            UserDefaults.standard.set(isHDRCaptureMode, forKey: "captureHDREnabled")
            needsDisplay = true
        case .pin:
            overlayDelegate?.overlayViewDidRequestPin()
        case .ocr:
            overlayDelegate?.overlayViewDidRequestOCR()
        case .autoRedact:
            performAutoRedact()
        case .removeBackground:
            if #available(macOS 14.0, *) {
                overlayDelegate?.overlayViewDidRequestRemoveBackground()
            }
        case .invertColors:
            invertImageColors()
        case .effects:
            let btn = bottomStripView?.buttonViews.first { if case .effects = $0.action { return true }; return false }
            showEffectsPopover(anchorView: btn)
        case .beautify:
            commitTextFieldIfNeeded()
            stampPreviewPoint = nil
            loupeCursorPoint = .zero
            // Auto-enable beautify on first click in this session
            if !beautifyEnabled {
                beautifyEnabled = true
                UserDefaults.standard.set(true, forKey: "beautifyEnabled")
                startBeautifyToolbarAnimation()
            }
            showBeautifyInOptionsRow = true
            needsDisplay = true
        case .beautifyStyle:
            beautifyStyleIndex = (beautifyStyleIndex + 1) % BeautifyRenderer.styles.count
            UserDefaults.standard.set(beautifyStyleIndex, forKey: "beautifyStyleIndex")
            needsDisplay = true
        case .delayCapture:
            break
        case .translate:
            if translateEnabled {
                // Toggle off: remove overlays, restore original
                translateEnabled = false
                annotations.removeAll { $0.tool == .translateOverlay }
                isTranslating = false
            } else {
                translateEnabled = true
                performTranslate(targetLang: TranslationService.targetLanguage)
            }
            needsDisplay = true
        case .record:
            // Enter recording mode — shows recording setup toolbar
            overlayDelegate?.overlayViewDidRequestEnterRecordingMode()
        case .startRecord:
            // Start recording — overlay will be dismissed by AppDelegate
            overlayDelegate?.overlayViewDidRequestStartRecording(rect: selectionRect)
        case .stopRecord:
            // Exit recording mode — dismiss overlay entirely (user changed mind)
            isRecording = false
            overlayDelegate?.overlayViewDidCancel()
        case .mouseHighlight:
            let current = UserDefaults.standard.bool(forKey: "recordMouseHighlight")
            UserDefaults.standard.set(!current, forKey: "recordMouseHighlight")
            rebuildToolbarLayout()
        case .showKeystrokes:
            toggleKeystrokeOverlay()
        case .systemAudio:
            let current = UserDefaults.standard.bool(forKey: "recordSystemAudio")
            UserDefaults.standard.set(!current, forKey: "recordSystemAudio")
            rebuildToolbarLayout()
        case .micAudio:
            toggleMicAudio()
        case .webcam:
            toggleWebcamOverlay()
        case .cancel:
            overlayDelegate?.overlayViewDidCancel()
        case .detach:
            overlayDelegate?.overlayViewDidRequestDetach()
        case .scrollCapture:
            overlayDelegate?.overlayViewDidRequestScrollCapture(rect: selectionRect)
        case .addCapture:
            overlayDelegate?.overlayViewDidRequestAddCapture()
        case .recordSettings:
            let gearBtn = rightStripView?.buttonViews.first { if case .recordSettings = $0.action { return true }; return false }
            showRecordingSettingsPopover(anchorView: gearBtn)
        }

        // Rebuild toolbars to reflect new state (selected tool, color, etc.)
        rebuildToolbarLayout()
    }

    func toolbarButtonView(for action: ToolbarButtonAction) -> ToolbarButtonView? {
        let views = (bottomStripView?.buttonViews ?? []) + (rightStripView?.buttonViews ?? [])
        return views.first { view in
            switch (view.action, action) {
            case (.color, .color), (.more, .more), (.undo, .undo), (.redo, .redo),
                 (.copy, .copy), (.save, .save), (.pin, .pin), (.ocr, .ocr),
                 (.autoRedact, .autoRedact), (.beautify, .beautify),
                 (.beautifyStyle, .beautifyStyle), (.cancel, .cancel),
                 (.moveSelection, .moveSelection), (.delayCapture, .delayCapture),
                 (.upload, .upload), (.share, .share),
                 (.removeBackground, .removeBackground), (.invertColors, .invertColors),
                 (.loupe, .loupe), (.translate, .translate), (.record, .record),
                 (.startRecord, .startRecord), (.stopRecord, .stopRecord),
                 (.mouseHighlight, .mouseHighlight), (.systemAudio, .systemAudio),
                 (.micAudio, .micAudio), (.detach, .detach), (.scrollCapture, .scrollCapture),
                 (.addCapture, .addCapture), (.showKeystrokes, .showKeystrokes),
                 (.webcam, .webcam), (.recordSettings, .recordSettings),
                 (.effects, .effects), (.sizeDisplay, .sizeDisplay), (.hdrToggle, .hdrToggle):
                return true
            case (.tool(let lhs), .tool(let rhs)):
                return lhs == rhs
            default:
                return false
            }
        }
    }

    /// Returns a color if a preset swatch was clicked, toggles the inline HSB picker
    /// if the custom picker swatch was clicked, or picks from the HSB gradient.
    /// Returns nil if nothing was hit.

    func applyColorToTextIfEditing() {
        if textEditor.isEditing {
            textEditor.applyColorToLiveText(color: annotationColor)
        }
    }

    /// Push a property change undo entry. Called by ToolOptionsRowView when editing completes.
    func updateBeautifySwatch(styleIndex: Int) {
        toolOptionsRowView?.updateBeautifySwatch(styleIndex: styleIndex)
    }

    func pushPropertyChangeUndo(annotation: Annotation, snapshot: Annotation) {
        undoStack.append(.propertyChange(annotation: annotation, snapshot: snapshot))
        redoStack.removeAll()
        cachedCompositedImage = nil
    }

    func applyColorToSelectedAnnotation() {
        guard !selectedAnnotations.isEmpty else { return }
        for ann in selectedAnnotations {
            ann.color = opacityAppliedColor(for: ann.tool)
        }
        cachedCompositedImage = nil
        needsDisplay = true
    }

    /// Apply current text formatting from textEditor to selected text annotations (when not actively editing).
    func applyTextFormattingToSelectedAnnotations() {
        guard textEditor.textView == nil else { return }  // skip if actively editing
        var changed = false
        for ann in selectedAnnotations where ann.tool == .text {
            ann.fontSize = textEditor.fontSize
            ann.isBold = textEditor.bold
            ann.isItalic = textEditor.italic
            ann.isUnderline = textEditor.underline
            ann.isStrikethrough = textEditor.strikethrough
            ann.fontFamilyName = textEditor.fontFamily == "System" ? nil : textEditor.fontFamily
            ann.textAlignment = textEditor.alignment
            ann.reRenderTextImage()
            changed = true
        }
        if changed {
            cachedCompositedImage = nil
            needsDisplay = true
        }
    }

    /// Apply current glyph-stroke state to the live NSTextView (if open).
    /// Touches existing text + future typing so the change is visible immediately.
    func applyGlyphStrokeToLiveTextView() {
        guard let tv = textEditor.textView, let storage = tv.textStorage else { return }
        let range = NSRange(location: 0, length: storage.length)
        if textEditor.glyphStrokeEnabled {
            if range.length > 0 {
                storage.addAttribute(.strokeColor, value: textEditor.glyphStrokeColor, range: range)
                storage.addAttribute(.strokeWidth, value: -6.0, range: range)
            }
            tv.typingAttributes[.strokeColor] = textEditor.glyphStrokeColor
            tv.typingAttributes[.strokeWidth] = -6.0
        } else {
            if range.length > 0 {
                storage.removeAttribute(.strokeColor, range: range)
                storage.removeAttribute(.strokeWidth, range: range)
            }
            tv.typingAttributes.removeValue(forKey: .strokeColor)
            tv.typingAttributes.removeValue(forKey: .strokeWidth)
        }
        tv.needsDisplay = true
    }

    /// Apply text background/outline toggle to selected text annotations.
    func applyTextBgOutlineToSelectedAnnotations() {
        guard textEditor.textView == nil else { return }
        var changed = false
        for ann in selectedAnnotations where ann.tool == .text {
            ann.textBgColor = textEditor.bgEnabled ? textEditor.bgColor : nil
            ann.textOutlineColor = textEditor.outlineEnabled ? textEditor.outlineColor : nil
            ann.textGlyphStrokeColor = textEditor.glyphStrokeEnabled ? textEditor.glyphStrokeColor : nil
            ann.reRenderTextImage()
            changed = true
        }
        if changed {
            cachedCompositedImage = nil
        }
    }

    /// Returns currentColor with opacity applied for tools that respect it.
    /// Marker uses a fixed alpha in its draw method; loupe/measure/pixelate/blur are color-independent.
    func opacityAppliedColor(for tool: AnnotationTool) -> NSColor {
        switch tool {
        case .marker, .loupe, .measure, .pixelate, .blur, .translateOverlay:
            return currentColor
        default:
            return annotationColor
        }
    }

}
