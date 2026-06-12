import Cocoa

extension Annotation {
    // MARK: - Translate overlay

    func drawTranslateOverlay() {
        guard let translatedText = text, !translatedText.isEmpty else { return }

        let rect = boundingRect
        guard rect.width > 2, rect.height > 2 else { return }

        // Background: use `color` (sampled avg color stored at creation time)
        // with a slight blur-like fill behind text
        let bgColor = color
        let bgPath = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        bgColor.setFill()
        bgPath.fill()

        // Determine contrasting text color
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        bgColor.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        let textColor: NSColor = luminance > 0.55 ? .black : .white

        // Fit text into the rect — start at stored fontSize, shrink if needed
        let hPad: CGFloat = 3
        let vPad: CGFloat = 2
        let availW = rect.width - hPad * 2
        let availH = rect.height - vPad * 2

        // Keep translated text readable: never shrink below ~14pt. The overlay
        // box is grown to fit at creation time, so heavy shrinking shouldn't be
        // needed; this floor just guards against cramming.
        let minFontSize: CGFloat = 14
        var fs = max(minFontSize, fontSize)
        var attrStr: NSAttributedString
        repeat {
            let font = NSFont.systemFont(ofSize: fs, weight: .medium)
            attrStr = NSAttributedString(string: translatedText, attributes: [
                .font: font,
                .foregroundColor: textColor,
            ])
            let needed = attrStr.boundingRect(
                with: NSSize(width: availW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            if needed.height <= availH || fs <= minFontSize { break }
            fs -= 1
        } while fs > minFontSize

        // Draw text top-aligned within the block
        let textRect = NSRect(
            x: rect.minX + hPad,
            y: rect.minY + vPad,
            width: availW,
            height: availH
        )
        attrStr.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}
