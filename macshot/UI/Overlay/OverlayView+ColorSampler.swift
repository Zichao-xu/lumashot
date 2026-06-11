import AVFoundation
import Cocoa
import UniformTypeIdentifiers

extension OverlayView {
    // MARK: - Color Sampler Preview

    /// Sample the pixel color at `canvasPoint` from the screenshot and draw a live preview.
    func drawColorSamplerPreview(at canvasPoint: NSPoint) {
        guard let screenshot = screenshotImage else { return }
        guard let result = sampleColor(from: screenshot, at: canvasPoint) else { return }
        let sampledColor = result.color
        let hexStr = result.hex

        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()

        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        let copyFont = NSFont.systemFont(ofSize: 10, weight: .regular)
        let hexAttrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.white,
        ]
        let copyAttrs: [NSAttributedString.Key: Any] = [
            .font: copyFont, .foregroundColor: NSColor.white.withAlphaComponent(0.5),
        ]

        let hexSize = (hexStr as NSString).size(withAttributes: hexAttrs)
        let copyText = L("Right-click to copy")
        let copySize = (copyText as NSString).size(withAttributes: copyAttrs)

        let swatchSize: CGFloat = 16
        let padding: CGFloat = 8
        let gap: CGFloat = 6
        let labelW = padding + swatchSize + gap + max(hexSize.width, copySize.width) + padding
        let labelH = padding + hexSize.height + 2 + copySize.height + padding

        let labelX = canvasPoint.x + 16
        let labelY = canvasPoint.y - labelH - 8
        let labelRect = NSRect(x: labelX, y: labelY, width: labelW, height: labelH)

        // Background pill
        NSColor.black.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 6, yRadius: 6).fill()

        // Color swatch
        let swatchRect = NSRect(
            x: labelRect.minX + padding,
            y: labelRect.midY - swatchSize / 2,
            width: swatchSize, height: swatchSize)
        sampledColor.setFill()
        NSBezierPath(roundedRect: swatchRect, xRadius: 3, yRadius: 3).fill()
        NSColor.white.withAlphaComponent(0.4).setStroke()
        let swatchBorder = NSBezierPath(roundedRect: swatchRect, xRadius: 3, yRadius: 3)
        swatchBorder.lineWidth = 0.5
        swatchBorder.stroke()

        // Hex text + copy hint
        let textX = swatchRect.maxX + gap
        (hexStr as NSString).draw(
            at: NSPoint(x: textX, y: labelRect.maxY - padding - hexSize.height),
            withAttributes: hexAttrs)
        (copyText as NSString).draw(
            at: NSPoint(x: textX, y: labelRect.minY + padding), withAttributes: copyAttrs)

        context.restoreGraphicsState()
    }

    /// Sample a pixel color from the screenshot at the given canvas-space point.
    /// Returns (NSColor for display, hex string with raw sRGB values matching what other tools report).
    func sampleColor(from image: NSImage, at canvasPoint: NSPoint) -> (
        color: NSColor, hex: String
    )? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let imgSize = image.size
        let drawRect = captureDrawRect

        let px = (canvasPoint.x - drawRect.origin.x) * imgSize.width / drawRect.width
        let py = (canvasPoint.y - drawRect.origin.y) * imgSize.height / drawRect.height
        guard px >= 0, py >= 0, px < imgSize.width, py < imgSize.height else { return nil }

        // Map to CGImage pixel coordinates.
        let scaleX = CGFloat(cgImage.width) / imgSize.width
        let scaleY = CGFloat(cgImage.height) / imgSize.height
        let cgX = Int(px * scaleX)
        let cgY = Int(CGFloat(cgImage.height) - 1 - py * scaleY)  // flip Y for CGImage (top-left origin)
        guard cgX >= 0, cgX < cgImage.width, cgY >= 0, cgY < cgImage.height else { return nil }

        // Render the single pixel into a known-format 1×1 sRGB bitmap to get correct raw values.
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        guard
            let ctx = CGContext(
                data: nil, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4,
                space: srgb,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(
            cgImage,
            in: CGRect(
                x: -CGFloat(cgX), y: -(CGFloat(cgImage.height) - 1 - CGFloat(cgY)),
                width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        guard let data = ctx.data else { return nil }
        let ptr = data.assumingMemoryBound(to: UInt8.self)
        let a = CGFloat(ptr[3]) / 255
        guard a > 0 else { return nil }
        // Undo premultiplication
        let r = UInt8(min(255, CGFloat(ptr[0]) / a))
        let g = UInt8(min(255, CGFloat(ptr[1]) / a))
        let b = UInt8(min(255, CGFloat(ptr[2]) / a))

        let hex = String(format: "#%02X%02X%02X", r, g, b)
        let color = NSColor(
            srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        return (color, hex)
    }

}
