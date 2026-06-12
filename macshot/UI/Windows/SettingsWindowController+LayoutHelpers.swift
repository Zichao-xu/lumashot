import Cocoa
import Carbon
import ServiceManagement
import ScreenCaptureKit

extension SettingsWindowController {
    // MARK: - Layout helpers

    func sectionHeader(_ text: String) -> NSTextField {
        let lbl = NSTextField(labelWithString: text.uppercased())
        lbl.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        lbl.textColor = .secondaryLabelColor
        return lbl
    }

    /// Width of the right-aligned label column for `labeledRow`. Wide
    /// enough to fit the longest localized string in practice — Polish's
    /// "Szybkie przechwycenie:" (issue #130) used to get clipped at the
    /// old 140pt column. 180pt covers every shipping locale with a bit
    /// of headroom.
    static let labelColumnWidth: CGFloat = 180

    /// A horizontal row: right-aligned label on the left, controls on the right.
    func labeledRow(_ labelText: String, controls: [NSView]) -> NSView {
        let lbl = NSTextField(labelWithString: labelText)
        lbl.font = NSFont.systemFont(ofSize: 13)
        lbl.alignment = .right
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.widthAnchor.constraint(equalToConstant: Self.labelColumnWidth).isActive = true

        let row = NSStackView(views: [lbl] + controls)
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    /// Indents a view to align with the control column.
    func indented(_ view: NSView) -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        // Label column + row spacing (8pt).
        spacer.widthAnchor.constraint(equalToConstant: Self.labelColumnWidth + 8).isActive = true

        let row = NSStackView(views: [spacer, view])
        row.orientation = .horizontal
        row.spacing = 0
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    func addTranslationEngineItem(title: String, provider: TranslationProvider) {
        translationEnginePopup.addItem(withTitle: title)
        translationEnginePopup.lastItem?.representedObject = provider.rawValue
    }

    func selectTranslationEngine(_ provider: TranslationProvider) {
        let items = translationEnginePopup.itemArray
        if let index = items.firstIndex(where: { ($0.representedObject as? String) == provider.rawValue }) {
            translationEnginePopup.selectItem(at: index)
        } else if let googleIndex = items.firstIndex(where: { ($0.representedObject as? String) == TranslationProvider.google.rawValue }) {
            translationEnginePopup.selectItem(at: googleIndex)
            TranslationService.provider = .google
        }
    }

    func saveAITranslationSettings() {
        TranslationService.aiBaseURL = aiBaseURLField?.stringValue ?? ""
        TranslationService.aiAPIKey = aiAPIKeyField?.stringValue ?? ""
        TranslationService.aiModel = aiModelField?.stringValue ?? ""
        TranslationService.aiPrompt = aiPromptField?.stringValue ?? ""
    }

    func updateAITranslationControlsEnabled() {
        let aiSelected = TranslationService.provider == .ai
        let localSelected = TranslationService.provider == .local
        let controls: [NSControl?] = [aiBaseURLField, aiAPIKeyField, aiModelField, aiPromptField]
        for control in controls {
            control?.isEnabled = aiSelected
        }
        localModelActionButton?.isEnabled = localSelected && !LocalModelService.shared.isInstalling
        localModelStatusLabel?.textColor = localSelected ? .secondaryLabelColor : .tertiaryLabelColor
        updateLocalModelControls()
    }

    func updateLocalModelControls() {
        localModelActionButton?.title = LocalModelService.shared.installButtonTitle
        localModelActionButton?.isEnabled = TranslationService.provider == .local && !LocalModelService.shared.isInstalling
        localModelStatusLabel?.stringValue = LocalModelService.shared.statusText
        // Hide progress bar when not installing
        if !LocalModelService.shared.isInstalling {
            localModelProgressIndicator?.isHidden = true
        }
    }

    /// Two-column grid of checkboxes in a rounded box, fills parent width.
    func makeToggleGrid(items: [(tag: Int, label: String)],
                                 defaultsKey: String,
                                 enabledValues: [Int]?) -> NSView {
        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.5).cgColor
        box.layer?.cornerRadius = 6
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.separatorColor.cgColor

        // Build rows of 2 columns using horizontal stack views inside a vertical stack
        let vStack = NSStackView()
        vStack.orientation = .vertical
        vStack.spacing = 0
        vStack.alignment = .leading
        vStack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(vStack)

        let pad: CGFloat = 8
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: box.topAnchor, constant: pad),
            vStack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: pad),
            vStack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -pad),
            vStack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -pad),
        ])

        let cols = 2
        let rows = Int(ceil(Double(items.count) / Double(cols)))

        for row in 0..<rows {
            let hStack = NSStackView()
            hStack.orientation = .horizontal
            hStack.distribution = .fillEqually
            hStack.spacing = 0
            hStack.translatesAutoresizingMaskIntoConstraints = false
            // Row must be AT LEAST 28pt so single-line checkboxes still look
            // consistent, but can grow if a translated label wraps to two
            // lines. Without this relaxation, long locale strings get
            // horizontally clipped (issue #130).
            hStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true

            for col in 0..<cols {
                let idx = row * cols + col
                if idx < items.count {
                    let item = items[idx]
                    let isEnabled = enabledValues == nil || enabledValues!.contains(item.tag)
                    let cb = NSButton(checkboxWithTitle: item.label, target: self, action: #selector(toggleItemChanged(_:)))
                    cb.state = isEnabled ? .on : .off
                    cb.tag = item.tag
                    cb.identifier = NSUserInterfaceItemIdentifier(defaultsKey)
                    cb.translatesAutoresizingMaskIntoConstraints = false
                    // Let the title wrap when it doesn't fit the column —
                    // the native NSButton checkbox truncates by default.
                    // Word-wrap is graceful; the cell takes a second line
                    // of text when needed instead of swallowing characters.
                    cb.cell?.wraps = true
                    cb.cell?.isScrollable = false
                    cb.cell?.lineBreakMode = .byWordWrapping
                    if let cell = cb.cell as? NSButtonCell {
                        cell.usesSingleLineMode = false
                    }
                    hStack.addArrangedSubview(cb)
                } else {
                    let filler = NSView()
                    filler.translatesAutoresizingMaskIntoConstraints = false
                    hStack.addArrangedSubview(filler)
                }
            }
            vStack.addArrangedSubview(hStack)
            // Stretch row to fill the vStack's width (must be after addArrangedSubview
            // so both views share a common ancestor)
            hStack.widthAnchor.constraint(equalTo: vStack.widthAnchor).isActive = true
        }

        return box
    }

}
