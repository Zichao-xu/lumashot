import AVFoundation
import Cocoa
import UniformTypeIdentifiers

extension OverlayView {
    // MARK: - Toolbar Actions

    /// Handle right-click on a toolbar button (context menus, popovers).
    func handleToolbarButtonHover(_ action: ToolbarButtonAction, hovered: Bool, strip: ToolbarStripView?) {
        if hovered {
            let btn = strip?.buttonViews.first { bv in
                // Compare by identity — find the button that triggered the hover
                if case .tool(let t1) = bv.action, case .tool(let t2) = action { return t1 == t2 }
                // For non-tool actions, compare string representation
                return "\(bv.action)" == "\(action)"
            }
            hoveredTooltip = btn?.tooltipText
            hoveredTooltipButtonView = btn
        } else {
            hoveredTooltip = nil
            hoveredTooltipButtonView = nil
        }
        needsDisplay = true
    }

    func drawHoveredTooltip() {
        // In editor mode, tooltips are drawn via a floating NSView in the chrome parent
        if isEditorMode {
            updateEditorTooltipView()
            return
        }

        guard let tooltip = hoveredTooltip, !tooltip.isEmpty,
              let btn = hoveredTooltipButtonView,
              !PopoverHelper.isVisible else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: ToolbarLayout.iconColor,
        ]
        let str = tooltip as NSString
        let textSize = str.size(withAttributes: attrs)
        let pad: CGFloat = 6
        let tipW = textSize.width + pad * 2
        let tipH = textSize.height + pad

        // Convert button position to OverlayView coordinates
        let btnFrame = btn.convert(btn.bounds, to: self)
        let isBottomBar = btn.superview === bottomStripView
        let tipRect: NSRect

        if isBottomBar {
            // Above bottom bar, or below if no room
            var tipY = bottomBarRect.maxY + 4
            if tipY + tipH > bounds.maxY - 2 { tipY = bottomBarRect.minY - tipH - 4 }
            tipRect = NSRect(x: btnFrame.midX - tipW / 2, y: tipY, width: tipW, height: tipH)
        } else {
            // Left of right bar
            tipRect = NSRect(x: btnFrame.minX - tipW - 6, y: btnFrame.midY - tipH / 2, width: tipW, height: tipH)
        }

        // Clamp to bounds
        let clamped = NSRect(
            x: max(bounds.minX + 2, min(tipRect.minX, bounds.maxX - tipW - 2)),
            y: max(bounds.minY + 2, min(tipRect.minY, bounds.maxY - tipH - 2)),
            width: tipW, height: tipH)

