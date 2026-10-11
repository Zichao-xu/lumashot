import Cocoa

extension Annotation {
    // MARK: - Drawing methods

    func drawFreeform(alpha: CGFloat, width: CGFloat) {
        guard let points = points, !points.isEmpty else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Single point: draw a filled circle (dot)
        if points.count == 1 {
            let p = points[0]
            let r = width / 2
            ctx.setAlpha(alpha)
            color.withAlphaComponent(1.0).setFill()
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: width, height: width))
            ctx.setAlpha(1.0)
            return
        }

        // For dotted freeform, place dots at evenly-spaced arc-length positions
        // to avoid uneven spacing caused by segment boundaries in the polyline.
        if lineStyle == .dotted {
            ctx.setAlpha(alpha)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            color.withAlphaComponent(1.0).setFill()

            // Compute cumulative arc lengths
            var cumLengths: [CGFloat] = [0]
            for i in 1..<points.count {
                cumLengths.append(cumLengths[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y))
            }
            let totalLength = cumLengths.last!
            guard totalLength > 0 else {
                ctx.endTransparencyLayer()
                ctx.setAlpha(1.0)
                return
            }

            let gap = max(width * 2, 6)
            let count = max(1, round(totalLength / gap))
            let spacing = totalLength / count
            let dotRadius = width / 2

            var segIdx = 0
            var dist: CGFloat = 0
            while dist <= totalLength + 0.01 {
                // Find the segment containing this distance
                while segIdx < points.count - 2 && cumLengths[segIdx + 1] < dist {
                    segIdx += 1
                }
                let segStart = cumLengths[segIdx]
                let segLen = cumLengths[segIdx + 1] - segStart
                let t: CGFloat = segLen > 0 ? (dist - segStart) / segLen : 0
                let x = points[segIdx].x + t * (points[segIdx + 1].x - points[segIdx].x)
                let y = points[segIdx].y + t * (points[segIdx + 1].y - points[segIdx].y)
                let dotRect = NSRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                NSBezierPath(ovalIn: dotRect).fill()
                dist += spacing
            }

            ctx.endTransparencyLayer()
            ctx.setAlpha(1.0)
            return
        }

        // Variable-width stroke (pressure sensitive)
        if let pressures = pressures, pressures.count == points.count, lineStyle == .solid {
            ctx.setAlpha(alpha)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            color.withAlphaComponent(1.0).setFill()

            // Map raw pressure (0–1) to a usable width range:
            // - Minimum 20% of stroke width even at lightest touch
            // - Power curve (0.6) compresses the range so light/medium pressure
            //   differences are subtle, heavy pressure stands out
            let minFraction: CGFloat = 0.2
            func pressureWidth(_ p: CGFloat) -> CGFloat {
                let mapped = minFraction + pow(min(max(p, 0), 1), 0.6) * (1.0 - minFraction)
                return max(width * mapped, 0.5)
            }

            // Draw filled circles at each point + connecting quads for smooth width transitions
            for i in 0..<points.count {
                let r = pressureWidth(pressures[i]) / 2
                ctx.fillEllipse(in: CGRect(x: points[i].x - r, y: points[i].y - r, width: r * 2, height: r * 2))

                if i > 0 {
                    let p0 = points[i - 1]
                    let p1 = points[i]
                    let r0 = pressureWidth(pressures[i - 1]) / 2
                    let r1 = pressureWidth(pressures[i]) / 2

                    let dx = p1.x - p0.x
                    let dy = p1.y - p0.y
                    let len = hypot(dx, dy)
                    guard len > 0.1 else { continue }
                    // Normal perpendicular to the line segment
                    let nx = -dy / len
                    let ny = dx / len

                    // Build a quad connecting the two circles
                    let quad = NSBezierPath()
                    quad.move(to: NSPoint(x: p0.x + nx * r0, y: p0.y + ny * r0))
                    quad.line(to: NSPoint(x: p1.x + nx * r1, y: p1.y + ny * r1))
                    quad.line(to: NSPoint(x: p1.x - nx * r1, y: p1.y - ny * r1))
                    quad.line(to: NSPoint(x: p0.x - nx * r0, y: p0.y - ny * r0))
                    quad.close()
                    quad.fill()
                }
            }

            ctx.endTransparencyLayer()
            ctx.setAlpha(1.0)
            return
        }

        // Use a transparency layer so self-overlapping segments don't compound alpha
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        lineStyle.apply(to: path)
        color.withAlphaComponent(1.0).setStroke()
        path.move(to: points[0])
        for i in 1..<points.count {
            path.line(to: points[i])
        }
        path.stroke()
        ctx.endTransparencyLayer()
        ctx.setAlpha(1.0)
    }

    /// Build a smooth Catmull-Rom spline path through the given points.
    /// For 2 points: straight line. For 3+: smooth curves through all points.
    static func smoothPath(through pts: [NSPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard pts.count >= 2 else { return path }
        path.move(to: pts[0])
        if pts.count == 2 {
            path.line(to: pts[1])
            return path
        }
        // Catmull-Rom → cubic Bezier conversion
        // For each segment i→i+1, compute control points from surrounding points
        for i in 0..<(pts.count - 1) {
            let p0 = i > 0 ? pts[i - 1] : pts[i]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = i + 2 < pts.count ? pts[i + 2] : pts[i + 1]

            let cp1 = NSPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = NSPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.curve(to: p2, controlPoint1: cp1, controlPoint2: cp2)
        }
        return path
    }

    /// Approximate length of a smooth path through waypoints.
    static func smoothPathLength(_ pts: [NSPoint]) -> CGFloat {
        guard pts.count >= 2 else { return 0 }
        if pts.count == 2 {
            return hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y)
        }
        // Sample the Catmull-Rom spline
        let steps = pts.count * 20
        var length: CGFloat = 0
        var prev = pts[0]
        for s in 1...steps {
            let t = CGFloat(s) / CGFloat(steps)
            let totalSegments = CGFloat(pts.count - 1)
            let segF = t * totalSegments
            let seg = min(Int(segF), pts.count - 2)
            let localT = segF - CGFloat(seg)

            let p0 = seg > 0 ? pts[seg - 1] : pts[seg]
            let p1 = pts[seg]
            let p2 = pts[seg + 1]
            let p3 = seg + 2 < pts.count ? pts[seg + 2] : pts[seg + 1]

            let cp1 = NSPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = NSPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)

            let u = 1 - localT
            let px = u*u*u*p1.x + 3*u*u*localT*cp1.x + 3*u*localT*localT*cp2.x + localT*localT*localT*p2.x
            let py = u*u*u*p1.y + 3*u*u*localT*cp1.y + 3*u*localT*localT*cp2.y + localT*localT*localT*p2.y
            let cur = NSPoint(x: px, y: py)
            length += hypot(cur.x - prev.x, cur.y - prev.y)
            prev = cur
        }
        return length
    }

    func drawStraightLine() {
        // Multi-anchor: smooth Catmull-Rom spline
        if hasMultiAnchor {
            let pts = waypoints
            let path = Self.smoothPath(through: pts)
            path.lineWidth = strokeWidth
            path.lineCapStyle = .round
            if lineStyle != .solid {
                lineStyle.applyFitted(to: path, pathLength: Self.smoothPathLength(pts))
            }
            // Outline: same path stroked wider first, then normal on top
            if let oc = outlineColor {
                path.lineWidth = strokeWidth + 6
                oc.setStroke(); path.stroke()
                path.lineWidth = strokeWidth
            }
            color.setStroke(); path.stroke()
            return
        }

        // Legacy: straight line or single bezier bend
        let path = NSBezierPath()
        path.lineWidth = strokeWidth
        path.lineCapStyle = .round
        if lineStyle != .solid {
            let length: CGFloat
            if let cp = controlPoint {
                length = Annotation.approxBezierLength(from: startPoint, cp1: cp, cp2: cp, to: endPoint)
            } else {
                length = hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
            }
            lineStyle.applyFitted(to: path, pathLength: length)
        }
        path.move(to: startPoint)
        if let cp = controlPoint {
            path.curve(to: endPoint, controlPoint1: cp, controlPoint2: cp)
        } else {
            path.line(to: endPoint)
        }
        // Outline: same path stroked wider first, then normal on top
        if let oc = outlineColor {
            path.lineWidth = strokeWidth + 6
            oc.setStroke(); path.stroke()
            path.lineWidth = strokeWidth
        }
        color.setStroke(); path.stroke()
    }

    func drawArrow() {
        // Thick style is a completely different shape — handle separately
        if arrowStyle == .thick {
            drawThickArrow()
            return
        }

        let pts = arrowReversed ? waypoints.reversed() : waypoints
        guard pts.count >= 2 else { return }
        let firstPt = pts.first!
        let lastPt = pts.last!

        let fullArrowLen: CGFloat = max(14, strokeWidth * 5)
        let totalLen = hypot(lastPt.x - firstPt.x, lastPt.y - firstPt.y)
        let maxHead = totalLen * 0.45
        let arrowLen: CGFloat = min(fullArrowLen, max(4, maxHead))
        let arrowAngle: CGFloat = .pi / 6

        // End arrowhead angle
        let endAngle: CGFloat
        if hasMultiAnchor {
            let preLast = pts.count >= 2 ? pts[pts.count - 2] : firstPt
            endAngle = atan2(lastPt.y - preLast.y, lastPt.x - preLast.x)
        } else if let cp = controlPoint {
            endAngle = atan2(lastPt.y - cp.y, lastPt.x - cp.x)
        } else {
            endAngle = atan2(lastPt.y - firstPt.y, lastPt.x - firstPt.x)
        }
        let ep1 = NSPoint(x: lastPt.x - arrowLen * cos(endAngle - arrowAngle),
                           y: lastPt.y - arrowLen * sin(endAngle - arrowAngle))
        let ep2 = NSPoint(x: lastPt.x - arrowLen * cos(endAngle + arrowAngle),
                           y: lastPt.y - arrowLen * sin(endAngle + arrowAngle))
        let endBase = NSPoint(x: (ep1.x + ep2.x) / 2, y: (ep1.y + ep2.y) / 2)

        // Start arrowhead geometry (for double style)
        var startBase = firstPt
        var sp1 = firstPt, sp2 = firstPt
        if arrowStyle == .double {
            let startAngle: CGFloat
            if hasMultiAnchor {
                let postFirst = pts.count >= 2 ? pts[1] : lastPt
                startAngle = atan2(firstPt.y - postFirst.y, firstPt.x - postFirst.x)
            } else if let cp = controlPoint {
                startAngle = atan2(firstPt.y - cp.y, firstPt.x - cp.x)
            } else {
                startAngle = atan2(firstPt.y - lastPt.y, firstPt.x - lastPt.x)
            }
            sp1 = NSPoint(x: firstPt.x - arrowLen * cos(startAngle - arrowAngle),
                           y: firstPt.y - arrowLen * sin(startAngle - arrowAngle))
            sp2 = NSPoint(x: firstPt.x - arrowLen * cos(startAngle + arrowAngle),
                           y: firstPt.y - arrowLen * sin(startAngle + arrowAngle))
            startBase = NSPoint(x: (sp1.x + sp2.x) / 2, y: (sp1.y + sp2.y) / 2)
        }

        // Tail circle radius
        let tailRadius: CGFloat = max(4, strokeWidth * 2)
        let lineStart = arrowStyle == .double ? startBase : firstPt

        // Draw the line shaft
        let path: NSBezierPath
        if hasMultiAnchor {
            // Multi-anchor: smooth Catmull-Rom spline
            var shaftPts = pts
            shaftPts[0] = lineStart
            shaftPts[shaftPts.count - 1] = endBase
            path = Self.smoothPath(through: shaftPts)
        } else {
            // Legacy: straight or single bezier bend
            path = NSBezierPath()
            path.move(to: lineStart)
            if let cp = controlPoint {
                path.curve(to: endBase, controlPoint1: cp, controlPoint2: cp)
            } else {
                path.line(to: endBase)
            }
        }
        path.lineWidth = strokeWidth
        path.lineCapStyle = .round
        if lineStyle != .solid {
            let length = hasMultiAnchor ? Self.smoothPathLength(pts) :
                (controlPoint != nil ? Annotation.approxBezierLength(from: lineStart, cp1: controlPoint!, cp2: controlPoint!, to: endBase) :
                 hypot(endBase.x - lineStart.x, endBase.y - lineStart.y))
            lineStyle.applyFitted(to: path, pathLength: length)
        }
        // Outline: draw wider stroke behind everything
        let outlineW: CGFloat = 3
        if let oc = outlineColor {
            oc.setStroke()
            oc.setFill()
            let outlinePath = path.copy() as! NSBezierPath
            outlinePath.lineWidth = strokeWidth + outlineW * 2
            outlinePath.lineCapStyle = .round
            outlinePath.stroke()
            // Outline arrowheads
            switch arrowStyle {
            case .single, .tail:
                let h = NSBezierPath(); h.move(to: lastPt); h.line(to: ep1); h.line(to: ep2); h.close()
                h.lineWidth = outlineW * 2; h.lineJoinStyle = .round; h.stroke(); h.fill()
            case .double:
                let eh = NSBezierPath(); eh.move(to: lastPt); eh.line(to: ep1); eh.line(to: ep2); eh.close()
                eh.lineWidth = outlineW * 2; eh.lineJoinStyle = .round; eh.stroke(); eh.fill()
                let sh = NSBezierPath(); sh.move(to: firstPt); sh.line(to: sp1); sh.line(to: sp2); sh.close()
                sh.lineWidth = outlineW * 2; sh.lineJoinStyle = .round; sh.stroke(); sh.fill()
            case .open:
                let h = NSBezierPath(); h.lineWidth = strokeWidth + outlineW * 2
                h.lineCapStyle = .round; h.lineJoinStyle = .round
                h.move(to: ep1); h.line(to: lastPt); h.line(to: ep2); h.stroke()
            case .thick: break
            }
            if arrowStyle == .tail {
                let cr = NSRect(x: firstPt.x - tailRadius - outlineW, y: firstPt.y - tailRadius - outlineW,
                                width: (tailRadius + outlineW) * 2, height: (tailRadius + outlineW) * 2)
                NSBezierPath(ovalIn: cr).fill()
            }
        }

        color.setStroke()
        path.stroke()

        // Draw arrowhead(s)
        color.setFill()
        color.setStroke()
        switch arrowStyle {
        case .single, .tail:
            let head = NSBezierPath()
            head.move(to: lastPt)
            head.line(to: ep1)
            head.line(to: ep2)
            head.close()
            head.fill()
        case .double:
            let endHead = NSBezierPath()
            endHead.move(to: lastPt)
            endHead.line(to: ep1)
            endHead.line(to: ep2)
            endHead.close()
            endHead.fill()
            let startHead = NSBezierPath()
            startHead.move(to: firstPt)
            startHead.line(to: sp1)
            startHead.line(to: sp2)
            startHead.close()
            startHead.fill()
        case .open:
            let head = NSBezierPath()
            head.lineWidth = strokeWidth
            head.lineCapStyle = .round
            head.lineJoinStyle = .round
            head.move(to: ep1)
            head.line(to: lastPt)
            head.line(to: ep2)
            head.stroke()
        case .thick:
            break // handled by early return above
        }

        // Tail: circle at start
        if arrowStyle == .tail {
            let circleRect = NSRect(x: firstPt.x - tailRadius, y: firstPt.y - tailRadius,
                                    width: tailRadius * 2, height: tailRadius * 2)
            NSBezierPath(ovalIn: circleRect).fill()
        }
    }

    func drawThickArrow() {
        let pts = arrowReversed ? waypoints.reversed() : waypoints
        let firstPt = pts.first ?? startPoint
        let lastPt = pts.last ?? endPoint
        let totalLen = hasMultiAnchor ? Self.smoothPathLength(pts) : hypot(lastPt.x - firstPt.x, lastPt.y - firstPt.y)
        guard totalLen > 1 else { return }

        // End angle: direction of the last segment approaching the tip
        let preLast = pts.count >= 2 ? pts[pts.count - 2] : firstPt
        let endAngle: CGFloat
        if hasMultiAnchor {
            endAngle = atan2(lastPt.y - preLast.y, lastPt.x - preLast.x)
        } else if let cp = controlPoint {
            endAngle = atan2(lastPt.y - cp.y, lastPt.x - cp.x)
        } else {
            endAngle = atan2(lastPt.y - firstPt.y, lastPt.x - firstPt.x)
        }
        let epx = -sin(endAngle), epy = cos(endAngle)

        // Start angle: direction leaving the tail
        let postFirst = pts.count >= 2 ? pts[1] : lastPt
        let startAngle: CGFloat
        if hasMultiAnchor {
            startAngle = atan2(postFirst.y - firstPt.y, postFirst.x - firstPt.x)
        } else if let cp = controlPoint {
            startAngle = atan2(cp.y - firstPt.y, cp.x - firstPt.x)
        } else {
            startAngle = endAngle
        }
        let spx = -sin(startAngle), spy = cos(startAngle)

        // Sizing — the arrow's cross-section (shaft + head width) should never
        // exceed the arrow's length. Scale everything down proportionally.
        let rawTailHalf = max(2, strokeWidth * 0.5)
        let rawShaftHalf = max(4, strokeWidth * 1.5)
        let rawHeadHalf = rawShaftHalf * 2.0
        let maxCrossSection = rawHeadHalf * 2  // full head width
        let fitScale = min(1.0, totalLen / max(1, maxCrossSection * 1.5))
        let tailHalf = rawTailHalf * fitScale
        let shaftHalf = rawShaftHalf * fitScale
        let headHalf = rawHeadHalf * fitScale
        let headLen = min(totalLen * 0.35, headHalf * 1.8)
        let r: CGFloat = min(headLen * 0.22, headHalf * 0.3)  // corner rounding

        // Head base point
        let headBase = NSPoint(x: lastPt.x - headLen * cos(endAngle),
                               y: lastPt.y - headLen * sin(endAngle))

        // Sample points along the shaft (tail → headBase), offset perpendicular for taper
        // More samples for multi-anchor curves to avoid self-intersection at tight bends
        let steps = hasMultiAnchor ? max(64, pts.count * 32) : 64
        var leftPts: [NSPoint] = []
        var rightPts: [NSPoint] = []

        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let bx, by, tx, ty: CGFloat

            if hasMultiAnchor {
                // Sample a modified curve where the last point is headBase
                var shaftPts = pts
                shaftPts[shaftPts.count - 1] = headBase
                let totalSegs = CGFloat(shaftPts.count - 1)
                let segF = t * totalSegs
                let seg = min(Int(segF), shaftPts.count - 2)
                let lt = segF - CGFloat(seg)
                let p0 = seg > 0 ? shaftPts[seg - 1] : shaftPts[seg]
                let p1 = shaftPts[seg]
                let p2 = shaftPts[seg + 1]
                let p3 = seg + 2 < shaftPts.count ? shaftPts[seg + 2] : shaftPts[seg + 1]
                let cp1 = NSPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let cp2 = NSPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                let u = 1 - lt
                bx = u*u*u*p1.x + 3*u*u*lt*cp1.x + 3*u*lt*lt*cp2.x + lt*lt*lt*p2.x
                by = u*u*u*p1.y + 3*u*u*lt*cp1.y + 3*u*lt*lt*cp2.y + lt*lt*lt*p2.y
                tx = 3*u*u*(cp1.x-p1.x) + 6*u*lt*(cp2.x-cp1.x) + 3*lt*lt*(p2.x-cp2.x)
                ty = 3*u*u*(cp1.y-p1.y) + 6*u*lt*(cp2.y-cp1.y) + 3*lt*lt*(p2.y-cp2.y)
            } else if let cp = controlPoint {
                let mt = 1.0 - t
                bx = mt * mt * firstPt.x + 2 * mt * t * cp.x + t * t * headBase.x
                by = mt * mt * firstPt.y + 2 * mt * t * cp.y + t * t * headBase.y
                tx = 2 * (1 - t) * (cp.x - firstPt.x) + 2 * t * (headBase.x - cp.x)
                ty = 2 * (1 - t) * (cp.y - firstPt.y) + 2 * t * (headBase.y - cp.y)
            } else {
                bx = firstPt.x + t * (headBase.x - firstPt.x)
                by = firstPt.y + t * (headBase.y - firstPt.y)
                tx = headBase.x - firstPt.x
                ty = headBase.y - firstPt.y
            }

            let tLen = max(hypot(tx, ty), 0.001)
            let nx = -ty / tLen, ny = tx / tLen
            let half = tailHalf + (shaftHalf - tailHalf) * t
            leftPts.append(NSPoint(x: bx + nx * half, y: by + ny * half))
            rightPts.append(NSPoint(x: bx - nx * half, y: by - ny * half))
        }

        // Head wing points (the 3 triangle corners)
        let endPoint = lastPt
        let headLeft  = NSPoint(x: headBase.x + epx * headHalf, y: headBase.y + epy * headHalf)
        let headRight = NSPoint(x: headBase.x - epx * headHalf, y: headBase.y - epy * headHalf)
        let shaftLeftEnd  = leftPts.last!
        let shaftRightEnd = rightPts.last!

        // Helper: point along segment from A to B at distance d from A
        func along(_ a: NSPoint, _ b: NSPoint, _ d: CGFloat) -> NSPoint {
            let len = max(hypot(b.x - a.x, b.y - a.y), 0.001)
            let t = min(d / len, 0.45)
            return NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }

        // Build single unified path
        let path = NSBezierPath()

        // Left shaft edge (tail → head base)
        path.move(to: leftPts[0])
        for p in leftPts.dropFirst() { path.line(to: p) }

        // Corner 1: left wing (shaftLeftEnd → headLeft → endPoint)
        // Approach headLeft from shaft side, curve through headLeft, continue toward tip
        let wL1 = along(headLeft, shaftLeftEnd, r)   // before the corner, on shaft→wing edge
        let wL2 = along(headLeft, endPoint, r)        // after the corner, on wing→tip edge
        path.line(to: wL1)
        path.curve(to: wL2, controlPoint1: headLeft, controlPoint2: headLeft)

        // Corner 2: tip (headLeft → endPoint → headRight)
        let tL = along(endPoint, headLeft, r)         // before tip, on left wing→tip edge
        let tR = along(endPoint, headRight, r)        // after tip, on tip→right wing edge
        path.line(to: tL)
        path.curve(to: tR, controlPoint1: endPoint, controlPoint2: endPoint)

        // Corner 3: right wing (endPoint → headRight → shaftRightEnd)
        let wR1 = along(headRight, endPoint, r)       // before the corner, on tip→wing edge
        let wR2 = along(headRight, shaftRightEnd, r)  // after the corner, on wing→shaft edge
        path.line(to: wR1)
        path.curve(to: wR2, controlPoint1: headRight, controlPoint2: headRight)

        // Right shaft edge (head base → tail)
        path.line(to: shaftRightEnd)
        for p in rightPts.reversed().dropFirst() { path.line(to: p) }

        path.close()

        // Outline: stroke the unified shape behind the fill
        if let oc = outlineColor {
            oc.setStroke()
            path.lineWidth = 6
            path.lineJoinStyle = .round
            path.stroke()
        }

        color.setFill()
        path.fill()
    }

    func drawRectangle(forceFilled: Bool = false) {
        let rect = boundingRect
        guard rect.width > 0, rect.height > 0 else { return }
        let cornerRadius: CGFloat = rectCornerRadius > 0 ? rectCornerRadius : (isRounded ? min(rect.width, rect.height) * 0.2 : 0)
        let style = forceFilled ? RectFillStyle.fill : rectFillStyle

        // When outline is active, force solid style (dashed/dotted disabled in UI)
        let effectiveLineStyle = outlineColor != nil ? .solid : lineStyle

        let rectPerimeter: CGFloat = {
            let r = min(cornerRadius, min(rect.width, rect.height) / 2)
            return 2 * (rect.width - 2 * r) + 2 * (rect.height - 2 * r) + 2 * .pi * r
        }()

        switch style {
        case .fill:
            if let oc = outlineColor {
                let outlinePath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
                outlinePath.lineWidth = strokeWidth + 6
                outlinePath.lineJoinStyle = cornerRadius > 0 ? .round : .miter
                oc.setStroke()
                outlinePath.stroke()
            }
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()

        case .strokeAndFill:
            let fillAlpha = color.alphaComponent * 0.5
            color.withAlphaComponent(fillAlpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            path.lineWidth = strokeWidth
            path.lineJoinStyle = cornerRadius > 0 ? .round : .miter
            if effectiveLineStyle != .solid {
                effectiveLineStyle.applyFitted(to: path, pathLength: rectPerimeter)
            }
            if let oc = outlineColor {
                path.lineWidth = strokeWidth + 6
                oc.setStroke(); path.stroke()
                path.lineWidth = strokeWidth
            }
            color.setStroke()
            path.stroke()

        case .stroke:
            if cornerRadius < 1 && (effectiveLineStyle == .dotted || effectiveLineStyle == .dashed) {
                if effectiveLineStyle == .dotted {
                    drawDottedRectPerSide(rect: rect)
                } else {
                    drawDashedRectPerSide(rect: rect)
                }
            } else {
                let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
                path.lineWidth = strokeWidth
                path.lineJoinStyle = cornerRadius > 0 ? .round : .miter
                if effectiveLineStyle != .solid {
                    effectiveLineStyle.applyFitted(to: path, pathLength: rectPerimeter)
                }
                if let oc = outlineColor {
                    path.lineWidth = strokeWidth + 6
                    oc.setStroke(); path.stroke()
                    path.lineWidth = strokeWidth
                }
                color.setStroke()
                path.stroke()
            }
        }
    }

    /// Draw a dotted rectangle with dots guaranteed at every corner.
    /// Each side is drawn independently so dots tile evenly per-side.
    func drawDottedRectPerSide(rect: NSRect) {
        let dotRadius = strokeWidth / 2
        let idealGap = max(strokeWidth * 2, 6)
        color.setFill()

        // Corner points (bottom-left origin, clockwise: BL → TL → TR → BR)
        let corners = [
            NSPoint(x: rect.minX, y: rect.minY),  // bottom-left
            NSPoint(x: rect.minX, y: rect.maxY),  // top-left
            NSPoint(x: rect.maxX, y: rect.maxY),  // top-right
            NSPoint(x: rect.maxX, y: rect.minY),  // bottom-right
        ]

        for i in 0..<4 {
            let p0 = corners[i]
            let p1 = corners[(i + 1) % 4]
            let sideLen = hypot(p1.x - p0.x, p1.y - p0.y)
            guard sideLen > 0 else { continue }

            // Number of segments (gaps between dots). At least 1 so we get dots at both ends.
            let n = max(1, Int(round(sideLen / idealGap)))
            let step = sideLen / CGFloat(n)
            let dx = (p1.x - p0.x) / sideLen
            let dy = (p1.y - p0.y) / sideLen

            // Draw dots from p0 to p1 (inclusive of p0, exclusive of p1 to avoid double-drawing corners)
            for j in 0..<n {
                let t = CGFloat(j) * step
                let x = p0.x + dx * t
                let y = p0.y + dy * t
                let dotRect = NSRect(x: x - dotRadius, y: y - dotRadius, width: strokeWidth, height: strokeWidth)
                NSBezierPath(ovalIn: dotRect).fill()
            }
        }
    }

    /// Draw a dashed rectangle with dashes evenly distributed per side.
    /// Each side is inset by half the stroke width so corners don't overlap.
    func drawDashedRectPerSide(rect: NSRect) {
        let idealDash = strokeWidth * 3
        let idealGap = strokeWidth * 2
        let idealCycle = idealDash + idealGap
        let hw = strokeWidth / 2  // half stroke width — inset to avoid corner overlap
        color.setStroke()

        // Corners inset by half stroke width along each side's direction
        let sides: [(NSPoint, NSPoint)] = [
            // bottom: left→right
            (NSPoint(x: rect.minX + hw, y: rect.minY), NSPoint(x: rect.maxX - hw, y: rect.minY)),
            // left: bottom→top
            (NSPoint(x: rect.minX, y: rect.minY + hw), NSPoint(x: rect.minX, y: rect.maxY - hw)),
            // top: left→right
            (NSPoint(x: rect.minX + hw, y: rect.maxY), NSPoint(x: rect.maxX - hw, y: rect.maxY)),
            // right: bottom→top
            (NSPoint(x: rect.maxX, y: rect.minY + hw), NSPoint(x: rect.maxX, y: rect.maxY - hw)),
        ]

        for (p0, p1) in sides {
            let sideLen = hypot(p1.x - p0.x, p1.y - p0.y)
            guard sideLen > 0 else { continue }

            let path = NSBezierPath()
            path.lineWidth = strokeWidth
            path.lineCapStyle = .butt
            path.move(to: p0)
            path.line(to: p1)

            let n = max(1, round(sideLen / idealCycle))
            let adjustedCycle = sideLen / n
            let ratio = idealDash / idealCycle
            let dash = adjustedCycle * ratio
            let gap = adjustedCycle - dash
            let pattern: [CGFloat] = [dash, gap]
            path.setLineDash(pattern, count: 2, phase: dash / 2)
            path.stroke()
        }
    }

    func drawEllipse() {
        let rect = boundingRect
        guard rect.width > 0, rect.height > 0 else { return }

        // When outline is active, force solid style (dashed/dotted disabled in UI)
        let effectiveLineStyle = outlineColor != nil ? .solid : lineStyle

        let ellipsePerimeter: CGFloat = {
            let a = rect.width / 2, b = rect.height / 2
            return CGFloat.pi * (3 * (a + b) - sqrt((3 * a + b) * (a + 3 * b)))
        }()

        switch rectFillStyle {
        case .fill:
            if let oc = outlineColor {
                let outlinePath = NSBezierPath(ovalIn: rect)
                outlinePath.lineWidth = strokeWidth + 6
                oc.setStroke()
                outlinePath.stroke()
            }
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()

        case .strokeAndFill:
            let fillAlpha = color.alphaComponent * 0.5
            color.withAlphaComponent(fillAlpha).setFill()
            NSBezierPath(ovalIn: rect).fill()
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = strokeWidth
            if effectiveLineStyle != .solid {
                effectiveLineStyle.applyFitted(to: path, pathLength: ellipsePerimeter)
            }
            if let oc = outlineColor {
                path.lineWidth = strokeWidth + 6
                oc.setStroke(); path.stroke()
                path.lineWidth = strokeWidth
            }
            color.setStroke()
            path.stroke()

        case .stroke:
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = strokeWidth
            if effectiveLineStyle != .solid {
                effectiveLineStyle.applyFitted(to: path, pathLength: ellipsePerimeter)
            }
            if let oc = outlineColor {
                path.lineWidth = strokeWidth + 6
                oc.setStroke(); path.stroke()
                path.lineWidth = strokeWidth
            }
            color.setStroke()
            path.stroke()
        }
    }

    func drawText() {
        guard let image = textImage, textDrawRect != .zero else { return }
        let pad: CGFloat = 4
        let pillRect = textDrawRect.insetBy(dx: -pad, dy: -pad)
        let cornerR: CGFloat = 4

        // Background pill
        if let bg = textBgColor {
            bg.setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: cornerR, yRadius: cornerR).fill()
        }

        // Outline
        if let outline = textOutlineColor {
            outline.setStroke()
            let outlinePath = NSBezierPath(roundedRect: pillRect, xRadius: cornerR, yRadius: cornerR)
            outlinePath.lineWidth = 2
            outlinePath.stroke()
        }

        image.draw(in: textDrawRect)
    }

    /// Re-render the text image from attributedText with current formatting properties.
    /// Call after changing fontSize, bold, italic, font family, alignment, etc. on a committed text annotation.
    func reRenderTextImage() {
        guard tool == .text, let attrText = attributedText, textDrawRect != .zero else { return }

        // Rebuild attributed string with updated properties
        let mutable = NSMutableAttributedString(attributedString: attrText)
        let range = NSRange(location: 0, length: mutable.length)

        var font: NSFont
        if let familyName = fontFamilyName, familyName != "System",
           let familyFont = NSFont(name: familyName, size: fontSize) {
            font = familyFont
        } else {
            font = NSFont.systemFont(ofSize: fontSize)
        }
        if isBold && isItalic {
            font = NSFontManager.shared.convert(font, toHaveTrait: [.boldFontMask, .italicFontMask])
        } else if isBold {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        } else if isItalic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        mutable.addAttribute(.font, value: font, range: range)

        if isUnderline {
            mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        } else {
            mutable.removeAttribute(.underlineStyle, range: range)
        }
        if isStrikethrough {
            mutable.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        } else {
            mutable.removeAttribute(.strikethroughStyle, range: range)
        }
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = textAlignment
        mutable.addAttribute(.paragraphStyle, value: paraStyle, range: range)

        // Per-glyph stroke. NSAttributedString's .strokeWidth is a percentage
        // of font point size; negative means "fill AND stroke" (positive
        // would skip the fill, leaving just an outline).
        if let glyphStroke = textGlyphStrokeColor {
            mutable.addAttribute(.strokeColor, value: glyphStroke, range: range)
            mutable.addAttribute(.strokeWidth, value: -6.0, range: range)
        } else {
            mutable.removeAttribute(.strokeColor, range: range)
            mutable.removeAttribute(.strokeWidth, range: range)
        }

        attributedText = mutable

        // Calculate new size using the current textDrawRect width
        let inset: CGFloat = 4
        let drawWidth = textDrawRect.width - inset * 2
        let boundingRect = mutable.boundingRect(
            with: NSSize(width: drawWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let newHeight = max(textDrawRect.height, ceil(boundingRect.height) + inset * 2)
        let imgSize = NSSize(width: textDrawRect.width, height: newHeight)

        // Re-render image
        let img = NSImage(size: imgSize, flipped: true) { _ in
            mutable.draw(in: NSRect(
                x: inset, y: inset,
                width: imgSize.width - inset * 2,
                height: imgSize.height - inset * 2))
            return true
        }
        textImage = img

        // Update draw rect height (keep top edge fixed in AppKit coords: maxY stays the same)
        let heightDelta = newHeight - textDrawRect.height
        if heightDelta != 0 {
            textDrawRect = NSRect(
                x: textDrawRect.minX, y: textDrawRect.minY - heightDelta,
                width: textDrawRect.width, height: newHeight)
            startPoint = textDrawRect.origin
            endPoint = NSPoint(x: textDrawRect.maxX, y: textDrawRect.maxY)
        }

        outlineGlowImage = nil
    }

    func drawNumber() {
        guard let number = number else { return }
        let radius: CGFloat = 8 + strokeWidth * 3
        let center = startPoint

        // Draw pointer cone if dragged (startPoint != endPoint)
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let dist = hypot(dx, dy)
        if dist > 4 {
            let angle = atan2(dy, dx)
            // Cone base width tapers from the circle edge, narrowing to a point
            let baseHalfWidth = radius * 0.55
            let perpAngle = angle + .pi / 2

            // Base points on the circle's edge
            let baseL = NSPoint(x: center.x + baseHalfWidth * cos(perpAngle),
                                y: center.y + baseHalfWidth * sin(perpAngle))
            let baseR = NSPoint(x: center.x - baseHalfWidth * cos(perpAngle),
                                y: center.y - baseHalfWidth * sin(perpAngle))

            let cone = NSBezierPath()
            cone.move(to: baseL)
            cone.line(to: endPoint)
            cone.line(to: baseR)
            cone.close()
            color.setFill()
            cone.fill()
        }

        // Draw the circle on top of the cone
        let circleRect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        // Outline behind circle
        if let oc = outlineColor {
            let outlineCircle = NSBezierPath(ovalIn: circleRect.insetBy(dx: -2, dy: -2))
            outlineCircle.lineWidth = 3
            oc.setStroke()
            outlineCircle.stroke()
        }
        color.setFill()
        NSBezierPath(ovalIn: circleRect).fill()

        // Choose contrasting text color: black for light backgrounds, white for dark
        let textColor: NSColor = {
            guard let rgb = color.usingColorSpace(.sRGB) else { return .white }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
            let luminance = 0.299 * r + 0.587 * g + 0.114 * b
            return luminance > 0.6 ? .black : .white
        }()
        let fontSize = radius * 1.1
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: textColor
        ]
        let str = numberFormat.format(number) as NSString
        let size = str.size(withAttributes: attrs)
        str.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attrs)
    }

    func drawStamp() {
        guard let image = stampImage else { return }
        let rect = boundingRect
        guard rect.width > 0, rect.height > 0 else { return }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])
    }

    func drawMeasure() {
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let distance = hypot(dx, dy)
        guard distance > 1 else { return }

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        // Main measurement line
        let lineColor = color
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        lineColor.setStroke()
        path.move(to: startPoint)
        path.line(to: endPoint)
        path.stroke()

        // Perpendicular end caps (small ticks at each end)
        let angle = atan2(dy, dx)
        let perpAngle = angle + .pi / 2
        let capLength: CGFloat = 6
        let capDx = capLength * cos(perpAngle)
        let capDy = capLength * sin(perpAngle)

        let capPath = NSBezierPath()
        capPath.lineWidth = 1.5
        capPath.lineCapStyle = .round
        lineColor.setStroke()
        // Start cap
        capPath.move(to: NSPoint(x: startPoint.x - capDx, y: startPoint.y - capDy))
        capPath.line(to: NSPoint(x: startPoint.x + capDx, y: startPoint.y + capDy))
        // End cap
        capPath.move(to: NSPoint(x: endPoint.x - capDx, y: endPoint.y - capDy))
        capPath.line(to: NSPoint(x: endPoint.x + capDx, y: endPoint.y + capDy))
        capPath.stroke()

        // Dimension label
        let unit = measureInPoints ? "pt" : "px"
        let s = measureInPoints ? 1.0 : scale
        let dispDistance = Int(distance * s)
        let dispWidth = Int(abs(dx) * s)
        let dispHeight = Int(abs(dy) * s)
        let labelText: String
        if dispWidth < 3 {
            labelText = "\(dispHeight)\(unit)"
        } else if dispHeight < 3 {
            labelText = "\(dispWidth)\(unit)"
        } else {
            labelText = "\(dispDistance)\(unit) (\(dispWidth) × \(dispHeight))"
        }

        let fontSize: CGFloat = 11
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let str = labelText as NSString
        let strSize = str.size(withAttributes: attrs)

        // Position label at midpoint, offset perpendicular to the line
        let midX = (startPoint.x + endPoint.x) / 2
        let midY = (startPoint.y + endPoint.y) / 2
        let offsetDist: CGFloat = 12
        let labelX = midX + offsetDist * cos(perpAngle) - strSize.width / 2
        let labelY = midY + offsetDist * sin(perpAngle) - strSize.height / 2

        // Background pill for readability
        let padding: CGFloat = 4
        let bgRect = NSRect(
            x: labelX - padding,
            y: labelY - padding / 2,
            width: strSize.width + padding * 2,
            height: strSize.height + padding
        )
        NSColor(white: 0.0, alpha: 0.75).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4).fill()

        str.draw(at: NSPoint(x: labelX, y: labelY), withAttributes: attrs)
    }

}
