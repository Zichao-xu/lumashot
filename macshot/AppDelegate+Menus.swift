import Cocoa
import Carbon
import UniformTypeIdentifiers
import AVFoundation
import WebP

extension AppDelegate {
    // MARK: - Open Image

    @objc func openImageFromMenu() {
        openImageWithPanel()
    }

    @objc func openImageFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let image = NSImage(pasteboard: pasteboard), image.isValid,
              image.size.width > 0, image.size.height > 0 else {
            let alert = NSAlert()
            alert.messageText = L("No Image on Clipboard")
            alert.informativeText = L("Copy an image to the clipboard first, then try again.")
            alert.alertStyle = .informational
            alert.addButton(withTitle: L("OK"))
            alert.runModal()
            return
        }
        DetachedEditorWindowController.open(image: image)
    }

    func openImageWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif, .heic, .webP, .image]
        panel.message = "Choose an image to open in Lumashot editor"

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                self.openImageFile(url: url)
            }
        }
    }

    func openImageFile(url: URL) {
        let image: NSImage
        if url.pathExtension.lowercased() == "webp",
           let data = try? Data(contentsOf: url),
           let decoded = try? WebPDecoder().decode(toNSImage: data, options: WebPDecoderOptions()) {
            image = decoded
        } else if let loaded = NSImage(contentsOf: url) {
            image = loaded
        } else {
            return
        }
        DetachedEditorWindowController.open(image: image)
    }

    // MARK: - Open Video

    @objc func openVideoFromMenu() {
        openVideoWithPanel()
    }

    func openVideoWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie, .video, .gif]
        panel.message = L("Choose a video to open in Lumashot editor")

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                self.openVideoFile(url: url)
            }
        }
    }

    func openVideoFile(url: URL) {
        // Never let the editor delete the user's source file on close.
        VideoEditorWindowController.open(url: url, deleteOnClose: false)
    }

    /// Handle files opened via Finder "Open With", drag-to-dock, or command line.
    func application(_ application: NSApplication, open urls: [URL]) {
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "tif", "bmp", "gif", "heic", "heif", "webp", "icns"]
        let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
        for url in urls {
            if url.scheme == "lumashot" {
                let urlSchemeEnabled = UserDefaults.standard.object(forKey: "urlSchemeEnabled") as? Bool ?? true
                guard urlSchemeEnabled else { continue }
                handleURLSchemeAction(url)
                continue
            }
            let ext = url.pathExtension.lowercased()
            // GIFs can be opened in either the image editor or the video
            // editor. Default to image editor (matches prior behavior) — users
            // wanting to trim a GIF use "Open Video..." explicitly.
            if imageExtensions.contains(ext) {
                openImageFile(url: url)
            } else if videoExtensions.contains(ext) {
                openVideoFile(url: url)
            }
        }
    }

    /// Handle lumashot:// URL scheme actions from external tools (Raycast, Alfred, etc.).
    /// Usage: `open lumashot://capture`, `open lumashot://ocr`, etc.
    func handleURLSchemeAction(_ url: URL) {
        guard let action = url.host else { return }
        switch action {
        case "capture":             captureScreen()
        case "capture-fullscreen":  captureFullScreen()
        case "quick-capture":       quickCapture()
        case "ocr":                 captureOCR()
        case "record":              recordArea()
        case "record-fullscreen":   recordFullScreen()
        case "scroll-capture":      scrollCapture()
        case "history":             showHistoryOverlay()
        case "settings":            openSettings()
        case "stop-recording":      stopRecording()
        case "capture-last":        captureLastArea()
        case "open":
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let path = components.queryItems?.first(where: { $0.name == "file" })?.value {
                openImageFile(url: URL(fileURLWithPath: path))
            }
        default: break
        }
    }

    // MARK: - Settings

    @objc func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController()
            settingsController?.onHotkeyChanged = { [weak self] in
                self?.registerHotkey()
                self?.rebuildStatusBarMenu()
            }
        }
        settingsController?.showWindow()
    }

    // MARK: - Quit

    @objc func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        releaseUpdateChecker.checkNow(presentNoUpdate: true)
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}
