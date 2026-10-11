import Cocoa

extension ToolOptionsRowView {
    // MARK: - Section builders

    func finishRowLayout(contentRightX: CGFloat) {
        let totalW = ceil(max(contentRightX + padding, padding * 2))
        contentWidth = totalW
        frame.size = NSSize(width: totalW, height: rowHeight)

        // Text editing buttons reserve a slot near the trailing edge.
        let textActionRightEdge = totalW - padding
        if let confirmBtn = viewWithTag(991) {
            confirmBtn.frame.origin.x = textActionRightEdge - 30
        }
        if let cancelBtn = viewWithTag(990) {
            cancelBtn.frame.origin.x = textActionRightEdge - 30 - 4 - 30
        }

        updateGlassBackgroundView()
    }

    func configureGlassBackgroundViewIfAvailable() {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = ToolbarLayout.optionsRowCornerRadius
            glass.tintColor = ToolbarLayout.bgColor.withAlphaComponent(0.16)
            glassBackgroundView = glass
            addSubview(glass, positioned: .below, relativeTo: nil)
        }
    }

    func ensureGlassBackgroundViewAttached() {
        guard let glassBackgroundView else { return }
        glassBackgroundView.removeFromSuperview()
        addSubview(glassBackgroundView, positioned: .below, relativeTo: nil)
    }

    func updateGlassBackgroundView() {
        guard let glassBackgroundView else { return }
        glassBackgroundView.frame = bounds
        glassBackgroundView.isHidden = bounds.width <= 0 || bounds.height <= 0
        if #available(macOS 26.0, *), let glass = glassBackgroundView as? NSGlassEffectView {
            glass.style = .regular
            glass.cornerRadius = ToolbarLayout.optionsRowCornerRadius
            glass.tintColor = ToolbarLayout.bgColor.withAlphaComponent(0.16)
        }
        needsDisplay = true
    }

    func addSeparator(at x: CGFloat) -> CGFloat {
        let sep = NSView(frame: NSRect(x: x + 6, y: 8, width: 1, height: rowHeight - 16))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = ToolbarLayout.iconColor.withAlphaComponent(0.1).cgColor
        addSubview(sep)
        return x + 13
    }

    func addStrokeSlider(at x: CGFloat, tool: AnnotationTool, ov: OverlayView) -> CGFloat {
        var curX = x

        let nameLabel = NSTextField(labelWithString: tool == .loupe ? L("Size") : L("Stroke"))
        nameLabel.font = NSFont.systemFont(ofSize: labelFontSize, weight: .medium)
        nameLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.52)
        nameLabel.sizeToFit()
        nameLabel.frame.origin = NSPoint(x: curX, y: (rowHeight - nameLabel.frame.height) / 2)
        addSubview(nameLabel)
        curX += nameLabel.frame.width + 5

        let currentVal = editingAnnotation?.strokeWidth ?? ov.activeStrokeWidthForTool(tool)
        let sliderW: CGFloat = 100
        let slider = NSSlider(value: Double(currentVal),
                              minValue: tool == .loupe ? 40 : 1, maxValue: tool == .loupe ? 320 : 30,
                              target: self, action: #selector(strokeSliderChanged(_:)))
        slider.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: sliderW, height: controlHeight)
        slider.isContinuous = true
        slider.tag = tool.rawValue
        addSubview(slider)
        curX += sliderW + 5

        let val = Int(currentVal)
        let valStr = tool == .loupe ? "\(val)" : "\(val)px"
        let labelW: CGFloat = tool == .loupe ? 38 : 34
        let label = NSTextField(labelWithString: valStr)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: valueFontSize, weight: .medium)
        label.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.72)
        label.alignment = .right
        label.frame = NSRect(x: curX, y: (rowHeight - 17) / 2, width: labelW, height: 17)
        label.tag = 997  // stroke value label
        addSubview(label)
        curX += labelW

        return curX
    }

    func addLineStyleSegment(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        let seg = NSSegmentedControl()
        seg.segmentCount = LineStyle.allCases.count
        seg.trackingMode = .selectOne
        seg.target = self
        seg.action = #selector(lineStyleChanged(_:))
        seg.tag = 979  // tag for finding this segment to disable dashed/dotted when outline is on
        for (i, style) in LineStyle.allCases.enumerated() {
            seg.setImage(Self.lineStyleImage(style), forSegment: i)
            seg.setWidth(36, forSegment: i)
        }
        let currentStyle = editingAnnotation?.lineStyle ?? ov.currentLineStyle
        seg.selectedSegment = currentStyle.rawValue
        let segW = CGFloat(LineStyle.allCases.count) * 36
        seg.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: segW, height: controlHeight)
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect

        // Disable dashed/dotted for rect/ellipse when outline is enabled
        let isShapeTool = [AnnotationTool.rectangle, .ellipse].contains(editingAnnotation?.tool ?? ov.currentTool)
        let hasOutline = editingAnnotation?.outlineColor != nil || (isShapeTool && UserDefaults.standard.bool(forKey: "annotationOutlineEnabled"))
        if isShapeTool && hasOutline {
            for (i, style) in LineStyle.allCases.enumerated() {
                if style != .solid {
                    seg.setEnabled(false, forSegment: i)
                }
            }
            // Force solid if currently dashed/dotted
            if currentStyle != .solid {
                seg.selectedSegment = LineStyle.solid.rawValue
                if let ann = editingAnnotation {
                    ann.lineStyle = .solid
                    ov.cachedCompositedImage = nil
                } else {
                    ov.currentLineStyle = .solid
                }
            }
        }

        addSubview(seg)
        curX += segW
        return curX
    }

    func addArrowStyleSegment(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        let seg = NSSegmentedControl()
        seg.segmentCount = ArrowStyle.allCases.count
        seg.trackingMode = .selectOne
        seg.target = self
        seg.action = #selector(arrowStyleChanged(_:))
        for (i, style) in ArrowStyle.allCases.enumerated() {
            seg.setImage(Self.arrowStyleImage(style), forSegment: i)
            seg.setWidth(30, forSegment: i)
        }
        seg.selectedSegment = (editingAnnotation?.arrowStyle ?? ov.currentArrowStyle).rawValue
        let segW = CGFloat(ArrowStyle.allCases.count) * 30
        seg.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: segW, height: controlHeight)
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        addSubview(seg)
        curX += segW
        return curX
    }

    func addShapeFillSegment(at x: CGFloat, tool: AnnotationTool, ov: OverlayView) -> CGFloat {
        var curX = x
        let isOval = tool == .ellipse
        let seg = NSSegmentedControl()
        seg.segmentCount = RectFillStyle.allCases.count
        seg.trackingMode = .selectOne
        seg.target = self
        seg.action = #selector(shapeFillChanged(_:))
        for (i, style) in RectFillStyle.allCases.enumerated() {
            seg.setImage(Self.shapeFillImage(style, oval: isOval), forSegment: i)
            seg.setWidth(30, forSegment: i)
        }
        seg.selectedSegment = (editingAnnotation?.rectFillStyle ?? ov.currentRectFillStyle).rawValue
        let segW = CGFloat(RectFillStyle.allCases.count) * 30
        seg.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: segW, height: controlHeight)
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        addSubview(seg)
        curX += segW
        return curX
    }

    func addCensorModeSegment(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        let seg = NSSegmentedControl()
        seg.segmentCount = CensorMode.allCases.count
        seg.trackingMode = .selectOne
        seg.target = self
        seg.action = #selector(censorModeChanged(_:))
        seg.font = NSFont.systemFont(ofSize: controlFontSize, weight: .medium)
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        for (i, mode) in CensorMode.allCases.enumerated() {
            seg.setLabel(mode.label, forSegment: i)
            seg.setWidth(0, forSegment: i)
        }
        let currentMode: CensorMode
        if let ann = editingAnnotation, ann.tool == .pixelate || ann.tool == .blur {
            currentMode = ann.censorMode
        } else {
            currentMode = CensorMode(rawValue: UserDefaults.standard.integer(forKey: "censorMode")) ?? .pixelate
        }
        seg.selectedSegment = currentMode.rawValue
        seg.sizeToFit()
        seg.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: seg.frame.width, height: controlHeight)
        addSubview(seg)
        curX += seg.frame.width
        return curX
    }

    /// Add a uniform redact action button using NSSegmentedControl for consistent sizing.
    /// If `dropdownAction` is provided, adds a second narrow segment with a ▾ arrow.
    func addRedactButton(at x: CGFloat, title: String, action: Selector,
                                  font: NSFont, height: CGFloat, y: CGFloat,
                                  dropdownAction: Selector? = nil) -> CGFloat {
        var curX = x
        let seg = NSSegmentedControl()
        seg.trackingMode = .momentary
        seg.font = font
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect

        if dropdownAction != nil {
            seg.segmentCount = 2
            seg.setLabel(title, forSegment: 0)
            seg.setLabel("▾", forSegment: 1)
            seg.setWidth(0, forSegment: 0)
            seg.setWidth(18, forSegment: 1)
            seg.target = self
            seg.action = #selector(piiSegmentClicked(_:))
        } else {
            seg.segmentCount = 1
            seg.setLabel(title, forSegment: 0)
            seg.setWidth(0, forSegment: 0)
            seg.target = self
            seg.action = action
        }

        seg.sizeToFit()
        seg.frame = NSRect(x: curX, y: y, width: seg.frame.width, height: height)
        addSubview(seg)
        curX += seg.frame.width + 4
        return curX
    }

    @objc func piiSegmentClicked(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            redactPIIClicked()
        } else {
            redactTypesClicked(sender)
        }
    }

}
