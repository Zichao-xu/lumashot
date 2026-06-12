import Cocoa
import Carbon
import UniformTypeIdentifiers
import AVFoundation
import WebP

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem!
    var releaseUpdateChecker: GitHubReleaseUpdateChecker!
    var overlayControllers: [OverlayWindowController] = []
    var settingsController: SettingsWindowController?
    var onboardingController: PermissionOnboardingController?
    var pinControllers: [PinWindowController] = []
    var thumbnailControllers: [FloatingThumbnailController] = []
    var ocrController: OCRResultController?
    var historyMenu: NSMenu?
    var historyOverlayController: HistoryOverlayController?
    var isCapturing = false
    var delayCountdownWindow: NSWindow?

    // Pending capture-mode flags + saved window/app state (used by AppDelegate+Hotkey /
    // +Capture) — stored properties must live on the class, not an extension.
    var pendingRecordMode: Bool = false
    var pendingFullScreen: Bool = false
    var pendingFullScreenRecord: Bool = false
    var pendingFullScreenRecordAutoStart: Bool = false
    var pendingOCRMode: Bool = false
    var pendingQuickCaptureMode: Bool = false
    var pendingScrollCaptureMode: Bool = false
    var capturedWindowTitle: String?
    /// The app that was active before Lumashot showed its overlay — re-activated on dismiss.
    var previousApp: NSRunningApplication?
    /// Titled Lumashot windows hidden during capture so `NSApp.activate` can't pull them
    /// in front of the user's frontmost app; restored (in order) when the overlay dismisses.
    var stashedBackgroundWindows: [NSWindow] = []
    var pendingRestoreLastArea: Bool = false
    var delayTimer: Timer?
    var delayEscMonitor: Any?
    var uploadToastController: UploadToastController?
    var recordingEngine: RecordingEngine?
    var audioMergeController: AudioMergeController?
    var recordingOverlayController: OverlayWindowController?
    var recordingHUDPanel: RecordingHUDPanel?
    var recordingScreenRect: NSRect = .zero  // screen-space capture rect
    var recordingScreen: NSScreen?
    var mouseHighlightOverlay: MouseHighlightOverlay?
    var keystrokeOverlay: KeystrokeOverlay?
    var webcamOverlay: WebcamOverlay?
    var selectionBorderOverlay: SelectionBorderOverlay?
    var menuBarIconWasHidden: Bool = false  // restore after recording if user had it hidden
    var scrollCaptureController: ScrollCaptureController?
    /// The overlay controller whose selection is being scroll-captured.
    var scrollCaptureOverlayController: OverlayWindowController?
    var scrollCapturePreviewPanel: ScrollCapturePreviewPanel?
    var statusBarMenu: NSMenu?

    /// Shared capture sound — loaded once, reused everywhere.
    static let captureSound: NSSound? = {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        return NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Tink")
    }()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Prevent multiple instances — if already running, activate the existing one and quit
        let bundleID = Bundle.main.bundleIdentifier ?? "com.sw33tlie.macshot.macshot"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if running.count > 1 {
            // Tell the existing instance to show its icon and open Settings
            DistributedNotificationCenter.default().postNotificationName(
                .init("com.sw33tlie.macshot.showAndOpenPrefs"),
                object: nil, userInfo: nil, deliverImmediately: true
            )
            NSApp.terminate(nil)
            return
        }

        // Offer to move to /Applications if running from a DMG or translocated path
        promptToMoveToApplicationsIfNeeded()

        migrateFilenameTemplateIfNeeded()

        // Touch the clipboard tmp dir early so it adopts any leftover file
        // BEFORE the sweep runs — otherwise the sweeper might delete the
        // leftover while the adoption code was about to claim it, and we'd
        // end up with a stale `currentClipboardFileURL` pointing at nothing.
        _ = ImageEncoder.clipboardTmpDirectory

        // Reclaim disk from stale tmp leftovers (cancelled recordings,
        // legacy clipboard PNGs, share-sheet scratch). Runs off the main
        // thread so it can't delay launch.
        LaunchCleanup.runAll()

        // Force-init the history singleton so its launch-time orphan
        // prune runs even if the user doesn't take a screenshot this
        // session. Without this, the prune only fires the first time
        // something references ScreenshotHistory.shared.
        _ = ScreenshotHistory.shared

        releaseUpdateChecker = GitHubReleaseUpdateChecker()
        setupMainMenu()
        setupStatusBar()
        releaseUpdateChecker.start()
        if UserDefaults.standard.bool(forKey: "hideMenuBarIcon") {
            setMenuBarIconVisible(false)
        }
        registerHotkey()
        // Pre-warm CoreAudio so the first capture sound doesn't stall ~1s.
        if let sound = Self.captureSound {
            sound.volume = 0
            sound.play()
            sound.stop()
            sound.volume = 1
        }

        // Listen for duplicate-launch notification to restore icon
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleShowAndOpenPrefs),
            name: .init("com.sw33tlie.macshot.showAndOpenPrefs"), object: nil
        )

        // Dismiss overlays when the user switches spaces
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(spaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )

        // Pin from history panel
        NotificationCenter.default.addObserver(
            self, selector: #selector(pinFromHistory(_:)),
            name: .init("macshot.pinFromHistory"), object: nil
        )

        // Check screen recording permission. If not yet granted, show the
        // custom onboarding window instead of letting macOS throw its own dialogs.
        PermissionOnboardingController.checkPermissionSync { [weak self] granted in
            guard let self = self else { return }
            if !granted {
                self.showOnboarding()
            }
        }
    }

    func showOnboarding() {
        // If already open, just bring it to front
        if let existing = onboardingController {
            existing.show()
            return
        }
        let oc = PermissionOnboardingController()
        oc.onPermissionGranted = { [weak self] in
            self?.onboardingController = nil
        }
        onboardingController = oc
        oc.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Re-launching Lumashot while it's running: show the menu bar icon
        if UserDefaults.standard.bool(forKey: "hideMenuBarIcon") {
            UserDefaults.standard.set(false, forKey: "hideMenuBarIcon")
            setMenuBarIconVisible(true)
        }
        // Only open settings if no windows are visible (e.g. pure menu-bar state).
        // If editor/video editor is already open, just bring the app to the front.
        if !flag {
            openSettings()
        }
        return false
    }

    func setMenuBarIconVisible(_ visible: Bool) {
        statusItem.isVisible = visible
    }

    /// Dock menu shown on right-click of the Dock icon.
    ///
    /// macOS only auto-populates the Dock menu's window list for document-based
    /// apps (apps using `NSDocumentController`). Our editor windows aren't
    /// documents, so we build the list ourselves: each visible titled window
    /// gets an entry that brings that specific window forward when clicked.
    /// Without this users only see "Show All Windows" and can't jump directly
    /// to a particular editor session.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let windows = NSApp.windows.filter {
            $0.styleMask.contains(.titled) && ($0.isVisible || $0.isMiniaturized)
        }
        guard !windows.isEmpty else { return nil }
        let menu = NSMenu()
        // Sort by title so the menu order is stable across dock-menu openings.
        for window in windows.sorted(by: { $0.title < $1.title }) {
            let item = NSMenuItem(
                title: window.title.isEmpty ? L("Untitled") : window.title,
                action: #selector(activateWindowFromDockMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = window
            if window.isMiniaturized {
                // Visual cue so users know clicking will also de-minimize.
                item.state = .mixed
            }
            menu.addItem(item)
        }
        return menu
    }

    @objc func activateWindowFromDockMenu(_ sender: NSMenuItem) {
        guard let window = sender.representedObject as? NSWindow else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// One-shot migration from the legacy `useWindowTitleInFilename` checkbox
    /// to the new `filenameTemplate` string. Runs once — seeds the template
    /// from the old bool then clears the legacy key.
    func migrateFilenameTemplateIfNeeded() {
        let d = UserDefaults.standard
        guard d.object(forKey: FilenameFormatter.userDefaultsKey) == nil else { return }
        let hadWindowTitle = d.bool(forKey: "useWindowTitleInFilename")
        let template = hadWindowTitle
            ? "Screenshot {date} at {time} — {window}"
            : FilenameFormatter.defaultTemplate
        d.set(template, forKey: FilenameFormatter.userDefaultsKey)
        d.removeObject(forKey: "useWindowTitleInFilename")
    }

    /// If the app is running from a DMG volume or a translocated path,
    /// offer to move it to /Applications for proper operation (update checks,
    /// persistent preferences, no translocation issues).
    func promptToMoveToApplicationsIfNeeded() {
        let bundlePath = Bundle.main.bundlePath
        let isOnDMG = bundlePath.hasPrefix("/Volumes/")
        let isTranslocated = bundlePath.contains("/AppTranslocation/")
        guard isOnDMG || isTranslocated else { return }
        guard !UserDefaults.standard.bool(forKey: "suppressMoveToApplications") else { return }

        let alert = NSAlert()
        alert.messageText = "Move to Applications folder?"
        alert.informativeText = "Lumashot is running from a disk image. Move it to your Applications folder for update checks and best experience."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: "suppressMoveToApplications")
        }
        guard response == .alertFirstButtonReturn else { return }

        let dest = URL(fileURLWithPath: "/Applications/Lumashot.app")
        let src = URL(fileURLWithPath: bundlePath)
        do {
            // Remove old version if present
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: src, to: dest)
            // Relaunch from /Applications
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-n", dest.path]
            try task.run()
            NSApp.terminate(nil)
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Could not move to Applications"
            errAlert.informativeText = "Please drag Lumashot to your Applications folder manually.\n\n\(error.localizedDescription)"
            errAlert.runModal()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        HotkeyManager.shared.unregister()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Main Menu (required when no storyboard)

    func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Lumashot", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Lumashot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
    }

}

// MARK: - OverlayWindowControllerDelegate

