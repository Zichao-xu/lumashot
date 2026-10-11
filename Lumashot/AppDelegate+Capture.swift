import Cocoa
import Carbon
import UniformTypeIdentifiers
import AVFoundation
import WebP

extension AppDelegate {
    // MARK: - Capture

    @objc func captureScreen() {
        startCapture(fromMenu: true)
    }

    @objc func captureFullScreen() {
        pendingFullScreen = true
        startCapture(fromMenu: true)
    }

    @objc func showHistoryOverlay() {
        if let existing = historyOverlayController {
            existing.dismiss()
            historyOverlayController = nil
            return
        }
        let controller = HistoryOverlayController()
        controller.onDismiss = { [weak self] in
            self?.historyOverlayController = nil
        }
        controller.show()
        historyOverlayController = controller
    }

    @objc func captureOCR() {
        pendingOCRMode = true
        startCapture(fromMenu: true)
    }

    @objc func quickCapture() {
        pendingQuickCaptureMode = true
        startCapture(fromMenu: true)
    }

    @objc func scrollCapture() {
        pendingScrollCaptureMode = true
        startCapture(fromMenu: true)
    }

    /// Open the capture overlay with the last selection area pre-applied.
    /// If no previous selection exists, falls back to a normal capture.
    @objc func captureLastArea() {
        pendingRestoreLastArea = true
        startCapture(fromMenu: true)
    }

    @objc func recordArea() {
        pendingRecordMode = true
        startCapture(fromMenu: true)
    }

    @objc func recordFullScreen() {
        pendingFullScreenRecord = true
        if UserDefaults.standard.integer(forKey: "captureDelaySeconds") > 0 {
            pendingFullScreenRecordAutoStart = true
        }
        startCapture(fromMenu: true)
    }

