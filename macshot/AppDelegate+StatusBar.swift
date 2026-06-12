import Cocoa
import Carbon
import UniformTypeIdentifiers
import AVFoundation
import WebP

extension AppDelegate {
    // MARK: - Status Bar

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        applyNormalStatusBarIcon()
        rebuildStatusBarMenu()
    }

    func applyNormalStatusBarIcon() {
        if let button = statusItem.button {
            if let img = NSImage(named: "StatusBarIcon") {
                img.isTemplate = true
                img.size = NSSize(width: 22, height: 22)
                button.image = img
            } else {
                button.title = "Lumashot"
            }
            // Use custom click handler so we can dismiss modals before showing the menu
            button.target = self
            button.action = #selector(statusBarIconClicked(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            (button.cell as? NSButtonCell)?.highlightsBy = .pushInCellMask
        }
    }

    @objc func statusBarIconClicked(_ sender: NSStatusBarButton) {
        // Pre-warm ScreenCaptureKit content while the user browses the menu
        ScreenCaptureManager.prewarm()

        if let modalWin = NSApp.modalWindow {
            // Modal is active — dismiss it, then show menu after it unwinds
            NSApp.stopModal()
            modalWin.close()
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let menu = self.statusBarMenu else { return }
                // Show via the standard statusItem path so it looks native (no arrow)
                self.statusItem.menu = menu
                sender.performClick(nil)
                self.statusItem.menu = nil
            }
        } else {
            // No modal — show menu normally via standard NSStatusItem path
            guard let menu = statusBarMenu else { return }
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        }
    }

    func rebuildStatusBarMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let captureAreaItem = NSMenuItem(title: L("Capture Area"), action: #selector(captureScreen), keyEquivalent: "")
        captureAreaItem.target = self
        captureAreaItem.image = NSImage(systemSymbolName: "crop", accessibilityDescription: nil)
        HotkeyManager.applyMenuShortcut(for: .captureArea, to: captureAreaItem)
        menu.addItem(captureAreaItem)

        let captureFullItem = NSMenuItem(title: L("Capture Screen"), action: #selector(captureFullScreen), keyEquivalent: "")
        captureFullItem.target = self
        captureFullItem.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: nil)
        HotkeyManager.applyMenuShortcut(for: .captureFullScreen, to: captureFullItem)
        menu.addItem(captureFullItem)

        let captureOCRItem = NSMenuItem(title: L("Capture OCR"), action: #selector(captureOCR), keyEquivalent: "")
        captureOCRItem.target = self
        captureOCRItem.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)
        HotkeyManager.applyMenuShortcut(for: .captureOCR, to: captureOCRItem)
        menu.addItem(captureOCRItem)

        let quickCaptureItem = NSMenuItem(title: L("Quick Capture"), action: #selector(quickCapture), keyEquivalent: "")
        quickCaptureItem.target = self
        quickCaptureItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        HotkeyManager.applyMenuShortcut(for: .quickCapture, to: quickCaptureItem)
        menu.addItem(quickCaptureItem)

        let captureLastAreaItem = NSMenuItem(title: L("Capture Last Area"), action: #selector(captureLastArea), keyEquivalent: "")
        captureLastAreaItem.target = self
        captureLastAreaItem.image = NSImage(systemSymbolName: "arrow.counterclockwise.circle", accessibilityDescription: nil)
        HotkeyManager.applyMenuShortcut(for: .captureLastArea, to: captureLastAreaItem)
        menu.addItem(captureLastAreaItem)

        let scrollCaptureItem = NSMenuItem(title: L("Scroll Capture"), action: #selector(scrollCapture), keyEquivalent: "")
        scrollCaptureItem.target = self
        scrollCaptureItem.image = NSImage(systemSymbolName: "scroll", accessibilityDescription: nil)
        HotkeyManager.applyMenuShortcut(for: .scrollCapture, to: scrollCaptureItem)
        menu.addItem(scrollCaptureItem)

        // Capture Delay submenu
        let delayItem = NSMenuItem(title: L("Capture Delay"), action: nil, keyEquivalent: "")
        delayItem.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
        let delaySubmenu = NSMenu()
        delaySubmenu.autoenablesItems = false
        let currentDelay = UserDefaults.standard.integer(forKey: "captureDelaySeconds")
        for seconds in [0, 3, 5, 10, 30] {
            let title = seconds == 0 ? L("None") : String(format: L("%d seconds"), seconds)
            let item = NSMenuItem(title: title, action: #selector(setDelaySeconds(_:)), keyEquivalent: "")
            item.target = self
            item.tag = seconds
            item.state = seconds == currentDelay ? .on : .off
            delaySubmenu.addItem(item)
        }
        delayItem.submenu = delaySubmenu
        menu.addItem(delayItem)

        menu.addItem(NSMenuItem.separator())

        let recordAreaItem = NSMenuItem(title: L("Record Area"), action: #selector(recordArea), keyEquivalent: "")
        recordAreaItem.target = self
        recordAreaItem.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: nil)
        HotkeyManager.applyMenuShortcut(for: .recordArea, to: recordAreaItem)
        menu.addItem(recordAreaItem)

        let recordScreenItem = NSMenuItem(title: L("Record Screen"), action: #selector(recordFullScreen), keyEquivalent: "")
        recordScreenItem.target = self
        recordScreenItem.image = NSImage(systemSymbolName: "menubar.dock.rectangle", accessibilityDescription: nil)
        HotkeyManager.applyMenuShortcut(for: .recordScreen, to: recordScreenItem)
        menu.addItem(recordScreenItem)

        menu.addItem(NSMenuItem.separator())

        // Recent Captures submenu
        let historyItem = NSMenuItem(title: L("Recent Captures"), action: nil, keyEquivalent: "")
        historyItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        let historySubmenu = NSMenu()
        historySubmenu.delegate = self
        historyItem.submenu = historySubmenu
        self.historyMenu = historySubmenu
        menu.addItem(historyItem)

        let historyOverlayItem = NSMenuItem(title: L("Show History Panel"), action: #selector(showHistoryOverlay), keyEquivalent: "")
        historyOverlayItem.target = self
        historyOverlayItem.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        HotkeyManager.applyMenuShortcut(for: .historyOverlay, to: historyOverlayItem)
        menu.addItem(historyOverlayItem)

        menu.addItem(NSMenuItem.separator())

        let openImageItem = NSMenuItem(title: L("Open Image..."), action: #selector(openImageFromMenu), keyEquivalent: "")
        openImageItem.target = self
        openImageItem.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil)
        menu.addItem(openImageItem)

        let openVideoItem = NSMenuItem(title: L("Open Video..."), action: #selector(openVideoFromMenu), keyEquivalent: "")
        openVideoItem.target = self
        openVideoItem.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
        menu.addItem(openVideoItem)

        let pasteImageItem = NSMenuItem(title: L("Open from Clipboard"), action: #selector(openImageFromClipboard), keyEquivalent: "")
        pasteImageItem.target = self
        pasteImageItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        HotkeyManager.applyMenuShortcut(for: .openFromClipboard, to: pasteImageItem)
        menu.addItem(pasteImageItem)

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: L("Settings..."), action: #selector(openSettings), keyEquivalent: ",")
        prefsItem.target = self
        prefsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        menu.addItem(prefsItem)

        let updateItem = NSMenuItem(title: L("Check for Updates..."), action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        updateItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L("Quit Lumashot"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusBarMenu = menu
    }

}
