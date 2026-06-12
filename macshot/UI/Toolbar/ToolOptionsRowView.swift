import Cocoa

/// Real NSView-based tool options row, replacing the custom-drawn drawToolOptionsRow().
/// Dynamically rebuilds its content when the selected tool changes.
class ToolOptionsRowView: NSView {

    weak var overlayView: OverlayView?
    var currentTool: AnnotationTool?
    /// When set, the options row edits this annotation's properties instead of global tool state.
    var editingAnnotation: Annotation?
    /// Snapshot taken before the first property edit, for undo.
    var editingSnapshot: Annotation?
    let rowHeight: CGFloat = 38
    let padding: CGFloat = 8
    let controlHeight: CGFloat = 24
    let labelFontSize: CGFloat = 11
    let controlFontSize: CGFloat = 12
    let valueFontSize: CGFloat = 12
    var glassBackgroundView: NSView?
    var toolbarVisibilityTarget = false
    /// The natural content width calculated during rebuild, before any external resizing.
    var contentWidth: CGFloat = 0
    // Consume clicks on gaps between controls so they don't fall through to OverlayView.
    // In editor mode, let gap clicks pass through so drawing works over the options area.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if let result = super.hitTest(point), result !== self { return result }
        if overlayView?.isEditorMode == true { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    /// Auto-tint controls to match toolbar accent color.
    /// Buttons with tag 990+ are excluded (they have custom colors like red/green/white).
    override func addSubview(_ view: NSView) {
        super.addSubview(view)
        if let btn = view as? NSButton, btn.tag < 990 { btn.contentTintColor = ToolbarLayout.accentColor }
        if let slider = view as? NSSlider { slider.trackFillColor = ToolbarLayout.accentColor }
        if let seg = view as? NSSegmentedControl { seg.selectedSegmentBezelColor = ToolbarLayout.accentColor }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = ToolbarLayout.optionsRowCornerRadius
        ToolbarLayout.applyContinuousCornerCurve(to: layer)
        layer?.backgroundColor = NSColor.clear.cgColor
        configureGlassBackgroundViewIfAvailable()
        // Match appearance to toolbar background brightness so system controls
        // (NSSegmentedControl labels, NSTextField, NSButton titles) stay readable.
        appearance = ToolbarLayout.appearance
    }

    required init?(coder: NSCoder) { fatalError() }

    func setToolbarVisible(_ visible: Bool, animated: Bool) {
        if visible {
            let finalOrigin = frame.origin
            let shouldAnimate = animated && (!toolbarVisibilityTarget || isHidden || alphaValue < 0.99)
            toolbarVisibilityTarget = true
            isHidden = false

            if shouldAnimate {
                alphaValue = 0
                frame.origin = NSPoint(x: finalOrigin.x, y: finalOrigin.y + 5)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.08, 0.18, 1.0)
                    animator().alphaValue = 1
                    animator().setFrameOrigin(finalOrigin)
                }
            } else {
                alphaValue = 1
                frame.origin = finalOrigin
            }
        } else {
            guard toolbarVisibilityTarget || !isHidden else { return }
            toolbarVisibilityTarget = false

            guard animated && !isHidden else {
                alphaValue = 0
                isHidden = true
                return
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.08, 0.18, 1.0)
                animator().alphaValue = 0
            } completionHandler: { [weak self] in
                guard let self, !self.toolbarVisibilityTarget else { return }
                self.isHidden = true
                self.alphaValue = 0
            }
        }
    }

    /// Rebuild the options row for a selected annotation's tool, reading values from the annotation.
    func rebuild(forAnnotation ann: Annotation) {
        editingAnnotation = ann
        editingSnapshot = nil  // snapshot taken on first edit
        rebuild(for: ann.tool)
    }

    /// Clear editing state so future rebuilds use global tool defaults.
    /// Update color swatches in-place without rebuilding the entire row.
    func updateSwatchColors() {
        guard let ov = overlayView else { return }
        // Text background swatch (tag 975)
        if let swatch = viewWithTag(975) {
            swatch.layer?.backgroundColor = ov.textEditor.bgColor.cgColor
        }
        // Text outline swatch (tag 976)
        if let swatch = viewWithTag(976) {
            swatch.layer?.backgroundColor = ov.textEditor.outlineColor.cgColor
        }
        // Text glyph-stroke swatch (tag 977)
        if let swatch = viewWithTag(977) {
            swatch.layer?.backgroundColor = ov.textEditor.glyphStrokeColor.cgColor
        }
        // Annotation outline swatch (tag 978)
        if let swatch = viewWithTag(978) {
            let col = editingAnnotation?.outlineColor ?? Self.savedOutlineColor
            swatch.layer?.backgroundColor = col.cgColor
        }
    }

    func clearEditingAnnotation() {
        commitEditingSnapshot()
        editingAnnotation = nil
        editingSnapshot = nil
    }

    /// Push the undo entry if we have a snapshot (i.e., at least one property was changed).
    func commitEditingSnapshot() {
        guard let ann = editingAnnotation, let snapshot = editingSnapshot else { return }
        overlayView?.pushPropertyChangeUndo(annotation: ann, snapshot: snapshot)
        editingSnapshot = nil
    }

    /// Take a snapshot before the first edit so we can undo.
    func ensureSnapshot() {
        guard let ann = editingAnnotation, editingSnapshot == nil else { return }
        editingSnapshot = ann.clone()
    }

    /// Rebuild the options row for the given tool. Call when tool or state changes.
    func rebuild(for tool: AnnotationTool) {
        // Remove old subviews
        subviews
            .filter { $0 !== glassBackgroundView }
            .forEach { $0.removeFromSuperview() }
        ensureGlassBackgroundViewAttached()
        guard let ov = overlayView else { return }

        currentTool = tool
        var curX: CGFloat = padding

        // ── Beautify options (overrides tool options when active) ──
        if ov.showBeautifyInOptionsRow {
            curX = addBeautifyOptions(at: curX, ov: ov)
            finishRowLayout(contentRightX: curX)
            return
        }

        // ── Stroke width slider (most drawing tools) ──
        let hasStroke = [.pencil, .line, .arrow, .rectangle, .ellipse, .marker, .number, .loupe].contains(tool)
        if hasStroke {
            curX = addStrokeSlider(at: curX, tool: tool, ov: ov)
        }

        // ── Line style (line, pencil, rectangle) ──
        let hasLineStyle = [.line, .pencil, .rectangle, .arrow, .ellipse].contains(tool)
        if hasLineStyle {
            if hasStroke { curX = addSeparator(at: curX) }
            curX = addLineStyleSegment(at: curX, ov: ov)
        }

        // ── Arrow style + outline + reverse toggle ──
        if tool == .arrow {
            curX = addSeparator(at: curX)
            curX = addArrowStyleSegment(at: curX, ov: ov)
            curX = addSeparator(at: curX)
            curX = addOutlineControls(at: curX, ov: ov)
            curX = addSeparator(at: curX)
            let flipIsOn = editingAnnotation?.arrowReversed ?? ov.arrowReversed
            curX = addToggle(at: curX, title: L("Flip"), isOn: flipIsOn) { [weak self, weak ov] isOn in
                if let ann = self?.editingAnnotation {
                    self?.ensureSnapshot()
                    ann.arrowReversed = isOn
                    ov?.cachedCompositedImage = nil
                }
                ov?.arrowReversed = isOn
                UserDefaults.standard.set(isOn, forKey: "arrowReversed")
                ov?.needsDisplay = true
            }
        }

        // ── Shape fill style (rectangle, ellipse) ──
        if tool == .rectangle || tool == .ellipse {
            curX = addSeparator(at: curX)
            curX = addShapeFillSegment(at: curX, tool: tool, ov: ov)
        }

        // ── Corner radius slider (rectangle) ──
        if tool == .rectangle {
            curX = addSeparator(at: curX)
            curX = addCornerRadiusSlider(at: curX, ov: ov)
        }



        // ── Pencil smooth mode selector ──
        if tool == .pencil {
            curX = addSeparator(at: curX)
            let seg = NSSegmentedControl(labels: [L("None"), L("Smooth"), L("Refined")],
                                          trackingMode: .selectOne,
                                          target: self, action: #selector(pencilSmoothModeChanged(_:)))
            seg.selectedSegment = ov.pencilSmoothMode
            seg.font = NSFont.systemFont(ofSize: controlFontSize, weight: .medium)
            (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
            seg.sizeToFit()
            seg.frame = NSRect(x: curX, y: (rowHeight - controlHeight) / 2, width: seg.frame.width, height: controlHeight)
            addSubview(seg)
            curX += seg.frame.width + 4

            // ── Pressure sensitivity toggle ──
            curX = addSeparator(at: curX)
            curX = addToggle(at: curX, title: L("Pressure"), isOn: ov.pencilPressureEnabled) { [weak ov] isOn in
                ov?.pencilPressureEnabled = isOn
                UserDefaults.standard.set(isOn, forKey: "pencilPressureEnabled")
            }
        }

        // ── Smart marker toggle ──
        if tool == .marker {
            curX = addSeparator(at: curX)
            curX = addToggle(at: curX, title: L("Smart"), isOn: ov.smartMarkerEnabled) { [weak ov, weak self] isOn in
                ov?.smartMarkerEnabled = isOn
                UserDefaults.standard.set(isOn, forKey: "smartMarkerEnabled")
                ov?.updateCursorForCurrentTool()
                ov?.needsDisplay = true
                // Rebuild to update stroke slider enabled state
                self?.rebuild(for: .marker)
            }
            // Disable stroke slider when smart marker is on (auto-sized)
            if ov.smartMarkerEnabled {
                for sub in subviews {
                    if let slider = sub as? NSSlider, slider.tag == AnnotationTool.marker.rawValue {
                        slider.isEnabled = false
                        slider.alphaValue = 0.35
                    }
                }
                if let label = viewWithTag(997) as? NSTextField {
                    label.alphaValue = 0.35
                }
                // Also dim the "Stroke" label
                for sub in subviews {
                    if let tf = sub as? NSTextField, tf.stringValue == L("Stroke"), tf.tag == 0 {
                        tf.alphaValue = 0.35
                    }
                }
            }
        }

        // ── Number format + start-at ──
        if tool == .number {
            curX = addSeparator(at: curX)
            curX = addNumberOptions(at: curX, ov: ov)
        }

        // ── Text formatting ──
        if tool == .text {
            curX = addTextOptions(at: curX, ov: ov)
        }

        // ── Measure px/pt toggle ──
        if tool == .measure {
            curX = addMeasureToggle(at: curX, ov: ov)
        }

        // ── Stamp/emoji row ──
        if tool == .stamp {
            curX = addStampOptions(at: curX, ov: ov)
        }

        // ── Censor tool: mode selector + redact buttons ──
        if tool == .pixelate {
            curX = addCensorModeSegment(at: curX, ov: ov)
            curX = addSeparator(at: curX)
            curX = addRedactOptions(at: curX, ov: ov)
        }

        // ── Outline toggle + color swatch (line, rectangle, ellipse, number — arrow handled above) ──
        let hasOutlineGeneric: [AnnotationTool] = [.line, .rectangle, .ellipse, .number]
        if hasOutlineGeneric.contains(tool) {
            curX = addSeparator(at: curX)
            curX = addOutlineControls(at: curX, ov: ov)
        }

        finishRowLayout(contentRightX: curX)
    }

    override func layout() {
        super.layout()
        updateGlassBackgroundView()
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = ToolbarLayout.optionsRowCornerRadius
        let path = ToolbarLayout.continuousRoundedPath(in: bounds, radius: radius)
        if glassBackgroundView == nil {
            ToolbarLayout.bgColor.withAlphaComponent(0.72).setFill()
        } else {
            ToolbarLayout.bgColor.withAlphaComponent(0.26).setFill()
        }
        path.fill()

        NSColor.white.withAlphaComponent(glassBackgroundView == nil ? 0.08 : 0.18).setStroke()
        let inner = ToolbarLayout.continuousRoundedPath(in: bounds, radius: radius, inset: 0.75)
        inner.lineWidth = 1
        inner.stroke()

        NSColor.black.withAlphaComponent(glassBackgroundView == nil ? 0.25 : 0.28).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

}

final class ToolbarSwitchControl: NSControl {
    let trackLayer = CALayer()
    let knobLayer = CALayer()
    let checkLayer = CAShapeLayer()
    var isOn: Bool
    @objc dynamic var progress: CGFloat = 0 {
        didSet { updateLayers() }
    }

    init(isOn: Bool) {
        self.isOn = isOn
        super.init(frame: NSRect(x: 0, y: 0, width: 34, height: 20))
        wantsLayer = true
        layer?.masksToBounds = false
        animations = [
            NSAnimatablePropertyKey("progress"): ToolbarOptionsMotion.progressAnimation
        ]

        trackLayer.cornerRadius = 10
        trackLayer.masksToBounds = true
        layer?.addSublayer(trackLayer)

        knobLayer.backgroundColor = ToolbarLayout.iconColor.withAlphaComponent(0.96).cgColor
        knobLayer.cornerRadius = 8
        knobLayer.shadowColor = NSColor.black.cgColor
        knobLayer.shadowOpacity = 0.20
        knobLayer.shadowRadius = 2
        knobLayer.shadowOffset = CGSize(width: 0, height: -1)
        layer?.addSublayer(knobLayer)

        checkLayer.fillColor = nil
        checkLayer.strokeColor = ToolbarLayout.accentColor.cgColor
        checkLayer.lineWidth = 1.5
        checkLayer.lineCap = .round
        checkLayer.lineJoin = .round
        knobLayer.addSublayer(checkLayer)

        progress = isOn ? 1 : 0
        updateLayers()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        updateLayers()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        setOn(!isOn, animated: true)
        sendAction(action, to: target)
    }

    func setOn(_ newValue: Bool, animated: Bool) {
        guard newValue != isOn else { return }
        isOn = newValue
        let targetProgress: CGFloat = newValue ? 1 : 0
        guard animated && window != nil else {
            progress = targetProgress
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = ToolbarOptionsMotion.timingFunction
            animator().setValue(targetProgress, forKey: "progress")
        }
    }

    func updateLayers() {
        let t = max(0, min(1, progress))
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        trackLayer.frame = bounds
        trackLayer.cornerRadius = bounds.height / 2
        trackLayer.backgroundColor = Self.blend(
            ToolbarLayout.iconColor.withAlphaComponent(0.16),
            ToolbarLayout.accentColor.withAlphaComponent(0.88),
            progress: t
        ).cgColor

        let knobSize = bounds.height - 4
        let knobX = 2 + (bounds.width - knobSize - 4) * t
        knobLayer.frame = CGRect(x: knobX, y: 2, width: knobSize, height: knobSize)
        knobLayer.cornerRadius = knobSize / 2
        knobLayer.opacity = Float(0.90 + 0.10 * t)

        checkLayer.frame = knobLayer.bounds
        checkLayer.opacity = Float(t)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: knobSize * 0.30, y: knobSize * 0.50))
        path.addLine(to: CGPoint(x: knobSize * 0.45, y: knobSize * 0.34))
        path.addLine(to: CGPoint(x: knobSize * 0.72, y: knobSize * 0.66))
        checkLayer.path = path

        CATransaction.commit()
    }

    static func blend(_ from: NSColor, _ to: NSColor, progress: CGFloat) -> NSColor {
        let t = max(0, min(1, progress))
        let a = from.usingColorSpace(.sRGB) ?? from
        let b = to.usingColorSpace(.sRGB) ?? to
        var ar: CGFloat = 0
        var ag: CGFloat = 0
        var ab: CGFloat = 0
        var aa: CGFloat = 0
        var br: CGFloat = 0
        var bg: CGFloat = 0
        var bb: CGFloat = 0
        var ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let red = ar + (br - ar) * t
        let green = ag + (bg - ag) * t
        let blue = ab + (bb - ab) * t
        let alpha = aa + (ba - aa) * t
        return NSColor(
            srgbRed: red,
            green: green,
            blue: blue,
            alpha: alpha)
    }
}

private enum ToolbarOptionsMotion {
    static let timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.08, 0.18, 1.0)

    static var progressAnimation: CABasicAnimation {
        let animation = CABasicAnimation()
        animation.timingFunction = timingFunction
        return animation
    }
}

// Helper for toggle closures
class ToggleHandler: NSObject {
    let action: (Bool) -> Void
    init(action: @escaping (Bool) -> Void) { self.action = action }
    @objc func toggled(_ sender: Any) {
        if let toggle = sender as? ToolbarSwitchControl {
            action(toggle.isOn)
        } else if let button = sender as? NSButton {
            action(button.state == .on)
        }
    }
}
