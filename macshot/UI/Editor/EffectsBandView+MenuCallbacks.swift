import Cocoa

extension EffectsBandView {
    // MARK: - Menu callbacks

    @objc func handleDeleteSelectedFromMenu() {
        guard let id = selectedSegmentID else { return }
        removeSegment(id: id)
    }

    @objc func handleSetCensorStyleFromMenu(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? CensorStyleMenuContext,
              let seg = censorSegments.first(where: { $0.id == ctx.segmentID }) else { return }
        seg.style = ctx.style
        delegate?.effectsBandDidMutate(self)
        needsDisplay = true
    }

    @objc func handleSetFadeFromMenu(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? FadeMenuContext else { return }
        if let seg = zoomSegments.first(where: { $0.id == ctx.segmentID }) {
            seg.fadeIn = ctx.seconds
            seg.fadeOut = ctx.seconds
        } else if let seg = censorSegments.first(where: { $0.id == ctx.segmentID }) {
            seg.fadeIn = ctx.seconds
            seg.fadeOut = ctx.seconds
        } else {
            return
        }
        delegate?.effectsBandDidMutate(self)
        needsDisplay = true
    }

    @objc func handleAddZoomFromMenu(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? AddEffectContext else { return }
        addZoomSegment(clickTime: ctx.clickTime, gapStart: ctx.gapStart, gapEnd: ctx.gapEnd)
    }

    @objc func handleAddCensorFromMenu(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? AddEffectContext else { return }
        addCensorSegment(clickTime: ctx.clickTime)
    }

    @objc func handleAddCutFromMenu(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? AddEffectContext else { return }
        addCutSegment(clickTime: ctx.clickTime)
    }

    @objc func handleAddSpeedFromMenu(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? AddEffectContext else { return }
        addSpeedSegment(clickTime: ctx.clickTime, gapStart: ctx.gapStart, gapEnd: ctx.gapEnd)
    }

    @objc func handleAddFreezeFromMenu(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? AddEffectContext else { return }
        addFreezeSegment(atTime: ctx.clickTime)
    }

    @objc func handleSetFreezeDurationFromMenu(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? FreezeDurationMenuContext,
              let seg = freezeSegments.first(where: { $0.id == ctx.segmentID }) else { return }
        seg.holdDuration = VideoFreezeSegment.clampDuration(ctx.seconds)
        delegate?.effectsBandDidMutate(self)
        needsDisplay = true
    }

    @objc func handleSetSpeedFactorFromMenu(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? SpeedFactorMenuContext,
              let seg = speedSegments.first(where: { $0.id == ctx.segmentID }) else { return }
        let newFactor = VideoSpeedSegment.clampFactor(ctx.factor)
        // Respect the composition-duration floor. If the new factor would
        // shrink the piece below min, shorten the source range so comp
        // duration stays at the floor.
        let minSrcDur = VideoSpeedSegment.minCompDuration * newFactor
        if seg.sourceDuration < minSrcDur {
            seg.endTime = min(duration, seg.startTime + minSrcDur)
        }
        seg.speedFactor = newFactor
        delegate?.effectsBandDidMutate(self)
        needsDisplay = true
    }

    func addZoomSegment(clickTime: Double, gapStart: Double, gapEnd: Double) {
        guard duration > 0 else { return }
        let gapDuration = gapEnd - gapStart
        guard gapDuration >= VideoZoomSegment.minDuration else {
            delegate?.effectsBand(self, showStatus: L("Not enough room here"), isError: true)
            return
        }
        let segDuration = min(2.0, gapDuration)
        var start = clickTime - segDuration / 2
        start = max(gapStart, min(gapEnd - segDuration, start))
        let seg = VideoZoomSegment(startTime: start, endTime: start + segDuration,
                                    zoomLevel: 2.0, center: CGPoint(x: 0.5, y: 0.5))
        zoomSegments.append(seg)
        selectedSegmentID = seg.id
        relayoutAndNotify()
    }

