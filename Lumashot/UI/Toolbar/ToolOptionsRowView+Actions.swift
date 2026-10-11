import Cocoa

extension ToolOptionsRowView {
    // MARK: - Beautify Actions

    @objc func beautifyModeChanged(_ sender: NSSegmentedControl) {
        guard let ov = overlayView else { return }
        ov.beautifyMode = sender.selectedSegment == 0 ? .window : .rounded
        UserDefaults.standard.set(ov.beautifyMode.rawValue, forKey: "beautifyMode")
        ov.needsDisplay = true
    }

    @objc func beautifyPaddingChanged(_ sender: NSSlider) {
        guard let ov = overlayView else { return }
        ov.beautifyPadding = CGFloat(sender.floatValue)
        UserDefaults.standard.set(sender.doubleValue, forKey: "beautifyPadding")
        ov.needsDisplay = true
    }

    @objc func beautifyCornerChanged(_ sender: NSSlider) {
        guard let ov = overlayView else { return }
        ov.beautifyCornerRadius = CGFloat(sender.floatValue)
        UserDefaults.standard.set(sender.doubleValue, forKey: "beautifyCornerRadius")
        ov.needsDisplay = true
    }

    @objc func beautifyShadowChanged(_ sender: NSSlider) {
        guard let ov = overlayView else { return }
        ov.beautifyShadowRadius = CGFloat(sender.floatValue)
        UserDefaults.standard.set(sender.doubleValue, forKey: "beautifyShadowRadius")
        ov.needsDisplay = true
    }

    @objc func beautifyBlurChanged(_ sender: NSSlider) {
        guard let ov = overlayView else { return }
        ov.beautifyBackgroundBlur = CGFloat(sender.floatValue)
        UserDefaults.standard.set(sender.doubleValue, forKey: "beautifyBgBlur")
        ov.cachedCompositedImage = nil
        ov.needsDisplay = true
    }

    func updateBeautifySwatch(styleIndex: Int) {
        guard let btn = viewWithTag(995) as? NSButton else { return }
        btn.image = Self.gradientSwatchImage(styleIndex: styleIndex, size: 22)
    }

    @objc func beautifyGradientClicked(_ sender: NSButton) {
        if PopoverHelper.isVisible { PopoverHelper.dismiss(); return }
        guard let ov = overlayView else { return }
        let swatchBtn = viewWithTag(995) as? NSButton ?? sender
        ov.showBeautifyGradientPopover(anchorView: swatchBtn)
    }

    @objc func beautifyToggleChanged(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        ov.beautifyEnabled = sender.state == .on
        UserDefaults.standard.set(ov.beautifyEnabled, forKey: "beautifyEnabled")
        ov.needsDisplay = true
    }

