import Cocoa
import Carbon
import UniformTypeIdentifiers
import AVFoundation
import WebP

extension AppDelegate: OverlayWindowControllerDelegate {
    func overlayDidCancel(_ controller: OverlayWindowController) {
        // If the user cancels while in recording setup (before capture started),
        // just dismiss. If recording is actively capturing, stop it.
        if controller === recordingOverlayController, let engine = recordingEngine {
            engine.stopRecording()
            // stopRecordingUI() will be called by onCompletion callback
        }
        dismissOverlays()

        // Focus is returned to the previous app by dismissOverlays() above.
    }

    func overlayDidConfirm(_ controller: OverlayWindowController, capturedImage: NSImage?, annotationData: CaptureAnnotationData?) {
        dismissOverlays()
        if let image = capturedImage {
            ScreenshotHistory.shared.add(
                image: image,
                rawImage: annotationData?.rawImage,
                annotations: annotationData?.annotations)
            // The entry just added is at index 0
            let entryID = ScreenshotHistory.shared.entries.first?.id
            // Defer thumbnail to next runloop cycle so overlay teardown completes first
            // and the main thread is free for the next capture trigger
            let annData = annotationData
            DispatchQueue.main.async { [weak self] in
                self?.showFloatingThumbnail(image: image, annotationData: annData, historyEntryID: entryID)
            }

            // "Also open in Editor" preference — open with history entry ID so Done saves back
            if UserDefaults.standard.bool(forKey: "quickCaptureOpenEditor") {
                if let data = annotationData {
                    DetachedEditorWindowController.open(image: data.rawImage, annotations: data.annotations, historyEntryID: entryID)
                } else {
                    DetachedEditorWindowController.open(image: image, historyEntryID: entryID, disableBeautify: true)
                }
            }
        }
    }

