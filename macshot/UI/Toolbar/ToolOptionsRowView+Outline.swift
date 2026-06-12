import Cocoa

extension ToolOptionsRowView {
    // MARK: - Annotation outline

    func addOutlineControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        let outlineEnabled: Bool
        let outlineCol: NSColor
        if let ann = editingAnnotation {
            outlineEnabled = ann.outlineColor != nil
            outlineCol = ann.outlineColor ?? Self.savedOutlineColor
        } else {
            outlineEnabled = UserDefaults.standard.bool(forKey: "annotationOutlineEnabled")
            outlineCol = Self.savedOutlineColor
        }
        let outlineBtn = NSButton(title: L("Outline"), target: self, action: #selector(annotationOutlineToggled(_:)))
        outlineBtn.bezelStyle = .recessed
        outlineBtn.setButtonType(.toggle)
        outlineBtn.state = outlineEnabled ? .on : .off
        outlineBtn.font = NSFont.systemFont(ofSize: controlFontSize, weight: .medium)
        outlineBtn.attributedTitle = NSAttributedString(string: L("Outline"), attributes: [
            .font: NSFont.systemFont(ofSize: controlFontSize, weight: .medium),
            .baselineOffset: 0.5,
        ])
        outlineBtn.sizeToFit()
        let rowHeight: CGFloat = frame.height > 0 ? frame.height : 30
        outlineBtn.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: max(58, outlineBtn.frame.width + 2), height: controlHeight)
        addSubview(outlineBtn)
        curX += outlineBtn.frame.width + 2

        let swatchSize: CGFloat = 20
        let swatch = NSButton(frame: NSRect(x: curX, y: (rowHeight - swatchSize) / 2, width: swatchSize, height: swatchSize))
        swatch.title = ""
        swatch.isBordered = false
        swatch.wantsLayer = true
        swatch.layer?.backgroundColor = outlineCol.cgColor
        swatch.layer?.cornerRadius = 3
        ToolbarLayout.applyContinuousCornerCurve(to: swatch.layer)
        swatch.layer?.borderWidth = 1.5
        swatch.layer?.borderColor = ToolbarLayout.iconColor.withAlphaComponent(0.4).cgColor
        swatch.layer?.opacity = outlineEnabled ? 1.0 : 0.3
        swatch.tag = 978
        swatch.target = self
        swatch.action = #selector(annotationOutlineColorClicked(_:))
        addSubview(swatch)
        curX += swatchSize
        return curX
    }

    static var savedOutlineColor: NSColor {
        if let data = UserDefaults.standard.data(forKey: "annotationOutlineColor"),
           let c = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) { return c }
        return .white
    }

    @objc func annotationOutlineToggled(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        let isOn = sender.state == .on
        UserDefaults.standard.set(isOn, forKey: "annotationOutlineEnabled")
        if let swatch = viewWithTag(978) { swatch.layer?.opacity = isOn ? 1.0 : 0.3 }
        if let ann = editingAnnotation {
            ensureSnapshot()
            ann.outlineColor = isOn ? Self.savedOutlineColor : nil
            ov.cachedCompositedImage = nil
        }
        // Rebuild to update line style segment enabled state (rect/ellipse disable dashed/dotted with outline)
        let tool = editingAnnotation?.tool ?? ov.currentTool
        if tool == .rectangle || tool == .ellipse {
            if let ann = editingAnnotation {
                rebuild(forAnnotation: ann)
            } else {
                rebuild(for: tool)
            }
        }
        ov.needsDisplay = true
    }

    @objc func annotationOutlineColorClicked(_ sender: NSButton) {
        if PopoverHelper.isVisible { PopoverHelper.dismiss(); return }
        guard let ov = overlayView else { return }
        ov.showColorPickerPopover(target: .annotationOutline, anchorView: sender)
    }

    @objc func textCancelClicked() {
        overlayView?.cancelTextEditing()
    }

    @objc func textConfirmClicked() {
        overlayView?.commitTextFieldIfNeeded()
    }
}
