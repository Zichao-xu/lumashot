import Cocoa

extension EffectsBandView {
    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        layoutRows()

        guard duration > 0, bounds.width > horizontalInset * 2 else { return }

        let row0 = row0Rect

        // Background across every row (continuous rounded strip).
        let bandRect = NSRect(
            x: row0.minX,
            y: row0.minY,
            width: row0.width,
            height: CGFloat(effectRowCount) * rowStride - rowGap
        )
        let bgPath = NSBezierPath(roundedRect: bandRect, xRadius: 5, yRadius: 5)
        ToolbarLayout.iconColor.withAlphaComponent(0.06).setFill()
        bgPath.fill()

        // Separator lines between stacked rows.
        if effectRowCount >= 2 {
            NSColor.white.withAlphaComponent(0.10).setFill()
            for i in 1..<effectRowCount {
                let y = row0.minY + CGFloat(i) * rowStride - 1
                NSBezierPath(rect: NSRect(x: row0.minX, y: y, width: row0.width, height: 1)).fill()
            }
        }

        // Pills.
        for seg in zoomSegments {
            let rect = zoomPillRect(for: seg)
            guard rect.width > 0 else { continue }
            drawEffectPill(
                rect: rect,
                isSelected: seg.id == selectedSegmentID,
                baseFillColor: NSColor(calibratedRed: 0.25, green: 0.55, blue: 1.0, alpha: 1.0),
                fadeInFrac: seg.effectiveFadeIn / max(seg.duration, 0.001),
                fadeOutFrac: seg.effectiveFadeOut / max(seg.duration, 0.001),
                iconSymbol: "plus.magnifyingglass",
                label: formatZoom(seg.zoomLevel)
            )
        }
        for seg in censorSegments {
            let rect = censorPillRect(for: seg)
            guard rect.width > 0 else { continue }
            let styleIcon: String
            let styleLabel: String
            switch seg.style {
            case .solid:    styleIcon = "square.fill";           styleLabel = L("Solid")
            case .pixelate: styleIcon = "squareshape.split.2x2"; styleLabel = L("Pixelate")
            case .blur:     styleIcon = "drop.fill";             styleLabel = L("Blur")
            }
            drawEffectPill(
                rect: rect,
                isSelected: seg.id == selectedSegmentID,
                baseFillColor: NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.35, alpha: 1.0),
                fadeInFrac: seg.effectiveFadeIn / max(seg.duration, 0.001),
                fadeOutFrac: seg.effectiveFadeOut / max(seg.duration, 0.001),
                iconSymbol: styleIcon,
                label: styleLabel
            )
        }
        // Speed — drawn before cuts but after zoom/censor. Teal pill with
        // factor text.
        for seg in speedSegments {
            let rect = speedPillRect(for: seg)
            guard rect.width > 0 else { continue }
            // tortoise.fill is wider + has more trailing whitespace than
            // forward.fill, so it needs an even bigger gap to not kiss the
            // factor text.
            let isSlow = seg.speedFactor < 1.0
            drawEffectPill(
                rect: rect,
                isSelected: seg.id == selectedSegmentID,
                baseFillColor: NSColor(calibratedRed: 0.20, green: 0.65, blue: 0.60, alpha: 1.0),
                fadeInFrac: 0,
                fadeOutFrac: 0,
                iconSymbol: isSlow ? "tortoise.fill" : "forward.fill",
                label: formatSpeedLabel(seg.speedFactor),
                iconLabelGap: isSlow ? 11 : 8
            )
        }
        // Cuts — drawn last so they sit visually above other pills in their
        // row. Distinct striped/dark look signals that the range is removed.
        for seg in cutSegments {
            let rect = cutPillRect(for: seg)
            guard rect.width > 0 else { continue }
            drawCutPill(rect: rect,
                         isSelected: seg.id == selectedSegmentID,
                         label: formatCutLabel(duration: seg.duration))
        }
        // Freezes — violet pill with snowflake icon + hold duration.
        for seg in freezeSegments {
            let rect = freezePillRect(for: seg)
            guard rect.width > 0 else { continue }
            drawEffectPill(
                rect: rect,
                isSelected: seg.id == selectedSegmentID,
                baseFillColor: NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.85, alpha: 1.0),
                fadeInFrac: 0,
                fadeOutFrac: 0,
                iconSymbol: "snowflake",
                label: formatFreezeLabel(seg.holdDuration),
                iconLabelGap: 6
            )
        }

        // Empty-state hint.
        if zoomSegments.isEmpty && censorSegments.isEmpty && cutSegments.isEmpty && speedSegments.isEmpty && freezeSegments.isEmpty {
            let hint = L("Click to add effects") as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(0.55),
            ]
            let size = hint.size(withAttributes: attrs)
            hint.draw(at: NSPoint(x: bandRect.midX - size.width / 2,
                                   y: bandRect.midY - size.height / 2),
                       withAttributes: attrs)
        }

        // Cursor-follow + icon.
        drawCursorFollowPlus(bandRect: bandRect)
    }

    func drawCursorFollowPlus(bandRect: NSRect) {
        guard let p = cursorOnBand,
              draggingSegmentID == nil,
              !pointIsOverAnyPill(p) else { return }
        let accent = NSColor(calibratedRed: 0.5, green: 0.75, blue: 1.0, alpha: 0.9)
        let iconSize: CGFloat = 14
        let drawRect = NSRect(x: p.x + 10, y: p.y - 10, width: iconSize, height: iconSize)
        guard let icon = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: iconSize, weight: .semibold)) else { return }
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        let tinted = NSImage(size: icon.size, flipped: false) { r in
            icon.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
            accent.setFill()
            r.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: drawRect)
        NSGraphicsContext.restoreGraphicsState()
    }

    func drawEffectPill(rect: NSRect,
                                 isSelected: Bool,
                                 baseFillColor: NSColor,
                                 fadeInFrac: Double,
                                 fadeOutFrac: Double,
                                 iconSymbol: String,
                                 label: String,
                                 iconLabelGap: CGFloat = 4) {
        let fillColor = baseFillColor.withAlphaComponent(isSelected ? 1.0 : 0.88)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        fillColor.setFill()
        path.fill()

        let fadeColor = NSColor.black.withAlphaComponent(0.18)
        let fadeInW = CGFloat(fadeInFrac) * rect.width
        let fadeOutW = CGFloat(fadeOutFrac) * rect.width
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        fadeColor.setFill()
        if fadeInW > 1 {
            NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: fadeInW, height: rect.height)).fill()
        }
        if fadeOutW > 1 {
            NSBezierPath(rect: NSRect(x: rect.maxX - fadeOutW, y: rect.minY, width: fadeOutW, height: rect.height)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let labelNS = label as NSString
        let labelSize = labelNS.size(withAttributes: labelAttrs)
        let iconSize: CGFloat = 11
        let contentW = iconSize + iconLabelGap + labelSize.width
        if rect.width > contentW + 6 {
            let startX = rect.midX - contentW / 2
            if let icon = NSImage(systemSymbolName: iconSymbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: iconSize, weight: .semibold)) {
                let tinted = NSImage(size: icon.size, flipped: false) { r in
                    icon.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
                    NSColor.white.setFill()
                    r.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: NSRect(x: startX, y: rect.midY - icon.size.height / 2,
                                        width: icon.size.width, height: icon.size.height))
            }
            labelNS.draw(at: NSPoint(x: startX + iconSize + iconLabelGap, y: rect.midY - labelSize.height / 2),
                          withAttributes: labelAttrs)
        } else if rect.width > iconSize + 4 {
            if let icon = NSImage(systemSymbolName: iconSymbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: iconSize, weight: .semibold)) {
                let tinted = NSImage(size: icon.size, flipped: false) { r in
                    icon.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
                    NSColor.white.setFill()
                    r.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: NSRect(x: rect.midX - icon.size.width / 2,
                                        y: rect.midY - icon.size.height / 2,
                                        width: icon.size.width, height: icon.size.height))
            }
        }

        if isSelected {
            NSColor.white.withAlphaComponent(0.95).setStroke()
            let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 6, yRadius: 6)
            border.lineWidth = 1.5
            border.stroke()
        }

        let handleW: CGFloat = 6
        let handleH: CGFloat = rect.height + 6
        let handleY = rect.minY - 3
        let handleColor = NSColor.white.withAlphaComponent(isSelected ? 1.0 : 0.9)
        let left = NSRect(x: rect.minX - handleW / 2 + 1, y: handleY, width: handleW, height: handleH)
        handleColor.setFill()
        NSBezierPath(roundedRect: left, xRadius: 2, yRadius: 2).fill()
        drawHandleGrip(in: left)
        let right = NSRect(x: rect.maxX - handleW / 2 - 1, y: handleY, width: handleW, height: handleH)
        handleColor.setFill()
        NSBezierPath(roundedRect: right, xRadius: 2, yRadius: 2).fill()
        drawHandleGrip(in: right)
    }

    /// Draw a cut pill. Distinct visual from zoom/censor: dark-red base with
    /// diagonal hatching to signal "this span is being removed."
    func drawCutPill(rect: NSRect, isSelected: Bool, label: String) {
        let base = NSColor(calibratedRed: 0.35, green: 0.08, blue: 0.10, alpha: isSelected ? 1.0 : 0.95)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        base.setFill()
        path.fill()

        // Diagonal stripes inside the pill — film-strip deletion cue.
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor.white.withAlphaComponent(0.10).setStroke()
        let stripe = NSBezierPath()
        stripe.lineWidth = 1
        let step: CGFloat = 6
        var x = rect.minX - rect.height
        while x < rect.maxX + rect.height {
            stripe.move(to: NSPoint(x: x, y: rect.minY))
            stripe.line(to: NSPoint(x: x + rect.height, y: rect.maxY))
            x += step
        }
        stripe.stroke()
        NSGraphicsContext.restoreGraphicsState()

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let labelNS = label as NSString
        let labelSize = labelNS.size(withAttributes: labelAttrs)
        let iconSize: CGFloat = 11
        // Scissors glyph is narrower than "+" / drop / square so its trailing
        // whitespace looks smaller against the label — bump the gap explicitly.
        let iconLabelGap: CGFloat = 7
        let contentW = iconSize + iconLabelGap + labelSize.width
        if rect.width > contentW + 6,
           let icon = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: iconSize, weight: .semibold)) {
            let startX = rect.midX - contentW / 2
            let tinted = NSImage(size: icon.size, flipped: false) { r in
                icon.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
                NSColor.white.setFill()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: startX, y: rect.midY - icon.size.height / 2,
                                    width: icon.size.width, height: icon.size.height))
            labelNS.draw(at: NSPoint(x: startX + iconSize + iconLabelGap, y: rect.midY - labelSize.height / 2),
                          withAttributes: labelAttrs)
        } else if rect.width > iconSize + 4,
                  let icon = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: iconSize, weight: .semibold)) {
            let tinted = NSImage(size: icon.size, flipped: false) { r in
                icon.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
                NSColor.white.setFill()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: rect.midX - icon.size.width / 2,
                                    y: rect.midY - icon.size.height / 2,
                                    width: icon.size.width, height: icon.size.height))
        }

        if isSelected {
            NSColor.white.withAlphaComponent(0.95).setStroke()
            let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 6, yRadius: 6)
            border.lineWidth = 1.5
            border.stroke()
        }

        // Same grab handles as other pills so drag-to-resize feels uniform.
        let handleW: CGFloat = 6
        let handleH: CGFloat = rect.height + 6
        let handleY = rect.minY - 3
        let handleColor = NSColor.white.withAlphaComponent(isSelected ? 1.0 : 0.9)
        let left = NSRect(x: rect.minX - handleW / 2 + 1, y: handleY, width: handleW, height: handleH)
        handleColor.setFill()
        NSBezierPath(roundedRect: left, xRadius: 2, yRadius: 2).fill()
        drawHandleGrip(in: left)
        let right = NSRect(x: rect.maxX - handleW / 2 - 1, y: handleY, width: handleW, height: handleH)
        handleColor.setFill()
        NSBezierPath(roundedRect: right, xRadius: 2, yRadius: 2).fill()
        drawHandleGrip(in: right)
    }

    func formatCutLabel(duration: Double) -> String {
        if duration < 1 { return String(format: "%.1fs", duration) }
        return String(format: "%.1fs", duration)
    }

    func formatSpeedLabel(_ factor: Double) -> String {
        // Round to 2 decimals but drop trailing zeros ("2×" not "2.00×").
        let rounded = (factor * 100).rounded() / 100
        if abs(rounded - rounded.rounded()) < 0.01 {
            return "\(Int(rounded.rounded()))×"
        }
        return String(format: "%g×", rounded)
    }

    func formatFreezeLabel(_ seconds: Double) -> String {
        if abs(seconds - seconds.rounded()) < 0.01 {
            return "\(Int(seconds.rounded()))s"
        }
        return String(format: "%.1fs", seconds)
    }

    func drawHandleGrip(in rect: NSRect) {
        NSColor(calibratedRed: 0.18, green: 0.45, blue: 0.85, alpha: 0.85).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        let midY = rect.midY
        for dy in stride(from: -2.5 as CGFloat, through: 2.5, by: 2.5) {
            path.move(to: NSPoint(x: rect.midX - 1.2, y: midY + dy))
            path.line(to: NSPoint(x: rect.midX + 1.2, y: midY + dy))
        }
        path.stroke()
    }

    func formatZoom(_ level: CGFloat) -> String {
        if abs(level.rounded() - level) < 0.01 { return "\(Int(level.rounded()))x" }
        return String(format: "%.1fx", level)
    }

}
