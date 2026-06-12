import Cocoa
import Carbon
import ServiceManagement
import ScreenCaptureKit

extension SettingsWindowController {
    // MARK: - Capture Tab

    func makeCaptureTabView() -> NSView {
        let (scroll, stack) = makeSettingsScrollStack()

        // ── Capture ──────────────────────────────────────────
        stack.addArrangedSubview(sectionHeader(L("Capture")))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        // Quick Capture action
        quickModePopup = NSPopUpButton()
        quickModePopup.addItems(withTitles: [L("Save to file"), L("Copy to clipboard"), L("Save + copy to clipboard"), L("Do nothing")])
        quickModePopup.target = self
        quickModePopup.action = #selector(quickModeChanged(_:))

        stack.addArrangedSubview(labeledRow("\(L("Quick Capture")):", controls: [quickModePopup]))
        stack.setCustomSpacing(6, after: stack.arrangedSubviews.last!)

        quickCaptureOpenEditorCheckbox = NSButton(checkboxWithTitle: L("Also open in Editor"), target: self, action: #selector(quickCaptureOpenEditorChanged(_:)))
        stack.addArrangedSubview(indented(quickCaptureOpenEditorCheckbox))
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)

        // OCR action dropdown
        ocrActionPopup = NSPopUpButton()
        ocrActionPopup.addItems(withTitles: [
            L("Show window + copy to clipboard"),
            L("Show window only"),
            L("Copy to clipboard only"),
        ])
        ocrActionPopup.target = self
        ocrActionPopup.action = #selector(ocrActionChanged(_:))

        stack.addArrangedSubview(labeledRow(L("OCR Capture:"), controls: [ocrActionPopup]))
        stack.setCustomSpacing(12, after: stack.arrangedSubviews.last!)

        // Checkboxes
        copySoundCheckbox = NSButton(checkboxWithTitle: L("Play sound on capture"), target: self, action: #selector(copySoundChanged(_:)))
        rememberToolCheckbox = NSButton(checkboxWithTitle: L("Remember last selected tool"), target: self, action: #selector(rememberToolChanged(_:)))
        thumbnailCheckbox = NSButton(checkboxWithTitle: L("Show floating thumbnail after capture"), target: self, action: #selector(thumbnailChanged(_:)))
        snapGuidesCheckbox = NSButton(checkboxWithTitle: L("Show snap alignment guides"), target: self, action: #selector(snapGuidesChanged(_:)))
        captureCursorCheckbox = NSButton(checkboxWithTitle: L("Capture mouse cursor in screenshot"), target: self, action: #selector(captureCursorChanged(_:)))
        filenameTemplateField = NSTextField()
        filenameTemplateField.placeholderString = FilenameFormatter.defaultTemplate
        filenameTemplateField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        filenameTemplateField.stringValue = UserDefaults.standard.string(forKey: FilenameFormatter.userDefaultsKey) ?? FilenameFormatter.defaultTemplate
        filenameTemplateField.target = self
        filenameTemplateField.action = #selector(filenameTemplateCommitted(_:))
        filenameTemplateField.delegate = self
        filenameTemplateField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        filenameTemplatePreview = NSTextField(labelWithString: "")
        filenameTemplatePreview.font = NSFont.systemFont(ofSize: 10)
        filenameTemplatePreview.textColor = .secondaryLabelColor
        filenameTemplatePreview.lineBreakMode = .byTruncatingMiddle

        for cb in [copySoundCheckbox!, rememberToolCheckbox!, thumbnailCheckbox!] {
            stack.addArrangedSubview(indented(cb))
            stack.setCustomSpacing(6, after: stack.arrangedSubviews.last!)
        }

        // Thumbnail auto-dismiss stepper
        thumbnailAutoDismissField = NSTextField()
        thumbnailAutoDismissField.isEditable = false
        thumbnailAutoDismissField.isSelectable = false
        thumbnailAutoDismissField.alignment = .center
        thumbnailAutoDismissField.widthAnchor.constraint(equalToConstant: 40).isActive = true

        thumbnailAutoDismissStepper = NSStepper()
        thumbnailAutoDismissStepper.minValue = 0
        thumbnailAutoDismissStepper.maxValue = 60
        thumbnailAutoDismissStepper.increment = 1
        thumbnailAutoDismissStepper.target = self
        thumbnailAutoDismissStepper.action = #selector(thumbnailAutoDismissChanged(_:))

        let dismissNote = NSTextField(labelWithString: L("sec (0 = never)"))
        dismissNote.font = NSFont.systemFont(ofSize: 11)
        dismissNote.textColor = .secondaryLabelColor

        stack.addArrangedSubview(indented(labeledRow(L("  Dismiss after:"), controls: [thumbnailAutoDismissField!, thumbnailAutoDismissStepper!, dismissNote])))
        stack.setCustomSpacing(6, after: stack.arrangedSubviews.last!)

        // Thumbnail stacking popup
        thumbnailStackingPopup = NSPopUpButton()
        thumbnailStackingPopup.addItems(withTitles: [L("Stack (keep all)"), L("Replace (show only latest)")])
        thumbnailStackingPopup.target = self
        thumbnailStackingPopup.action = #selector(thumbnailStackingChanged(_:))

        stack.addArrangedSubview(indented(labeledRow(L("  Multiple previews:"), controls: [thumbnailStackingPopup!])))
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)

        let sizeSlider = NSSlider(value: UserDefaults.standard.object(forKey: "thumbnailScale") as? Double ?? 1.0,
                                   minValue: 0.5, maxValue: 2.0, target: self, action: #selector(thumbnailScaleChanged(_:)))
        sizeSlider.controlSize = .small
        sizeSlider.widthAnchor.constraint(equalToConstant: 120).isActive = true
        thumbnailScaleLabel = NSTextField(labelWithString: scalePercentString(sizeSlider.doubleValue))
        thumbnailScaleLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        thumbnailScaleLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(indented(labeledRow(L("  Preview size:"), controls: [sizeSlider, thumbnailScaleLabel])))
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)

        stack.addArrangedSubview(indented(snapGuidesCheckbox))
        stack.setCustomSpacing(6, after: stack.arrangedSubviews.last!)

        stack.addArrangedSubview(indented(captureCursorCheckbox))
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        // ── Output ───────────────────────────────────────────
        stack.addArrangedSubview(sectionHeader(L("Output")))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        // Save folder
        savePathField = NSTextField()
        savePathField.isEditable = false
        savePathField.isSelectable = false
        savePathField.lineBreakMode = .byTruncatingMiddle

        let browseBtn = NSButton(title: L("Browse…"), target: self, action: #selector(browseSavePath(_:)))
        browseBtn.bezelStyle = .rounded

        stack.addArrangedSubview(labeledRow(L("Save folder:"), controls: [savePathField, browseBtn]))
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)

        // Filename template
        let filenameResetBtn = NSButton(title: L("Reset"), target: self, action: #selector(filenameTemplateReset(_:)))
        filenameResetBtn.bezelStyle = .rounded

        let filenameInfoIcon = HoverPopoverIconView(
            image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: L("Filename tokens")),
            tintColor: .secondaryLabelColor,
            toolTip: L("Show available filename tokens")
        )
        filenameInfoIcon.onHover = { [weak self] sourceView, shown in
            if shown { self?.showFilenameTemplateInfoPopover(near: sourceView) }
        }

        stack.addArrangedSubview(labeledRow(L("Filename:"), controls: [filenameTemplateField, filenameInfoIcon, filenameResetBtn]))
        stack.setCustomSpacing(2, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(indented(filenameTemplatePreview))
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)
        updateFilenamePreview()

        // Image format
        imageFormatPopup = NSPopUpButton()
        imageFormatPopup.addItems(withTitles: ["PNG", "JPEG", "HEIC", "WebP"])
        imageFormatPopup.target = self
        imageFormatPopup.action = #selector(imageFormatChanged(_:))

        stack.addArrangedSubview(labeledRow(L("Image format:"), controls: [imageFormatPopup]))
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)

        // Quality (applies to JPEG and HEIC)
        qualitySlider = NSSlider()
        qualitySlider.minValue = 10
        qualitySlider.maxValue = 100
        qualitySlider.target = self
        qualitySlider.action = #selector(qualityChanged(_:))
        qualitySlider.widthAnchor.constraint(equalToConstant: 160).isActive = true

        qualityLabel = NSTextField(labelWithString: String(format: L("%d%%"), 85))
        qualityLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        qualityLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true

        qualityRowLabel = NSTextField(labelWithString: L("Quality:"))
        qualityRowLabel.font = NSFont.systemFont(ofSize: 13)
        qualityRowLabel.alignment = .right
        qualityRowLabel.translatesAutoresizingMaskIntoConstraints = false
        qualityRowLabel.widthAnchor.constraint(equalToConstant: 140).isActive = true

        let qualityRow = NSStackView(views: [qualityRowLabel, qualitySlider, qualityLabel])
        qualityRow.orientation = .horizontal
        qualityRow.spacing = 8
        qualityRow.alignment = .centerY
        qualityRow.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(qualityRow)
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)

        // Downscale Retina
        downscaleRetinaCheckbox = NSButton(checkboxWithTitle: L("Save at standard resolution (1x)"), target: self, action: #selector(downscaleRetinaChanged(_:)))
        stack.addArrangedSubview(indented(downscaleRetinaCheckbox))
        stack.setCustomSpacing(2, after: stack.arrangedSubviews.last!)

        let downscaleNote = NSTextField(labelWithString: L("Halves dimensions on Retina displays, ~4x smaller files"))
        downscaleNote.font = NSFont.systemFont(ofSize: 10)
        downscaleNote.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(indented(downscaleNote))
        stack.setCustomSpacing(6, after: stack.arrangedSubviews.last!)

        // Color profile is always embedded (native display profile) — no toggle needed.

        // History size
        historySizeField = NSTextField()
        historySizeField.isEditable = false
        historySizeField.isSelectable = false
        historySizeField.alignment = .center
        historySizeField.widthAnchor.constraint(equalToConstant: 40).isActive = true

        historySizeStepper = NSStepper()
        historySizeStepper.minValue = 0
        historySizeStepper.maxValue = 50
        historySizeStepper.increment = 1
        historySizeStepper.target = self
        historySizeStepper.action = #selector(historySizeChanged(_:))

        historyUnlimitedCheckbox = NSButton(checkboxWithTitle: L("Unlimited"), target: self, action: #selector(historyUnlimitedChanged(_:)))
        historyUnlimitedCheckbox.font = NSFont.systemFont(ofSize: 11)

        let histNote = NSTextField(labelWithString: L("(0 = off)"))
        histNote.font = NSFont.systemFont(ofSize: 11)
        histNote.textColor = .secondaryLabelColor

        stack.addArrangedSubview(labeledRow(L("History size:"), controls: [historySizeField, historySizeStepper, histNote, historyUnlimitedCheckbox]))
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        // ── Translation ──────────────────────────────────────
        stack.addArrangedSubview(sectionHeader(L("Translation")))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        translationEnginePopup = NSPopUpButton()
        if TranslationService.appleTranslationAvailable {
            addTranslationEngineItem(title: L("Apple (on-device)"), provider: .apple)
        }
        addTranslationEngineItem(title: L("Google Translate"), provider: .google)
        addTranslationEngineItem(title: L("AI Model (OpenAI-compatible)"), provider: .ai)
        addTranslationEngineItem(title: L("Local Model"), provider: .local)
        selectTranslationEngine(TranslationService.provider)
        translationEnginePopup.target = self
        translationEnginePopup.action = #selector(translationProviderChanged(_:))
        stack.addArrangedSubview(labeledRow(L("Engine:"), controls: [translationEnginePopup]))
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)

        let providerNote = NSTextField(wrappingLabelWithString: L("Apple works offline when language packs are installed. Google is quick. AI Model uses an OpenAI-compatible chat completions endpoint."))
        providerNote.font = NSFont.systemFont(ofSize: 10)
        providerNote.textColor = .secondaryLabelColor
        stack.addArrangedSubview(indented(providerNote))
        stack.setCustomSpacing(6, after: stack.arrangedSubviews.last!)

        if TranslationService.appleTranslationAvailable {
            let downloadLink = NSButton(title: L("Download language packs in System Settings…"), target: self, action: #selector(openTranslationSettings))
            downloadLink.bezelStyle = .inline
            downloadLink.isBordered = false
            downloadLink.contentTintColor = .linkColor
            downloadLink.font = NSFont.systemFont(ofSize: 10)
            stack.addArrangedSubview(indented(downloadLink))
            stack.setCustomSpacing(12, after: stack.arrangedSubviews.last!)
        }

        aiBaseURLField = NSTextField()
        aiBaseURLField.placeholderString = TranslationService.defaultAIBaseURL
        aiBaseURLField.stringValue = TranslationService.aiBaseURL
        aiBaseURLField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        aiBaseURLField.target = self
        aiBaseURLField.action = #selector(aiTranslationFieldChanged(_:))
        aiBaseURLField.delegate = self
        aiBaseURLField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        stack.addArrangedSubview(labeledRow(L("AI Base URL:"), controls: [aiBaseURLField]))
        stack.setCustomSpacing(6, after: stack.arrangedSubviews.last!)

        aiAPIKeyField = NSSecureTextField()
        aiAPIKeyField.placeholderString = L("Optional for local models")
        aiAPIKeyField.stringValue = TranslationService.aiAPIKey
        aiAPIKeyField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        aiAPIKeyField.target = self
        aiAPIKeyField.action = #selector(aiTranslationFieldChanged(_:))
        aiAPIKeyField.delegate = self
        aiAPIKeyField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        let openOpenAIKeysButton = NSButton(title: L("Open API Keys…"), target: self, action: #selector(openOpenAIAPIKeys))
        openOpenAIKeysButton.bezelStyle = .rounded
        stack.addArrangedSubview(labeledRow(L("AI API Key:"), controls: [aiAPIKeyField, openOpenAIKeysButton]))
        stack.setCustomSpacing(6, after: stack.arrangedSubviews.last!)

        aiModelField = NSTextField()
        aiModelField.placeholderString = TranslationService.defaultAIModel
        aiModelField.stringValue = TranslationService.aiModel
        aiModelField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        aiModelField.target = self
        aiModelField.action = #selector(aiTranslationFieldChanged(_:))
        aiModelField.delegate = self
        aiModelField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        stack.addArrangedSubview(labeledRow(L("AI Model:"), controls: [aiModelField]))
        stack.setCustomSpacing(6, after: stack.arrangedSubviews.last!)

        aiPromptField = NSTextField()
        aiPromptField.placeholderString = TranslationService.defaultAIPrompt
        aiPromptField.stringValue = TranslationService.aiPrompt
        aiPromptField.target = self
        aiPromptField.action = #selector(aiTranslationFieldChanged(_:))
        aiPromptField.delegate = self
        aiPromptField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        stack.addArrangedSubview(labeledRow(L("AI Prompt:"), controls: [aiPromptField]))
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)

        let aiNote = NSTextField(wrappingLabelWithString: L("API keys are stored in Keychain. Examples: https://api.openai.com/v1, http://localhost:11434/v1, https://api.deepseek.com/v1. The app posts to /chat/completions."))
        aiNote.font = NSFont.systemFont(ofSize: 10)
        aiNote.textColor = .secondaryLabelColor
        stack.addArrangedSubview(indented(aiNote))
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        localModelActionButton = NSButton(title: LocalModelService.shared.installButtonTitle, target: self, action: #selector(localModelAction(_:)))
        localModelActionButton.bezelStyle = .rounded
        stack.addArrangedSubview(labeledRow(L("Local Model:"), controls: [localModelActionButton]))
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)

        localModelProgressIndicator = NSProgressIndicator()
        localModelProgressIndicator.style = .bar
        localModelProgressIndicator.isIndeterminate = false
        localModelProgressIndicator.minValue = 0
        localModelProgressIndicator.maxValue = 100
        localModelProgressIndicator.isHidden = true
        localModelProgressIndicator.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(indented(localModelProgressIndicator))
        NSLayoutConstraint.activate([
            localModelProgressIndicator.widthAnchor.constraint(equalToConstant: 300)
        ])
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)

        localModelStatusLabel = NSTextField(wrappingLabelWithString: LocalModelService.shared.statusText)
        localModelStatusLabel.font = NSFont.systemFont(ofSize: 10)
        localModelStatusLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(indented(localModelStatusLabel))
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        localModelObserver = NotificationCenter.default.addObserver(
            forName: LocalModelService.statusChangedNotification,
            object: LocalModelService.shared,
            queue: .main
        ) { [weak self] _ in
            self?.updateLocalModelControls()
        }

        updateAITranslationControlsEnabled()

        finalizeSettingsStack(scroll: scroll, stack: stack)
        return scroll
    }

}
