import Cocoa
import Carbon
import ServiceManagement
import ScreenCaptureKit

extension SettingsWindowController {
    // MARK: - Shortcuts Tab

    func makeShortcutsTabView() -> NSView {
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

        stack.addArrangedSubview(sectionHeader(L("Keyboard Shortcuts")))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        for slot in HotkeyManager.HotkeySlot.allCases {
            let field = NSTextField()
            field.isEditable = false
            field.isSelectable = false
            field.alignment = .center
            field.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            field.widthAnchor.constraint(equalToConstant: 80).isActive = true
            field.stringValue = HotkeyManager.displayString(for: slot)

            let btn = NSButton(title: L("Set"), target: self, action: #selector(recordShortcut(_:)))
            btn.bezelStyle = .rounded
            btn.tag = slot.rawValue

            let clearBtn = NSButton(title: "", target: self, action: #selector(clearShortcut(_:)))
            clearBtn.bezelStyle = .inline
            clearBtn.isBordered = false
            clearBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L("None"))
            clearBtn.contentTintColor = .secondaryLabelColor
            clearBtn.imagePosition = .imageOnly
            clearBtn.tag = slot.rawValue
            clearBtn.toolTip = L("None")
            clearBtn.widthAnchor.constraint(equalToConstant: 20).isActive = true

            let resetBtn = NSButton(title: "", target: self, action: #selector(resetShortcut(_:)))
            resetBtn.bezelStyle = .inline
            resetBtn.isBordered = false
            resetBtn.image = NSImage(systemSymbolName: "arrow.counterclockwise.circle.fill", accessibilityDescription: L("Reset to default"))
            resetBtn.contentTintColor = .secondaryLabelColor
            resetBtn.imagePosition = .imageOnly
            resetBtn.tag = slot.rawValue
            resetBtn.toolTip = L("Reset to default")
            resetBtn.widthAnchor.constraint(equalToConstant: 20).isActive = true

            hotkeyFields[slot] = field
            hotkeyButtons[slot] = btn

            stack.addArrangedSubview(labeledRow("\(slot.label):", controls: [field, btn, clearBtn, resetBtn]))
            stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)
        }

        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)

        let note = NSTextField(wrappingLabelWithString: L("Click \"Set\" and press a key combination with at least one modifier (⌘, ⌥, ⌃, ⇧) to set a shortcut."))
        note.font = NSFont.systemFont(ofSize: 10)
        note.textColor = .secondaryLabelColor
        stack.addArrangedSubview(indented(note))

        // ── Overlay / Editor Tool Shortcuts ──────────────────
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(sectionHeader(L("Overlay / Editor Shortcuts")))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        for action in ToolShortcutManager.Action.allCases {
            let field = NSTextField()
            field.isEditable = false
            field.isSelectable = false
            field.alignment = .center
            field.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            field.widthAnchor.constraint(equalToConstant: 80).isActive = true
            field.stringValue = ToolShortcutManager.displayString(for: action)

            let btn = NSButton(title: L("Set"), target: self, action: #selector(recordToolShortcut(_:)))
            btn.bezelStyle = .rounded
            btn.tag = ToolShortcutManager.Action.allCases.firstIndex(of: action)!

            let clearBtn = NSButton(title: "", target: self, action: #selector(clearToolShortcut(_:)))
            clearBtn.bezelStyle = .inline
            clearBtn.isBordered = false
            clearBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L("None"))
            clearBtn.contentTintColor = .secondaryLabelColor
            clearBtn.imagePosition = .imageOnly
            clearBtn.tag = ToolShortcutManager.Action.allCases.firstIndex(of: action)!
            clearBtn.toolTip = L("None")
            clearBtn.widthAnchor.constraint(equalToConstant: 20).isActive = true

            let resetBtn = NSButton(title: "", target: self, action: #selector(resetToolShortcut(_:)))
            resetBtn.bezelStyle = .inline
            resetBtn.isBordered = false
            resetBtn.image = NSImage(systemSymbolName: "arrow.counterclockwise.circle.fill", accessibilityDescription: L("Reset to default"))
            resetBtn.contentTintColor = .secondaryLabelColor
            resetBtn.imagePosition = .imageOnly
            resetBtn.tag = ToolShortcutManager.Action.allCases.firstIndex(of: action)!
            resetBtn.toolTip = L("Reset to default")
            resetBtn.widthAnchor.constraint(equalToConstant: 20).isActive = true

            toolShortcutFields[action] = field
            toolShortcutButtons[action] = btn

            stack.addArrangedSubview(labeledRow("\(action.label):", controls: [field, btn, clearBtn, resetBtn]))
            stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)
        }

        let toolNote = NSTextField(wrappingLabelWithString: L("Press a single key to assign it as the shortcut for that tool. These work when the overlay or editor is active."))
        toolNote.font = NSFont.systemFont(ofSize: 10)
        toolNote.textColor = .secondaryLabelColor
        stack.addArrangedSubview(indented(toolNote))

        // Spacer to push content to top
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

    @objc func recordShortcut(_ sender: NSButton) {
        guard let slot = HotkeyManager.HotkeySlot(rawValue: sender.tag) else { return }

        // If already recording this slot, stop
        if recordingSlot == slot {
            stopShortcutRecording()
            return
        }
        // Stop any previous recording (global or tool)
        stopShortcutRecording()
        stopToolShortcutRecording()

        recordingSlot = slot
        sender.title = L("Press keys...")
        hotkeyFields[slot]?.stringValue = L("Waiting...")

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let modifiers = event.modifierFlags
            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            let keyCode = UInt32(event.keyCode)
            if carbonMods == 0 && !HotkeyManager.isFunctionKey(keyCode) { return nil }
            HotkeyManager.saveHotkey(for: slot, keyCode: keyCode, modifiers: carbonMods)
            self.hotkeyFields[slot]?.stringValue = HotkeyManager.displayString(for: slot)
            self.stopShortcutRecording()
            self.onHotkeyChanged?()
            return nil
        }
    }

    @objc func clearShortcut(_ sender: NSButton) {
        guard let slot = HotkeyManager.HotkeySlot(rawValue: sender.tag) else { return }
        stopShortcutRecording()
        HotkeyManager.disableHotkey(for: slot)
        hotkeyFields[slot]?.stringValue = L("None")
        onHotkeyChanged?()
    }

    @objc func resetShortcut(_ sender: NSButton) {
        guard let slot = HotkeyManager.HotkeySlot(rawValue: sender.tag) else { return }
        stopShortcutRecording()
        HotkeyManager.saveHotkey(for: slot, keyCode: slot.defaultKeyCode, modifiers: slot.defaultModifiers)
        hotkeyFields[slot]?.stringValue = HotkeyManager.displayString(for: slot)
        onHotkeyChanged?()
    }

    func stopShortcutRecording() {
        if let slot = recordingSlot {
            hotkeyButtons[slot]?.title = L("Set")
            hotkeyFields[slot]?.stringValue = HotkeyManager.displayString(for: slot)
        }
        recordingSlot = nil
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    // MARK: - Overlay Tool Shortcuts

    @objc func recordToolShortcut(_ sender: NSButton) {
        let allActions = ToolShortcutManager.Action.allCases
        guard sender.tag >= 0, sender.tag < allActions.count else { return }
        let action = allActions[sender.tag]

        // If already recording this action, stop
        if recordingToolAction == action {
            stopToolShortcutRecording()
            return
        }
        // Stop any other recording (global or tool)
        stopShortcutRecording()
        stopToolShortcutRecording()

        recordingToolAction = action
        sender.title = L("Press...")
        toolShortcutFields[action]?.stringValue = "…"

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            // Only accept single keys without modifiers (or allow Escape to cancel)
            if event.keyCode == 53 { // Escape — cancel
                self.stopToolShortcutRecording()
                return nil
            }
            guard !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.option),
                  !event.modifierFlags.contains(.control),
                  let char = event.charactersIgnoringModifiers?.lowercased(),
                  char.count == 1 else { return nil }

            ToolShortcutManager.setKey(char, for: action)
            self.toolShortcutFields[action]?.stringValue = ToolShortcutManager.displayString(for: action)
            self.stopToolShortcutRecording()
            return nil
        }
    }

    @objc func clearToolShortcut(_ sender: NSButton) {
        let allActions = ToolShortcutManager.Action.allCases
        guard sender.tag >= 0, sender.tag < allActions.count else { return }
        let action = allActions[sender.tag]
        stopToolShortcutRecording()
        ToolShortcutManager.setKey("", for: action)
        toolShortcutFields[action]?.stringValue = L("None")
    }

    @objc func resetToolShortcut(_ sender: NSButton) {
        let allActions = ToolShortcutManager.Action.allCases
        guard sender.tag >= 0, sender.tag < allActions.count else { return }
        let action = allActions[sender.tag]
        stopToolShortcutRecording()
        ToolShortcutManager.setKey(action.defaultKey, for: action)
        toolShortcutFields[action]?.stringValue = ToolShortcutManager.displayString(for: action)
    }

    func stopToolShortcutRecording() {
        if let action = recordingToolAction {
            toolShortcutFields[action]?.stringValue = ToolShortcutManager.displayString(for: action)
            toolShortcutButtons[action]?.title = L("Set")
        }
        recordingToolAction = nil
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

}
