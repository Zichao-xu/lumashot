import Cocoa
import Carbon
import ServiceManagement
import ScreenCaptureKit

/// Settings window that intercepts Cmd+Q to close itself instead of quitting the app.
private class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.keyCode == 12 {  // Q
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

class SettingsWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {

    // Info popovers (used by SettingsWindowController+ThemePresets) — stored
    // properties must live on the class, not in an extension.
    var urlSchemeInfoPopover: NSPopover?
    var filenameTemplateInfoPopover: NSPopover?

    // MARK: - Toolbar tab definitions
    struct TabDef {
        let id: String
        let label: String
        let symbolName: String
        let legacyImageName: String  // fallback for older macOS if needed
    }
    static let tabDefs: [TabDef] = [
        TabDef(id: "general",   label: "General",   symbolName: "gearshape",                 legacyImageName: NSImage.preferencesGeneralName),
        TabDef(id: "capture",   label: "Capture",   symbolName: "camera.viewfinder",         legacyImageName: NSImage.preferencesGeneralName),
        TabDef(id: "shortcuts", label: "Shortcuts", symbolName: "keyboard",                  legacyImageName: NSImage.preferencesGeneralName),
        TabDef(id: "tools",     label: "Tools",     symbolName: "paintbrush",                legacyImageName: NSImage.preferencesGeneralName),
        TabDef(id: "recording", label: "Recording", symbolName: "record.circle",             legacyImageName: NSImage.preferencesGeneralName),
        TabDef(id: "uploads",   label: "Uploads",   symbolName: "icloud.and.arrow.up",       legacyImageName: NSImage.preferencesGeneralName),
        TabDef(id: "about",     label: "About",     symbolName: "info.circle",               legacyImageName: NSImage.preferencesGeneralName),
    ]

    var tabContentContainer: NSView!
    var tabContentViews: [String: NSView] = [:]
    var currentTabID: String = "general"


    var hotkeyFields: [HotkeyManager.HotkeySlot: NSTextField] = [:]
    var hotkeyButtons: [HotkeyManager.HotkeySlot: NSButton] = [:]
    var recordingSlot: HotkeyManager.HotkeySlot?
    var toolShortcutFields: [ToolShortcutManager.Action: NSTextField] = [:]
    var toolShortcutButtons: [ToolShortcutManager.Action: NSButton] = [:]
    var recordingToolAction: ToolShortcutManager.Action?
    var savePathField: NSTextField!
    var ocrActionPopup: NSPopUpButton!
    var copySoundCheckbox: NSButton!
    // rememberSelectionCheckbox removed — selection is always saved for "Capture Last Area"
    var rememberToolCheckbox: NSButton!
    var thumbnailCheckbox: NSButton!
    var thumbnailAutoDismissStepper: NSStepper!
    var thumbnailAutoDismissField: NSTextField!
    var thumbnailStackingPopup: NSPopUpButton!
    var historyUnlimitedCheckbox: NSButton!
    var thumbnailScaleLabel: NSTextField!
    var launchAtLoginCheckbox: NSButton!
    var hideMenuBarIconCheckbox: NSButton!
    var historySizeField: NSTextField!
    var historySizeStepper: NSStepper!
    var snapGuidesCheckbox: NSButton!
    var captureCursorCheckbox: NSButton!
    var filenameTemplateField: NSTextField!
    var filenameTemplatePreview: NSTextField!
    var recordingFilenameTemplateField: NSTextField!
    var recordingFilenameTemplatePreview: NSTextField!
    var autoUpdateCheckbox: NSButton!
    var accentColorWell: NSColorWell!
    var iconColorWell: NSColorWell!
    var bgColorWell: NSColorWell!
    var themePresetPopup: NSPopUpButton!
    var quickModePopup: NSPopUpButton!
    var quickCaptureOpenEditorCheckbox: NSButton!
    var imageFormatPopup: NSPopUpButton!
    var qualitySlider: NSSlider!
    var qualityLabel: NSTextField!
    var qualityRowLabel: NSTextField!
    var downscaleRetinaCheckbox: NSButton!
    // embedColorProfileCheckbox removed — native color profile is always embedded
    var imgbbKeyField: NSTextField!
    var localMonitor: Any?
    weak var uploadsStack: NSStackView?
    var providerPopup: NSPopUpButton!
    var translationEnginePopup: NSPopUpButton!
    var aiBaseURLField: NSTextField!
    var aiAPIKeyField: NSSecureTextField!
    var aiModelField: NSTextField!
    var aiPromptField: NSTextField!
    var localModelStatusLabel: NSTextField!
    var localModelActionButton: NSButton!
    var localModelProgressIndicator: NSProgressIndicator!
    var localModelObserver: NSObjectProtocol?
    var gdriveSignInBtn: NSButton!
    var gdriveStatusLabel: NSTextField!
    // S3 tab controls
    var s3EndpointField: NSTextField!
    var s3RegionField: NSTextField!
    var s3BucketField: NSTextField!
    var s3AccessKeyField: NSTextField!
    var s3SecretKeyField: NSSecureTextField!
    var s3PublicURLField: NSTextField!
    var s3PathPrefixField: NSTextField!
    var s3TestBtn: NSButton!
    var s3StatusLabel: NSTextField!
    // Recording tab controls
    var recordingFPSPopup: NSPopUpButton!
    var recordingOnStopPopup: NSPopUpButton!
    var recSavePathField: NSTextField!
    // Webcam controls
    var webcamPositionPopup: NSPopUpButton!
    var webcamSizePopup: NSPopUpButton!
    var webcamShapePopup: NSPopUpButton!
    // Scroll capture controls
    var scrollAutoScrollCheckbox: NSButton!
    var scrollSpeedPopup: NSPopUpButton!
    var scrollMaxHeightField: NSTextField!
    var scrollMaxHeightStepper: NSStepper!
    var scrollFrozenDetectionCheckbox: NSButton!
    var languagePopup: NSPopUpButton!