    func overlayDidCaptureHDRFile(_ controller: OverlayWindowController, fileURL: URL, previewImage: NSImage?) {
        dismissOverlays()
        guard let image = previewImage ?? NSImage(contentsOf: fileURL) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.showFloatingThumbnail(image: image, representedFileURL: fileURL)
        }
    }

    func stitchCrossScreenCapture(primary: OverlayWindowController, others: [OverlayWindowController]) -> NSImage? {
        let primaryOrigin = primary.screen.frame.origin
        let primarySelRect = primary.selectionRect
        // Global selection rect
        let globalRect = NSRect(x: primarySelRect.origin.x + primaryOrigin.x,
                                y: primarySelRect.origin.y + primaryOrigin.y,
                                width: primarySelRect.width, height: primarySelRect.height)

        // Determine scale from primary screen
        let scale: CGFloat
        if let screenshot = primary.screenshotImage,
           let cg = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            scale = CGFloat(cg.width) / screenshot.size.width
        } else {
            scale = primary.screen.backingScaleFactor
        }

        let pixelW = Int(globalRect.width * scale)
        let pixelH = Int(globalRect.height * scale)
        // Use the source image's color space to avoid expensive conversion
        let cs: CGColorSpace
        if let screenshot = primary.screenshotImage,
           let cg = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let srcCS = cg.colorSpace {
            cs = srcCS
        } else {
            cs = CGColorSpace(name: CGColorSpace.sRGB)!
        }
        guard let cgCtx = CGContext(data: nil, width: pixelW, height: pixelH,
                                     bitsPerComponent: 8, bytesPerRow: pixelW * 4,
                                     space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        cgCtx.scaleBy(x: scale, y: scale)

        // Draw each screen's contribution
        let allControllers = [primary] + others
        for controller in allControllers {
            guard let screenshot = controller.screenshotImage else { continue }
            let screenFrame = controller.screen.frame
            // Where this screen sits relative to the global selection rect
            let drawX = screenFrame.origin.x - globalRect.origin.x
            let drawY = screenFrame.origin.y - globalRect.origin.y
            let drawRect = NSRect(x: drawX, y: drawY, width: screenFrame.width, height: screenFrame.height)

            cgCtx.saveGState()
            // Clip to only the portion within our output bounds
            cgCtx.clip(to: CGRect(x: 0, y: 0, width: globalRect.width, height: globalRect.height))
            let nsContext = NSGraphicsContext(cgContext: cgCtx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsContext
            screenshot.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            cgCtx.restoreGState()
        }

        guard let cgImage = cgCtx.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: globalRect.size)
    }

    func overlayDidRequestPin(_ controller: OverlayWindowController, image: NSImage) {
        ScreenshotHistory.shared.add(image: image)
        let appToRefocus = previousApp
        dismissOverlays(refocusPreviousApp: false)
        let pin = PinWindowController(image: image)
        pin.delegate = self
        pin.show()
        pinControllers.append(pin)
        // Return focus to previous app — pin stays visible (hidesOnDeactivate=false, orderFrontRegardless)
        if let app = appToRefocus, !app.isTerminated, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            DispatchQueue.main.async { AppDelegate.activateApp(app) }
        }
    }

    func overlayDidRequestOCR(_ controller: OverlayWindowController, text: String, image: NSImage?) {
        // OCR action: 0 = window + copy (default), 1 = window only, 2 = copy only
        let ocrAction = UserDefaults.standard.integer(forKey: "ocrAction")
        let shouldCopy = ocrAction == 0 || ocrAction == 2
        let shouldShowWindow = ocrAction == 0 || ocrAction == 1
        dismissOverlays(refocusPreviousApp: !shouldShowWindow)

        if shouldCopy && !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        if shouldShowWindow {
            ocrController?.close()
            let ocr = OCRResultController(text: text, image: image)
            ocrController = ocr
            ocr.show()
        }
    }

    func overlayDidRequestUpload(_ controller: OverlayWindowController, image: NSImage) {
        ScreenshotHistory.shared.add(image: image)
        let appToRefocus = previousApp
        dismissOverlays(refocusPreviousApp: false)
        showUploadProgress(image: image)
        // Return focus — upload toast stays visible (hidesOnDeactivate=false)
        if let app = appToRefocus, !app.isTerminated, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            DispatchQueue.main.async { AppDelegate.activateApp(app) }
        }
    }

    func overlayDidRequestStartRecording(_ controller: OverlayWindowController, rect: NSRect, screen: NSScreen) {
        recordingScreenRect = rect
        recordingScreen = screen

        // Capture session overrides before dismissing overlays (which destroys the overlay view)
        let fpsOverride = controller.sessionRecordingFPS
        let onStopOverride = controller.sessionRecordingOnStop
        let delayOverride = controller.sessionRecordingDelay
        let hideHUD = controller.sessionHideRecordingHUD ?? UserDefaults.standard.bool(forKey: "hideRecordingHUD")

        // Detach webcam preview before dismissing overlays so we can reuse the live session
        let existingWebcam = controller.detachWebcamPreview()

        // Use the same focus return path as normal screenshot confirm:
        // dismissOverlays with refocus → returnFocusIfNeeded → NSApp.hide(nil).
        // This reliably transfers focus AND mouse event routing.
        // Then create recording UI on the next run loop — all non-activating
        // panels, so they appear without stealing focus back.
        dismissOverlays()  // refocusPreviousApp: true (default) — handles focus
        previousApp = nil

        let delay = delayOverride ?? UserDefaults.standard.integer(forKey: "captureDelaySeconds")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if delay > 0 {
                existingWebcam?.stopPreview()
                existingWebcam?.close()
                self.startRecordingCountdown(seconds: delay, rect: rect, screen: screen,
                                        fpsOverride: fpsOverride,
                                        onStopOverride: onStopOverride)
            } else {
                self.beginRecording(rect: rect, screen: screen,
                               fpsOverride: fpsOverride,
                               onStopOverride: onStopOverride,
                               existingWebcam: existingWebcam,
                               hideHUD: hideHUD)
            }
        }
    }

    func startRecordingCountdown(seconds: Int, rect: NSRect, screen: NSScreen,
                                          fpsOverride: Int?,
                                          onStopOverride: String?) {
        let size = NSSize(width: 140, height: 140)
        let origin = NSPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let countdownView = CountdownView(frame: NSRect(origin: .zero, size: size))
        countdownView.remaining = seconds
        window.contentView = countdownView
        window.makeKeyAndOrderFront(nil)
        delayCountdownWindow = window

        // Show selection border during countdown so user sees what area will be recorded
        let border = SelectionBorderOverlay(screen: screen)
        border.setSelectionRect(rect)
        border.orderFrontRegardless()
        selectionBorderOverlay = border

        // Escape to cancel
        delayEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelRecordingCountdown()
                return nil
            }
            return event
        }

        var remaining = seconds
        delayTimer?.invalidate()
        delayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                self?.delayTimer = nil
                self?.delayCountdownWindow?.orderOut(nil)
                self?.delayCountdownWindow = nil
                self?.removeDelayEscMonitors()
                self?.beginRecording(rect: rect, screen: screen,
                                     fpsOverride: fpsOverride,
                                     onStopOverride: onStopOverride)
            } else {
                countdownView.remaining = remaining
                countdownView.needsDisplay = true
            }
        }
    }

    func cancelRecordingCountdown() {
        delayTimer?.invalidate()
        delayTimer = nil
        delayCountdownWindow?.orderOut(nil)
        delayCountdownWindow = nil
        selectionBorderOverlay?.close()
        selectionBorderOverlay = nil
        removeDelayEscMonitors()
    }

    func beginRecording(rect: NSRect, screen: NSScreen,
                                 fpsOverride: Int?,
                                 onStopOverride: String?,
                                 existingWebcam: WebcamOverlay? = nil,
                                 hideHUD: Bool = false) {
        let engine = RecordingEngine()
        engine.onProgress = { [weak self] seconds in
            self?.updateRecordingHUD(seconds: seconds)
        }
        // Capture audio settings before recording starts (they may change during)
        let hadSystemAudio = UserDefaults.standard.bool(forKey: "recordSystemAudio")
        let hadMicAudio = UserDefaults.standard.bool(forKey: "recordMicAudio")

        engine.onCompletion = { [weak self] url, error in
            guard let self = self else { return }
            self.stopRecordingUI()

            if let url = url {
                let deliverRecording: (URL) -> Void = { [weak self] finalURL in
                    guard let self = self else { return }
                    let onStop = onStopOverride ?? UserDefaults.standard.string(forKey: "recordingOnStop") ?? "editor"
                    switch onStop {
                    case "finder":
                        // Move the recording out of our sandbox tmp to a
                        // user-visible directory before revealing. Otherwise
                        // Finder would open inside the sandbox container
                        // (confusing to navigate, and our launch sweep can't
                        // safely clean tmp Recordings since they look
                        // user-managed).
                        self.revealRecordingInFinder(tmpURL: finalURL)
                    case "clipboard":
                        self.copyRecordingToClipboard(url: finalURL)
                    default:
                        VideoEditorWindowController.open(url: finalURL)
                    }
                }

                // Offer audio merge when both mic + system audio were recorded
                if hadSystemAudio && hadMicAudio {
                    let merger = AudioMergeController()
                    self.audioMergeController = merger
                    merger.show(url: url) { [weak self] finalURL in
                        self?.audioMergeController = nil
                        deliverRecording(finalURL)
                    }
                } else {
                    deliverRecording(url)
                }
            } else if let error = error {
                #if DEBUG
                print("Recording failed: \(error.localizedDescription)")
                #endif
            }
        }
        recordingEngine = engine

        // Always show selection border so user knows what area is being recorded
        // (may already exist from countdown — recreate to be safe)
        selectionBorderOverlay?.close()
        let border = SelectionBorderOverlay(screen: screen)
        border.setSelectionRect(rect)
        border.orderFrontRegardless()
        selectionBorderOverlay = border

        if !hideHUD {
            // Show the floating timer HUD
            let hud = RecordingHUDPanel()
            hud.update(elapsedSeconds: 0)
            hud.positionOnScreen(relativeTo: rect, screen: screen)
            hud.onStopRecording = { [weak self] in
                self?.stopRecording()
            }
            hud.onPauseRecording = { [weak self] in
                self?.recordingEngine?.pauseRecording()
            }
            hud.onResumeRecording = { [weak self] in
                self?.recordingEngine?.resumeRecording()
            }
            hud.orderFrontRegardless()
            recordingHUDPanel = hud

            engine.onPauseChanged = { [weak self] paused in
                self?.recordingHUDPanel?.setPaused(paused)
            }
        }

        // Start mouse highlight overlay if enabled (requires Input Monitoring permission)
        if UserDefaults.standard.bool(forKey: "recordMouseHighlight") && CGPreflightListenEventAccess() {
            let overlay = MouseHighlightOverlay(screen: screen)
            overlay.orderFrontRegardless()
            overlay.startMonitoring()
            mouseHighlightOverlay = overlay
        }

        // Start keystroke overlay if enabled
        if UserDefaults.standard.bool(forKey: "recordKeystroke") && KeystrokeOverlay.hasInputMonitoringPermission {
            let overlay = KeystrokeOverlay(screen: screen)
            overlay.setRecordingRect(rect)
            overlay.orderFrontRegardless()
            overlay.startMonitoring()
            keystrokeOverlay = overlay
        }

        // Start webcam overlay if enabled — reuse existing session to avoid camera restart flash
        if UserDefaults.standard.bool(forKey: "recordWebcam") &&
           AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            if let existing = existingWebcam {
                // Reuse the live preview — just lock it in place
                existing.setDraggable(false)
                existing.orderFrontRegardless()
                webcamOverlay = existing
            } else {
                let overlay = WebcamOverlay(screen: screen)
                let position = WebcamPosition(rawValue: UserDefaults.standard.string(forKey: "webcamPosition") ?? "bottomRight") ?? .bottomRight
                let wcSize = WebcamSize(rawValue: UserDefaults.standard.string(forKey: "webcamSize") ?? "medium") ?? .medium
                let shape = WebcamShape(rawValue: UserDefaults.standard.string(forKey: "webcamShape") ?? "circle") ?? .circle
                overlay.configure(position: position, size: wcSize, shape: shape, recordingRect: rect)
                overlay.startPreview(deviceUID: UserDefaults.standard.string(forKey: "selectedCameraDeviceUID"))
                overlay.setDraggable(false)
                overlay.orderFrontRegardless()
                webcamOverlay = overlay
            }
        } else {
            // Webcam not enabled — clean up any detached preview
            existingWebcam?.stopPreview()
            existingWebcam?.close()
        }

        // Turn menu bar icon into a stop button (ensure it's visible even if user hid it)
        enterRecordingMenuBarMode()

        // Collect window IDs of UI chrome to exclude from the recording
        // (selection border + HUD). Webcam, mouse highlight, and keystroke
        // overlays are intentionally captured.
        var excludeIDs: [CGWindowID] = []
        if let w = selectionBorderOverlay { excludeIDs.append(CGWindowID(w.windowNumber)) }
        if let w = recordingHUDPanel { excludeIDs.append(CGWindowID(w.windowNumber)) }

        // Start recording
        engine.startRecording(rect: rect, screen: screen, fpsOverride: fpsOverride, excludeWindowNumbers: excludeIDs)
    }

    func overlayDidRequestStopRecording(_ controller: OverlayWindowController) {
        if let engine = recordingEngine {
            engine.stopRecording()
        } else {
            // Recording mode was entered but capture never started — just dismiss
            dismissOverlays()
        }
    }

    // MARK: - Recording UI

    @objc func stopRecording() {
        guard let engine = recordingEngine else { return }
        engine.stopRecording()
    }

    func updateRecordingHUD(seconds: Int) {
        recordingHUDPanel?.update(elapsedSeconds: seconds)
        if let screen = recordingScreen, !(recordingHUDPanel?.userHasDragged ?? false) {
            recordingHUDPanel?.positionOnScreen(relativeTo: recordingScreenRect, screen: screen)
        }
    }

    func enterRecordingMenuBarMode() {
        menuBarIconWasHidden = UserDefaults.standard.bool(forKey: "hideMenuBarIcon")
        if menuBarIconWasHidden {
            setMenuBarIconVisible(true)
        }
        // Replace menu with a single stop action, change icon to stop symbol
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop Recording")
            button.image?.isTemplate = true
            button.image?.size = NSSize(width: 22, height: 22)
        }
        statusItem.menu = nil
        statusItem.button?.target = self
        statusItem.button?.action = #selector(stopRecording)
    }

    func exitRecordingMenuBarMode() {
        applyNormalStatusBarIcon()
        rebuildStatusBarMenu()

        // Hide icon again if user had it hidden before recording
        if menuBarIconWasHidden {
            setMenuBarIconVisible(false)
            menuBarIconWasHidden = false
        }
    }

    /// Move a recording out of our sandbox tmp to a user-visible directory
    /// and reveal it in Finder. Used by the `recordingOnStop = "finder"`
    /// flow so the user doesn't end up staring at a deep sandbox path.
    ///
    /// Resolution order:
    ///   1. Recording save directory (if configured + bookmark still valid)
    ///   2. Same as screenshots (if configured + bookmark still valid)
    ///   3. Save panel — user picks a location explicitly
    ///
    /// On a collision at the destination, we append " (N)" to the filename
    /// so nothing gets silently overwritten.
    func revealRecordingInFinder(tmpURL: URL) {
        // Try the configured recording dir first.
        if let recDir = SaveDirectoryAccess.resolveRecordingDirectoryIfAccessible() {
            defer { SaveDirectoryAccess.stopAccessing(url: recDir) }
            if let moved = moveRecording(from: tmpURL, intoDirectory: recDir) {
                NSWorkspace.shared.activateFileViewerSelecting([moved])
                return
            }
        }
        // Fall back to the general screenshot save directory if THAT has a
        // valid bookmark. (SaveDirectoryAccess.resolve() always returns
        // something, but without a bookmark we have no sandbox write access.)
        if UserDefaults.standard.data(forKey: "saveDirectoryBookmark") != nil {
            let screenshotDir = SaveDirectoryAccess.resolve()
            defer { SaveDirectoryAccess.stopAccessing(url: screenshotDir) }
            if let moved = moveRecording(from: tmpURL, intoDirectory: screenshotDir) {
                NSWorkspace.shared.activateFileViewerSelecting([moved])
                return
            }
        }
        // No usable saved location — prompt the user via NSSavePanel.
        promptToSaveRecording(tmpURL: tmpURL)
    }

    /// Move `src` into `dir`, renaming on collision, returning the new URL.
    /// Returns nil if the move fails (bad permissions, disk full, etc.).
    func moveRecording(from src: URL, intoDirectory dir: URL) -> URL? {
        let fm = FileManager.default
        let name = src.lastPathComponent
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension

        var dest = dir.appendingPathComponent(name)
        var counter = 2
        while fm.fileExists(atPath: dest.path) {
            let newName = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            dest = dir.appendingPathComponent(newName)
            counter += 1
            if counter > 1000 { return nil }  // sanity cap
        }
        do {
            try fm.moveItem(at: src, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    /// Last-resort: the user has no configured save dir, so ask them where
    /// to put the recording. On cancel we leave the tmp file in place —
    /// the launch sweep won't touch it (Recording prefix is preserved)
    /// but the user can still deal with it manually if they want.
    func promptToSaveRecording(tmpURL: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = tmpURL.lastPathComponent
        panel.title = L("Save Recording")
        panel.prompt = L("Save")
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.moveItem(at: tmpURL, to: dest)) != nil {
                NSWorkspace.shared.activateFileViewerSelecting([dest])
            }
        }
    }

    func copyRecordingToClipboard(url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Move the recording to a fixed clipboard path so we only ever have
        // one-per-extension on disk. The user's recording tmp at `url` would
        // otherwise linger forever (the pasteboard keeps the file URL
        // reference so we can't delete it; but we can overwrite the same
        // fixed path on the next clipboard copy).
        let ext = url.pathExtension.lowercased()
        let fixedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lumashot-clipboard-recording.\(ext)")
        try? FileManager.default.removeItem(at: fixedURL)
        let pasteURL: URL
        if (try? FileManager.default.moveItem(at: url, to: fixedURL)) != nil {
            pasteURL = fixedURL
        } else {
            // Move failed (cross-volume? permissions?) — fall back to the
            // original path. Launch sweep will still clean it up later.
            pasteURL = url
        }

        if ext == "gif", let data = try? Data(contentsOf: pasteURL) {
            // Write raw GIF data so apps can render the animation inline
            let item = NSPasteboardItem()
            item.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
            // Also add file URL for Finder compatibility
            item.setString(pasteURL.absoluteString, forType: .fileURL)
            pasteboard.writeObjects([item])
        } else {
            // MP4: write file URL (apps like Slack/Discord accept file drops)
            pasteboard.writeObjects([pasteURL as NSURL])
        }
        playCopySound()
    }

    func stopRecordingUI() {
        recordingHUDPanel?.close()
        recordingHUDPanel = nil
        selectionBorderOverlay?.close()
        selectionBorderOverlay = nil
        mouseHighlightOverlay?.stopMonitoring()
        mouseHighlightOverlay?.close()
        mouseHighlightOverlay = nil
        keystrokeOverlay?.stopMonitoring()
        keystrokeOverlay?.close()
        keystrokeOverlay = nil
        webcamOverlay?.stopPreview()
        webcamOverlay?.close()
        webcamOverlay = nil
        recordingEngine = nil
        recordingOverlayController = nil
        recordingScreenRect = .zero
        recordingScreen = nil
        exitRecordingMenuBarMode()
    }

    func overlayDidRequestScrollCapture(_ controller: OverlayWindowController, rect: NSRect, screen: NSScreen) {
        if !AXIsProcessTrusted() {
            dismissOverlays()
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
            let alert = NSAlert()
            alert.messageText = L("Accessibility Access Required")
            alert.informativeText = L("Lumashot needs Accessibility permission for scroll capture. Please grant access in System Settings, then try again.")
            alert.alertStyle = .warning
            alert.addButton(withTitle: L("Open Settings"))
            alert.addButton(withTitle: L("Cancel"))
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }

        scrollCaptureOverlayController = controller

        let scc = ScrollCaptureController(captureRect: rect, screen: screen)
        scc.excludedWindowIDs = overlayControllers.map { $0.windowNumber }
        scrollCaptureController = scc

        // Read max height for the overlay HUD progress bar
        let maxH = UserDefaults.standard.object(forKey: "scrollMaxHeight") as? Int ?? 30000

        // Tell the triggering overlay to enter scroll capture mode
        controller.setScrollCaptureState(isActive: true, maxHeight: maxH)

        // Create live preview panel if there's space beside the capture region
        let overlayLevel = 257  // matches overlay window level
        if let previewPanel = ScrollCapturePreviewPanel(captureRect: rect, screen: screen, overlayLevel: overlayLevel) {
            previewPanel.orderFront(nil)
            scrollCapturePreviewPanel = previewPanel
        }

        scc.onStripAdded = { [weak self, weak controller] count in
            guard let self = self, let scc = self.scrollCaptureController else { return }
            controller?.updateScrollCaptureProgress(
                stripCount: count, pixelSize: scc.stitchedPixelSize,
                autoScrolling: scc.autoScrollActive)
        }
        scc.onPreviewUpdated = { [weak self] image in
            self?.scrollCapturePreviewPanel?.updatePreview(image: image)
        }
        scc.onAutoScrollStarted = { [weak self, weak controller] in
            guard let self = self, let scc = self.scrollCaptureController else { return }
            controller?.updateScrollCaptureProgress(
                stripCount: scc.stripCount, pixelSize: scc.stitchedPixelSize,
                autoScrolling: true)
        }
        scc.onSessionDone = { [weak self] finalImage in
            self?.handleScrollCaptureCompleted(finalImage: finalImage)
        }

        Task { await scc.startSession() }
    }

    func overlayDidRequestStopScrollCapture(_ controller: OverlayWindowController) {
        scrollCaptureController?.stopSession()
        // onSessionDone fires asynchronously via handleScrollCaptureCompleted
    }

    func overlayDidRequestAccessibilityPermission(_ controller: OverlayWindowController) {
        dismissOverlays()
        // Only trigger the system dialog if not already granted — avoids
        // repeatedly forcing the auth prompt when Accessibility is already authorized.
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }
        let alert = NSAlert()
        alert.messageText = L("Accessibility Access Required")
        alert.informativeText = L("Lumashot needs Accessibility permission to show keystrokes during recording. Please grant access in System Settings, then try again.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Open Settings"))
        alert.addButton(withTitle: L("Cancel"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func overlayDidRequestInputMonitoringPermission(_ controller: OverlayWindowController) {
        dismissOverlays()
        KeystrokeOverlay.requestInputMonitoringPermission()
        let alert = NSAlert()
        alert.messageText = L("Input Monitoring Required")
        alert.informativeText = L("Lumashot needs Input Monitoring permission to show keystrokes during recording. Please grant access in System Settings, then try again.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Open Settings"))
        alert.addButton(withTitle: L("Cancel"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func overlayDidRequestToggleAutoScroll(_ controller: OverlayWindowController) {
        guard let scc = scrollCaptureController else { return }

        // If turning on, check Accessibility permission first
        if !scc.autoScrollActive {
            if !AXIsProcessTrusted() {
                // Cancel session without delivering a result, then dismiss overlays
                scc.cancelSession()
                scrollCaptureController = nil
                scrollCapturePreviewPanel?.close()
                scrollCapturePreviewPanel = nil
                scrollCaptureOverlayController?.setScrollCaptureState(isActive: false)
                scrollCaptureOverlayController = nil
                dismissOverlays()

                let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                AXIsProcessTrustedWithOptions(opts)
                let alert = NSAlert()
                alert.messageText = L("Accessibility Access Required")
                alert.informativeText = L("Lumashot needs Accessibility permission to auto-scroll other apps. Please grant access in System Settings, then try again.")
                alert.alertStyle = .warning
                alert.addButton(withTitle: L("Open Settings"))
                alert.addButton(withTitle: L("Cancel"))
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                return
            }
        }

        scc.toggleAutoScroll()
        let autoScrolling = scc.isActive && scc.autoScrollActive
        controller.updateScrollCaptureProgress(
            stripCount: scc.stripCount, pixelSize: scc.stitchedPixelSize,
            autoScrolling: autoScrolling)
    }

    func overlayDidBeginSelection(_ controller: OverlayWindowController) {
        for other in overlayControllers where other !== controller {
            other.clearSelection()
            other.setRemoteSelection(.zero)
        }
    }

    func overlayDidChangeSelection(_ controller: OverlayWindowController, globalRect: NSRect) {
        for other in overlayControllers where other !== controller {
            let otherOrigin = other.screen.frame.origin
            let localRect = NSRect(x: globalRect.origin.x - otherOrigin.x,
                                   y: globalRect.origin.y - otherOrigin.y,
                                   width: globalRect.width, height: globalRect.height)
            let clipped = localRect.intersection(NSRect(origin: .zero, size: other.screen.frame.size))
            other.setRemoteSelection(clipped.isEmpty ? .zero : clipped, fullRect: localRect)
        }
    }

    func overlayDidRemoteResizeSelection(_ controller: OverlayWindowController, globalRect: NSRect) {
        // Update the primary screen's actual selection
        guard let primary = overlayControllers.first(where: { $0 !== controller && $0.selectionRect.width >= 1 }) else { return }
        let primaryOrigin = primary.screen.frame.origin
        let primaryLocal = NSRect(x: globalRect.origin.x - primaryOrigin.x,
                                  y: globalRect.origin.y - primaryOrigin.y,
                                  width: globalRect.width, height: globalRect.height)
        primary.applySelection(primaryLocal)

        // Update other secondary screens (not the caller — it manages its own remoteSelectionRect during drag)
        for other in overlayControllers where other !== controller && other !== primary {
            let otherOrigin = other.screen.frame.origin
            let localRect = NSRect(x: globalRect.origin.x - otherOrigin.x,
                                   y: globalRect.origin.y - otherOrigin.y,
                                   width: globalRect.width, height: globalRect.height)
            let clipped = localRect.intersection(NSRect(origin: .zero, size: other.screen.frame.size))
            other.setRemoteSelection(clipped.isEmpty ? .zero : clipped, fullRect: localRect)
        }
    }

    func overlayDidFinishRemoteResize(_ controller: OverlayWindowController, globalRect: NSRect) {
        // Final sync after remote resize — update primary, re-sync ALL secondaries, transfer focus
        guard let primary = overlayControllers.first(where: { $0 !== controller && $0.selectionRect.width >= 1 }) else { return }
        let primaryOrigin = primary.screen.frame.origin
        let primaryLocal = NSRect(x: globalRect.origin.x - primaryOrigin.x,
                                  y: globalRect.origin.y - primaryOrigin.y,
                                  width: globalRect.width, height: globalRect.height)
        primary.applySelection(primaryLocal)
        primary.makeKey()

        // Re-sync ALL secondary screens (including the caller) from the primary's authoritative rect
        let primarySel = primary.selectionRect
        let primaryGlobal = NSRect(x: primarySel.origin.x + primaryOrigin.x,
                                   y: primarySel.origin.y + primaryOrigin.y,
                                   width: primarySel.width, height: primarySel.height)
        for other in overlayControllers where other !== primary {
            let otherOrigin = other.screen.frame.origin
            let localRect = NSRect(x: primaryGlobal.origin.x - otherOrigin.x,
                                   y: primaryGlobal.origin.y - otherOrigin.y,
                                   width: primaryGlobal.width, height: primaryGlobal.height)
            let clipped = localRect.intersection(NSRect(origin: .zero, size: other.screen.frame.size))
            other.setRemoteSelection(clipped.isEmpty ? .zero : clipped, fullRect: localRect)
        }
    }

    func overlayCrossScreenImage(_ controller: OverlayWindowController) -> NSImage? {
        let others = overlayControllers.filter { $0 !== controller && $0.remoteSelectionRect.width >= 1 && $0.remoteSelectionRect.height >= 1 }
        guard !others.isEmpty else { return nil }
        return stitchCrossScreenCapture(primary: controller, others: others)
    }

    func overlayDidChangeWindowSnapState(_ controller: OverlayWindowController) {
        // Notify all other overlays to redraw (for multi-monitor setups)
        // When window snap state changes via Tab key, all overlays need to update
        // their helper text to show the new ON/OFF state
        for other in overlayControllers where other !== controller {
            other.triggerRedraw()
        }
    }

    func handleScrollCaptureCompleted(finalImage: NSImage?) {
        scrollCapturePreviewPanel?.close()
        scrollCapturePreviewPanel = nil
        scrollCaptureOverlayController?.setScrollCaptureState(isActive: false)
        scrollCaptureOverlayController = nil
        scrollCaptureController = nil

        dismissOverlays()

        guard let image = finalImage else { return }

        ScreenshotHistory.shared.add(image: image)
        let entryID = ScreenshotHistory.shared.entries.first?.id
        // quickCaptureMode: 0=save, 1=copy, 2=both, 3=do nothing (thumbnail only)
        let mode = UserDefaults.standard.object(forKey: "quickCaptureMode") as? Int ?? 1
        if mode == 1 || mode == 2 {
            ImageEncoder.copyToClipboard(image)
        }
        if mode == 0 || mode == 2 {
            saveImageToFile(image)
        }
        playCopySound()
        showFloatingThumbnail(image: image)

        if UserDefaults.standard.bool(forKey: "quickCaptureOpenEditor") {
            DetachedEditorWindowController.open(image: image, historyEntryID: entryID)
        }
    }

}

// MARK: - PinWindowControllerDelegate

