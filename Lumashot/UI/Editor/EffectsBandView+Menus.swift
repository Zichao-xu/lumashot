import Cocoa

extension EffectsBandView {
    // MARK: - Right-click menus

    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let edgeSlop: CGFloat = 6
        // Freezes first — narrow markers, hardest to hit accidentally.
        for seg in freezeSegments.reversed() {
            let pill = freezePillRect(for: seg)
            if pill.insetBy(dx: -edgeSlop, dy: -5).contains(p) {
                selectedSegmentID = seg.id
                needsDisplay = true
                showFreezePillContextMenu(for: seg, at: event)
                return
            }
        }
        for seg in cutSegments.reversed() {
            let pill = cutPillRect(for: seg)
            if pill.insetBy(dx: -edgeSlop, dy: -5).contains(p) {
                selectedSegmentID = seg.id
                needsDisplay = true
                showCutPillContextMenu(for: seg, at: event)
                return
            }
        }
        for seg in speedSegments.reversed() {
            let pill = speedPillRect(for: seg)
            if pill.insetBy(dx: -edgeSlop, dy: -5).contains(p) {
                selectedSegmentID = seg.id
                needsDisplay = true
                showSpeedPillContextMenu(for: seg, at: event)
                return
            }
        }
        for seg in zoomSegments.reversed() {
            let pill = zoomPillRect(for: seg)
            if pill.insetBy(dx: -edgeSlop, dy: -5).contains(p) {
                selectedSegmentID = seg.id
                needsDisplay = true
                showZoomPillContextMenu(for: seg, at: event)
                return
            }
        }
        for seg in censorSegments.reversed() {
            let pill = censorPillRect(for: seg)
            if pill.insetBy(dx: -edgeSlop, dy: -5).contains(p) {
                selectedSegmentID = seg.id
                needsDisplay = true
                showCensorPillContextMenu(for: seg, at: event)
                return
            }
        }
        // Clamp to [0, duration] so a click in the handle-overhang zone
        // (the 4pt gap between row0Rect and the band's edges, which
        // exists so edge-pill handles render fully) doesn't produce a
        // click-time slightly outside the timeline. Without this clamp
        // the drag anchor gets a sub-duration offset, causing dragged
        // pills to stop just short of 0 / duration.
        let clickTime = max(0, min(duration,
            Double((p.x - row0Rect.minX) / max(row0Rect.width, 1)) * duration))
        showAddEffectMenu(at: p, clickTime: clickTime)
    }

    func showCutPillContextMenu(for seg: VideoCutSegment, at event: NSEvent) {
        let menu = NSMenu()
        attachAddEffectSubmenu(to: menu, event: event)
        menu.addItem(.separator())
        let del = NSMenuItem(title: L("Delete Cut"),
                              action: #selector(handleDeleteSelectedFromMenu),
                              keyEquivalent: "")
        del.target = self
        menu.addItem(del)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    func showFreezePillContextMenu(for seg: VideoFreezeSegment, at event: NSEvent) {
        let menu = NSMenu()
        // Duration presets — quick way to change how long the freeze holds.
        for preset in VideoFreezeSegment.presetDurations {
            let item = NSMenuItem(title: formatFreezeLabel(preset),
                                  action: #selector(handleSetFreezeDurationFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = FreezeDurationMenuContext(segmentID: seg.id, seconds: preset)
            item.state = (abs(seg.holdDuration - preset) < 0.01) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        attachAddEffectSubmenu(to: menu, event: event)
        menu.addItem(.separator())
        let del = NSMenuItem(title: L("Delete Freeze"),
                              action: #selector(handleDeleteSelectedFromMenu),
                              keyEquivalent: "")
        del.target = self
        menu.addItem(del)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    func showSpeedPillContextMenu(for seg: VideoSpeedSegment, at event: NSEvent) {
        let menu = NSMenu()
        for factor in VideoSpeedSegment.presetFactors {
            let item = NSMenuItem(title: "\(formatSpeedLabel(factor))",
                                  action: #selector(handleSetSpeedFactorFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = SpeedFactorMenuContext(segmentID: seg.id, factor: factor)
            item.state = (abs(seg.speedFactor - factor) < 0.001) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        attachAddEffectSubmenu(to: menu, event: event)
        menu.addItem(.separator())
        let del = NSMenuItem(title: L("Delete Speed"),
                              action: #selector(handleDeleteSelectedFromMenu),
                              keyEquivalent: "")
        del.target = self
        menu.addItem(del)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    func showZoomPillContextMenu(for seg: VideoZoomSegment, at event: NSEvent) {
        let menu = NSMenu()
        attachFadeSubmenu(to: menu, segmentID: seg.id, currentFade: seg.fadeIn)
        menu.addItem(.separator())
        attachAddEffectSubmenu(to: menu, event: event)
        menu.addItem(.separator())
        let del = NSMenuItem(title: L("Delete Zoom"),
                              action: #selector(handleDeleteSelectedFromMenu),
                              keyEquivalent: "")
        del.target = self
        menu.addItem(del)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    func showCensorPillContextMenu(for seg: VideoCensorSegment, at event: NSEvent) {
        let menu = NSMenu()
        let styles: [(String, VideoCensorSegment.Style)] = [
            (L("Solid"),    .solid),
            (L("Pixelate"), .pixelate),
            (L("Blur"),     .blur),
        ]
        for (title, style) in styles {
            let item = NSMenuItem(title: title,
                                  action: #selector(handleSetCensorStyleFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = CensorStyleMenuContext(segmentID: seg.id, style: style)
            item.state = (seg.style == style) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        attachFadeSubmenu(to: menu, segmentID: seg.id, currentFade: seg.fadeIn)
        menu.addItem(.separator())
        attachAddEffectSubmenu(to: menu, event: event)
        menu.addItem(.separator())
        let del = NSMenuItem(title: L("Delete Censor"),
                              action: #selector(handleDeleteSelectedFromMenu),
                              keyEquivalent: "")
        del.target = self
        menu.addItem(del)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    /// Adds a "Fade" submenu to `menu` listing a few preset durations. The
    /// same value is applied to both fade-in and fade-out since exposing two
    /// knobs is overkill for this UI.
    func attachFadeSubmenu(to menu: NSMenu, segmentID: UUID, currentFade: Double) {
        let parent = NSMenuItem(title: L("Fade"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        // Presets in seconds. 0 = hard cut. Matching tolerance of 0.02s for the
        // checkmark comparison so drift from prior auto-fade values still shows
        // the "right" item as active.
        let presets: [Double] = [0, 0.15, 0.35, 0.5, 1.0]
        for seconds in presets {
            let title: String = (seconds == 0)
                ? L("None")
                : (seconds == 1.0 ? "1s" : String(format: "%.2fs", seconds))
            let item = NSMenuItem(title: title,
                                  action: #selector(handleSetFadeFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = FadeMenuContext(segmentID: segmentID, seconds: seconds)
            item.state = (abs(currentFade - seconds) < 0.02) ? .on : .off
            sub.addItem(item)
        }
        parent.submenu = sub
        menu.addItem(parent)
    }

    func showAddEffectMenu(at point: NSPoint, clickTime: Double) {
        let menu = NSMenu()
        let zoomItem = NSMenuItem(title: L("Add Zoom"),
                                  action: #selector(handleAddZoomFromMenu(_:)),
                                  keyEquivalent: "")
        zoomItem.image = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: nil)
        zoomItem.target = self
        if let g = zoomGapAtClickTime(clickTime) {
            zoomItem.representedObject = AddEffectContext(clickTime: clickTime, gapStart: g.0, gapEnd: g.1)
            zoomItem.isEnabled = true
        } else {
            zoomItem.isEnabled = false
        }
        menu.addItem(zoomItem)

        let censorItem = NSMenuItem(title: L("Add Censor"),
                                    action: #selector(handleAddCensorFromMenu(_:)),
                                    keyEquivalent: "")
        censorItem.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
        censorItem.target = self
        censorItem.representedObject = AddEffectContext(clickTime: clickTime, gapStart: 0, gapEnd: duration)
        menu.addItem(censorItem)

        let cutItem = NSMenuItem(title: L("Add Cut"),
                                 action: #selector(handleAddCutFromMenu(_:)),
                                 keyEquivalent: "")
        cutItem.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)
        cutItem.target = self
        cutItem.representedObject = AddEffectContext(clickTime: clickTime, gapStart: 0, gapEnd: duration)
        menu.addItem(cutItem)

        let speedItem = NSMenuItem(title: L("Add Speed"),
                                    action: #selector(handleAddSpeedFromMenu(_:)),
                                    keyEquivalent: "")
        speedItem.image = NSImage(systemSymbolName: "forward.fill", accessibilityDescription: nil)
        speedItem.target = self
        if let g = speedGapAtClickTime(clickTime) {
            speedItem.representedObject = AddEffectContext(clickTime: clickTime, gapStart: g.0, gapEnd: g.1)
            speedItem.isEnabled = true
        } else {
            speedItem.isEnabled = false
        }
        menu.addItem(speedItem)

        let freezeItem = NSMenuItem(title: L("Add Freeze"),
                                     action: #selector(handleAddFreezeFromMenu(_:)),
                                     keyEquivalent: "")
        freezeItem.image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: nil)
        freezeItem.target = self
        freezeItem.representedObject = AddEffectContext(clickTime: clickTime, gapStart: 0, gapEnd: duration)
        menu.addItem(freezeItem)

        menu.popUp(positioning: nil, at: point, in: self)
    }

    func attachAddEffectSubmenu(to menu: NSMenu, event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        // Clamp to [0, duration] so a click in the handle-overhang zone
        // (the 4pt gap between row0Rect and the band's edges, which
        // exists so edge-pill handles render fully) doesn't produce a
        // click-time slightly outside the timeline. Without this clamp
        // the drag anchor gets a sub-duration offset, causing dragged
        // pills to stop just short of 0 / duration.
        let clickTime = max(0, min(duration,
            Double((p.x - row0Rect.minX) / max(row0Rect.width, 1)) * duration))
        let parent = NSMenuItem(title: L("Add effect"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let zoomGap = zoomGapAtClickTime(clickTime)
        let zoomItem = NSMenuItem(title: L("Add Zoom"),
                                  action: #selector(handleAddZoomFromMenu(_:)),
                                  keyEquivalent: "")
        zoomItem.target = self
        if let g = zoomGap {
            zoomItem.representedObject = AddEffectContext(clickTime: clickTime, gapStart: g.0, gapEnd: g.1)
            zoomItem.isEnabled = true
        } else {
            zoomItem.isEnabled = false
        }
        sub.addItem(zoomItem)
        let censorItem = NSMenuItem(title: L("Add Censor"),
                                    action: #selector(handleAddCensorFromMenu(_:)),
                                    keyEquivalent: "")
        censorItem.target = self
        censorItem.representedObject = AddEffectContext(clickTime: clickTime, gapStart: 0, gapEnd: duration)
        sub.addItem(censorItem)
        let cutItem = NSMenuItem(title: L("Add Cut"),
                                 action: #selector(handleAddCutFromMenu(_:)),
                                 keyEquivalent: "")
        cutItem.target = self
        cutItem.representedObject = AddEffectContext(clickTime: clickTime, gapStart: 0, gapEnd: duration)
        sub.addItem(cutItem)
        let speedItem = NSMenuItem(title: L("Add Speed"),
                                    action: #selector(handleAddSpeedFromMenu(_:)),
                                    keyEquivalent: "")
        speedItem.target = self
        if let g = speedGapAtClickTime(clickTime) {
            speedItem.representedObject = AddEffectContext(clickTime: clickTime, gapStart: g.0, gapEnd: g.1)
            speedItem.isEnabled = true
        } else {
            speedItem.isEnabled = false
        }
        sub.addItem(speedItem)
        let freezeItem = NSMenuItem(title: L("Add Freeze"),
                                     action: #selector(handleAddFreezeFromMenu(_:)),
                                     keyEquivalent: "")
        freezeItem.target = self
        freezeItem.representedObject = AddEffectContext(clickTime: clickTime, gapStart: 0, gapEnd: duration)
        sub.addItem(freezeItem)
        parent.submenu = sub
        menu.addItem(parent)
    }

    /// Returns the (start, end) of the speed-free interval containing `t`,
    /// or nil if `t` is inside an existing speed segment. Same logic as
    /// `zoomGapAtClickTime` so the UI refuses to place overlapping speeds.
    func speedGapAtClickTime(_ t: Double) -> (Double, Double)? {
        guard duration > 0 else { return nil }
        let speeds = speedSegments
            .filter { $0.endTime > $0.startTime }
            .sorted { $0.startTime < $1.startTime }
        var cursor: Double = 0
        for s in speeds {
            if s.startTime > cursor + 0.001 {
                if t >= cursor && t <= s.startTime
                    && (s.startTime - cursor) >= 0.3 {
                    return (cursor, s.startTime)
                }
            }
            cursor = max(cursor, s.endTime)
        }
        if cursor < duration - 0.001 && t >= cursor && t <= duration
            && (duration - cursor) >= 0.3 {
            return (cursor, duration)
        }
        return nil
    }

    /// Returns the (start, end) of the zoom-free interval containing `t`, or
    /// nil if `t` is inside a zoom segment.
    func zoomGapAtClickTime(_ t: Double) -> (Double, Double)? {
        guard duration > 0 else { return nil }
        let zooms = zoomSegments
            .filter { $0.endTime > $0.startTime }
            .sorted { $0.startTime < $1.startTime }
        var cursor: Double = 0
        for z in zooms {
            if z.startTime > cursor + 0.001 {
                if t >= cursor && t <= z.startTime
                    && (z.startTime - cursor) >= VideoZoomSegment.minDuration {
                    return (cursor, z.startTime)
                }
            }
            cursor = max(cursor, z.endTime)
        }
        if cursor < duration - 0.001 && t >= cursor && t <= duration
            && (duration - cursor) >= VideoZoomSegment.minDuration {
            return (cursor, duration)
        }
        return nil
    }

}