    var onHotkeyChanged: (() -> Void)?

    init() {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("Lumashot Settings")
        window.center()
        window.isReleasedWhenClosed = false
        // Window is non-resizable (no .resizable in styleMask), so content size
        // is locked. We also set the content size explicitly after the toolbar
        // is installed (in setupUI) to override NSToolbar's auto-sizing.
        super.init(window: window)
        window.delegate = self
        setupUI()
        loadSettings()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let observer = localModelObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Top-level layout

    func setupUI() {
        guard let window = window, let cv = window.contentView else { return }

        // Toolbar (preference style — icon + label, Shottr-like)
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .preference
        }
        window.toolbar = toolbar
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier("general")
        // Re-apply content size after toolbar install, since NSToolbar can
        // resize the window to fit its items.
        //
        // Width went from 560 → 620 to accommodate longer translated
        // strings (issue #130 — Polish "Szybkie przechwycenie:" + the
        // "Automatycznie zamazuj dane wrażliwe" checkbox both overflowed
        // the old layout). The extra 60pt flows evenly across the two
        // toggle-grid columns so Polish/German/Dutch labels fit on one
        // line instead of wrapping.
        window.setContentSize(NSSize(width: 620, height: 520))

        // Build all tab content views up front (preserves existing behavior — nothing lazy-created)
        tabContentViews["general"]   = makeGeneralTabView()
        tabContentViews["capture"]   = makeCaptureTabView()
        tabContentViews["shortcuts"] = makeShortcutsTabView()
        tabContentViews["tools"]     = makeToolsTabView()
        tabContentViews["recording"] = makeRecordingTabView()
        tabContentViews["uploads"]   = makeUploadsTabView()
        tabContentViews["about"]     = makeAboutTabView()

        // Container that swaps content views
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        tabContentContainer = container

        // Footer separator
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false

        // Footer labels
        let madeBy = NSTextField(labelWithString: "Based on upstream macshot by sw33tLie")
        madeBy.font = NSFont.systemFont(ofSize: 11)
        madeBy.textColor = .secondaryLabelColor
        madeBy.translatesAutoresizingMaskIntoConstraints = false

        let linkBtn = NSButton(title: "github.com/Zichao-xu/lumashot", target: self, action: #selector(openGitHub))
        linkBtn.bezelStyle = .inline
        linkBtn.isBordered = false
        linkBtn.font = NSFont.systemFont(ofSize: 11)
        linkBtn.attributedTitle = NSAttributedString(string: "github.com/Zichao-xu/lumashot", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        linkBtn.translatesAutoresizingMaskIntoConstraints = false

        let footerStack = NSStackView(views: [madeBy, NSView(), linkBtn])
        footerStack.orientation = .horizontal
        footerStack.spacing = 0
        footerStack.translatesAutoresizingMaskIntoConstraints = false

        cv.addSubview(container)
        cv.addSubview(sep)
        cv.addSubview(footerStack)

        NSLayoutConstraint.activate([
            // Content container fills above the footer
            container.topAnchor.constraint(equalTo: cv.topAnchor),
            container.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: sep.topAnchor),

            // Footer separator
            sep.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -6),
            sep.heightAnchor.constraint(equalToConstant: 1),

            // Footer
            footerStack.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            footerStack.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),
            footerStack.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -8),
            footerStack.heightAnchor.constraint(equalToConstant: 20),
        ])

