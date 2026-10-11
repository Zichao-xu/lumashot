import Cocoa

extension Annotation {
    // MARK: - Loupe (Magnifying Glass)

    // MARK: - Loupe (Magnifying Glass)

    func bakeLoupe() {
        guard tool == .loupe else { return }
        if let live = generateLoupeImage() {
            bakedBlurNSImage = live
        }
        // Do NOT set self.sourceImage = nil so that if the user moves it later, it can still magnify!
    }

    func generateLoupeImage() -> NSImage? {
        // Real-time geometric magnification of the source underlying the circle
        guard let image = sourceImage else { return nil }

        let bounds = sourceImageBounds
        let imageSize = image.size
        let scaleX = imageSize.width / bounds.width
        let scaleY = imageSize.height / bounds.height
        
        let rect = boundingRect
        let scale: CGFloat = 2.0 // 2x Magnification
        
        // Always force a perfect circle
        let size = min(rect.width, rect.height)
        guard size > 10 else { return nil }

        let centerX = rect.origin.x + rect.width / 2
        let centerY = rect.origin.y + rect.height / 2
        
        let srcSize = size / scale
        let srcX = centerX - srcSize / 2
        let srcY = centerY - srcSize / 2
        
        // Extract the original region.
        // NSImage and the overlay view share the same coordinate system (Y=0 at bottom),
        // so no Y-flip is needed — just scale directly.
        let cropRect = NSRect(
            x: srcX * scaleX,
            y: srcY * scaleY,
            width: srcSize * scaleX,
            height: srcSize * scaleY
        )
        
        let magnifiedImage = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            if let ctx = NSGraphicsContext.current {
                ctx.imageInterpolation = .high
            }
            image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                       from: cropRect,
                       operation: .copy,
                       fraction: 1.0)
            return true
        }
        
        return magnifiedImage
    }

    // Cached loupe chrome objects (shared across all loupe annotations)
    static let loupeOuterShadow: NSShadow = {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.4)
        s.shadowOffset = NSSize(width: 0, height: -6)
        s.shadowBlurRadius = 14
        return s
    }()
    static let loupeInnerShadow: NSShadow = {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.5)
        s.shadowOffset = NSSize(width: 0, height: -3)
        s.shadowBlurRadius = 6
        return s
    }()
    static let loupeGradient: CGGradient? = {
        let colors = [
            NSColor.white.withAlphaComponent(0.95).cgColor,
            NSColor(white: 0.7, alpha: 0.85).cgColor,
        ] as CFArray
        return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0.0, 1.0])
    }()

    func drawLoupe(in context: NSGraphicsContext) {
        let rect = boundingRect
        guard rect.width > 10, rect.height > 10 else { return }

        let size = min(rect.width, rect.height)
        let squareRect = NSRect(
            x: rect.origin.x + (rect.width - size) / 2,
            y: rect.origin.y + (rect.height - size) / 2,
            width: size,
            height: size
        )

        let path = NSBezierPath(ovalIn: squareRect)

        // 1. Outer drop shadow
        context.saveGraphicsState()
        Self.loupeOuterShadow.set()
        NSColor.white.setFill()
        path.fill()
        context.restoreGraphicsState()

        // 2. Magnified content clipped to circle
        context.saveGraphicsState()
        path.addClip()

        if let baked = bakedBlurNSImage {
            baked.draw(in: squareRect, from: NSRect(origin: .zero, size: baked.size),
                       operation: .sourceOver, fraction: 1.0)
        } else if let image = sourceImage {
            // Draw directly from source without creating an intermediate image.
            let imgSize = image.size
            let scaleX = imgSize.width / sourceImageBounds.width
            let scaleY = imgSize.height / sourceImageBounds.height
            let magnification: CGFloat = 2.0
            let srcSize = size / magnification
            let cx = rect.midX, cy = rect.midY
            let fromRect = NSRect(
                x: (cx - srcSize/2) * scaleX,
                y: (cy - srcSize/2) * scaleY,
                width: srcSize * scaleX,
                height: srcSize * scaleY
            )
            context.imageInterpolation = .high
            image.draw(in: squareRect, from: fromRect, operation: .copy, fraction: 1.0)
        }
        context.restoreGraphicsState()

        // 3. Gradient border ring
        let cgCtx = context.cgContext
        let borderWidth: CGFloat = 4.0
        let innerPath = NSBezierPath(ovalIn: squareRect.insetBy(dx: borderWidth, dy: borderWidth))
        let ringPath = NSBezierPath()
        ringPath.append(path)
        ringPath.append(innerPath.reversed)
        cgCtx.saveGState()
        ringPath.addClip()
        if let gradient = Self.loupeGradient {
            cgCtx.drawLinearGradient(
                gradient,
                start: CGPoint(x: squareRect.midX, y: squareRect.maxY),
                end:   CGPoint(x: squareRect.midX, y: squareRect.minY),
                options: []
            )
        }
        cgCtx.restoreGState()

        // 4. Inner shadow
        context.saveGraphicsState()
        Self.loupeInnerShadow.set()
        let holeRect = squareRect.insetBy(dx: -30, dy: -30)
        let innerHole = NSBezierPath(rect: holeRect)
        innerHole.append(NSBezierPath(ovalIn: squareRect).reversed)
        path.addClip()
        NSColor.black.withAlphaComponent(0.8).setFill()
        innerHole.fill()
        context.restoreGraphicsState()
    }

}
