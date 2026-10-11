import Cocoa
import Carbon
import ServiceManagement
import ScreenCaptureKit

extension SettingsWindowController {
    // MARK: - Theme presets

    struct ThemePreset {
        let name: String
        let accent: NSColor
        let icon: NSColor
        let bg: NSColor

        static let all: [ThemePreset] = [
            ThemePreset(name: "Default",
                        accent: ToolbarLayout.defaultAccentColor,
                        icon:   ToolbarLayout.defaultIconColor,
                        bg:     ToolbarLayout.defaultBgColor),
            ThemePreset(name: "Classic",
                        accent: NSColor(calibratedRed: 0.00, green: 0.48, blue: 1.00, alpha: 1.0),
                        icon:   .white,
                        bg:     NSColor(white: 0.12, alpha: 1.0)),
            ThemePreset(name: "Ocean",
                        accent: NSColor(calibratedRed: 0.20, green: 0.70, blue: 0.75, alpha: 1.0),
                        icon:   .white,
                        bg:     NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.18, alpha: 1.0)),
            ThemePreset(name: "Sunset",
                        accent: NSColor(calibratedRed: 1.00, green: 0.55, blue: 0.20, alpha: 1.0),
                        icon:   .white,
                        bg:     NSColor(calibratedRed: 0.15, green: 0.10, blue: 0.12, alpha: 1.0)),
            ThemePreset(name: "Forest",
                        accent: NSColor(calibratedRed: 0.30, green: 0.75, blue: 0.45, alpha: 1.0),
                        icon:   .white,
                        bg:     NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.10, alpha: 1.0)),
            ThemePreset(name: "Mono",
                        accent: NSColor(white: 0.30, alpha: 1.0),
                        icon:   .white,
                        bg:     NSColor(white: 0.10, alpha: 1.0)),
        ]
    }

    func makeColorColumn(well: NSColorWell, caption: String) -> NSView {
        let label = NSTextField(labelWithString: caption)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .center

        let col = NSStackView(views: [well, label])
        col.orientation = .vertical
        col.alignment = .centerX
        col.spacing = 4
        col.translatesAutoresizingMaskIntoConstraints = false
        return col
    }

    @objc func themePresetChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx < ThemePreset.all.count else { return } // "Custom" — no-op
        applyThemePreset(ThemePreset.all[idx])
    }

    func applyThemePreset(_ preset: ThemePreset) {
        ToolbarLayout.saveAccentColor(preset.accent)
        ToolbarLayout.saveIconColor(preset.icon)
        ToolbarLayout.saveBgColor(preset.bg)
        accentColorWell.color = preset.accent
        iconColorWell.color = preset.icon
        bgColorWell.color = preset.bg
        notifyToolbarColorChange()
        updateThemePresetSelection()
    }

    func updateThemePresetSelection() {
        guard let popup = themePresetPopup else { return }
        let current = (ToolbarLayout.accentColor, ToolbarLayout.iconColor, ToolbarLayout.bgColor)
        for (i, preset) in ThemePreset.all.enumerated() {
            if colorsClose(current.0, preset.accent) &&
               colorsClose(current.1, preset.icon) &&
               colorsClose(current.2, preset.bg) {
                popup.selectItem(at: i)
                return
            }
        }
        // No match — select "Custom" (the last item)
        popup.selectItem(at: ThemePreset.all.count)
    }

    /// Compare two NSColors in sRGB with a small tolerance (color picker rounding).
    func colorsClose(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return false }
        let tol: CGFloat = 0.01
        return abs(x.redComponent - y.redComponent) < tol
            && abs(x.greenComponent - y.greenComponent) < tol
            && abs(x.blueComponent - y.blueComponent) < tol
            && abs(x.alphaComponent - y.alphaComponent) < tol
    }
    func notifyToolbarColorChange() {
        NotificationCenter.default.post(name: .toolbarColorsDidChange, object: nil)
    }
    @objc func copyUploadURL(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, id.hasPrefix("link::") else { return }
        let url = String(id.dropFirst(6))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        let orig = sender.title
        sender.title = "✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { sender.title = orig }
    }
    @objc func snapGuidesChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "snapGuidesEnabled")
    }
    @objc func captureCursorChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "captureCursor")
    }
    @objc func filenameTemplateCommitted(_ sender: NSTextField) {
        let trimmed = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? FilenameFormatter.defaultTemplate : sender.stringValue
        if trimmed.isEmpty {
            sender.stringValue = FilenameFormatter.defaultTemplate
        }
        UserDefaults.standard.set(value, forKey: FilenameFormatter.userDefaultsKey)
        updateFilenamePreview()
    }

    @objc func filenameTemplateReset(_ sender: NSButton) {
        filenameTemplateField.stringValue = FilenameFormatter.defaultTemplate
        UserDefaults.standard.set(FilenameFormatter.defaultTemplate, forKey: FilenameFormatter.userDefaultsKey)
        updateFilenamePreview()
    }

    func updateFilenamePreview() {
        guard let field = filenameTemplateField, let preview = filenameTemplatePreview else { return }
        let raw = field.stringValue
        let template = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? FilenameFormatter.defaultTemplate : raw
        let sampleDate = sampleFilenameDate()
        let sampleWindow = template.contains("{window}") ? "Example Window" : nil
        let sampleIndex = template.contains("{index}") ? 1 : nil
        let base = FilenameFormatter.format(template: template, windowTitle: sampleWindow, index: sampleIndex, date: sampleDate)
        preview.stringValue = "\(L("Preview:")) \(base).\(ImageEncoder.fileExtension)"
    }

    @objc func recordingFilenameTemplateCommitted(_ sender: NSTextField) {
        let trimmed = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? FilenameFormatter.defaultRecordingTemplate : sender.stringValue
        if trimmed.isEmpty {
            sender.stringValue = FilenameFormatter.defaultRecordingTemplate
        }
        UserDefaults.standard.set(value, forKey: FilenameFormatter.recordingUserDefaultsKey)
        updateRecordingFilenamePreview()
    }

    @objc func recordingFilenameTemplateReset(_ sender: NSButton) {
        recordingFilenameTemplateField.stringValue = FilenameFormatter.defaultRecordingTemplate
        UserDefaults.standard.set(FilenameFormatter.defaultRecordingTemplate, forKey: FilenameFormatter.recordingUserDefaultsKey)
        updateRecordingFilenamePreview()
    }

    func updateRecordingFilenamePreview() {
        guard let field = recordingFilenameTemplateField, let preview = recordingFilenameTemplatePreview else { return }
        let raw = field.stringValue
        let template = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? FilenameFormatter.defaultRecordingTemplate : raw
        let sampleDate = sampleFilenameDate()
        let sampleIndex = template.contains("{index}") ? 1 : nil
        let base = FilenameFormatter.format(template: template, windowTitle: nil, index: sampleIndex, date: sampleDate, fallback: FilenameFormatter.defaultRecordingTemplate)
        preview.stringValue = "\(L("Preview:")) \(base).mp4"
    }

    func sampleFilenameDate() -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4; comps.day = 17
        comps.hour = 14; comps.minute = 22; comps.second = 5
        return Calendar(identifier: .gregorian).date(from: comps) ?? Date()
    }
    @objc func launchAtLoginChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
        if #available(macOS 13.0, *) {
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                #if DEBUG
                print("Failed to update login item: \(error)")
                #endif
            }
        }
    }

    @objc func urlSchemeChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "urlSchemeEnabled")
    }

    func showURLSchemeInfoPopover(near sourceView: NSView) {
        if let existing = urlSchemeInfoPopover, existing.isShown { return }

        let commands: [(String, String)] = [
            ("lumashot://capture",             L("Start area capture")),
            ("lumashot://capture-fullscreen",  L("Capture the full screen")),
            ("lumashot://capture-last",        L("Re-capture the last selected area")),
            ("lumashot://quick-capture",       L("Quick capture (uses your Enter action)")),
            ("lumashot://ocr",                 L("Capture area and extract text")),
            ("lumashot://record",              L("Start area recording")),
            ("lumashot://record-fullscreen",   L("Start full-screen recording")),
            ("lumashot://stop-recording",      L("Stop the current recording")),
            ("lumashot://scroll-capture",      L("Start scroll capture")),
            ("lumashot://history",             L("Open the recent captures overlay")),
            ("lumashot://settings",            L("Open this settings window")),
            ("lumashot://open?file=/path.png", L("Open an image file in the editor")),
        ]

        let title = NSTextField(labelWithString: L("Supported URL Scheme Commands"))
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(wrappingLabelWithString: L("Trigger Lumashot from Raycast, Alfred, Shortcuts, or any tool that opens URLs."))
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.preferredMaxLayoutWidth = 440
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        // NSGridView for perfect column alignment — each row's cmd column and
        // desc column line up precisely regardless of text width.
        let grid = NSGridView(numberOfColumns: 2, rows: commands.count)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 4
        grid.columnSpacing = 16
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .leading

        for (i, entry) in commands.enumerated() {
            let cmdLabel = NSTextField(labelWithString: entry.0)
            cmdLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            cmdLabel.textColor = .labelColor
            cmdLabel.isSelectable = true

            let descLabel = NSTextField(labelWithString: entry.1)
            descLabel.font = NSFont.systemFont(ofSize: 11)
            descLabel.textColor = .secondaryLabelColor

            grid.cell(atColumnIndex: 0, rowIndex: i).contentView = cmdLabel
            grid.cell(atColumnIndex: 1, rowIndex: i).contentView = descLabel
        }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)
        container.addSubview(subtitle)
        container.addSubview(grid)

        let pad: CGFloat = 14
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: pad),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
            title.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -pad),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -pad),

            grid.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 12),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -pad),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -pad),
        ])

        let vc = NSViewController()
        vc.view = container

        // Compute fitting size for the popover
        container.layoutSubtreeIfNeeded()
        let fitting = container.fittingSize

        let popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.contentSize = fitting
        popover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
        urlSchemeInfoPopover = popover
    }

    @objc func hideMenuBarIconChanged(_ sender: NSButton) {
        let hidden = sender.state == .on
        UserDefaults.standard.set(hidden, forKey: "hideMenuBarIcon")
        (NSApp.delegate as? AppDelegate)?.setMenuBarIconVisible(!hidden)
    }

    @objc func autoUpdateChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: GitHubReleaseUpdateChecker.automaticChecksEnabledKey)
    }

    @objc func translationProviderChanged(_ sender: NSPopUpButton) {
        if let raw = sender.selectedItem?.representedObject as? String,
           let provider = TranslationProvider(rawValue: raw) {
            TranslationService.provider = provider
        }
        updateAITranslationControlsEnabled()
    }

    @objc func aiTranslationFieldChanged(_ sender: NSTextField) {
        saveAITranslationSettings()
    }

    @objc func localModelAction(_ sender: NSButton) {
        sender.isEnabled = false
        localModelProgressIndicator.isHidden = false
        localModelProgressIndicator.doubleValue = 0

        // Connect progress handler
        LocalModelService.shared.downloadProgressHandler = { [weak self] progress in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let percentage = progress.totalBytes > 0 ? Double(progress.bytesWritten) / Double(progress.totalBytes) * 100 : 0
                self.localModelProgressIndicator.doubleValue = percentage
                self.localModelStatusLabel.stringValue = String(format: L("Downloading %@: %.0f%%"), progress.fileName, percentage)
            }
        }

        if LocalModelService.shared.isReady {
            LocalModelService.shared.start { [weak self] result in
                self?.updateLocalModelControls()
                if case .failure(let error) = result {
                    self?.showLocalModelError(error)
                }
            }
        } else {
            LocalModelService.shared.install { [weak self] result in
                self?.updateLocalModelControls()
                switch result {
                case .failure(let error):
                    self?.showLocalModelError(error)
                case .success:
                    LocalModelService.shared.start { startResult in
                        self?.updateLocalModelControls()
                        if case .failure(let error) = startResult {
                            self?.showLocalModelError(error)
                        }
                    }
                }
            }
        }
    }

    @objc func openTranslationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization.Settings.extension?Translation") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openOpenAIAPIKeys() {
        if let url = URL(string: "https://platform.openai.com/api-keys") {
            NSWorkspace.shared.open(url)
        }
    }

    func showLocalModelError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L("Local Model Failed")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        if let window = self.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    func showWindow() {
        loadSettings()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        (NSApp.delegate as? AppDelegate)?.returnFocusIfNeeded()
    }
}
