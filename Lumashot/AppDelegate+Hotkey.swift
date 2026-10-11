import Cocoa
import Carbon
import UniformTypeIdentifiers
import AVFoundation
import WebP

extension AppDelegate {
    // MARK: - Hotkey

    func registerHotkey() {
        HotkeyManager.shared.registerAll(
            captureArea: { [weak self] in
                DispatchQueue.main.async { self?.startCapture(fromMenu: false) }
            },
            captureFullScreen: { [weak self] in
                DispatchQueue.main.async { self?.captureFullScreen() }
            },
            recordArea: { [weak self] in
                DispatchQueue.main.async { self?.recordArea() }
            },
            recordScreen: { [weak self] in
                DispatchQueue.main.async { self?.recordFullScreen() }
            },
            historyOverlay: { [weak self] in
                DispatchQueue.main.async { self?.showHistoryOverlay() }
            },
            captureOCR: { [weak self] in
                DispatchQueue.main.async { self?.captureOCR() }
            },
            quickCapture: { [weak self] in
                DispatchQueue.main.async { self?.quickCapture() }
            },
            scrollCapture: { [weak self] in
                DispatchQueue.main.async { self?.scrollCapture() }
            },
            openFromClipboard: { [weak self] in
                DispatchQueue.main.async { self?.openImageFromClipboard() }
            },
            captureLastArea: { [weak self] in
                DispatchQueue.main.async { self?.captureLastArea() }
            }
        )
    }


    /// True when floating thumbnails or pin windows are visible.
    var hasVisibleFloatingPanels: Bool {
        !thumbnailControllers.isEmpty || !pinControllers.isEmpty
    }

    /// Call when a Lumashot window closes. If no titled windows remain,
    /// switches to accessory activation policy and returns focus to
    /// the previous app (or the next regular app in line).
    func returnFocusIfNeeded() {
        let appToActivate = previousApp
        previousApp = nil
        DispatchQueue.main.async { [weak self] in
            // Don't hide the app while a recording is in progress — the HUD
            // and selection border are non-titled panels that would be killed.
            if self?.recordingEngine != nil { return }
            let hasVisibleWindows = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
            // Windows we hid for the screenshot count as "visible" for
            // activation-policy purposes — they're coming back as soon as
            // the previous app regains focus, so we mustn't downgrade.
            let hasStashedWindows = !(self?.stashedBackgroundWindows.isEmpty ?? true)
            guard !hasVisibleWindows, !hasStashedWindows else { return }
            NSApp.setActivationPolicy(.accessory)
            if let prev = appToActivate, !prev.isTerminated,
               prev.bundleIdentifier != Bundle.main.bundleIdentifier {
                Self.activateApp(prev)
            } else {
                // No known previous app — yield focus to whatever is frontmost.
                // Avoid NSApp.hide(nil) which can suspend the Carbon event loop
                // and break global hotkeys until the app is reactivated.
                Self.activateApp(
                    NSWorkspace.shared.runningApplications.first {
                        $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                    } ?? NSWorkspace.shared.frontmostApplication ?? NSRunningApplication.current
                )
            }
        }
    }

    /// Activate another app using the modern cooperative activation API.
    static func activateApp(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: app)
            app.activate()
        } else {
            app.activate(options: .activateIgnoringOtherApps)
        }
    }

}