        // Show initial tab
        showTab(id: "general")
    }

    func showTab(id: String) {
        guard let container = tabContentContainer, let view = tabContentViews[id] else { return }
        // Remove existing content
        for sub in container.subviews { sub.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        currentTabID = id
        window?.title = "\(L("Lumashot Settings")) — \(L(Self.tabDefs.first(where: { $0.id == id })?.label ?? ""))"
        if id == "uploads" {
            reloadUploadsTab()
        }
    }

    @objc func toolbarTabSelected(_ sender: NSToolbarItem) {
        showTab(id: sender.itemIdentifier.rawValue)
    }

}

// MARK: - NSTextFieldDelegate (live filename preview)

extension SettingsWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === filenameTemplateField {
            // Save on every keystroke so closing the window without pressing
            // Enter doesn't silently lose the edit. Empty value resets to
            // the default template at commit time (see controlTextDidEndEditing).
            UserDefaults.standard.set(field.stringValue, forKey: FilenameFormatter.userDefaultsKey)
            updateFilenamePreview()
        } else if field === recordingFilenameTemplateField {
            UserDefaults.standard.set(field.stringValue, forKey: FilenameFormatter.recordingUserDefaultsKey)
            updateRecordingFilenamePreview()
        } else if field === aiBaseURLField || field === aiAPIKeyField || field === aiModelField || field === aiPromptField {
            saveAITranslationSettings()
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // On commit, replace empty/whitespace-only values with the default so
        // the user never ends up with a blank template saved.
        guard let field = obj.object as? NSTextField else { return }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if field === filenameTemplateField, trimmed.isEmpty {
            field.stringValue = FilenameFormatter.defaultTemplate
            UserDefaults.standard.set(FilenameFormatter.defaultTemplate, forKey: FilenameFormatter.userDefaultsKey)
            updateFilenamePreview()
        } else if field === recordingFilenameTemplateField, trimmed.isEmpty {
            field.stringValue = FilenameFormatter.defaultRecordingTemplate
            UserDefaults.standard.set(FilenameFormatter.defaultRecordingTemplate, forKey: FilenameFormatter.recordingUserDefaultsKey)
            updateRecordingFilenamePreview()
        }
    }
}

// MARK: - Filename template info popover

extension SettingsWindowController {
    func showFilenameTemplateInfoPopover(near sourceView: NSView) {
        if let existing = filenameTemplateInfoPopover, existing.isShown { return }

        let tokens: [(String, String)] = [
            ("{date}",      "2026-04-17"),
            ("{time}",      "14-22-05"),
            ("{timestamp}", "2026-04-17_14-22-05"),
            ("{unix}",      "1745592125"),
            ("{window}",    L("Screenshots only — captured window title (blank otherwise)")),
            ("{index}",     L("Counter for multi-screen captures")),
            ("{random}",    L("8-character random string (e.g. k3j7x9q2)")),
        ]

        let title = NSTextField(labelWithString: L("Filename Template Tokens"))
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(wrappingLabelWithString: L("The file extension is appended automatically. Slashes and colons in {window} become dashes."))
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.preferredMaxLayoutWidth = 380
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let grid = NSGridView(numberOfColumns: 2, rows: tokens.count)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 4
        grid.columnSpacing = 16
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .leading

        for (i, entry) in tokens.enumerated() {
            let tok = NSTextField(labelWithString: entry.0)
            tok.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            tok.textColor = .labelColor
            tok.isSelectable = true

            let desc = NSTextField(labelWithString: entry.1)
            desc.font = NSFont.systemFont(ofSize: 11)
            desc.textColor = .secondaryLabelColor

            grid.cell(atColumnIndex: 0, rowIndex: i).contentView = tok
            grid.cell(atColumnIndex: 1, rowIndex: i).contentView = desc
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
        container.layoutSubtreeIfNeeded()
        vc.preferredContentSize = container.fittingSize

        let popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
        filenameTemplateInfoPopover = popover
    }
}
