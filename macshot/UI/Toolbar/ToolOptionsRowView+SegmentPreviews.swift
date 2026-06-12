import Cocoa

extension ToolOptionsRowView {
    // MARK: - Segment preview images

    static func lineStyleImage(_ style: LineStyle) -> NSImage {
        let size = NSSize(width: 28, height: 16)
        return NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath()
            path.lineWidth = 2
            path.lineCapStyle = .round
            style.apply(to: path)
            ToolbarLayout.iconColor.setStroke()
            path.move(to: NSPoint(x: 4, y: size.height / 2))
            path.line(to: NSPoint(x: size.width - 4, y: size.height / 2))
            path.stroke()
            return true
        }
    }

    static func arrowStyleImage(_ style: ArrowStyle) -> NSImage {
        let size = NSSize(width: 24, height: 16)
        return NSImage(size: size, flipped: false) { _ in
            let mid = size.height / 2
            let from = NSPoint(x: 3, y: mid)
            let to = NSPoint(x: size.width - 3, y: mid)
            ToolbarLayout.iconColor.setStroke()
            ToolbarLayout.iconColor.setFill()

            switch style {
            case .single:
                let path = NSBezierPath()
                path.lineWidth = 1.5
                path.move(to: from)
                path.line(to: NSPoint(x: to.x - 4, y: mid))
                path.stroke()
                let head = NSBezierPath()
                head.move(to: to)
                head.line(to: NSPoint(x: to.x - 5, y: mid + 3))
                head.line(to: NSPoint(x: to.x - 5, y: mid - 3))
                head.close()
                head.fill()
            case .thick:
                // Thick shaft stops before the head
                let path = NSBezierPath()
                path.lineWidth = 2.5
                path.move(to: from)
                path.line(to: NSPoint(x: to.x - 6, y: mid))
                path.stroke()
                let head = NSBezierPath()
                head.move(to: to)
                head.line(to: NSPoint(x: to.x - 7, y: mid + 5))
                head.line(to: NSPoint(x: to.x - 7, y: mid - 5))
                head.close()
                head.fill()
            case .double:
                let path = NSBezierPath()
                path.lineWidth = 1.5
                path.move(to: NSPoint(x: from.x + 4, y: mid))
                path.line(to: NSPoint(x: to.x - 4, y: mid))
                path.stroke()
                // Left arrowhead (pointing left)
                let headL = NSBezierPath()
                headL.move(to: from)
                headL.line(to: NSPoint(x: from.x + 5, y: mid + 3))
                headL.line(to: NSPoint(x: from.x + 5, y: mid - 3))
                headL.close()
                headL.fill()
                // Right arrowhead (pointing right)
                let headR = NSBezierPath()
                headR.move(to: to)
                headR.line(to: NSPoint(x: to.x - 5, y: mid + 3))
                headR.line(to: NSPoint(x: to.x - 5, y: mid - 3))
                headR.close()
                headR.fill()
            case .open:
                let path = NSBezierPath()
                path.lineWidth = 1.5
                path.move(to: from)
                path.line(to: to)
                path.move(to: NSPoint(x: to.x - 5, y: mid + 3))
                path.line(to: to)
                path.line(to: NSPoint(x: to.x - 5, y: mid - 3))
                path.stroke()
            case .tail:
                let path = NSBezierPath()
                path.lineWidth = 1.5
                path.move(to: from)
                path.line(to: NSPoint(x: to.x - 4, y: mid))
                path.stroke()
                // Tail crossbar — taller so it's clearly a line, not a dot
                let tail = NSBezierPath()
                tail.lineWidth = 1.5
                tail.move(to: NSPoint(x: from.x, y: mid + 5))
                tail.line(to: NSPoint(x: from.x, y: mid - 5))
                tail.stroke()
                let head = NSBezierPath()
                head.move(to: to)
                head.line(to: NSPoint(x: to.x - 5, y: mid + 3))
                head.line(to: NSPoint(x: to.x - 5, y: mid - 3))
                head.close()
                head.fill()
            }
            return true
        }
    }

    static func shapeFillImage(_ style: RectFillStyle, oval: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 16)
        return NSImage(size: size, flipped: false) { _ in
            let r = NSRect(x: 3, y: 2, width: size.width - 6, height: size.height - 4)
            let path = oval ? NSBezierPath(ovalIn: r) : ToolbarLayout.continuousRoundedPath(in: r, radius: 2)
            path.lineWidth = 1.5
            switch style {
            case .stroke:
                ToolbarLayout.iconColor.setStroke()
                path.stroke()
            case .strokeAndFill:
                ToolbarLayout.iconColor.withAlphaComponent(0.4).setFill()
                path.fill()
                ToolbarLayout.iconColor.setStroke()
                path.stroke()
            case .fill:
                ToolbarLayout.iconColor.setFill()
                path.fill()
            }
            return true
        }
    }

    static func gradientSwatchImage(styleIndex: Int, size: CGFloat) -> NSImage {
        // Custom image background swatch
        if styleIndex == -1 {
            if let data = UserDefaults.standard.data(forKey: "beautifyCustomBgImageData"),
               let img = NSImage(data: data) {
                return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
                    let r = NSRect(x: 0, y: 0, width: size, height: size)
                    let path = ToolbarLayout.continuousRoundedPath(in: r, radius: ToolbarLayout.swatchCornerRadius)
                    NSGraphicsContext.saveGraphicsState()
                    path.addClip()
                    img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1.0)
                    NSGraphicsContext.restoreGraphicsState()
                    ToolbarLayout.iconColor.withAlphaComponent(0.3).setStroke()
                    path.lineWidth = 0.5
                    path.stroke()
                    return true
                }
            }
            return NSImage(size: NSSize(width: size, height: size))
        }
        let styles = BeautifyRenderer.styles
        guard styleIndex >= 0, styleIndex < styles.count else {
            return NSImage(size: NSSize(width: size, height: size))
        }
        let style = styles[styleIndex]
        // Use mesh rendering on macOS 15+ for mesh styles
        if #available(macOS 15.0, *), let mesh = style.meshDef,
           let meshImg = BeautifyRenderer.renderMeshSwatch(mesh, size: size) {
            return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
                let r = NSRect(x: 0, y: 0, width: size, height: size)
                let path = ToolbarLayout.continuousRoundedPath(in: r, radius: ToolbarLayout.swatchCornerRadius)
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                meshImg.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1.0)
                NSGraphicsContext.restoreGraphicsState()
                ToolbarLayout.iconColor.withAlphaComponent(0.3).setStroke()
                path.lineWidth = 0.5
                path.stroke()
                return true
            }
        }
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let r = NSRect(x: 0, y: 0, width: size, height: size)
            let path = ToolbarLayout.continuousRoundedPath(in: r, radius: ToolbarLayout.swatchCornerRadius)
            if let grad = NSGradient(
                colors: style.stops.map { $0.0 },
                atLocations: style.stops.map { $0.1 },
                colorSpace: .deviceRGB)
            {
                grad.draw(in: path, angle: style.angle - 90)
            }
            ToolbarLayout.iconColor.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
    }

    func addCornerRadiusSlider(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        let label = NSTextField(labelWithString: L("Radius"))
        label.font = NSFont.systemFont(ofSize: labelFontSize, weight: .medium)
        label.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        label.sizeToFit()
        label.frame.origin = NSPoint(x: curX, y: (rowHeight - label.frame.height) / 2)
        addSubview(label)
        curX += label.frame.width + 4

        let radiusVal = editingAnnotation?.rectCornerRadius ?? ov.currentRectCornerRadius
        let slider = NSSlider(value: Double(radiusVal),
                              minValue: 0, maxValue: 30,
                              target: self, action: #selector(cornerRadiusChanged(_:)))
        slider.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: 84, height: controlHeight)
        slider.isContinuous = true
        addSubview(slider)
        curX += 84 + 5

        let valLabel = NSTextField(labelWithString: "\(Int(radiusVal))px")
        valLabel.font = NSFont.monospacedDigitSystemFont(ofSize: valueFontSize, weight: .medium)
        valLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.72)
        valLabel.alignment = .right
        valLabel.frame = NSRect(x: curX, y: (rowHeight - 17) / 2, width: 34, height: 17)
        valLabel.tag = 996  // corner radius value label
        addSubview(valLabel)
        curX += 34

        return curX
    }

    func addToggle(at x: CGFloat, title: String, isOn: Bool, action: @escaping (Bool) -> Void) -> CGFloat {
        var curX = x

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: controlFontSize, weight: .medium)
        label.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.78)
        label.sizeToFit()
        label.frame.origin = NSPoint(x: curX, y: (rowHeight - label.frame.height) / 2)
        addSubview(label)
        curX += label.frame.width + 6

        let toggle = ToolbarSwitchControl(isOn: isOn)
        toggle.frame.origin = NSPoint(x: curX, y: (rowHeight - toggle.frame.height) / 2)
        let handler = ToggleHandler(action: action)
        toggle.target = handler
        toggle.action = #selector(ToggleHandler.toggled(_:))
        objc_setAssociatedObject(toggle, "handler", handler, .OBJC_ASSOCIATION_RETAIN)
        addSubview(toggle)
        curX += toggle.frame.width + 8
        return curX
    }

    func addNumberOptions(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        let formats = ["1", "I", "A", "a"]
        let seg = NSSegmentedControl(labels: formats, trackingMode: .selectOne,
                                     target: self, action: #selector(numberFormatChanged(_:)))
        seg.selectedSegment = ov.currentNumberFormat.rawValue
        seg.font = NSFont.systemFont(ofSize: controlFontSize, weight: .medium)
        seg.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: 108, height: controlHeight)
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        addSubview(seg)
        curX += 108

        curX = addSeparator(at: curX)

        let startLabel = NSTextField(labelWithString: L("Start:"))
        startLabel.font = NSFont.systemFont(ofSize: labelFontSize, weight: .medium)
        startLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.52)
        startLabel.sizeToFit()
        startLabel.frame.origin = NSPoint(x: curX, y: (rowHeight - startLabel.frame.height) / 2)
        addSubview(startLabel)
        curX += startLabel.frame.width + 4

        let stepper = NSStepper()
        stepper.minValue = 1
        stepper.maxValue = 999
        stepper.integerValue = ov.numberStartAt
        stepper.target = self
        stepper.action = #selector(numberStartChanged(_:))
        stepper.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: 19, height: controlHeight)
        addSubview(stepper)

        let valLabel = NSTextField(labelWithString: ov.currentNumberFormat.format(ov.numberStartAt))
        valLabel.font = NSFont.monospacedDigitSystemFont(ofSize: valueFontSize, weight: .medium)
        valLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.88)
        valLabel.tag = 999  // tag for finding later
        valLabel.sizeToFit()
        valLabel.frame.origin = NSPoint(x: curX + 22, y: (rowHeight - valLabel.frame.height) / 2)
        addSubview(valLabel)
        curX += 50

        return curX
    }

    func addTextOptions(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x

        // Font family dropdown
        let displayName = ov.textEditor.fontFamily == "System" ? "System" : ov.textEditor.fontFamily
        let fontBtn = NSButton(title: "\(displayName) ▾", target: self, action: #selector(fontFamilyClicked(_:)))
        fontBtn.bezelStyle = .recessed
        fontBtn.font = NSFont.systemFont(ofSize: controlFontSize, weight: .medium)
        fontBtn.attributedTitle = NSAttributedString(string: "\(displayName) ▾", attributes: [
            .font: NSFont.systemFont(ofSize: controlFontSize, weight: .medium),
            .baselineOffset: 0.5,
        ])
        fontBtn.sizeToFit()
        fontBtn.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: max(74, fontBtn.frame.width + 10), height: controlHeight)
        addSubview(fontBtn)
        curX += fontBtn.frame.width + 6

        // Bold / Italic / Underline / Strikethrough
        let textStyles: [(String, String, Bool, Selector, Int)] = [
            ("bold", "B", ov.textEditor.bold, #selector(boldToggled), 980),
            ("italic", "I", ov.textEditor.italic, #selector(italicToggled), 981),
            ("underline", "U", ov.textEditor.underline, #selector(underlineToggled), 982),
            ("strikethrough", "S", ov.textEditor.strikethrough, #selector(strikethroughToggled), 983),
        ]
        for (_, label, isOn, sel, tag) in textStyles {
            let btn = NSButton(title: label, target: self, action: sel)
            btn.bezelStyle = .smallSquare
            btn.isBordered = false
            btn.wantsLayer = true
            btn.tag = tag
            btn.layer?.cornerRadius = 4
            ToolbarLayout.applyContinuousCornerCurve(to: btn.layer)
            btn.layer?.backgroundColor = isOn ? ToolbarLayout.accentColor.withAlphaComponent(0.85).cgColor : nil
            btn.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            btn.attributedTitle = NSAttributedString(string: label, attributes: [
                .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(isOn ? 1.0 : 0.6),
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            ])
            btn.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: 28, height: controlHeight)
            addSubview(btn)
            curX += 30
        }

        curX = addSeparator(at: curX)

        // Alignment buttons
        let alignments: [(String, NSTextAlignment)] = [
            ("text.alignleft", .left), ("text.aligncenter", .center), ("text.alignright", .right)
        ]
        for (symbol, alignment) in alignments {
            let btn = NSButton()
            btn.bezelStyle = .recessed
            btn.isBordered = false
            btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            btn.state = ov.textEditor.alignment == alignment ? .on : .off
            btn.setButtonType(.toggle)
            btn.tag = alignment.rawValue
            btn.target = self
            btn.action = #selector(alignmentChanged(_:))
            btn.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: 28, height: controlHeight)
            addSubview(btn)
            curX += 30
        }

        curX = addSeparator(at: curX)

        // Font size −/+
        let minusBtn = NSButton(title: "−", target: self, action: #selector(fontSizeDecreased))
        minusBtn.bezelStyle = .recessed
        minusBtn.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        minusBtn.isContinuous = true
        (minusBtn.cell as? NSButtonCell)?.setPeriodicDelay(0.3, interval: 0.05)
        minusBtn.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: 22, height: controlHeight)
        addSubview(minusBtn)
        curX += 22

        let sizeLabel = NSTextField(labelWithString: "\(Int(ov.textEditor.fontSize))")
        sizeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: valueFontSize, weight: .medium)
        sizeLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.78)
        sizeLabel.alignment = .center
        sizeLabel.tag = 998
        sizeLabel.frame = NSRect(x: curX, y: (rowHeight - 17) / 2, width: 30, height: 17)
        addSubview(sizeLabel)
        curX += 30

        let plusBtn = NSButton(title: "+", target: self, action: #selector(fontSizeIncreased))
        plusBtn.bezelStyle = .recessed
        plusBtn.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        plusBtn.isContinuous = true
        (plusBtn.cell as? NSButtonCell)?.setPeriodicDelay(0.3, interval: 0.05)
        plusBtn.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: 22, height: controlHeight)
        addSubview(plusBtn)
        curX += 26

        curX = addSeparator(at: curX)

        // Fill: clickable label (toggles on/off) + color swatch (opens color picker)
        let fillSwatchSize: CGFloat = 20
        let fillLabelBtn = NSButton(title: L("Fill"), target: self, action: #selector(textBgToggled(_:)))
        fillLabelBtn.bezelStyle = .recessed
        fillLabelBtn.setButtonType(.toggle)
        fillLabelBtn.state = ov.textEditor.bgEnabled ? .on : .off
        fillLabelBtn.font = NSFont.systemFont(ofSize: controlFontSize, weight: .medium)
        fillLabelBtn.attributedTitle = NSAttributedString(string: L("Fill"), attributes: [
            .font: NSFont.systemFont(ofSize: controlFontSize, weight: .medium),
            .baselineOffset: 0.5,
        ])
        fillLabelBtn.sizeToFit()
        fillLabelBtn.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: max(34, fillLabelBtn.frame.width + 2), height: controlHeight)
        addSubview(fillLabelBtn)
        curX += fillLabelBtn.frame.width + 2

        let fillSwatch = NSButton(frame: NSRect(x: curX, y: (rowHeight - fillSwatchSize) / 2, width: fillSwatchSize, height: fillSwatchSize))
        fillSwatch.title = ""
        fillSwatch.isBordered = false
        fillSwatch.wantsLayer = true
        fillSwatch.layer?.backgroundColor = ov.textEditor.bgColor.cgColor
        fillSwatch.layer?.cornerRadius = 3
        ToolbarLayout.applyContinuousCornerCurve(to: fillSwatch.layer)
        fillSwatch.layer?.borderWidth = 1.5
        fillSwatch.layer?.borderColor = ToolbarLayout.iconColor.withAlphaComponent(0.4).cgColor
        fillSwatch.layer?.opacity = ov.textEditor.bgEnabled ? 1.0 : 0.3
        fillSwatch.tag = 975
        fillSwatch.target = self
        fillSwatch.action = #selector(textBgColorClicked(_:))
        addSubview(fillSwatch)
        curX += fillSwatchSize + 6

        // Outline: clickable label (toggles on/off) + color swatch (opens color picker)
        let outlineLabelBtn = NSButton(title: L("Outline"), target: self, action: #selector(textOutlineToggled(_:)))
        outlineLabelBtn.bezelStyle = .recessed
        outlineLabelBtn.setButtonType(.toggle)
        outlineLabelBtn.state = ov.textEditor.outlineEnabled ? .on : .off
        outlineLabelBtn.font = NSFont.systemFont(ofSize: controlFontSize, weight: .medium)
        outlineLabelBtn.attributedTitle = NSAttributedString(string: L("Outline"), attributes: [
            .font: NSFont.systemFont(ofSize: controlFontSize, weight: .medium),
            .baselineOffset: 0.5,
        ])
        outlineLabelBtn.sizeToFit()
        outlineLabelBtn.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: max(58, outlineLabelBtn.frame.width + 2), height: controlHeight)
        addSubview(outlineLabelBtn)
        curX += outlineLabelBtn.frame.width + 2

        let outlineSwatch = NSButton(frame: NSRect(x: curX, y: (rowHeight - fillSwatchSize) / 2, width: fillSwatchSize, height: fillSwatchSize))
        outlineSwatch.title = ""
        outlineSwatch.isBordered = false
        outlineSwatch.wantsLayer = true
        outlineSwatch.layer?.backgroundColor = ov.textEditor.outlineColor.cgColor
        outlineSwatch.layer?.cornerRadius = 3
        ToolbarLayout.applyContinuousCornerCurve(to: outlineSwatch.layer)
        outlineSwatch.layer?.borderWidth = 1.5
        outlineSwatch.layer?.borderColor = ToolbarLayout.iconColor.withAlphaComponent(0.4).cgColor
        outlineSwatch.layer?.opacity = ov.textEditor.outlineEnabled ? 1.0 : 0.3
        outlineSwatch.tag = 976
        outlineSwatch.target = self
        outlineSwatch.action = #selector(textOutlineColorClicked(_:))
        addSubview(outlineSwatch)
        curX += fillSwatchSize + 6

        // Stroke (per-glyph): clickable label (toggles on/off) + color swatch
        let strokeLabelBtn = NSButton(title: L("Stroke"), target: self, action: #selector(textGlyphStrokeToggled(_:)))
        strokeLabelBtn.bezelStyle = .recessed
        strokeLabelBtn.setButtonType(.toggle)
        strokeLabelBtn.state = ov.textEditor.glyphStrokeEnabled ? .on : .off
        strokeLabelBtn.font = NSFont.systemFont(ofSize: controlFontSize, weight: .medium)
        strokeLabelBtn.attributedTitle = NSAttributedString(string: L("Stroke"), attributes: [
            .font: NSFont.systemFont(ofSize: controlFontSize, weight: .medium),
            .baselineOffset: 0.5,
        ])
        strokeLabelBtn.sizeToFit()
        strokeLabelBtn.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: max(54, strokeLabelBtn.frame.width + 2), height: controlHeight)
        addSubview(strokeLabelBtn)
        curX += strokeLabelBtn.frame.width + 2

        let strokeSwatch = NSButton(frame: NSRect(x: curX, y: (rowHeight - fillSwatchSize) / 2, width: fillSwatchSize, height: fillSwatchSize))
        strokeSwatch.title = ""
        strokeSwatch.isBordered = false
        strokeSwatch.wantsLayer = true
        strokeSwatch.layer?.backgroundColor = ov.textEditor.glyphStrokeColor.cgColor
        strokeSwatch.layer?.cornerRadius = 3
        ToolbarLayout.applyContinuousCornerCurve(to: strokeSwatch.layer)
        strokeSwatch.layer?.borderWidth = 1.5
        strokeSwatch.layer?.borderColor = ToolbarLayout.iconColor.withAlphaComponent(0.4).cgColor
        strokeSwatch.layer?.opacity = ov.textEditor.glyphStrokeEnabled ? 1.0 : 0.3
        strokeSwatch.tag = 977
        strokeSwatch.target = self
        strokeSwatch.action = #selector(textGlyphStrokeColorClicked(_:))
        addSubview(strokeSwatch)
        curX += fillSwatchSize

        // Cancel / Confirm — only when actively editing text, right-aligned
        if ov.textEditor.isEditing {
            curX = addSeparator(at: curX)
            let cancelBtn = NSButton(title: "✕", target: self, action: #selector(textCancelClicked))
            cancelBtn.bezelStyle = .smallSquare
            cancelBtn.isBordered = false
            cancelBtn.wantsLayer = true
            cancelBtn.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.8).cgColor
            cancelBtn.layer?.cornerRadius = 4
            ToolbarLayout.applyContinuousCornerCurve(to: cancelBtn.layer)
            cancelBtn.font = NSFont.systemFont(ofSize: valueFontSize, weight: .bold)
            cancelBtn.attributedTitle = NSAttributedString(string: "✕", attributes: [
                .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: valueFontSize, weight: .bold)])
            cancelBtn.frame = NSRect(x: 0, y: (rowHeight - controlHeight) / 2, width: 30, height: controlHeight)
            cancelBtn.tag = 990
            addSubview(cancelBtn)

            let confirmBtn = NSButton(title: "✓", target: self, action: #selector(textConfirmClicked))
            confirmBtn.bezelStyle = .smallSquare
            confirmBtn.isBordered = false
            confirmBtn.wantsLayer = true
            confirmBtn.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.8).cgColor
            confirmBtn.layer?.cornerRadius = 4
            ToolbarLayout.applyContinuousCornerCurve(to: confirmBtn.layer)
            confirmBtn.font = NSFont.systemFont(ofSize: 13, weight: .bold)
            confirmBtn.attributedTitle = NSAttributedString(string: "✓", attributes: [
                .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13, weight: .bold)])
            confirmBtn.frame = NSRect(x: 0, y: (rowHeight - controlHeight) / 2, width: 30, height: controlHeight)
            confirmBtn.tag = 991
            addSubview(confirmBtn)

            curX += 68  // reserve space for right-aligned buttons
        }
        return curX
    }

    func addMeasureToggle(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        let seg = NSSegmentedControl(labels: ["px", "pt"], trackingMode: .selectOne,
                                     target: self, action: #selector(measureUnitChanged(_:)))
        seg.selectedSegment = ov.currentMeasureInPoints ? 1 : 0
        seg.font = NSFont.systemFont(ofSize: controlFontSize, weight: .medium)
        seg.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: 66, height: controlHeight)
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        addSubview(seg)
        curX += 78

        // Hint
        curX = addHintLabel(at: curX, text: L("Hold 1 auto-vertical  ·  Hold 2 auto-horizontal"))
        return curX
    }

    func addStampOptions(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        // Quick emoji buttons
        for emoji in StampEmojis.common {
            let btn = NSButton(title: emoji, target: self, action: #selector(quickEmojiClicked(_:)))
            btn.bezelStyle = .recessed
            btn.isBordered = false
            btn.font = NSFont.systemFont(ofSize: 18)
            btn.frame = NSRect(x: curX, y: (rowHeight - 26) / 2, width: 26, height: 26)
            addSubview(btn)
            curX += 26
        }
        curX += 4

        curX = addSeparator(at: curX)

        let moreBtn = NSButton()
        moreBtn.bezelStyle = .recessed
        moreBtn.isBordered = false
        moreBtn.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: L("More Emojis"))?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        moreBtn.toolTip = L("More Emojis")
        moreBtn.target = self
        moreBtn.action = #selector(moreEmojisClicked(_:))
        moreBtn.frame = NSRect(x: curX, y: (rowHeight - 26) / 2, width: 28, height: 26)
        addSubview(moreBtn)
        moreBtn.contentTintColor = ToolbarLayout.iconColor  // after addSubview to override auto-tint
        curX += 30

        let loadBtn = NSButton()
        loadBtn.bezelStyle = .recessed
        loadBtn.isBordered = false
        loadBtn.image = NSImage(systemSymbolName: "photo", accessibilityDescription: L("Load Image"))?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        loadBtn.toolTip = L("Load Image")
        loadBtn.target = self
        loadBtn.action = #selector(loadImageClicked)
        loadBtn.frame = NSRect(x: curX, y: (rowHeight - 26) / 2, width: 28, height: 26)
        addSubview(loadBtn)
        loadBtn.contentTintColor = ToolbarLayout.iconColor  // after addSubview to override auto-tint
        curX += 30

        return curX
    }

    func addRedactOptions(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x

        // — Draw mode: All / Text Only segmented control —
        let drawLabel = NSTextField(labelWithString: L("Draw:"))
        drawLabel.font = NSFont.systemFont(ofSize: labelFontSize, weight: .medium)
        drawLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.52)
        drawLabel.sizeToFit()
        drawLabel.frame.origin = NSPoint(x: curX, y: (rowHeight - drawLabel.frame.height) / 2)
        addSubview(drawLabel)
        curX += drawLabel.frame.width + 4

        let textOnly = UserDefaults.standard.bool(forKey: "censorTextOnly")
        let drawSeg = NSSegmentedControl(labels: [L("All"), L("Text Only")], trackingMode: .selectOne,
                                          target: self, action: #selector(drawModeChanged(_:)))
        drawSeg.selectedSegment = textOnly ? 1 : 0
        drawSeg.font = NSFont.systemFont(ofSize: controlFontSize, weight: .medium)
        (drawSeg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        drawSeg.sizeToFit()
        drawSeg.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: drawSeg.frame.width, height: controlHeight)
        addSubview(drawSeg)
        curX += drawSeg.frame.width + 4

        curX = addSeparator(at: curX)

        // — Auto-detect buttons —
        let autoLabel = NSTextField(labelWithString: L("Auto:"))
        autoLabel.font = NSFont.systemFont(ofSize: labelFontSize, weight: .medium)
        autoLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.52)
        autoLabel.sizeToFit()
        autoLabel.frame.origin = NSPoint(x: curX, y: (rowHeight - autoLabel.frame.height) / 2)
        addSubview(autoLabel)
        curX += autoLabel.frame.width + 4

        let btnH: CGFloat = controlHeight
        let btnFont = NSFont.systemFont(ofSize: controlFontSize, weight: .medium)
        let btnY = (rowHeight - btnH) / 2

        curX = addRedactButton(at: curX, title: L("All Text"), action: #selector(redactAllTextClicked),
                               font: btnFont, height: btnH, y: btnY)

        // PII button with dropdown arrow for type selection
        curX = addRedactButton(at: curX, title: L("PII"), action: #selector(redactPIIClicked),
                               font: btnFont, height: btnH, y: btnY,
                               dropdownAction: #selector(redactTypesClicked(_:)))

        curX = addRedactButton(at: curX, title: L("Faces"), action: #selector(redactFacesClicked),
                               font: btnFont, height: btnH, y: btnY)

        curX = addRedactButton(at: curX, title: L("People"), action: #selector(redactPeopleClicked),
                               font: btnFont, height: btnH, y: btnY)

        return curX
    }

    func addBeautifyOptions(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        let isSnap = ov.selectionIsWindowSnap

        // Mode toggle: Window / Rounded — hidden for snapped windows (always uses native chrome)
        if !isSnap {
            let modeSeg = NSSegmentedControl(labels: ["W", "R"], trackingMode: .selectOne,
                                             target: self, action: #selector(beautifyModeChanged(_:)))
            modeSeg.selectedSegment = ov.beautifyMode == .window ? 0 : 1
            modeSeg.font = NSFont.systemFont(ofSize: controlFontSize, weight: .medium)
            modeSeg.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: 62, height: controlHeight)
            (modeSeg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
            addSubview(modeSeg)
            curX += 62

            curX = addSeparator(at: curX)
        }

        // Padding slider
        curX = addBeautifySlider(at: curX, label: L("Padding"), value: ov.beautifyPadding, min: 16, max: 96, action: #selector(beautifyPaddingChanged(_:)))

        // Corner radius slider — hidden for snapped windows (native corners are baked in)
        if !isSnap {
            curX = addBeautifySlider(at: curX, label: L("Radius"), value: ov.beautifyCornerRadius, min: 0, max: 30, action: #selector(beautifyCornerChanged(_:)))
        }

        // Shadow slider
        curX = addBeautifySlider(at: curX, label: L("Shadow"), value: ov.beautifyShadowRadius, min: 0, max: 100, action: #selector(beautifyShadowChanged(_:)))

        // Blur slider — only shown for custom image backgrounds
        if ov.beautifyStyleIndex == -1 {
            curX = addBeautifySlider(at: curX, label: L("Blur"), value: ov.beautifyBackgroundBlur, min: 0, max: 50, action: #selector(beautifyBlurChanged(_:)))
        }

        curX = addSeparator(at: curX)

        // Gradient style picker — swatch preview + dropdown arrow
        curX += 2
        let swatchSize: CGFloat = 22
        let swatchBtn = NSButton(frame: NSRect(x: curX, y: (rowHeight - swatchSize) / 2, width: swatchSize, height: swatchSize))
        swatchBtn.bezelStyle = .recessed
        swatchBtn.isBordered = false
        swatchBtn.image = Self.gradientSwatchImage(styleIndex: ov.beautifyStyleIndex, size: swatchSize)
        swatchBtn.imageScaling = .scaleProportionallyUpOrDown
        swatchBtn.target = self
        swatchBtn.action = #selector(beautifyGradientClicked(_:))
        swatchBtn.toolTip = L("Gradient Style")
        swatchBtn.tag = 995
        addSubview(swatchBtn)
        curX += swatchSize + 2

        let arrowBtn = NSButton(frame: NSRect(x: curX, y: (rowHeight - 16) / 2, width: 14, height: 16))
        arrowBtn.bezelStyle = .recessed
        arrowBtn.isBordered = false
        arrowBtn.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        arrowBtn.target = self
        arrowBtn.action = #selector(beautifyGradientClicked(_:))
        addSubview(arrowBtn)
        arrowBtn.contentTintColor = ToolbarLayout.iconColor.withAlphaComponent(0.6)
        curX += 18

        curX = addSeparator(at: curX)

        // On/off toggle
        let toggleBtn = NSButton(checkboxWithTitle: L("On"), target: self, action: #selector(beautifyToggleChanged(_:)))
        toggleBtn.state = ov.beautifyEnabled ? .on : .off
        toggleBtn.font = NSFont.systemFont(ofSize: controlFontSize, weight: .medium)
        if let cell = toggleBtn.cell as? NSButtonCell {
            cell.attributedTitle = NSAttributedString(string: L("On"), attributes: [
                .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(0.78),
                .font: NSFont.systemFont(ofSize: controlFontSize, weight: .medium)
            ])
        }
        toggleBtn.sizeToFit()
        toggleBtn.frame.origin = NSPoint(x: curX, y: (rowHeight - toggleBtn.frame.height) / 2)
        addSubview(toggleBtn)
        curX += toggleBtn.frame.width + 4

        return curX
    }

    func addBeautifySlider(at x: CGFloat, label: String, value: CGFloat, min: CGFloat, max: CGFloat, action: Selector) -> CGFloat {
        var curX = x
        let lbl = NSTextField(labelWithString: label)
        lbl.font = NSFont.systemFont(ofSize: labelFontSize, weight: .medium)
        lbl.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.62)
        lbl.sizeToFit()
        lbl.frame.origin = NSPoint(x: curX, y: (rowHeight - lbl.frame.height) / 2)
        addSubview(lbl)
        curX += lbl.frame.width + 4

        let slider = NSSlider(value: Double(value), minValue: Double(min), maxValue: Double(max),
                              target: self, action: action)
        slider.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: 66, height: 22)
        slider.isContinuous = true
        addSubview(slider)
        curX += 70

        return curX
    }

}