    func addHintLabel(at x: CGFloat, text: String) -> CGFloat {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: labelFontSize, weight: .medium)
        label.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.42)
        label.sizeToFit()
        label.frame.origin = NSPoint(x: x, y: (rowHeight - label.frame.height) / 2)
        addSubview(label)
        return x + label.frame.width + 8
    }

    // MARK: - Actions

    @objc func strokeSliderChanged(_ sender: NSSlider) {
        guard let ov = overlayView else { return }
        let val = CGFloat(sender.floatValue)
        if let ann = editingAnnotation {
            ensureSnapshot()
            ann.strokeWidth = val
            ov.cachedCompositedImage = nil
        }
        // Always update the global default so the last-picked stroke sticks
        // for the next capture, whether or not an annotation was being edited.
        if let tool = currentTool { ov.setActiveStrokeWidth(val, for: tool) }
        if let label = viewWithTag(997) as? NSTextField {
            label.stringValue = currentTool == .loupe ? "\(Int(val))" : "\(Int(val))px"
        }
        ov.needsDisplay = true
    }

    @objc func lineStyleChanged(_ sender: NSSegmentedControl) {
        guard let ov = overlayView else { return }
        if let style = LineStyle(rawValue: sender.selectedSegment) {
            if let ann = editingAnnotation {
                ensureSnapshot()
                ann.lineStyle = style
                ov.cachedCompositedImage = nil
            }
            ov.currentLineStyle = style
            UserDefaults.standard.set(style.rawValue, forKey: "currentLineStyle")
            ov.needsDisplay = true
        }
    }

    @objc func arrowStyleChanged(_ sender: NSSegmentedControl) {
        guard let ov = overlayView else { return }
        if let style = ArrowStyle(rawValue: sender.selectedSegment) {
            if let ann = editingAnnotation {
                ensureSnapshot()
                ann.arrowStyle = style
                ov.cachedCompositedImage = nil
            }
            ov.currentArrowStyle = style
            UserDefaults.standard.set(style.rawValue, forKey: "currentArrowStyle")
            ov.needsDisplay = true
        }
    }

    @objc func shapeFillChanged(_ sender: NSSegmentedControl) {
        guard let ov = overlayView else { return }
        if let style = RectFillStyle(rawValue: sender.selectedSegment) {
            if let ann = editingAnnotation {
                ensureSnapshot()
                ann.rectFillStyle = style
                ov.cachedCompositedImage = nil
            }
            ov.currentRectFillStyle = style
            UserDefaults.standard.set(style.rawValue, forKey: "currentRectFillStyle")
            ov.needsDisplay = true
        }
    }

    @objc func cornerRadiusChanged(_ sender: NSSlider) {
        guard let ov = overlayView else { return }
        let val = CGFloat(sender.floatValue)
        if let ann = editingAnnotation {
            ensureSnapshot()
            ann.rectCornerRadius = val
            ov.cachedCompositedImage = nil
        }
        ov.currentRectCornerRadius = val
        UserDefaults.standard.set(sender.doubleValue, forKey: "currentRectCornerRadius")
        if let label = viewWithTag(996) as? NSTextField {
            label.stringValue = "\(Int(val))px"
        }
        ov.needsDisplay = true
    }

    @objc func censorModeChanged(_ sender: NSSegmentedControl) {
        guard let mode = CensorMode(rawValue: sender.selectedSegment) else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: "censorMode")
        if let ann = editingAnnotation, ann.tool == .pixelate || ann.tool == .blur {
            ensureSnapshot()
            ann.censorMode = mode
            // Clear the baked image so bakePixelate re-runs with the new mode.
            ann.bakedBlurNSImage = nil
            ann.bakePixelate()
            overlayView?.cachedCompositedImage = nil
            overlayView?.needsDisplay = true
        }
    }

    @objc func numberFormatChanged(_ sender: NSSegmentedControl) {
        guard let ov = overlayView else { return }
        if let fmt = NumberFormat(rawValue: sender.selectedSegment) {
            ov.currentNumberFormat = fmt
            UserDefaults.standard.set(fmt.rawValue, forKey: "numberFormat")
            // Update start value preview to match new format
            if let label = viewWithTag(999) as? NSTextField {
                label.stringValue = fmt.format(ov.numberStartAt)
                label.sizeToFit()
            }
            ov.needsDisplay = true
        }
    }

    @objc func numberStartChanged(_ sender: NSStepper) {
        guard let ov = overlayView else { return }
        ov.numberStartAt = sender.integerValue
        UserDefaults.standard.set(sender.integerValue, forKey: "numberStartAt")
        // Update value label
        if let label = viewWithTag(999) as? NSTextField {
            label.stringValue = ov.currentNumberFormat.format(sender.integerValue)
            label.sizeToFit()
        }
        ov.needsDisplay = true
    }



    @objc func boldToggled() { overlayView?.textEditor.toggleBold(); overlayView.map { $0.applyTextFormattingToSelectedAnnotations(); $0.needsDisplay = true; rebuild(for: $0.currentTool) } }
    @objc func italicToggled() { overlayView?.textEditor.toggleItalic(); overlayView.map { $0.applyTextFormattingToSelectedAnnotations(); $0.needsDisplay = true; rebuild(for: $0.currentTool) } }
    @objc func underlineToggled() { overlayView?.textEditor.toggleUnderline(); overlayView.map { $0.applyTextFormattingToSelectedAnnotations(); $0.needsDisplay = true; rebuild(for: $0.currentTool) } }
    @objc func strikethroughToggled() { overlayView?.textEditor.toggleStrikethrough(); overlayView.map { $0.applyTextFormattingToSelectedAnnotations(); $0.needsDisplay = true; rebuild(for: $0.currentTool) } }

    @objc func measureUnitChanged(_ sender: NSSegmentedControl) {
        guard let ov = overlayView else { return }
        ov.currentMeasureInPoints = sender.selectedSegment == 1
        UserDefaults.standard.set(ov.currentMeasureInPoints, forKey: "measureInPoints")
        ov.needsDisplay = true
    }

    @objc func quickEmojiClicked(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        ov.currentStampImage = StampEmojis.renderEmoji(sender.title)
        ov.currentStampEmoji = sender.title
        ov.needsDisplay = true
    }

    @objc func moreEmojisClicked(_ sender: NSButton) {
        if PopoverHelper.isVisible { PopoverHelper.dismiss(); return }
        guard let ov = overlayView else { return }
        ov.showEmojiPopover(anchorView: sender)
    }

    @objc func loadImageClicked() {
        guard let ov = overlayView else { return }
        StampEmojis.loadStampImage { [weak ov] image in
            ov?.currentStampImage = image
            ov?.currentStampEmoji = nil
            ov?.needsDisplay = true
        }
    }

    @objc func drawModeChanged(_ sender: NSSegmentedControl) {
        UserDefaults.standard.set(sender.selectedSegment == 1, forKey: "censorTextOnly")
    }

    @objc func pencilSmoothModeChanged(_ sender: NSSegmentedControl) {
        let mode = sender.selectedSegment
        overlayView?.pencilSmoothMode = mode
        UserDefaults.standard.set(mode, forKey: "pencilSmoothMode")
    }

    @objc func redactAllTextClicked() {
        overlayView?.performRedactAllText()
    }

    @objc func redactPIIClicked() {
        overlayView?.performAutoRedact()
    }

    @objc func redactFacesClicked() {
        overlayView?.performRedactFaces()
    }

    @objc func redactPeopleClicked() {
        overlayView?.performRedactPeople()
    }

    @objc func redactTypesClicked(_ sender: NSView) {
        if PopoverHelper.isVisible { PopoverHelper.dismiss(); return }
        guard let ov = overlayView else { return }
        ov.showRedactTypePopover(anchorRect: .zero, anchorView: sender)
    }

    @objc func fontFamilyClicked(_ sender: NSButton) {
        // Toggle: close if already open
        if PopoverHelper.isVisible {
            PopoverHelper.dismiss()
            return
        }
        guard let ov = overlayView else { return }
        let picker = FontPickerView(selectedFamily: ov.textEditor.fontFamily)
        picker.onSelect = { [weak ov] family in
            guard let ov = ov else { return }
            ov.textEditor.fontFamily = family
            UserDefaults.standard.set(family, forKey: "textFontFamily")
            ov.textEditor.applyFontSizeChange()
            ov.applyTextFormattingToSelectedAnnotations()
            ov.rebuildToolbarLayout()
            ov.needsDisplay = true
            PopoverHelper.dismiss()
        }
        PopoverHelper.show(picker, size: picker.preferredSize, relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        DispatchQueue.main.async {
            picker.scrollToTop()
        }
    }

    @objc func alignmentChanged(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        if let align = NSTextAlignment(rawValue: sender.tag) {
            ov.textEditor.alignment = align
            ov.textEditor.applyAlignment()
            ov.applyTextFormattingToSelectedAnnotations()
            // Update all alignment buttons — only the selected one should be on
            for case let btn as NSButton in subviews where
                btn.tag == NSTextAlignment.left.rawValue ||
                btn.tag == NSTextAlignment.center.rawValue ||
                btn.tag == NSTextAlignment.right.rawValue {
                btn.state = btn.tag == align.rawValue ? .on : .off
            }
            ov.needsDisplay = true
        }
    }

    @objc func fontSizeDecreased() {
        guard let ov = overlayView else { return }
        ov.textEditor.fontSize = max(8, ov.textEditor.fontSize - 1)
        UserDefaults.standard.set(Double(ov.textEditor.fontSize), forKey: "textFontSize")
        ov.textEditor.applyFontSizeChange()
        ov.textEditor.resizeToFit()
        ov.applyTextFormattingToSelectedAnnotations()
        if let label = viewWithTag(998) as? NSTextField { label.stringValue = "\(Int(ov.textEditor.fontSize))" }
        ov.needsDisplay = true
    }

    @objc func fontSizeIncreased() {
        guard let ov = overlayView else { return }
        ov.textEditor.fontSize = min(200, ov.textEditor.fontSize + 1)
        UserDefaults.standard.set(Double(ov.textEditor.fontSize), forKey: "textFontSize")
        ov.textEditor.applyFontSizeChange()
        ov.textEditor.resizeToFit()
        ov.applyTextFormattingToSelectedAnnotations()
        if let label = viewWithTag(998) as? NSTextField { label.stringValue = "\(Int(ov.textEditor.fontSize))" }
        ov.needsDisplay = true
    }

    @objc func textBgToggled(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        ov.textEditor.bgEnabled = sender.state == .on
        UserDefaults.standard.set(ov.textEditor.bgEnabled, forKey: "textBgEnabled")
        // Update swatch opacity
        if let swatch = viewWithTag(975) { swatch.layer?.opacity = ov.textEditor.bgEnabled ? 1.0 : 0.3 }
        ov.applyTextBgOutlineToSelectedAnnotations()
        ov.needsDisplay = true
    }

    @objc func textOutlineToggled(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        ov.textEditor.outlineEnabled = sender.state == .on
        UserDefaults.standard.set(ov.textEditor.outlineEnabled, forKey: "textOutlineEnabled")
        if let swatch = viewWithTag(976) { swatch.layer?.opacity = ov.textEditor.outlineEnabled ? 1.0 : 0.3 }
        ov.applyTextBgOutlineToSelectedAnnotations()
        ov.needsDisplay = true
    }

    @objc func textBgColorClicked(_ sender: NSButton) {
        if PopoverHelper.isVisible { PopoverHelper.dismiss(); return }
        guard let ov = overlayView else { return }
        ov.showColorPickerPopover(target: .textBg, anchorView: sender)
    }

    @objc func textOutlineColorClicked(_ sender: NSButton) {
        if PopoverHelper.isVisible { PopoverHelper.dismiss(); return }
        guard let ov = overlayView else { return }
        ov.showColorPickerPopover(target: .textOutline, anchorView: sender)
    }

    @objc func textGlyphStrokeToggled(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        ov.textEditor.glyphStrokeEnabled = sender.state == .on
        UserDefaults.standard.set(ov.textEditor.glyphStrokeEnabled, forKey: "textGlyphStrokeEnabled")
        if let swatch = viewWithTag(977) { swatch.layer?.opacity = ov.textEditor.glyphStrokeEnabled ? 1.0 : 0.3 }
        ov.applyGlyphStrokeToLiveTextView()
        ov.applyTextBgOutlineToSelectedAnnotations()
        ov.needsDisplay = true
    }

    @objc func textGlyphStrokeColorClicked(_ sender: NSButton) {
        if PopoverHelper.isVisible { PopoverHelper.dismiss(); return }
        guard let ov = overlayView else { return }
        ov.showColorPickerPopover(target: .textGlyphStroke, anchorView: sender)
    }

}
