import Cocoa

extension EffectsBandView {
    // MARK: - Hit testing helpers

    func pointIsOverAnyPill(_ p: NSPoint) -> Bool {
        let slop: CGFloat = 6
        for seg in zoomSegments {
            if zoomPillRect(for: seg).insetBy(dx: -slop, dy: -5).contains(p) { return true }
        }
        for seg in censorSegments {
            if censorPillRect(for: seg).insetBy(dx: -slop, dy: -5).contains(p) { return true }
        }
        for seg in cutSegments {
            if cutPillRect(for: seg).insetBy(dx: -slop, dy: -5).contains(p) { return true }
        }
        for seg in speedSegments {
            if speedPillRect(for: seg).insetBy(dx: -slop, dy: -5).contains(p) { return true }
        }
        for seg in freezeSegments {
            if freezePillRect(for: seg).insetBy(dx: -slop, dy: -5).contains(p) { return true }
        }
        return false
    }

    // MARK: - Mouse

    override var acceptsFirstResponder: Bool { true }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        cursorOnBand = bounds.contains(p) ? p : nil
    }

    override func mouseExited(with event: NSEvent) {
        cursorOnBand = nil
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let edgeHitW: CGFloat = 9
        // Clamp to [0, duration] so a click in the handle-overhang zone
        // (the 4pt gap between row0Rect and the band's edges, which
        // exists so edge-pill handles render fully) doesn't produce a
        // click-time slightly outside the timeline. Without this clamp
        // the drag anchor gets a sub-duration offset, causing dragged
        // pills to stop just short of 0 / duration.
        let clickTime = max(0, min(duration,
            Double((p.x - row0Rect.minX) / max(row0Rect.width, 1)) * duration))

        // Freezes first — they're narrow point markers and easy to miss
        // if a wider pill underneath steals the click.
        for seg in freezeSegments.reversed() {
            let pill = freezePillRect(for: seg)
            if pill.insetBy(dx: -edgeHitW, dy: -5).contains(p) {
                // Freezes are move-only (no resize — a moment in time
                // has no width to stretch). `segStart == segEnd == atTime`
                // gives the existing drag machinery something to subtract
                // from when computing the anchor offset.
                beginSegmentDrag(id: seg.id,
                                  edge: .move,
                                  clickTime: clickTime,
                                  segStart: seg.atTime,
                                  segEnd: seg.atTime)
                return
            }
        }
        // Cuts next so they remain clickable even when visually stacked on
        // top of zoom/censor pills that share their time range.
        for seg in cutSegments.reversed() {
            let pill = cutPillRect(for: seg)
            if pill.insetBy(dx: -edgeHitW, dy: -5).contains(p) {
                beginSegmentDrag(id: seg.id,
                                  edge: edgeHitForX(p.x, pill: pill, hitW: edgeHitW),
                                  clickTime: clickTime,
                                  segStart: seg.startTime,
                                  segEnd: seg.endTime)
                return
            }
        }
        for seg in speedSegments.reversed() {
            let pill = speedPillRect(for: seg)
            if pill.insetBy(dx: -edgeHitW, dy: -5).contains(p) {
                beginSegmentDrag(id: seg.id,
                                  edge: edgeHitForX(p.x, pill: pill, hitW: edgeHitW),
                                  clickTime: clickTime,
                                  segStart: seg.startTime,
                                  segEnd: seg.endTime)
                return
            }
        }
        // Zooms (iterate reverse so the latest-drawn wins on overlap).
        for seg in zoomSegments.reversed() {
            let pill = zoomPillRect(for: seg)
            if pill.insetBy(dx: -edgeHitW, dy: -5).contains(p) {
                beginSegmentDrag(id: seg.id,
                                  edge: edgeHitForX(p.x, pill: pill, hitW: edgeHitW),
                                  clickTime: clickTime,
                                  segStart: seg.startTime,
                                  segEnd: seg.endTime)
                return
            }
        }
        for seg in censorSegments.reversed() {
            let pill = censorPillRect(for: seg)
            if pill.insetBy(dx: -edgeHitW, dy: -5).contains(p) {
                beginSegmentDrag(id: seg.id,
                                  edge: edgeHitForX(p.x, pill: pill, hitW: edgeHitW),
                                  clickTime: clickTime,
                                  segStart: seg.startTime,
                                  segEnd: seg.endTime)
                return
            }
        }
        // Empty band — open add menu at click point.
        showAddEffectMenu(at: p, clickTime: clickTime)
    }

    func edgeHitForX(_ x: CGFloat, pill: NSRect, hitW: CGFloat) -> SegmentDragKind {
        if abs(x - pill.minX) < hitW { return .resizeStart }
        if abs(x - pill.maxX) < hitW { return .resizeEnd }
        return .move
    }

    func beginSegmentDrag(id: UUID, edge: SegmentDragKind, clickTime: Double, segStart: Double, segEnd: Double) {
        selectedSegmentID = id
        draggingSegmentID = id
        draggingSegmentKind = edge
        switch edge {
        case .resizeStart: draggingSegmentAnchor = clickTime - segStart
        case .resizeEnd:   draggingSegmentAnchor = clickTime - segEnd
        case .move:        draggingSegmentAnchor = clickTime - segStart
        }
        delegate?.effectsBandDidMutate(self)   // selection is a kind of mutation for composition purposes
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let id = draggingSegmentID, let kind = draggingSegmentKind else { return }
        let p = convert(event.locationInWindow, from: nil)
        let t = max(0, min(duration, Double((p.x - row0Rect.minX) / max(row0Rect.width, 1)) * duration))
        if let seg = zoomSegments.first(where: { $0.id == id }) {
            dragZoomSegment(seg, kind: kind, time: t)
        } else if let seg = censorSegments.first(where: { $0.id == id }) {
            dragCensorSegment(seg, kind: kind, time: t)
        } else if let seg = cutSegments.first(where: { $0.id == id }) {
            dragCutSegment(seg, kind: kind, time: t)
        } else if let seg = speedSegments.first(where: { $0.id == id }) {
            dragSpeedSegment(seg, kind: kind, time: t)
        } else if let seg = freezeSegments.first(where: { $0.id == id }) {
            dragFreezeSegment(seg, time: t)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = draggingSegmentID != nil
        draggingSegmentID = nil
        draggingSegmentKind = nil
        if wasDragging {
            delegate?.effectsBandDidMutate(self)
        }
    }

    func dragZoomSegment(_ seg: VideoZoomSegment, kind: SegmentDragKind, time t: Double) {
        let others = zoomSegments.filter { $0.id != seg.id }.map { (start: $0.startTime, end: $0.endTime) }
        switch kind {
        case .move:
            let (newStart, newEnd) = resolveMove(segment: (seg.startTime, seg.endTime),
                                                  to: t - draggingSegmentAnchor,
                                                  others: others)
            seg.startTime = max(0, newStart); seg.endTime = min(duration, newEnd)
        case .resizeStart:
            let minEnd = seg.endTime - VideoZoomSegment.minDuration
            var newStart = max(0, min(minEnd, t - draggingSegmentAnchor))
            let lowerBound = others.filter { $0.end <= seg.endTime }.map(\.end).max() ?? 0
            newStart = max(lowerBound, newStart)
            seg.startTime = newStart
        case .resizeEnd:
            let minStart = seg.startTime + VideoZoomSegment.minDuration
            var newEnd = max(minStart, min(duration, t - draggingSegmentAnchor))
            let upperBound = others.filter { $0.start >= seg.startTime }.map(\.start).min() ?? duration
            newEnd = min(upperBound, newEnd)
            seg.endTime = newEnd
        }
        layoutRows()
        needsDisplay = true
    }

    func dragSpeedSegment(_ seg: VideoSpeedSegment, kind: SegmentDragKind, time t: Double) {
        // Speed segments can't overlap each other — enforce via neighbour
        // clamping. They're allowed to overlap cuts (they'll be silently
        // clipped to the kept range on export).
        let others = speedSegments.filter { $0.id != seg.id }.map { (start: $0.startTime, end: $0.endTime) }
        // Min source duration so composition duration stays >= minCompDuration.
        let minSrcDuration = VideoSpeedSegment.minCompDuration * seg.speedFactor
        switch kind {
        case .move:
            let (newStart, newEnd) = resolveMove(segment: (seg.startTime, seg.endTime),
                                                  to: t - draggingSegmentAnchor,
                                                  others: others)
            seg.startTime = max(0, newStart); seg.endTime = min(duration, newEnd)
        case .resizeStart:
            let minEnd = seg.endTime - minSrcDuration
            var newStart = max(0, min(minEnd, t - draggingSegmentAnchor))
            let lowerBound = others.filter { $0.end <= seg.endTime }.map(\.end).max() ?? 0
            newStart = max(lowerBound, newStart)
            seg.startTime = newStart
        case .resizeEnd:
            let minStart = seg.startTime + minSrcDuration
            var newEnd = max(minStart, min(duration, t - draggingSegmentAnchor))
            let upperBound = others.filter { $0.start >= seg.startTime }.map(\.start).min() ?? duration
            newEnd = min(upperBound, newEnd)
            seg.endTime = newEnd
        }
        layoutRows()
        needsDisplay = true
    }

    /// Move a freeze segment's `atTime` to follow the cursor. No resize —
    /// a freeze has no width in source time. Clamped to [0, duration] so
    /// it always stays over the timeline.
    func dragFreezeSegment(_ seg: VideoFreezeSegment, time t: Double) {
        let newAt = max(0, min(duration, t - draggingSegmentAnchor))
        seg.atTime = newAt
        layoutRows()
        needsDisplay = true
    }

    func dragCutSegment(_ seg: VideoCutSegment, kind: SegmentDragKind, time t: Double) {
        // Cuts can overlap freely — the export pipeline merges overlapping
        // cut ranges, so no need for neighbour-based clamping.
        switch kind {
        case .move:
            let (newStart, newEnd) = resolveMove(segment: (seg.startTime, seg.endTime),
                                                  to: t - draggingSegmentAnchor,
                                                  others: [])
            seg.startTime = max(0, newStart); seg.endTime = min(duration, newEnd)
        case .resizeStart:
            let minEnd = seg.endTime - VideoCutSegment.minDuration
            seg.startTime = max(0, min(minEnd, t - draggingSegmentAnchor))
        case .resizeEnd:
            let minStart = seg.startTime + VideoCutSegment.minDuration
            seg.endTime = max(minStart, min(duration, t - draggingSegmentAnchor))
        }
        layoutRows()
        needsDisplay = true
    }

    func dragCensorSegment(_ seg: VideoCensorSegment, kind: SegmentDragKind, time t: Double) {
        // Censors can overlap each other freely — empty others list.
        switch kind {
        case .move:
            let (newStart, newEnd) = resolveMove(segment: (seg.startTime, seg.endTime),
                                                  to: t - draggingSegmentAnchor,
                                                  others: [])
            seg.startTime = max(0, newStart); seg.endTime = min(duration, newEnd)
        case .resizeStart:
            let minEnd = seg.endTime - VideoCensorSegment.minDuration
            seg.startTime = max(0, min(minEnd, t - draggingSegmentAnchor))
        case .resizeEnd:
            let minStart = seg.startTime + VideoCensorSegment.minDuration
            seg.endTime = max(minStart, min(duration, t - draggingSegmentAnchor))
        }
        layoutRows()
        needsDisplay = true
    }

    func resolveMove(segment: (Double, Double),
                              to desiredStart: Double,
                              others: [(start: Double, end: Double)]) -> (Double, Double) {
        let segDuration = segment.1 - segment.0
        var newStart = max(0, min(duration - segDuration, desiredStart))
        var newEnd = newStart + segDuration
        let currentStart = segment.0
        for other in others.sorted(by: { $0.start < $1.start }) {
            if newStart < other.end && newEnd > other.start {
                if currentStart < other.start {
                    newEnd = other.start; newStart = newEnd - segDuration
                } else {
                    newStart = other.end;  newEnd = newStart + segDuration
                }
            }
        }
        return (newStart, newEnd)
    }

}
