import Cocoa
import Carbon
import ServiceManagement
import ScreenCaptureKit

extension SettingsWindowController {
    // MARK: - Actions

    @objc func browseSavePath(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = SaveDirectoryAccess.directoryHint()
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            SaveDirectoryAccess.save(url: url)
            self?.savePathField.stringValue = url.path
        }
    }

    @objc func ocrActionChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: "ocrAction")
    }
    @objc func copySoundChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "playCopySound")
    }
    @objc func rememberToolChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "rememberLastTool")
    }
    @objc func thumbnailChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "showFloatingThumbnail")
    }
    @objc func thumbnailAutoDismissChanged(_ sender: NSStepper) {
        thumbnailAutoDismissField.integerValue = sender.integerValue
        UserDefaults.standard.set(sender.integerValue, forKey: "thumbnailAutoDismiss")
    }
    @objc func thumbnailScaleChanged(_ sender: NSSlider) {
        UserDefaults.standard.set(sender.doubleValue, forKey: "thumbnailScale")
        thumbnailScaleLabel?.stringValue = scalePercentString(sender.doubleValue)
    }

    func scalePercentString(_ scale: Double) -> String {
        "\(Int(round(scale * 100)))%"
    }

    @objc func thumbnailStackingChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem == 0, forKey: "thumbnailStacking")
    }
    @objc func quickModeChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: "quickCaptureMode")
    }
    @objc func quickCaptureOpenEditorChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "quickCaptureOpenEditor")
    }
    @objc func languageChanged(_ sender: NSPopUpButton) {
        let languages = LanguageManager.availableLanguages
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < languages.count else { return }
        LanguageManager.shared.currentLanguage = languages[idx].code
    }
    @objc func openGitHub() {
        if let url = URL(string: "https://github.com/Zichao-xu/lumashot") { NSWorkspace.shared.open(url) }
    }
    @objc func imageFormatChanged(_ sender: NSPopUpButton) {
        let formats = ["png", "jpeg", "heic", "webp"]
        UserDefaults.standard.set(formats[sender.indexOfSelectedItem], forKey: "imageFormat")
        updateQualityVisibility()
    }
    @objc func qualityChanged(_ sender: NSSlider) {
        qualityLabel.stringValue = String(format: L("%d%%"), sender.integerValue)
        UserDefaults.standard.set(Double(sender.integerValue) / 100.0, forKey: "imageQuality")
    }
    @objc func downscaleRetinaChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "downscaleRetina")
    }
    @objc func imgbbKeyChanged(_ sender: NSTextField) {
        let key = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { UserDefaults.standard.removeObject(forKey: "imgbbAPIKey") }
        else { UserDefaults.standard.set(key, forKey: "imgbbAPIKey") }
    }
    @objc func historySizeChanged(_ sender: NSStepper) {
        historySizeField.integerValue = sender.integerValue
        UserDefaults.standard.set(sender.integerValue, forKey: "historySize")
        UserDefaults.standard.set(false, forKey: "historyUnlimited")
        historyUnlimitedCheckbox.state = .off
        updateHistoryControlsEnabled()
        ScreenshotHistory.shared.pruneToMax()
    }

    @objc func historyUnlimitedChanged(_ sender: NSButton) {
        let unlimited = sender.state == .on
        UserDefaults.standard.set(unlimited, forKey: "historyUnlimited")
        updateHistoryControlsEnabled()
    }

    func updateHistoryControlsEnabled() {
        let unlimited = UserDefaults.standard.bool(forKey: "historyUnlimited")
        historySizeField.alphaValue = unlimited ? 0.35 : 1.0
        historySizeStepper.isEnabled = !unlimited
    }
    @objc func recordingFPSChanged(_ sender: NSPopUpButton) {
        let fpsOptions = [15, 24, 30, 60, 120]
        let fps = fpsOptions[min(sender.indexOfSelectedItem, fpsOptions.count - 1)]
        UserDefaults.standard.set(fps, forKey: "recordingFPS")
    }
    @objc func recordingOnStopChanged(_ sender: NSPopUpButton) {
        let values = ["editor", "finder", "clipboard"]
        UserDefaults.standard.set(values[sender.indexOfSelectedItem], forKey: "recordingOnStop")
    }
    @objc func hideRecordingHUDChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "hideRecordingHUD")
    }

    @objc func webcamPositionChanged(_ sender: NSPopUpButton) {
        let values = ["bottomRight", "bottomLeft", "topRight", "topLeft"]
        UserDefaults.standard.set(values[sender.indexOfSelectedItem], forKey: "webcamPosition")
    }

    @objc func webcamSizeChanged(_ sender: NSPopUpButton) {
        let values = ["small", "medium", "large"]
        UserDefaults.standard.set(values[sender.indexOfSelectedItem], forKey: "webcamSize")
    }

    @objc func webcamShapeChanged(_ sender: NSPopUpButton) {
        let values = ["circle", "roundedRect"]
        UserDefaults.standard.set(values[sender.indexOfSelectedItem], forKey: "webcamShape")
    }

    @objc func browseRecSavePath(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = SaveDirectoryAccess.recordingDirectoryHint()
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            SaveDirectoryAccess.saveRecordingDirectory(url: url)
            self?.recSavePathField.stringValue = url.path
        }
    }
    @objc func clearRecSavePath(_ sender: NSButton) {
        SaveDirectoryAccess.clearRecordingDirectory()
        recSavePathField.stringValue = SaveDirectoryAccess.recordingDisplayPath
    }
    // MARK: - Scroll Capture actions
    @objc func scrollAutoScrollChanged(_ sender: NSButton) {
        let on = sender.state == .on
        UserDefaults.standard.set(on, forKey: "scrollAutoScrollEnabled")
        scrollSpeedPopup.isEnabled = on
    }
    @objc func scrollSpeedChanged(_ sender: NSPopUpButton) {
        // 0=Slow(1), 1=Medium(2), 2=Fast(3), 3=VeryFast(4)
        UserDefaults.standard.set(sender.indexOfSelectedItem + 1, forKey: "scrollAutoScrollSpeed")
    }
    @objc func scrollMaxHeightChanged(_ sender: NSStepper) {
        scrollMaxHeightField.integerValue = sender.integerValue
        UserDefaults.standard.set(sender.integerValue, forKey: "scrollMaxHeight")
    }
    @objc func scrollFrozenDetectionChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "scrollFrozenDetection")
    }
    @objc func toggleItemChanged(_ sender: NSButton) {
        let key = sender.identifier?.rawValue ?? "enabledTools"
        let allTools: [AnnotationTool] = [.pencil, .line, .arrow, .rectangle,
                                          .ellipse, .marker, .text, .number, .pixelate, .loupe, .stamp, .measure]
        let allActions: [Int] = [1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010]
        let defaultValues: [Int] = key == "enabledTools" ? allTools.map { $0.rawValue } : allActions
        var enabled = UserDefaults.standard.array(forKey: key) as? [Int] ?? defaultValues
        if sender.state == .on { if !enabled.contains(sender.tag) { enabled.append(sender.tag) } }
        else { enabled.removeAll { $0 == sender.tag } }
        UserDefaults.standard.set(enabled, forKey: key)
    }
    @objc func accentColorChanged(_ sender: NSColorWell) {
        ToolbarLayout.saveAccentColor(sender.color)
        notifyToolbarColorChange()
        updateThemePresetSelection()
    }
    @objc func iconColorChanged(_ sender: NSColorWell) {
        ToolbarLayout.saveIconColor(sender.color)
        notifyToolbarColorChange()
        updateThemePresetSelection()
    }
    @objc func bgColorChanged(_ sender: NSColorWell) {
        ToolbarLayout.saveBgColor(sender.color)
        notifyToolbarColorChange()
        updateThemePresetSelection()
    }
}
