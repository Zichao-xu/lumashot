import Cocoa

private enum ToolbarMotion {
    static let hoverDuration: TimeInterval = 0.14
    static let pressDuration: TimeInterval = 0.10
    static let selectionDuration: TimeInterval = 0.16
    static let timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.08, 0.18, 1.0)

    static var progressAnimation: CABasicAnimation {
        let animation = CABasicAnimation()
        animation.timingFunction = timingFunction
        return animation
    }
}

/// Real NSView for a single toolbar button. Handles its own hover, press, drawing.
/// Matches the existing dark toolbar look: purple accent, SF Symbols, color swatches.
class ToolbarButtonView: NSView {

    let action: ToolbarButtonAction
    var sfSymbol: String? { didSet { if oldValue != sfSymbol { cachedIcon = nil; cachedIconIsOn = nil; needsDisplay = true } } }
    var textTitle: String? { didSet { needsDisplay = true } }
    var isOn: Bool = false {
        didSet {
            guard oldValue != isOn else { return }
            cachedIcon = nil
            animateVisualProgress("selectionProgress", to: isOn ? 1 : 0, duration: ToolbarMotion.selectionDuration)
        }
    }
    var tintColor: NSColor = ToolbarLayout.iconColor { didSet { cachedIcon = nil; cachedIconIsOn = nil; needsDisplay = true } }
    var swatchColor: NSColor? { didSet { needsDisplay = true } }
    var hasContextMenu: Bool = false
    var role: ToolbarButtonRole = .normal { didSet { cachedIcon = nil; cachedIconIsOn = nil; needsDisplay = true } }
    var usesNativeGlassBackground: Bool = false { didSet { needsDisplay = true } }
    var usesSharedSelectionIndicator: Bool = false { didSet { needsDisplay = true } }
    /// Mic input level (0–1). When > 0, draws a green fill from the bottom of the button.
    var micLevel: Float = 0 { didSet { if abs(oldValue - micLevel) > 0.005 { needsDisplay = true } } }

    private var isHovered: Bool = false
    var isPressed: Bool = false
    private var trackingArea: NSTrackingArea?
    private var cachedIcon: NSImage?       // cached tinted SF Symbol for current state
    private var cachedIconIsOn: Bool?       // the isOn state when icon was cached
    @objc dynamic var hoverProgress: CGFloat = 0 { didSet { needsDisplay = true } }
    @objc dynamic var pressProgress: CGFloat = 0 { didSet { needsDisplay = true } }
    @objc dynamic var selectionProgress: CGFloat = 0 { didSet { needsDisplay = true } }

    /// Shared cross-instance cache: avoids re-rasterizing SF Symbols when toolbar is rebuilt.
    /// Key: "symbolName|isOn|colorHex"
    private static var iconCache: [String: NSImage] = [:]

