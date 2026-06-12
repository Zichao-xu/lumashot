import Cocoa
import Carbon
import ServiceManagement
import ScreenCaptureKit

extension SettingsWindowController {
    // MARK: - General Tab

    /// NSStackView subclass with flipped coordinates so content pins to the top
    /// of its scroll view (default AppKit origin is bottom-left, which would
    /// push short content to the bottom of a tall clip view).
    final class FlippedStackView: NSStackView {
        override var isFlipped: Bool { true }
    }

    /// Small SF Symbol icon that reports hover enter/exit via callback. Used for
    /// hover-to-show info popovers next to settings controls.
    final class HoverPopoverIconView: NSImageView {
        /// Called with (the view, true) on hover enter and (view, false) on exit.
        var onHover: ((NSView, Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        init(image: NSImage?, tintColor: NSColor, toolTip: String?) {
            super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
            self.image = image
            self.contentTintColor = tintColor
            self.toolTip = toolTip
            self.imageScaling = .scaleProportionallyDown
            self.translatesAutoresizingMaskIntoConstraints = false
            self.widthAnchor.constraint(equalToConstant: 16).isActive = true
            self.heightAnchor.constraint(equalToConstant: 16).isActive = true
        }

        required init?(coder: NSCoder) { fatalError() }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingArea { removeTrackingArea(existing) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) { onHover?(self, true) }
        override func mouseExited(with event: NSEvent)  { onHover?(self, false) }
    }

    /// Creates a scrollable vertical stack matching the layout used by all settings tabs.
    func makeSettingsScrollStack() -> (NSScrollView, NSStackView) {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]

        let stack = FlippedStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        return (scroll, stack)
    }

    /// Finalizes a settings tab by wiring the stack into the scroll view.
    func finalizeSettingsStack(scroll: NSScrollView, stack: NSStackView) {
        let clipView = scroll.contentView
        scroll.documentView = stack

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: clipView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            // no bottom constraint — stack grows to fit content, scroll handles overflow
        ])
    }

    func makeGeneralTabView() -> NSView {
        let (scroll, stack) = makeSettingsScrollStack()

        // ── Language ──────────────────────────────────────────
        stack.addArrangedSubview(sectionHeader(L("Language")))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        languagePopup = NSPopUpButton()
        for lang in LanguageManager.availableLanguages {
            languagePopup.addItem(withTitle: lang.name)
        }
        let currentLang = LanguageManager.shared.currentLanguage
        if let idx = LanguageManager.availableLanguages.firstIndex(where: { $0.code == currentLang }) {
            languagePopup.selectItem(at: idx)
        }
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))

        stack.addArrangedSubview(labeledRow(L("Language:"), controls: [languagePopup]))
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)

        let langNote = NSTextField(wrappingLabelWithString: L("Restart the app to fully apply the new language."))
        langNote.font = NSFont.systemFont(ofSize: 10)
        langNote.textColor = .secondaryLabelColor
        stack.addArrangedSubview(indented(langNote))
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        // ── Application ──────────────────────────────────────
        stack.addArrangedSubview(sectionHeader(L("Application")))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        launchAtLoginCheckbox = NSButton(checkboxWithTitle: L("Launch at login"), target: self, action: #selector(launchAtLoginChanged(_:)))
        stack.addArrangedSubview(indented(launchAtLoginCheckbox))
        stack.setCustomSpacing(6, after: stack.arrangedSubviews.last!)

        hideMenuBarIconCheckbox = NSButton(checkboxWithTitle: L("Hide menu bar icon"), target: self, action: #selector(hideMenuBarIconChanged(_:)))
        stack.addArrangedSubview(indented(hideMenuBarIconCheckbox))
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)

        let hideNote = NSTextField(wrappingLabelWithString: L("Hotkeys still work. To show the icon again, re-launch Lumashot."))
        hideNote.font = NSFont.systemFont(ofSize: 10)
        hideNote.textColor = .secondaryLabelColor
        stack.addArrangedSubview(indented(hideNote))
        stack.setCustomSpacing(6, after: stack.arrangedSubviews.last!)

        let urlSchemeCheckbox = NSButton(checkboxWithTitle: L("Enable lumashot:// URL scheme"), target: self, action: #selector(urlSchemeChanged(_:)))
        urlSchemeCheckbox.state = (UserDefaults.standard.object(forKey: "urlSchemeEnabled") as? Bool ?? true) ? .on : .off

        let urlSchemeInfoIcon = HoverPopoverIconView(
            image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: L("URL scheme info")),
            tintColor: .secondaryLabelColor,
            toolTip: L("Show supported URL scheme commands")
        )
        urlSchemeInfoIcon.onHover = { [weak self] sourceView, shown in
            if shown { self?.showURLSchemeInfoPopover(near: sourceView) }
            // On exit, do nothing — the popover is .transient, so clicking
            // anywhere outside it closes it. This lets the user move into the
            // popover to read/copy without it vanishing.
        }

        let urlSchemeRow = NSStackView(views: [urlSchemeCheckbox, urlSchemeInfoIcon])
        urlSchemeRow.orientation = .horizontal
        urlSchemeRow.spacing = 4
        urlSchemeRow.alignment = .centerY
        stack.addArrangedSubview(indented(urlSchemeRow))
        stack.setCustomSpacing(6, after: stack.arrangedSubviews.last!)

        autoUpdateCheckbox = NSButton(checkboxWithTitle: L("Check for updates automatically"), target: self, action: #selector(autoUpdateChanged(_:)))
        stack.addArrangedSubview(indented(autoUpdateCheckbox))
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        // ── Appearance ───────────────────────────────────────
        stack.addArrangedSubview(sectionHeader(L("Appearance")))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        // Theme preset dropdown
        themePresetPopup = NSPopUpButton()
        for preset in ThemePreset.all {
            themePresetPopup.addItem(withTitle: L(preset.name))
        }
        themePresetPopup.addItem(withTitle: L("Custom"))
        themePresetPopup.target = self
        themePresetPopup.action = #selector(themePresetChanged(_:))
        stack.addArrangedSubview(indented(labeledRow(L("Theme:"), controls: [themePresetPopup])))
        stack.setCustomSpacing(12, after: stack.arrangedSubviews.last!)

        // Three color wells in a single row with labels underneath
        accentColorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 32))
        accentColorWell.color = ToolbarLayout.accentColor
        accentColorWell.target = self
        accentColorWell.action = #selector(accentColorChanged(_:))

        iconColorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 32))
        iconColorWell.color = ToolbarLayout.iconColor
        iconColorWell.target = self
        iconColorWell.action = #selector(iconColorChanged(_:))

        bgColorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 32))
        bgColorWell.color = ToolbarLayout.bgColor
        bgColorWell.target = self
        bgColorWell.action = #selector(bgColorChanged(_:))

        let accentCol = makeColorColumn(well: accentColorWell, caption: L("Accent"))
        let iconCol   = makeColorColumn(well: iconColorWell,   caption: L("Icon"))
        let bgCol     = makeColorColumn(well: bgColorWell,     caption: L("Background"))

        let colorsRow = NSStackView(views: [accentCol, iconCol, bgCol])
        colorsRow.orientation = .horizontal
        colorsRow.alignment = .top
        colorsRow.spacing = 20
        stack.addArrangedSubview(indented(colorsRow))
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        // Sync preset popup to current colors
        updateThemePresetSelection()

        finalizeSettingsStack(scroll: scroll, stack: stack)
        return scroll
    }

}
