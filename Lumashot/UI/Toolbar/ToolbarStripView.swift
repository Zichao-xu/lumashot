import Cocoa

/// Real NSView container for a row (horizontal) or column (vertical) of ToolbarButtonViews.
/// Dark rounded background matching the existing toolbar look.
class ToolbarStripView: NSView {

    enum Orientation { case horizontal, vertical }

    let orientation: Orientation
    private(set) var buttonViews: [ToolbarButtonView] = []
    /// Set to true in editor mode so gap clicks pass through to the image beneath.
    var passesThrough = false

    var onClick: ((ToolbarButtonAction) -> Void)?
    var onRightClick: ((ToolbarButtonAction, NSView) -> Void)?
    var onHover: ((ToolbarButtonAction, Bool) -> Void)?

    private let padding: CGFloat = ToolbarLayout.toolbarPadding
    private let spacing: CGFloat = 3
    private let detachedActionGap: CGFloat = 10
    private let detachedActionSpacing: CGFloat = 8
    private var glassBodyView: NSView?
    private var detachedButtonGlassViews: [NSView] = []

    private var hasDetachedActions: Bool {
        orientation == .horizontal && buttonViews.contains { $0.role != .normal }
    }

    private var baseHeight: CGFloat {
        ToolbarButtonView.size + padding * 2
    }

    private var hitBounds: NSRect {
        buttonViews.reduce(toolbarBodyRect) { partial, view in
            partial.union(view.frame)
        }
    }

    private var toolbarBodyRect: NSRect {
        guard hasDetachedActions,
              let firstDetachedButton = buttonViews.first(where: { $0.role != .normal })
        else {
            return bounds
        }
        return NSRect(
            x: bounds.minX,
            y: bounds.midY - baseHeight / 2,
            width: max(0, firstDetachedButton.frame.minX - detachedActionGap),
            height: baseHeight)
    }

    var mainBodyWidth: CGFloat {
        toolbarBodyRect.width
    }