    private static func cacheKey(name: String, isOn: Bool, color: NSColor, pointSize: CGFloat, role: ToolbarButtonRole) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: nil)
        return "\(name)|\(isOn)|\(Int(pointSize))|\(role)|\(Int(r*255)),\(Int(g*255)),\(Int(b*255))"
    }

    var onClick: ((ToolbarButtonAction) -> Void)?
    var onMouseDown: ((ToolbarButtonAction) -> Void)?
    var onRightClick: ((ToolbarButtonAction, NSView) -> Void)?
    var onHover: ((ToolbarButtonAction, Bool) -> Void)?  // (action, isHovered)

    static let size: CGFloat = 36
    static let auxiliarySize: CGFloat = 52
    static let destructiveSize: CGFloat = 56
    static let primarySize: CGFloat = 62

    var visualSize: CGFloat {
        switch role {
        case .primary:
            return Self.primarySize
        case .auxiliary:
            return Self.auxiliarySize
        case .destructive:
            return Self.destructiveSize
        case .normal:
            return Self.size
        }
    }

    private func buttonCornerRadius(for rect: NSRect) -> CGFloat {
        switch role {
        case .auxiliary, .primary, .destructive:
            return min(rect.width, rect.height) / 2
        case .normal:
            return ToolbarLayout.buttonCornerRadius
        }
    }

    private func makeButtonPath(in rect: NSRect) -> NSBezierPath {
        if role != .normal && abs(rect.width - rect.height) < 0.5 {
            return ToolbarLayout.circlePath(in: rect)
        }
        return ToolbarLayout.continuousRoundedPath(in: rect, radius: buttonCornerRadius(for: rect))
    }

    private func makeButtonPath(in rect: NSRect, inset: CGFloat) -> NSBezierPath {
        if role != .normal && abs(rect.width - rect.height) < 0.5 {
            return ToolbarLayout.circlePath(in: rect.insetBy(dx: inset, dy: inset))
        }
        return ToolbarLayout.continuousRoundedPath(
            in: rect,
            radius: buttonCornerRadius(for: rect),
            inset: inset)
    }

    var tooltipText: String = ""

    init(action: ToolbarButtonAction, sfSymbol: String?, tooltip: String, textTitle: String? = nil) {
        self.action = action
        self.sfSymbol = sfSymbol
        self.textTitle = textTitle
        self.tooltipText = tooltip
        super.init(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        wantsLayer = true
        layer?.masksToBounds = false
        animations = [
            NSAnimatablePropertyKey("hoverProgress"): ToolbarMotion.progressAnimation,
            NSAnimatablePropertyKey("pressProgress"): ToolbarMotion.progressAnimation,
            NSAnimatablePropertyKey("selectionProgress"): ToolbarMotion.progressAnimation,
        ]
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let scale = 1 + hoverProgress * 0.012 - pressProgress * 0.035
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: bounds.midX, yBy: bounds.midY)
        transform.scale(by: scale)
        transform.translateX(by: -bounds.midX, yBy: -bounds.midY)
        transform.concat()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let buttonRect = usesNativeGlassBackground ? bounds : (role == .normal ? bounds : bounds.insetBy(dx: 1.5, dy: 1.5))
        let buttonPath = makeButtonPath(in: buttonRect)
        let bg = animatedBackgroundColor()
        bg.setFill()
        if role != .normal {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            let shadowAlpha = (usesNativeGlassBackground ? 0.16 : 0.28) * (0.72 + 0.28 * max(selectionProgress, hoverProgress))
            shadow.shadowColor = NSColor.black.withAlphaComponent(shadowAlpha)
            shadow.shadowBlurRadius = usesNativeGlassBackground ? 8 : (role == .primary ? 13 : 11)
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            buttonPath.fill()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            buttonPath.fill()
        }

        if role != .normal {
            let innerBorder = makeButtonPath(in: buttonRect, inset: 0.75)
            NSColor.white.withAlphaComponent(usesNativeGlassBackground ? 0.18 : 0.18).setStroke()
            innerBorder.lineWidth = 1
            innerBorder.stroke()

            let outerBorder = makeButtonPath(in: buttonRect)
            NSColor.black.withAlphaComponent(usesNativeGlassBackground ? 0.28 : 0.30).setStroke()
            outerBorder.lineWidth = 1
            outerBorder.stroke()
        }

        // Mic level fill — green bar rising from the bottom inside the button
        if micLevel > 0.001 {
            NSGraphicsContext.saveGraphicsState()
            makeButtonPath(in: bounds).addClip()
            let fillH = bounds.height * CGFloat(min(micLevel, 1.0))
            let fillRect = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: fillH)
            NSColor.systemGreen.withAlphaComponent(0.45).setFill()
            fillRect.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // Color swatch
        if let swatch = swatchColor {
            let inset: CGFloat = 6
            let r = bounds.insetBy(dx: inset, dy: inset)
            swatch.setFill()
            ToolbarLayout.continuousRoundedPath(in: r, radius: ToolbarLayout.swatchCornerRadius).fill()
            ToolbarLayout.iconColor.withAlphaComponent(0.4).setStroke()
            let border = ToolbarLayout.continuousRoundedPath(
                in: r,
                radius: ToolbarLayout.swatchCornerRadius,
                inset: 0.5)
            border.lineWidth = 0.5
            border.stroke()
            return
        }

        if let textTitle {
            let color: NSColor
            if role == .primary || role == .destructive || (role == .auxiliary && isOn) {
                color = .white
            } else if isOn {
                color = tintColor
            } else {
                color = ToolbarLayout.iconColor.withAlphaComponent(0.86)
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: color,
            ]
            let str = textTitle as NSString
            let size = str.size(withAttributes: attrs)
            str.draw(
                at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                withAttributes: attrs)
            return
        }

        // SF Symbol or custom icon (static cache survives toolbar rebuilds)
        guard let name = sfSymbol else { return }
        let currentIsOn = isOn
        if cachedIcon == nil || cachedIconIsOn != currentIsOn {
            let color: NSColor
            if role == .primary || role == .destructive {
                color = .white
            } else if currentIsOn {
                color = role == .auxiliary ? tintColor : ToolbarLayout.iconColor
            } else {
                switch role {
                case .primary:
                    color = .white
                case .auxiliary:
                    color = tintColor
                case .destructive:
                    color = .white
                case .normal:
                    color = tintColor
                }
            }
            let pointSize = Self.iconPointSize(for: role)
            let key = Self.cacheKey(name: name, isOn: currentIsOn, color: color, pointSize: pointSize, role: role)
            if let cached = Self.iconCache[key] {
                cachedIcon = cached
                cachedIconIsOn = currentIsOn
            } else {
                let img = Self.renderedIcon(
                    named: name,
                    color: color,
                    pointSize: pointSize,
                    weight: role == .normal ? .medium : .semibold)
                if let img = img {
                    img.lockFocus(); img.unlockFocus()
                    Self.iconCache[key] = img
                    cachedIcon = img
                    cachedIconIsOn = currentIsOn
                }
            }
        }
        if let icon = cachedIcon {
            let x = bounds.midX - icon.size.width / 2
            let y = bounds.midY - icon.size.height / 2
            icon.draw(at: NSPoint(x: x, y: y), from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        // Context menu triangle
        if hasContextMenu {
            let s: CGFloat = 4
            let path = NSBezierPath()
            path.move(to: NSPoint(x: bounds.maxX - s - 3, y: bounds.minY + 3))
            path.line(to: NSPoint(x: bounds.maxX - 3, y: bounds.minY + 3))
            path.line(to: NSPoint(x: bounds.maxX - 3, y: bounds.minY + 3 + s))
            path.close()
            ToolbarLayout.iconColor.withAlphaComponent(0.4).setFill()
            path.fill()
        }
    }

    // MARK: - Events

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        animateVisualProgress("hoverProgress", to: 1, duration: ToolbarMotion.hoverDuration)
        onHover?(action, true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        animateVisualProgress("hoverProgress", to: 0, duration: ToolbarMotion.hoverDuration)
        onHover?(action, false)
    }

    private var forwardingDrag = false
    /// The view that should receive forwarded drag events (set by onMouseDown handler).
    var dragForwardTarget: NSView?

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        animateVisualProgress("pressProgress", to: 1, duration: ToolbarMotion.pressDuration)
        if onMouseDown != nil {
            onMouseDown?(action)
            if dragForwardTarget != nil {
                forwardingDrag = true
            }
            return
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if forwardingDrag, let target = dragForwardTarget {
            target.mouseDragged(with: event)
            return
        }
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = isPressed
        isPressed = false
        animateVisualProgress("pressProgress", to: 0, duration: ToolbarMotion.pressDuration)
        if forwardingDrag, let target = dragForwardTarget {
            forwardingDrag = false
            target.mouseUp(with: event)
            return
        }
        forwardingDrag = false
        if wasPressed && bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?(action)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(action, self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    private func animateVisualProgress(_ key: String, to value: CGFloat, duration: TimeInterval) {
        guard window != nil else {
            setValue(value, forKey: key)
            needsDisplay = true
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = ToolbarMotion.timingFunction
            animator().setValue(value, forKey: key)
        }
    }

    private func animatedBackgroundColor() -> NSColor {
        let hover = max(0, min(1, hoverProgress))
        let press = max(0, min(1, pressProgress))
        let selected = max(0, min(1, selectionProgress))
        let base: NSColor
        let selectedColor: NSColor
        let pressedColor: NSColor

        switch role {
        case .normal:
            base = ToolbarLayout.iconColor.withAlphaComponent(0.12 * hover)
            if usesSharedSelectionIndicator {
                selectedColor = base
                pressedColor = ToolbarLayout.iconColor.withAlphaComponent(0.16)
            } else {
                selectedColor = ToolbarLayout.accentColor.withAlphaComponent(selected)
                pressedColor = ToolbarLayout.accentColor.withAlphaComponent(0.60)
            }
        case .auxiliary:
            let baseAlpha = usesNativeGlassBackground ? (0.26 + 0.08 * hover) : (0.30 + 0.16 * hover)
            base = ToolbarLayout.bgColor.withAlphaComponent(baseAlpha)
            selectedColor = ToolbarLayout.accentColor.withAlphaComponent(usesNativeGlassBackground ? 0.72 : 0.78)
            pressedColor = ToolbarLayout.iconColor.withAlphaComponent(usesNativeGlassBackground ? 0.18 : 0.20)
        case .primary, .destructive:
            let baseAlpha = usesNativeGlassBackground ? (0.26 + 0.08 * hover) : (0.30 + 0.16 * hover)
            base = ToolbarLayout.bgColor.withAlphaComponent(baseAlpha)
            selectedColor = ToolbarLayout.bgColor.withAlphaComponent(usesNativeGlassBackground ? 0.34 : 0.38)
            pressedColor = ToolbarLayout.iconColor.withAlphaComponent(usesNativeGlassBackground ? 0.18 : 0.20)
        }

        return Self.blend(Self.blend(base, selectedColor, progress: selected), pressedColor, progress: press)
    }

    private static func blend(_ from: NSColor, _ to: NSColor, progress: CGFloat) -> NSColor {
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

    // MARK: - Custom checkerboard icon

    static func menuIcon(named name: String?, color: NSColor = ToolbarLayout.iconColor) -> NSImage? {
        guard let name else { return nil }
        return renderedIcon(named: name, color: color, pointSize: 15, weight: .medium)
    }

    private static func iconPointSize(for role: ToolbarButtonRole) -> CGFloat {
        switch role {
        case .primary:
            return 34
        case .auxiliary:
            return 25
        case .destructive:
            return 30
        case .normal:
            return 16
        }
    }

    private static func renderedIcon(
        named name: String,
        color: NSColor,
        pointSize: CGFloat,
        weight: NSFont.Weight
    ) -> NSImage? {
        if name == "_custom.checkerboard" {
            return checkerboardIcon(color: color)
        }
        if name == "_custom.textbox" {
            return textBoxIcon(color: color)
        }

        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else {
            return nil
        }

        return NSImage(size: symbol.size, flipped: false) { r in
            symbol.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1.0)
            color.setFill()
            r.fill(using: .sourceAtop)
            return true
        }
    }

    /// Generate a checkerboard icon matching the style of SF Symbols, tinted with the given color.
    /// The result is a rounded square with a 4x4 checkerboard pattern.
    private static func checkerboardIcon(color: NSColor) -> NSImage {
        let size: CGFloat = 16
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let cornerRadius: CGFloat = 3
            let cellSize = size / 4
            let clip = ToolbarLayout.continuousRoundedPath(
                in: NSRect(x: 0, y: 0, width: size, height: size),
                radius: cornerRadius)
            clip.addClip()

            for row in 0..<4 {
                for col in 0..<4 {
                    let isDark = (row + col) % 2 == 0
                    if isDark {
                        color.setFill()
                    } else {
                        color.withAlphaComponent(0.35).setFill()
                    }
                    let cellRect = NSRect(x: CGFloat(col) * cellSize, y: CGFloat(row) * cellSize,
                                          width: cellSize, height: cellSize)
                    cellRect.fill()
                }
            }
            return true
        }
        return img
    }

    private static func textBoxIcon(color: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            let box = rect.insetBy(dx: 1.5, dy: 1.5)
            let path = ToolbarLayout.continuousRoundedPath(in: box, radius: 1.5)
            color.setStroke()
            path.lineWidth = 1.7
            path.stroke()

            let glyph = NSBezierPath()
            glyph.lineWidth = 1.7
            glyph.lineCapStyle = .butt
            glyph.move(to: NSPoint(x: rect.midX - 4.8, y: rect.midY + 3.1))
            glyph.line(to: NSPoint(x: rect.midX + 4.8, y: rect.midY + 3.1))
            glyph.move(to: NSPoint(x: rect.midX, y: rect.midY + 3.1))
            glyph.line(to: NSPoint(x: rect.midX, y: rect.midY - 4.4))
            color.setStroke()
            glyph.stroke()
            return true
        }
    }
}
