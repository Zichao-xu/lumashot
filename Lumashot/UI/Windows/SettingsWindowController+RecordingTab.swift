import Cocoa
import Carbon
import ServiceManagement
import ScreenCaptureKit

extension SettingsWindowController {
    // MARK: - Recording Tab

    func makeRecordingTabView() -> NSView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 16, right: 20)

        // ── Output ────────────────────────────────────────────
        stack.addArrangedSubview(sectionHeader(L("Output")))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        recordingFPSPopup = NSPopUpButton()
        recordingFPSPopup.addItems(withTitles: [L("15 fps"), L("24 fps"), L("30 fps"), L("60 fps"), L("120 fps")])
        recordingFPSPopup.target = self
        recordingFPSPopup.action = #selector(recordingFPSChanged(_:))
        stack.addArrangedSubview(labeledRow(L("Frame rate:"), controls: [recordingFPSPopup]))
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)

        recSavePathField = NSTextField()
        recSavePathField.isEditable = false
        recSavePathField.isSelectable = false
        recSavePathField.lineBreakMode = .byTruncatingMiddle

        let recBrowseBtn = NSButton(title: L("Browse…"), target: self, action: #selector(browseRecSavePath(_:)))
        recBrowseBtn.bezelStyle = .rounded
        let recClearBtn = NSButton(title: L("Clear"), target: self, action: #selector(clearRecSavePath(_:)))
        recClearBtn.bezelStyle = .rounded

        stack.addArrangedSubview(labeledRow(L("Save folder:"), controls: [recSavePathField, recBrowseBtn, recClearBtn]))
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)

        // Recording filename template
        recordingFilenameTemplateField = NSTextField()
        recordingFilenameTemplateField.placeholderString = FilenameFormatter.defaultRecordingTemplate
        recordingFilenameTemplateField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        recordingFilenameTemplateField.stringValue = UserDefaults.standard.string(forKey: FilenameFormatter.recordingUserDefaultsKey) ?? FilenameFormatter.defaultRecordingTemplate
        recordingFilenameTemplateField.target = self
        recordingFilenameTemplateField.action = #selector(recordingFilenameTemplateCommitted(_:))
        recordingFilenameTemplateField.delegate = self
        recordingFilenameTemplateField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        recordingFilenameTemplatePreview = NSTextField(labelWithString: "")
        recordingFilenameTemplatePreview.font = NSFont.systemFont(ofSize: 10)
        recordingFilenameTemplatePreview.textColor = .secondaryLabelColor
        recordingFilenameTemplatePreview.lineBreakMode = .byTruncatingMiddle

        let recFilenameResetBtn = NSButton(title: L("Reset"), target: self, action: #selector(recordingFilenameTemplateReset(_:)))
        recFilenameResetBtn.bezelStyle = .rounded

        let recFilenameInfoIcon = HoverPopoverIconView(
            image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: L("Filename tokens")),
            tintColor: .secondaryLabelColor,
            toolTip: L("Show available filename tokens")
        )
        recFilenameInfoIcon.onHover = { [weak self] sourceView, shown in
            if shown { self?.showFilenameTemplateInfoPopover(near: sourceView) }
        }

        stack.addArrangedSubview(labeledRow(L("Filename:"), controls: [recordingFilenameTemplateField, recFilenameInfoIcon, recFilenameResetBtn]))
        stack.setCustomSpacing(2, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(indented(recordingFilenameTemplatePreview))
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)
        updateRecordingFilenamePreview()

        // ── Behavior ──────────────────────────────────────────
        stack.addArrangedSubview(sectionHeader(L("Behavior")))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        recordingOnStopPopup = NSPopUpButton()
        recordingOnStopPopup.addItems(withTitles: [L("Open editor"), L("Show in Finder"), L("Copy to clipboard")])
        recordingOnStopPopup.target = self
        recordingOnStopPopup.action = #selector(recordingOnStopChanged(_:))
        stack.addArrangedSubview(labeledRow(L("When done:"), controls: [recordingOnStopPopup]))
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)

        let hideHUDCheckbox = NSButton(checkboxWithTitle: L("Hide recording controls"), target: self, action: #selector(hideRecordingHUDChanged(_:)))
        hideHUDCheckbox.state = UserDefaults.standard.bool(forKey: "hideRecordingHUD") ? .on : .off
        stack.addArrangedSubview(indented(hideHUDCheckbox))

        let hideHUDNote = NSTextField(labelWithString: L("Stop recording from the menu bar icon instead."))
        hideHUDNote.font = NSFont.systemFont(ofSize: 10)
        hideHUDNote.textColor = .secondaryLabelColor
        stack.addArrangedSubview(indented(hideHUDNote))
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        // ── Webcam ───────────────────────────────────────────
        stack.addArrangedSubview(sectionHeader(L("Webcam")))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        webcamPositionPopup = NSPopUpButton()
        webcamPositionPopup.addItems(withTitles: [L("Bottom Right"), L("Bottom Left"), L("Top Right"), L("Top Left")])
        webcamPositionPopup.target = self
        webcamPositionPopup.action = #selector(webcamPositionChanged(_:))
        stack.addArrangedSubview(labeledRow(L("Position:"), controls: [webcamPositionPopup]))
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)

        webcamSizePopup = NSPopUpButton()
        webcamSizePopup.addItems(withTitles: [L("Small"), L("Medium"), L("Large")])
        webcamSizePopup.target = self
        webcamSizePopup.action = #selector(webcamSizeChanged(_:))
        stack.addArrangedSubview(labeledRow(L("Size:"), controls: [webcamSizePopup]))
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)

        webcamShapePopup = NSPopUpButton()
        webcamShapePopup.addItems(withTitles: [L("Circle"), L("Rounded Rectangle")])
        webcamShapePopup.target = self
        webcamShapePopup.action = #selector(webcamShapeChanged(_:))
        stack.addArrangedSubview(labeledRow(L("Shape:"), controls: [webcamShapePopup]))
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        // ── Scroll Capture ────────────────────────────────────
        stack.addArrangedSubview(sectionHeader(L("Scroll Capture")))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        scrollAutoScrollCheckbox = NSButton(checkboxWithTitle: L("Auto-scroll (sends synthetic scroll events)"),
                                            target: self, action: #selector(scrollAutoScrollChanged(_:)))
        stack.addArrangedSubview(scrollAutoScrollCheckbox)
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)

        scrollSpeedPopup = NSPopUpButton()
        scrollSpeedPopup.addItems(withTitles: [L("Slow"), L("Medium"), L("Fast"), L("Very fast")])
        scrollSpeedPopup.target = self
        scrollSpeedPopup.action = #selector(scrollSpeedChanged(_:))
        stack.addArrangedSubview(labeledRow(L("Scroll speed:"), controls: [scrollSpeedPopup]))
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)

        scrollMaxHeightField = NSTextField()
        scrollMaxHeightField.isEditable = false
        scrollMaxHeightField.isSelectable = false
        scrollMaxHeightField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        scrollMaxHeightField.translatesAutoresizingMaskIntoConstraints = false
        scrollMaxHeightField.widthAnchor.constraint(equalToConstant: 60).isActive = true

        scrollMaxHeightStepper = NSStepper()
        scrollMaxHeightStepper.minValue = 0
        scrollMaxHeightStepper.maxValue = 100000
        scrollMaxHeightStepper.increment = 5000
        scrollMaxHeightStepper.valueWraps = false
        scrollMaxHeightStepper.target = self
        scrollMaxHeightStepper.action = #selector(scrollMaxHeightChanged(_:))

        let maxHeightNote = NSTextField(labelWithString: L("px (0 = unlimited)"))
        maxHeightNote.font = .systemFont(ofSize: 11)
        maxHeightNote.textColor = .secondaryLabelColor
        stack.addArrangedSubview(labeledRow(L("Max height:"), controls: [scrollMaxHeightField, scrollMaxHeightStepper, maxHeightNote]))
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)

        scrollFrozenDetectionCheckbox = NSButton(checkboxWithTitle: L("Detect fixed/sticky headers"),
                                                 target: self, action: #selector(scrollFrozenDetectionChanged(_:)))
        stack.addArrangedSubview(scrollFrozenDetectionCheckbox)
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        // Spacer to absorb remaining height, keeping content pinned to top
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.fittingSizeCompression, for: .vertical)
        stack.addArrangedSubview(spacer)

        let clipView = scroll.contentView
        scroll.documentView = stack

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: clipView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            stack.heightAnchor.constraint(greaterThanOrEqualTo: clipView.heightAnchor),
        ])

        return scroll
    }

}