    func addCensorSegment(clickTime: Double) {
        guard duration > 0 else { return }
        let segDuration = min(2.0, max(VideoCensorSegment.minDuration, duration))
        var start = clickTime - segDuration / 2
        start = max(0, min(duration - segDuration, start))
        let seg = VideoCensorSegment(startTime: start, endTime: start + segDuration, style: .blur)
        censorSegments.append(seg)
        selectedSegmentID = seg.id
        relayoutAndNotify()
    }

    func addCutSegment(clickTime: Double) {
        guard duration > 0 else { return }
        let segDuration = min(1.0, max(VideoCutSegment.minDuration, duration))
        var start = clickTime - segDuration / 2
        start = max(0, min(duration - segDuration, start))
        let seg = VideoCutSegment(startTime: start, endTime: start + segDuration)
        cutSegments.append(seg)
        selectedSegmentID = seg.id
        relayoutAndNotify()
    }

    func addSpeedSegment(clickTime: Double, gapStart: Double, gapEnd: Double) {
        guard duration > 0 else { return }
        let gapDuration = gapEnd - gapStart
        let defaultFactor: Double = 2.0
        let minSrcDur = VideoSpeedSegment.minCompDuration * defaultFactor
        guard gapDuration >= minSrcDur else {
            delegate?.effectsBand(self, showStatus: L("Not enough room here"), isError: true)
            return
        }
        // Default: 2s of source at 2× (so the pill takes up 2s visually on
        // the timeline but plays in 1s). Clamp to gap.
        let segDuration = min(2.0, gapDuration)
        var start = clickTime - segDuration / 2
        start = max(gapStart, min(gapEnd - segDuration, start))
        let seg = VideoSpeedSegment(startTime: start, endTime: start + segDuration, speedFactor: defaultFactor)
        speedSegments.append(seg)
        selectedSegmentID = seg.id
        relayoutAndNotify()
    }

    func addFreezeSegment(atTime clickTime: Double) {
        guard duration > 0 else { return }
        // Clamp a hair away from the edges so a freeze right at t=0 or
        // t=duration still lands inside a kept range (VideoCuts treats
        // exact boundaries as outside, which would cause the freeze to
        // be silently dropped at export).
        let eps = 0.001
        let t = max(eps, min(duration - eps, clickTime))
        let seg = VideoFreezeSegment(atTime: t)
        freezeSegments.append(seg)
        selectedSegmentID = seg.id
        relayoutAndNotify()
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117: // Delete / Forward-Delete
            if let id = selectedSegmentID {
                removeSegment(id: id)
            } else {
                super.keyDown(with: event)
            }
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Menu context carriers

    final class AddEffectContext: NSObject {
        let clickTime: Double
        let gapStart: Double
        let gapEnd: Double
        init(clickTime: Double, gapStart: Double, gapEnd: Double) {
            self.clickTime = clickTime
            self.gapStart = gapStart
            self.gapEnd = gapEnd
        }
    }

    final class CensorStyleMenuContext: NSObject {
        let segmentID: UUID
        let style: VideoCensorSegment.Style
        init(segmentID: UUID, style: VideoCensorSegment.Style) {
            self.segmentID = segmentID
            self.style = style
        }
    }

    final class FadeMenuContext: NSObject {
        let segmentID: UUID
        let seconds: Double
        init(segmentID: UUID, seconds: Double) {
            self.segmentID = segmentID
            self.seconds = seconds
        }
    }

    final class SpeedFactorMenuContext: NSObject {
        let segmentID: UUID
        let factor: Double
        init(segmentID: UUID, factor: Double) {
            self.segmentID = segmentID
            self.factor = factor
        }
    }

    final class FreezeDurationMenuContext: NSObject {
        let segmentID: UUID
        let seconds: Double
        init(segmentID: UUID, seconds: Double) {
            self.segmentID = segmentID
            self.seconds = seconds
        }
    }
}
