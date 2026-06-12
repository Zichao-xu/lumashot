import Cocoa

extension EffectsBandView {
    // MARK: - Geometry helpers

    /// The track rect where row 0 sits — the bottom row of the stack, offset
    /// up by `verticalInset` so the bottom row's lower handle has room.
    var row0Rect: NSRect {
        let x = horizontalInset
        let y: CGFloat = verticalInset
        let w = max(0, bounds.width - horizontalInset * 2)
        return NSRect(x: x, y: y, width: w, height: rowH)
    }

    /// Pill rect for a segment at its assigned row. Row 0 is the bottom row;
    /// higher row indices stack upward.
    func pillRect(id: UUID, startTime: Double, endTime: Double) -> NSRect {
        let row0 = row0Rect
        guard duration > 0, row0.width > 0 else { return .zero }
        let row = effectRowAssignment[id] ?? 0
        let y = row0.minY + CGFloat(row) * rowStride
        let x0 = row0.minX + CGFloat(startTime / duration) * row0.width
        let x1 = row0.minX + CGFloat(endTime / duration) * row0.width
        return NSRect(x: x0, y: y, width: max(2, x1 - x0), height: row0.height)
    }

    func zoomPillRect(for segment: VideoZoomSegment) -> NSRect {
        pillRect(id: segment.id, startTime: segment.startTime, endTime: segment.endTime)
    }

    func censorPillRect(for segment: VideoCensorSegment) -> NSRect {
        pillRect(id: segment.id, startTime: segment.startTime, endTime: segment.endTime)
    }

    func cutPillRect(for segment: VideoCutSegment) -> NSRect {
        pillRect(id: segment.id, startTime: segment.startTime, endTime: segment.endTime)
    }

    func speedPillRect(for segment: VideoSpeedSegment) -> NSRect {
        pillRect(id: segment.id, startTime: segment.startTime, endTime: segment.endTime)
    }

    /// Width of a freeze pill. Freezes are a single source instant, so
    /// there's no natural range to map to a pill width — we pick a fixed
    /// size that's wide enough to show the "❄ 1.0s" label without
    /// dominating the band.
    static let freezePillWidth: CGFloat = 62

    /// Freeze pill rect — centered on the freeze's source time. Rows
    /// assigned by `layoutRows` just like other pill types; hit-testing
    /// uses the rect's full bounds.
    func freezePillRect(for segment: VideoFreezeSegment) -> NSRect {
        let row0 = row0Rect
        guard duration > 0, row0.width > 0 else { return .zero }
        let row = effectRowAssignment[segment.id] ?? 0
        let y = row0.minY + CGFloat(row) * rowStride
        let cx = row0.minX + CGFloat(segment.atTime / duration) * row0.width
        let w = EffectsBandView.freezePillWidth
        // Clamp so the pill never slides off the band on either side.
        let x = max(row0.minX, min(row0.maxX - w, cx - w / 2))
        return NSRect(x: x, y: y, width: w, height: row0.height)
    }

    // MARK: - Layout

    /// The band's natural height, driven by the current row count. The
    /// enclosing scroll view reads this as the document view's height and
    /// enables vertical scrolling once it exceeds the clip view's bounds.
    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric,
                      height: CGFloat(effectRowCount) * rowStride - rowGap + verticalInset * 2)
    }

    override var isFlipped: Bool {
        // Keep AppKit default (y grows upward) so our rect math matches the
        // rest of the editor's drawing.
        return false
    }

    /// Greedy interval-graph coloring: each segment gets the lowest row index
    /// that doesn't collide with any segment already placed in that row.
    func layoutRows() {
        effectRowAssignment.removeAll(keepingCapacity: true)
        struct Item { let id: UUID; let start: Double; let end: Double }
        var items: [Item] = []
        for z in zoomSegments where z.endTime > z.startTime {
            items.append(Item(id: z.id, start: z.startTime, end: z.endTime))
        }
        for c in censorSegments where c.endTime > c.startTime {
            items.append(Item(id: c.id, start: c.startTime, end: c.endTime))
        }
        for k in cutSegments where k.endTime > k.startTime {
            items.append(Item(id: k.id, start: k.startTime, end: k.endTime))
        }
        for s in speedSegments where s.endTime > s.startTime {
            items.append(Item(id: s.id, start: s.startTime, end: s.endTime))
        }
        // Freezes are a single source instant; give them a synthetic
        // span equal to their pill's width mapped to source time so the
        // row-packer places them on their own row when they'd otherwise
        // overlap a zoom/censor/speed rectangle visually.
        if duration > 0, row0Rect.width > 0 {
            let pillPx = EffectsBandView.freezePillWidth
            let srcSpan = Double(pillPx / row0Rect.width) * duration
            for f in freezeSegments {
                let half = srcSpan / 2
                items.append(Item(id: f.id,
                                   start: max(0, f.atTime - half),
                                   end: min(duration, f.atTime + half)))
            }
        }
        items.sort { $0.start < $1.start }

        var rows: [[ClosedRange<Double>]] = [[]]
        for item in items {
            var assigned = -1
            for (idx, ranges) in rows.enumerated() {
                let clashes = ranges.contains { r in
                    item.start < r.upperBound && item.end > r.lowerBound
                        && !(item.start >= r.upperBound || item.end <= r.lowerBound)
                }
                if !clashes { assigned = idx; break }
            }
            if assigned < 0 {
                rows.append([])
                assigned = rows.count - 1
            }
            rows[assigned].append(item.start...item.end)
            effectRowAssignment[item.id] = assigned
        }
        let newRowCount = max(1, rows.count)
        if newRowCount != effectRowCount {
            effectRowCount = newRowCount
            invalidateIntrinsicContentSize()
            delegate?.effectsBand(self, didChangeRowCount: effectRowCount)
        } else {
            effectRowCount = newRowCount
        }
    }

    func relayoutAndNotify() {
        layoutRows()
        delegate?.effectsBandDidMutate(self)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

}
