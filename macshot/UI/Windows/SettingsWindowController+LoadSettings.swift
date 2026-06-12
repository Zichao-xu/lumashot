import Cocoa
import Carbon
import ServiceManagement
import ScreenCaptureKit

extension SettingsWindowController {
    // MARK: - Load settings

    func loadSettings() {
        // Load shortcut fields
        for slot in HotkeyManager.HotkeySlot.allCases {
            hotkeyFields[slot]?.stringValue = HotkeyManager.displayString(for: slot)
        }

        savePathField.stringValue = SaveDirectoryAccess.displayPath

        // Migrate legacy bool to new int setting
        if UserDefaults.standard.object(forKey: "ocrAction") == nil {
            let legacyAutoCopy = UserDefaults.standard.object(forKey: "autoCopyOCRText") as? Bool ?? true
            UserDefaults.standard.set(legacyAutoCopy ? 0 : 1, forKey: "ocrAction")
        }
        ocrActionPopup.selectItem(at: UserDefaults.standard.integer(forKey: "ocrAction"))

        let copySound = UserDefaults.standard.object(forKey: "playCopySound") as? Bool ?? true
        copySoundCheckbox.state = copySound ? .on : .off

        // rememberSelectionCheckbox removed

        let rememberTool = UserDefaults.standard.object(forKey: "rememberLastTool") as? Bool ?? true
        rememberToolCheckbox.state = rememberTool ? .on : .off

        let thumbnail = UserDefaults.standard.object(forKey: "showFloatingThumbnail") as? Bool ?? true
        thumbnailCheckbox.state = thumbnail ? .on : .off

        let autoDismiss = UserDefaults.standard.object(forKey: "thumbnailAutoDismiss") as? Int ?? 5
        thumbnailAutoDismissField.integerValue = autoDismiss
        thumbnailAutoDismissStepper.integerValue = autoDismiss

        let stacking = UserDefaults.standard.object(forKey: "thumbnailStacking") as? Bool ?? true
        thumbnailStackingPopup.selectItem(at: stacking ? 0 : 1)

        let launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        launchAtLoginCheckbox.state = launchAtLogin ? .on : .off

        hideMenuBarIconCheckbox.state = UserDefaults.standard.bool(forKey: "hideMenuBarIcon") ? .on : .off

        let snapGuides = UserDefaults.standard.object(forKey: "snapGuidesEnabled") as? Bool ?? true
        snapGuidesCheckbox.state = snapGuides ? .on : .off

        captureCursorCheckbox.state = UserDefaults.standard.bool(forKey: "captureCursor") ? .on : .off
        filenameTemplateField.stringValue = UserDefaults.standard.string(forKey: FilenameFormatter.userDefaultsKey) ?? FilenameFormatter.defaultTemplate
        updateFilenamePreview()
        recordingFilenameTemplateField.stringValue = UserDefaults.standard.string(forKey: FilenameFormatter.recordingUserDefaultsKey) ?? FilenameFormatter.defaultRecordingTemplate
        updateRecordingFilenamePreview()

        let autoUpdate = UserDefaults.standard.object(forKey: GitHubReleaseUpdateChecker.automaticChecksEnabledKey) as? Bool ?? true
        autoUpdateCheckbox.state = autoUpdate ? .on : .off

        accentColorWell.color = ToolbarLayout.accentColor
        iconColorWell.color = ToolbarLayout.iconColor
        bgColorWell.color = ToolbarLayout.bgColor

        let historySize = UserDefaults.standard.object(forKey: "historySize") as? Int ?? 10
        historySizeField.integerValue = historySize
        historySizeStepper.integerValue = historySize
        historyUnlimitedCheckbox.state = UserDefaults.standard.bool(forKey: "historyUnlimited") ? .on : .off
        updateHistoryControlsEnabled()

        // Migrate old bool setting to new int: 0=save, 1=copy, 2=both
        if let oldBool = UserDefaults.standard.object(forKey: "quickModeCopyToClipboard") as? Bool {
            let mode = oldBool ? 1 : 0
            // If old autoCopy was on + save mode, migrate to "both"
            let hadAutoCopy = UserDefaults.standard.object(forKey: "autoCopyToClipboard") as? Bool ?? true
            let migratedMode = (!oldBool && hadAutoCopy) ? 2 : mode
            UserDefaults.standard.set(migratedMode, forKey: "quickCaptureMode")
            UserDefaults.standard.removeObject(forKey: "quickModeCopyToClipboard")
            UserDefaults.standard.removeObject(forKey: "autoCopyToClipboard")
        }
        let quickMode = UserDefaults.standard.object(forKey: "quickCaptureMode") as? Int ?? 1
        quickModePopup.selectItem(at: quickMode)
        quickCaptureOpenEditorCheckbox.state = UserDefaults.standard.bool(forKey: "quickCaptureOpenEditor") ? .on : .off

        let format = ImageEncoder.format
        switch format {
        case .png:  imageFormatPopup.selectItem(at: 0)
        case .jpeg: imageFormatPopup.selectItem(at: 1)
        case .heic: imageFormatPopup.selectItem(at: 2)
        case .webp: imageFormatPopup.selectItem(at: 3)
        }

        let quality = Int(ImageEncoder.quality * 100)
        qualitySlider.integerValue = quality
        qualityLabel.stringValue = String(format: L("%d%%"), quality)

        downscaleRetinaCheckbox.state = ImageEncoder.downscaleRetina ? .on : .off
        updateQualityVisibility()

        imgbbKeyField.stringValue = UserDefaults.standard.string(forKey: "imgbbAPIKey") ?? ""

        selectTranslationEngine(TranslationService.provider)
        aiBaseURLField.stringValue = TranslationService.aiBaseURL
        aiAPIKeyField.stringValue = TranslationService.aiAPIKey
        aiModelField.stringValue = TranslationService.aiModel
        aiPromptField.stringValue = TranslationService.aiPrompt
        updateAITranslationControlsEnabled()

        // Recording
        let recFPS = UserDefaults.standard.integer(forKey: "recordingFPS")
        let mp4Options = [15, 24, 30, 60, 120]
        let fpsIdx = mp4Options.firstIndex(of: recFPS) ?? 2
        recordingFPSPopup.selectItem(at: fpsIdx)

        let onStop = UserDefaults.standard.string(forKey: "recordingOnStop") ?? "editor"
        switch onStop {
        case "finder": recordingOnStopPopup.selectItem(at: 1)
        case "clipboard": recordingOnStopPopup.selectItem(at: 2)
        default: recordingOnStopPopup.selectItem(at: 0)
        }

        recSavePathField.stringValue = SaveDirectoryAccess.recordingDisplayPath

        // Webcam
        let webcamPos = UserDefaults.standard.string(forKey: "webcamPosition") ?? "bottomRight"
        switch webcamPos {
        case "bottomRight": webcamPositionPopup.selectItem(at: 0)
        case "bottomLeft": webcamPositionPopup.selectItem(at: 1)
        case "topRight": webcamPositionPopup.selectItem(at: 2)
        case "topLeft": webcamPositionPopup.selectItem(at: 3)
        default: webcamPositionPopup.selectItem(at: 0)
        }

        let webcamSize = UserDefaults.standard.string(forKey: "webcamSize") ?? "medium"
        switch webcamSize {
        case "small": webcamSizePopup.selectItem(at: 0)
        case "medium": webcamSizePopup.selectItem(at: 1)
        case "large": webcamSizePopup.selectItem(at: 2)
        default: webcamSizePopup.selectItem(at: 1)
        }

        webcamShapePopup.selectItem(at: (UserDefaults.standard.string(forKey: "webcamShape") ?? "circle") == "roundedRect" ? 1 : 0)

        // Scroll Capture
        let autoScroll = UserDefaults.standard.object(forKey: "scrollAutoScrollEnabled") as? Bool ?? false
        scrollAutoScrollCheckbox.state = autoScroll ? .on : .off
        let speed = UserDefaults.standard.object(forKey: "scrollAutoScrollSpeed") as? Int ?? 3
        scrollSpeedPopup.selectItem(at: max(0, min(3, speed - 1)))
        scrollSpeedPopup.isEnabled = autoScroll
        let maxH = UserDefaults.standard.object(forKey: "scrollMaxHeight") as? Int ?? 30000
        scrollMaxHeightField.integerValue = maxH
        scrollMaxHeightStepper.integerValue = maxH
        let frozenDetect = UserDefaults.standard.object(forKey: "scrollFrozenDetection") as? Bool ?? true
        scrollFrozenDetectionCheckbox.state = frozenDetect ? .on : .off
    }

    func updateQualityVisibility() {
        let hasQuality = imageFormatPopup.indexOfSelectedItem >= 1  // JPEG or HEIC
        qualitySlider.isEnabled = hasQuality
        qualityLabel.textColor = hasQuality ? .labelColor : .tertiaryLabelColor
        qualityRowLabel.textColor = hasQuality ? .labelColor : .tertiaryLabelColor
    }

}