    @objc func setDelaySeconds(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: "captureDelaySeconds")
        // Update checkmarks
        if let menu = sender.menu {
            for item in menu.items {
                item.state = item.tag == sender.tag ? .on : .off
            }
        }
    }

    func startCapture(fromMenu: Bool = false) {
        guard !isCapturing else { return }
        // Don't allow captures while recording
        guard recordingEngine == nil else { return }
        isCapturing = true

        // Kick off SCShareableContent enumeration early — the cache will be ready
        // by the time performCapture() needs it (covers hotkey path where menu wasn't opened)
        ScreenCaptureManager.prewarm()

        // When "remember last tool" is off, clear persisted effects/beautify
        // so new OverlayView instances start clean
        let rememberTool = UserDefaults.standard.object(forKey: "rememberLastTool") as? Bool ?? true
        if !rememberTool {
            UserDefaults.standard.removeObject(forKey: "effectsPreset")
            UserDefaults.standard.removeObject(forKey: "effectsBrightness")
            UserDefaults.standard.removeObject(forKey: "effectsContrast")
            UserDefaults.standard.removeObject(forKey: "effectsSaturation")
            UserDefaults.standard.removeObject(forKey: "effectsSharpness")
            UserDefaults.standard.set(false, forKey: "beautifyEnabled")
        }

        // Grab focused app and window title before overlay steals focus
        previousApp = NSWorkspace.shared.frontmostApplication
        capturedWindowTitle = Self.focusedWindowTitle()

        // Clean up stale overlays without consuming previousApp — we just set it.
        dismissOverlays(refocusPreviousApp: false)

        // Hide any non-overlay titled windows (editors, preferences, update
        // dialogs). Without this, `NSApp.activate` inside performCapture drags
        // every visible app-owned window in front of the user's frontmost app
        // and those windows end up in the screenshot. Restored in
        // dismissOverlays once capture is over.
        stashBackgroundWindows()

        // Hide floating thumbnails so they don't visually flash on the overlay.
        // They're also excluded via ScreenCaptureKit's excludingWindows filter
        // in performCapture() so they never appear in the captured image.
        for tc in thumbnailControllers { tc.hideWindow() }

        let delay = UserDefaults.standard.integer(forKey: "captureDelaySeconds")
        if delay > 0 {
            showPreCaptureCountdown(seconds: delay)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.performCapture()
            }
        }
    }

    func showPreCaptureCountdown(seconds: Int) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let size = NSSize(width: 140, height: 140)
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2
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
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let countdownView = CountdownView(frame: NSRect(origin: .zero, size: size))
        countdownView.remaining = seconds
        window.contentView = countdownView
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        delayCountdownWindow = window

        // Listen for Escape to cancel countdown — use both local and global monitors
        // Local catches keys when Lumashot is active; global catches when another app has focus
        delayEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelPreCaptureCountdown()
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
                self?.performCapture()
            } else {
                countdownView.remaining = remaining
                countdownView.needsDisplay = true
            }
        }
    }

    func removeDelayEscMonitors() {
        if let m = delayEscMonitor { NSEvent.removeMonitor(m); delayEscMonitor = nil }
    }

    func cancelPreCaptureCountdown() {
        delayTimer?.invalidate()
        delayTimer = nil
        delayCountdownWindow?.orderOut(nil)
        delayCountdownWindow = nil
        removeDelayEscMonitors()
        isCapturing = false
        pendingRecordMode = false
        pendingFullScreen = false
        pendingFullScreenRecord = false
        pendingFullScreenRecordAutoStart = false
        pendingOCRMode = false
        pendingQuickCaptureMode = false
        pendingScrollCaptureMode = false
    }

    func performCapture() {
        // Show transparent overlays instantly — zero delay.
        // The user sees the live desktop through the overlay and can start
        // selecting immediately. The screenshot captures in the background
        // and is set on the overlay when ready.
        let screens = NSScreen.screens
        let mouseScreen = screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        for screen in screens {
            let controller = OverlayWindowController(screen: screen)
            controller.overlayDelegate = self
            controller.capturedWindowTitle = capturedWindowTitle
            if pendingRecordMode { controller.setAutoRecordMode() }
            if pendingOCRMode { controller.setAutoOCRMode() }
            if pendingQuickCaptureMode { controller.setAutoQuickSaveMode() }
            if pendingScrollCaptureMode { controller.setAutoScrollCaptureMode() }
            controller.showOverlay()
            let isMouseScreen = (screen == mouseScreen) || (mouseScreen == nil && screen == NSScreen.main)
            if (pendingFullScreen || pendingFullScreenRecord) && isMouseScreen {
                controller.applyFullScreenSelection()
            }
            if pendingFullScreenRecord && isMouseScreen {
                controller.enterRecordingMode()
                if pendingFullScreenRecordAutoStart {
                    controller.autoStartRecording()
                }
            }
            overlayControllers.append(controller)
        }

        CATransaction.flush()
        NSApp.activate(ignoringOtherApps: true)

        pendingRecordMode = false
        pendingFullScreenRecordAutoStart = false
        pendingOCRMode = false
        pendingQuickCaptureMode = false
        pendingScrollCaptureMode = false
        pendingFullScreen = false
        pendingFullScreenRecord = false

        // Capture screenshots in background — exclude overlay windows + thumbnails.
        let excludeIDs = thumbnailControllers.compactMap { $0.windowNumber }
            + overlayControllers.compactMap { $0.windowNumber }
        ScreenCaptureManager.captureAllScreens(excludingWindowNumbers: excludeIDs) { [weak self] captures in
            guard let self = self else { return }

            if captures.isEmpty {
                self.dismissOverlays(refocusPreviousApp: true)
                self.showOnboarding()
                return
            }

            for capture in captures {
                if let controller = self.overlayControllers.first(where: { $0.screen == capture.screen }) {
                    controller.setScreenshot(capture.image)
                }
            }

            // Apply last selection area if "Capture Last Area" was triggered
            if self.pendingRestoreLastArea {
                self.pendingRestoreLastArea = false
                self.restoreLastSelection(controllers: self.overlayControllers)
            }
        }
    }

    /// Apply the stored last selection rect to the matching overlay controller.
    func restoreLastSelection(controllers: [OverlayWindowController]) {
        guard let rectStr = UserDefaults.standard.string(forKey: "lastSelectionRect"),
              let screenStr = UserDefaults.standard.string(forKey: "lastSelectionScreenFrame") else { return }
        let savedRect = NSRectFromString(rectStr)
        let savedScreenFrame = NSRectFromString(screenStr)
        guard savedRect.width > 1, savedRect.height > 1 else { return }
        for controller in controllers where controller.screen.frame == savedScreenFrame {
            controller.applySelection(savedRect)
            break
        }
    }

    /// Returns the title of the frontmost window via CGWindowList (requires Screen Recording permission).
    static func focusedWindowTitle() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid,
                  let name = info[kCGWindowName as String] as? String, !name.isEmpty else { continue }
            return name
        }
        return nil
    }


    @objc func handleShowAndOpenPrefs() {
        if UserDefaults.standard.bool(forKey: "hideMenuBarIcon") {
            UserDefaults.standard.set(false, forKey: "hideMenuBarIcon")
            setMenuBarIconVisible(true)
        }
        openSettings()
    }

    @objc func spaceDidChange() {
        guard !overlayControllers.isEmpty else { return }
        dismissOverlays()
    }

    func dismissOverlays(refocusPreviousApp: Bool = true) {
        autoreleasepool {
            for controller in overlayControllers {
                controller.dismiss()
            }
            overlayControllers.removeAll()
        }
        isCapturing = false
        // Restore hidden thumbnails
        for tc in thumbnailControllers { tc.showWindow() }
        if refocusPreviousApp {
            // Restore AFTER another app takes focus so the stashed windows
            // come back behind it instead of on top. See
            // `scheduleBackgroundWindowRestore` for the timing logic.
            scheduleBackgroundWindowRestore()
            returnFocusIfNeeded()
        } else {
            // No focus switch coming — just bring them back immediately.
            restoreBackgroundWindowsNow()
        }
    }

    /// Hide non-overlay titled Lumashot windows so they can't be dragged in
    /// front of the user's frontmost app when the overlay activates.
    ///
    /// We only stash when another app was frontmost — that means the user is
    /// trying to screenshot something *other than* Lumashot, and any Lumashot
    /// windows still on screen are unintended background clutter. When
    /// Lumashot itself is frontmost the user presumably wants to capture one
    /// of its own windows, so we leave everything alone.
    func stashBackgroundWindows() {
        stashedBackgroundWindows.removeAll()
        let ourBundleID = Bundle.main.bundleIdentifier
        let lumashotWasFrontmost = previousApp?.bundleIdentifier == ourBundleID
        guard !lumashotWasFrontmost else { return }
        for window in NSApp.windows where window.isVisible && window.styleMask.contains(.titled) {
            stashedBackgroundWindows.append(window)
            window.orderOut(nil)
        }
    }

    /// Wait until another app becomes frontmost, then restore the stashed
    /// windows. If we restore before the user's previous app regains focus,
    /// the windows come back on top and clobber whatever was frontmost.
    ///
    /// Uses NSWorkspace's activation notification as the trigger, with a
    /// short timer fallback in case activation never completes (e.g. the
    /// previous app terminated during capture).
    func scheduleBackgroundWindowRestore() {
        guard !stashedBackgroundWindows.isEmpty else { return }
        let ws = NSWorkspace.shared.notificationCenter
        var token: NSObjectProtocol?
        token = ws.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier != Bundle.main.bundleIdentifier {
                if let token = token { ws.removeObserver(token) }
                self.restoreBackgroundWindowsNow()
            }
        }
        // Fallback — if no other app ever activates in the next 1s just
        // restore anyway. Otherwise the windows would stay invisible.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if !self.stashedBackgroundWindows.isEmpty {
                if let token = token { ws.removeObserver(token) }
                self.restoreBackgroundWindowsNow()
            }
        }
    }

    /// Reverse of `stashBackgroundWindows`. Uses `orderBack` instead of
    /// `orderFront` so the restored windows land behind every other
    /// app's windows rather than on top of them. (`orderFront` still
    /// raises windows in the global z-stack even when the owning app
    /// isn't frontmost, which is what was causing the editor to pop
    /// visible right after a screenshot.)
    func restoreBackgroundWindowsNow() {
        for window in stashedBackgroundWindows {
            window.orderBack(nil)
        }
        stashedBackgroundWindows.removeAll()
    }

    func showFloatingThumbnail(
        image: NSImage,
        annotationData: CaptureAnnotationData? = nil,
        historyEntryID: String? = nil,
        representedFileURL: URL? = nil
    ) {
        let enabled = UserDefaults.standard.object(forKey: "showFloatingThumbnail") as? Bool ?? true
        guard enabled else { return }

        let stacking = UserDefaults.standard.object(forKey: "thumbnailStacking") as? Bool ?? true
        if !stacking {
            // Replace mode: dismiss all existing thumbnails
            thumbnailControllers.forEach { $0.dismiss() }
            thumbnailControllers.removeAll()
        }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let padding: CGFloat = 16
        let gap: CGFloat = 8

        // Compute Y: stack above any existing thumbnails
        var yOrigin = screenFrame.minY + padding
        if let topController = thumbnailControllers.last {
            let topFrame = topController.windowFrame
            yOrigin = topFrame.maxY + gap
        }

        let controller = FloatingThumbnailController(image: image, representedFileURL: representedFileURL)
        controller.historyEntryID = historyEntryID
        controller.onDismiss = { [weak self] in
            self?.thumbnailControllers.removeAll { $0 === controller }
            self?.reflowThumbnails()
        }
        controller.onCopy = { [weak self] in
            guard let self = self else { return }
            if let representedFileURL {
                self.copyFileURLToClipboard(representedFileURL)
            } else {
                ImageEncoder.copyToClipboard(image)
            }
            self.playCopySound()
        }
        controller.onSave = { [weak self] in
            guard let self = self else { return }
            if let representedFileURL {
                self.saveFileURLToFile(representedFileURL)
            } else {
                self.saveImageToFile(image)
            }
        }
        controller.onPin = { [weak self] in
            guard let self = self else { return }
            ScreenshotHistory.shared.add(image: image)
            self.showPin(image: image)
            self.playCopySound()
        }
        controller.onEdit = {
            if let data = annotationData {
                DetachedEditorWindowController.open(image: data.rawImage, annotations: data.annotations, historyEntryID: historyEntryID)
            } else {
                // Image already has beautify/effects baked in — disable to avoid double-applying
                DetachedEditorWindowController.open(image: image, historyEntryID: historyEntryID, disableBeautify: true)
            }
        }
        controller.onUpload = { [weak self] in
            guard let self = self else { return }
            ScreenshotHistory.shared.add(image: image)
            self.showUploadProgress(image: image)
        }
        controller.onDelete = {
            if let id = historyEntryID {
                ScreenshotHistory.shared.removeEntry(id: id)
            }
        }
        controller.onCloseAll = { [weak self] in
            guard let self = self else { return }
            let all = self.thumbnailControllers
            self.thumbnailControllers.removeAll()
            for c in all { c.dismiss() }
        }
        controller.onSaveAll = { [weak self] in
            self?.saveAllThumbnailsToFolder()
        }
        thumbnailControllers.append(controller)
        controller.show(atY: yOrigin)
    }

    func saveAllThumbnailsToFolder() {
        let items = thumbnailControllers.map { (image: $0.image, fileURL: $0.representedFileURL) }
        guard !items.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        panel.message = "Choose a folder to save \(items.count) screenshot\(items.count == 1 ? "" : "s")"
        panel.level = .floating

        panel.begin { [weak self] response in
            guard response == .OK, let dirURL = panel.url else { return }
            let rawTemplate = UserDefaults.standard.string(forKey: FilenameFormatter.userDefaultsKey) ?? FilenameFormatter.defaultTemplate
            // Ensure batch writes don't collide when the template lacks {index}.
            let template = rawTemplate.contains("{index}") ? rawTemplate : "\(rawTemplate)-{index}"
            let batchDate = Date()

            DispatchQueue.global(qos: .userInitiated).async {
                for (i, item) in items.enumerated() {
                    let base = FilenameFormatter.format(template: template, index: i + 1, date: batchDate)
                    if let sourceURL = item.fileURL {
                        let ext = sourceURL.pathExtension.isEmpty ? "heic" : sourceURL.pathExtension
                        let fileURL = dirURL.appendingPathComponent("\(base).\(ext)")
                        try? FileManager.default.removeItem(at: fileURL)
                        try? FileManager.default.copyItem(at: sourceURL, to: fileURL)
                        continue
                    }

                    guard let data = ImageEncoder.encode(item.image) else { continue }
                    let filename = "\(base).\(ImageEncoder.fileExtension)"
                    let fileURL = dirURL.appendingPathComponent(filename)
                    try? data.write(to: fileURL)
                }
                DispatchQueue.main.async {
                    self?.playCopySound()
                    let all = self?.thumbnailControllers ?? []
                    self?.thumbnailControllers.removeAll()
                    for c in all { c.dismiss() }
                }
            }
        }
    }

    func reflowThumbnails() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let padding: CGFloat = 16
        let gap: CGFloat = 8
        var y = screen.visibleFrame.minY + padding
        for c in thumbnailControllers {
            let h = c.windowFrame.height  // height doesn't change, only Y moves
            c.moveTo(y: y)
            y += h + gap
        }
    }

    /// Update a floating thumbnail's image if it matches the given history entry.
    func refreshThumbnail(for entryID: String, image: NSImage) {
        for tc in thumbnailControllers where tc.historyEntryID == entryID {
            tc.updateImage(image)
        }
    }

    func playCopySound() {
        let soundEnabled = UserDefaults.standard.object(forKey: "playCopySound") as? Bool ?? true
        guard soundEnabled else { return }
        Self.captureSound?.stop()
        Self.captureSound?.play()
    }

    func saveImageToFile(_ image: NSImage) {
        guard let imageData = ImageEncoder.encode(image) else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [ImageEncoder.utType]
        savePanel.nameFieldStringValue = FilenameFormatter.defaultImageFilename()
        savePanel.directoryURL = SaveDirectoryAccess.directoryHint()
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? imageData.write(to: url)
                SaveDirectoryAccess.save(url: url.deletingLastPathComponent())
            }
        }
    }

    func copyFileURLToClipboard(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !pasteboard.writeObjects([url as NSURL]) {
            pasteboard.declareTypes([.fileURL], owner: nil)
            pasteboard.setString(url.absoluteString, forType: .fileURL)
        } else {
            pasteboard.setString(url.absoluteString, forType: .fileURL)
        }
    }

    func saveFileURLToFile(_ sourceURL: URL) {
        let savePanel = NSSavePanel()
        if let type = UTType(filenameExtension: sourceURL.pathExtension) {
            savePanel.allowedContentTypes = [type]
        }
        let ext = sourceURL.pathExtension.isEmpty ? "heic" : sourceURL.pathExtension
        savePanel.nameFieldStringValue = FilenameFormatter.defaultImageFilename(fileExtension: ext)
        savePanel.directoryURL = SaveDirectoryAccess.directoryHint()
        savePanel.canCreateDirectories = true
        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.copyItem(at: sourceURL, to: url)
                SaveDirectoryAccess.save(url: url.deletingLastPathComponent())
                self?.playCopySound()
            } catch {
                NSSound.beep()
            }
        }
    }

}