        ToolbarLayout.bgColor.setFill()
        NSBezierPath(roundedRect: clamped, xRadius: 4, yRadius: 4).fill()
        str.draw(at: NSPoint(x: clamped.minX + pad, y: clamped.minY + pad / 2), withAttributes: attrs)
    }

    /// In editor mode, show tooltip as a floating NSView in the chrome parent (container),
    /// since EditorView's draw() can only paint within the image bounds.
    func updateEditorTooltipView() {
        guard let parent = chromeParentView else {
            editorTooltipView?.removeFromSuperview()
            editorTooltipView = nil
            return
        }

        guard let tooltip = hoveredTooltip, !tooltip.isEmpty,
              let btn = hoveredTooltipButtonView,
              !PopoverHelper.isVisible else {
            editorTooltipView?.removeFromSuperview()
            editorTooltipView = nil
            return
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let str = tooltip as NSString
        let textSize = str.size(withAttributes: attrs)
        let pad: CGFloat = 6
        let tipW = textSize.width + pad * 2
        let tipH = textSize.height + pad

        let btnFrame = btn.convert(btn.bounds, to: parent)
        let isBottomBar = btn.superview === bottomStripView
        let tipRect: NSRect

        if isBottomBar {
            let stripFrame = bottomStripView?.frame ?? .zero
            var tipY = stripFrame.maxY + 4
            if tipY + tipH > parent.bounds.maxY - 2 { tipY = stripFrame.minY - tipH - 4 }
            tipRect = NSRect(x: btnFrame.midX - tipW / 2, y: tipY, width: tipW, height: tipH)
        } else {
            tipRect = NSRect(x: btnFrame.minX - tipW - 6, y: btnFrame.midY - tipH / 2, width: tipW, height: tipH)
        }

        let clamped = NSRect(
            x: max(parent.bounds.minX + 2, min(tipRect.minX, parent.bounds.maxX - tipW - 2)),
            y: max(parent.bounds.minY + 2, min(tipRect.minY, parent.bounds.maxY - tipH - 2)),
            width: tipW, height: tipH)

        let tip: TooltipBackgroundView
        if let existing = editorTooltipView as? TooltipBackgroundView {
            tip = existing
        } else {
            editorTooltipView?.removeFromSuperview()
            tip = TooltipBackgroundView(frame: clamped)
            parent.addSubview(tip)
            editorTooltipView = tip
        }
        tip.frame = clamped
        tip.text = tooltip
        tip.needsDisplay = true
    }

    func handleToolbarButtonRightClick(_ action: ToolbarButtonAction, anchorView: NSView) {
        switch action {
        case .autoRedact:
            showRedactTypePopover(
                anchorRect: anchorView.convert(anchorView.bounds, to: self), anchorView: anchorView)
        case .save:
            let menu = NSMenu()
            let saveAsItem = NSMenuItem(
                title: L("Save As..."), action: #selector(saveAsMenuAction), keyEquivalent: "")
            saveAsItem.target = self
            menu.addItem(saveAsItem)
            menu.popUp(
                positioning: nil, at: NSPoint(x: 0, y: anchorView.bounds.height), in: anchorView)
        case .upload:
            showUploadConfirmPopover(
                anchorRect: anchorView.convert(anchorView.bounds, to: self), anchorView: anchorView)
        case .translate:
            showTranslatePopover(
                anchorRect: anchorView.convert(anchorView.bounds, to: self), anchorView: anchorView)
        case .micAudio:
            showMicDeviceMenu(anchorView: anchorView)
        case .showKeystrokes:
            showKeystrokeModeMenu(anchorView: anchorView)
        case .webcam:
            showWebcamDeviceMenu(anchorView: anchorView)
        default:
            break
        }
    }

    func showKeystrokeModeMenu(anchorView: NSView) {
        let menu = NSMenu()
        let allKeys = UserDefaults.standard.bool(forKey: "keystrokeShowAll")

        let shortcutsItem = NSMenuItem(title: L("Shortcuts Only"), action: #selector(keystrokeModeShortcuts), keyEquivalent: "")
        shortcutsItem.target = self
        if !allKeys { shortcutsItem.state = .on }
        menu.addItem(shortcutsItem)

        let allItem = NSMenuItem(title: L("All Keystrokes"), action: #selector(keystrokeModeAll), keyEquivalent: "")
        allItem.target = self
        if allKeys { allItem.state = .on }
        menu.addItem(allItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchorView.bounds.height), in: anchorView)
    }

    @objc func keystrokeModeShortcuts() {
        UserDefaults.standard.set(false, forKey: "keystrokeShowAll")
    }

    @objc func keystrokeModeAll() {
        UserDefaults.standard.set(true, forKey: "keystrokeShowAll")
    }

    func showMicDeviceMenu(anchorView: NSView) {
        let menu = NSMenu()
        let savedUID = UserDefaults.standard.string(forKey: "selectedMicDeviceUID")
        let micOn = UserDefaults.standard.bool(forKey: "recordMicAudio")

        // "None" option — turns off mic recording
        let noneItem = NSMenuItem(title: L("None"), action: #selector(micMenuNone), keyEquivalent: "")
        noneItem.target = self
        if !micOn { noneItem.state = .on }
        menu.addItem(noneItem)
        menu.addItem(NSMenuItem.separator())

        // List available audio input devices (filter out virtual aggregate devices)
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio, position: .unspecified).devices
            .filter { !$0.uniqueID.contains("CADefaultDeviceAggregate") }
        for device in devices {
            let item = NSMenuItem(title: device.localizedName, action: #selector(micMenuSelectDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uniqueID
            if micOn && (savedUID == device.uniqueID || (savedUID == nil && device == AVCaptureDevice.default(for: .audio))) {
                item.state = .on
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchorView.bounds.height), in: anchorView)
    }

    @objc func micMenuNone() {
        UserDefaults.standard.set(false, forKey: "recordMicAudio")
        stopMicLevelMonitor()
        rebuildToolbarLayout()
    }

    @objc func micMenuSelectDevice(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        UserDefaults.standard.set(uid, forKey: "selectedMicDeviceUID")
        UserDefaults.standard.set(true, forKey: "recordMicAudio")
        rebuildToolbarLayout()
        startMicLevelMonitor()
    }

}