    init(orientation: Orientation) {
        self.orientation = orientation
        super.init(frame: .zero)
        configureGlassBodyViewIfAvailable()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Rebuild buttons from ToolbarButton data.
    func setButtons(_ buttons: [ToolbarButton]) {
        for bv in buttonViews { bv.removeFromSuperview() }
        buttonViews.removeAll()
        removeDetachedButtonGlassViews()

        for data in buttons {
            let bv = ToolbarButtonView(action: data.action, sfSymbol: data.sfSymbol, tooltip: data.tooltip)
            bv.isOn = data.isSelected
            bv.tintColor = data.tintColor
            bv.textTitle = data.textTitle
            bv.swatchColor = data.bgColor
            bv.hasContextMenu = data.hasContextMenu
            bv.role = data.role
            bv.usesNativeGlassBackground = false
            bv.onClick = { [weak self] action in self?.onClick?(action) }
            bv.onRightClick = { [weak self] action, view in self?.onRightClick?(action, view) }
            bv.onHover = { [weak self] action, hovered in self?.onHover?(action, hovered) }
            addSubview(bv)
            buttonViews.append(bv)
        }
        layoutButtons()
    }

    /// Update visual state without rebuilding.
    func updateState(from buttons: [ToolbarButton]) {
        for (i, data) in buttons.enumerated() where i < buttonViews.count {
            buttonViews[i].isOn = data.isSelected
            buttonViews[i].tintColor = data.tintColor
            buttonViews[i].textTitle = data.textTitle
            buttonViews[i].swatchColor = data.bgColor
            buttonViews[i].sfSymbol = data.sfSymbol
            buttonViews[i].role = data.role
            buttonViews[i].usesNativeGlassBackground = nativeGlassAvailable && data.role != .normal
            buttonViews[i].needsDisplay = true
        }
    }

    private func layoutButtons() {
        let btnSize = ToolbarButtonView.size
        let count = CGFloat(buttonViews.count)
        guard count > 0 else { frame.size = .zero; return }

        switch orientation {
        case .horizontal:
            let maxVisualSize = buttonViews.map(\.visualSize).max() ?? btnSize
            let h = hasDetachedActions ? max(baseHeight, maxVisualSize) : baseHeight
            var nextX = padding
            var maxX: CGFloat = 0
            var previousWasDetached = false
            for bv in buttonViews {
                let visualSize = bv.visualSize
                let isDetached = bv.role != .normal
                bv.usesNativeGlassBackground = nativeGlassAvailable && isDetached
                let xOrigin: CGFloat
                if isDetached {
                    xOrigin = nextX + (previousWasDetached ? detachedActionSpacing : detachedActionGap)
                } else {
                    xOrigin = nextX
                }
                let yOrigin = (h - visualSize) / 2
                bv.frame = NSRect(x: xOrigin, y: yOrigin, width: visualSize, height: visualSize)
                maxX = max(maxX, bv.frame.maxX)
                nextX = bv.frame.maxX + (isDetached ? 0 : extraGap(after: bv.action))
                previousWasDetached = isDetached
            }
            frame.size = NSSize(width: maxX + padding, height: h)
        case .vertical:
            let w = btnSize + padding * 2
            let h = count * btnSize + max(0, count - 1) * spacing + padding * 2
            frame.size = NSSize(width: w, height: h)
            for (i, bv) in buttonViews.enumerated() {
                // First button at top
                bv.frame.origin = NSPoint(x: padding, y: h - padding - btnSize - CGFloat(i) * (btnSize + spacing))
            }
        }
        updateGlassBodyView()
        updateDetachedButtonGlassViews()
    }

    private func extraGap(after action: ToolbarButtonAction) -> CGFloat {
        guard orientation == .horizontal else { return spacing }
        switch action {
        case .translate, .hdrToggle, .redo, .share, .cancel:
            return 12
        default:
            return spacing
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let bodyRect: NSRect
        if hasDetachedActions {
            bodyRect = toolbarBodyRect
        } else {
            bodyRect = bounds
        }
        let radius = ToolbarLayout.toolbarCornerRadius
        let bodyPath = ToolbarLayout.continuousRoundedPath(in: bodyRect, radius: radius)

        if glassBodyView == nil {
            ToolbarLayout.bgColor.withAlphaComponent(0.72).setFill()
            bodyPath.fill()
        } else {
            ToolbarLayout.bgColor.withAlphaComponent(0.26).setFill()
            bodyPath.fill()
        }

        NSColor.white.withAlphaComponent(glassBodyView == nil ? 0.09 : 0.18).setStroke()
        let inner = ToolbarLayout.continuousRoundedPath(in: bodyRect, radius: radius, inset: 0.75)
        inner.lineWidth = 1
        inner.stroke()

        NSColor.black.withAlphaComponent(glassBodyView == nil ? 0.28 : 0.28).setStroke()
        bodyPath.lineWidth = 1
        bodyPath.stroke()
    }

    // Consume clicks on gaps between buttons so they don't fall through to OverlayView.
    // In editor mode (passesThrough), let gap clicks pass through so drawing works
    // over the toolbar area.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard hitBounds.contains(local) else { return nil }
        for bv in buttonViews.reversed() {
            let buttonLocal = bv.convert(point, from: superview)
            if bv.bounds.contains(buttonLocal) {
                return bv
            }
        }
        if let result = super.hitTest(point), result !== self { return result }
        if passesThrough { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}

    override func resetCursorRects() {
        addCursorRect(hitBounds, cursor: .arrow)
    }

    func containsPointInSuperview(_ point: NSPoint) -> Bool {
        let local = convert(point, from: superview)
        return hitBounds.contains(local)
    }

    private func configureGlassBodyViewIfAvailable() {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = ToolbarLayout.toolbarCornerRadius
            glass.tintColor = ToolbarLayout.bgColor.withAlphaComponent(0.16)
            glass.isHidden = true
            addSubview(glass, positioned: .below, relativeTo: nil)
            glassBodyView = glass
        }
    }

    private func updateGlassBodyView() {
        guard let glassBodyView else { return }
        glassBodyView.frame = toolbarBodyRect
        glassBodyView.isHidden = toolbarBodyRect.width <= 0 || toolbarBodyRect.height <= 0

        if #available(macOS 26.0, *), let glass = glassBodyView as? NSGlassEffectView {
            glass.cornerRadius = ToolbarLayout.toolbarCornerRadius
            glass.style = .regular
            glass.tintColor = ToolbarLayout.bgColor.withAlphaComponent(0.16)
        }
        needsDisplay = true
    }

    private var nativeGlassAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    private func removeDetachedButtonGlassViews() {
        detachedButtonGlassViews.forEach { $0.removeFromSuperview() }
        detachedButtonGlassViews.removeAll()
    }

    private func updateDetachedButtonGlassViews() {
        removeDetachedButtonGlassViews()
        guard nativeGlassAvailable else { return }

        if #available(macOS 26.0, *) {
            let firstButton = buttonViews.first
            for buttonView in buttonViews where buttonView.role != .normal {
                let glass = NSGlassEffectView()
                glass.style = .regular
                glass.cornerRadius = Self.glassCornerRadius(for: buttonView)
                glass.tintColor = ToolbarLayout.bgColor.withAlphaComponent(0.16)
                glass.frame = buttonView.frame
                glass.autoresizingMask = []
                addSubview(glass, positioned: .below, relativeTo: firstButton)
                detachedButtonGlassViews.append(glass)
            }
        }
    }

    private static func glassCornerRadius(for buttonView: ToolbarButtonView) -> CGFloat {
        switch buttonView.role {
        case .auxiliary, .primary, .destructive:
            return buttonView.visualSize / 2
        case .normal:
            return ToolbarLayout.buttonCornerRadius
        }
    }
}
