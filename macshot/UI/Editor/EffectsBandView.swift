import Cocoa

/// The effects band — the horizontal strip below the trim timeline that
/// hosts zoom and censor pills, stacked across multiple rows when segments
/// overlap in time. Owns its own state, drawing, hit testing and input.
/// Communicates mutations back to the parent editor via its delegate.
@MainActor
protocol EffectsBandViewDelegate: AnyObject {
    /// Segment data (contents OR selection) changed; caller should rebuild
    /// the video composition, invalidate saved-URL state, etc.
    func effectsBandDidMutate(_ view: EffectsBandView)
    /// Selection changed; caller should update the preview overlay and
    /// optionally seek the player to a time that makes editing intuitive.
    func effectsBand(_ view: EffectsBandView, didSelectSegment segmentID: UUID?)
    /// Number of visible rows changed; caller should resize the scroll-view
    /// host / window. Called AFTER the band's intrinsicContentSize updates.
    func effectsBand(_ view: EffectsBandView, didChangeRowCount rowCount: Int)
    /// Convenience hook for "please show this status string" — mirrors the
    /// editor's in-view status banner so we don't duplicate that machinery.
    func effectsBand(_ view: EffectsBandView, showStatus message: String, isError: Bool)
}

@MainActor
final class EffectsBandView: NSView {

    // MARK: - Public state (owned by this view, read by the parent)

    weak var delegate: EffectsBandViewDelegate?

    /// Total source-asset duration in seconds. Parent must keep this updated
    /// (e.g. after the asset finishes loading).
    var duration: Double = 0 {
        didSet { if duration != oldValue { needsLayout = true; needsDisplay = true } }
    }

    var zoomSegments: [VideoZoomSegment] = []
    var censorSegments: [VideoCensorSegment] = []
    /// Cuts are temporal — frames in their range never reach the output.
    /// They render as a dimmed "deleted film" pill distinct from zoom/censor.
    var cutSegments: [VideoCutSegment] = []
    /// Speed segments retime a source range. Non-overlapping with each
    /// other (enforced at drag time). Shown as a teal pill with the
    /// factor text (e.g. "2×").
    var speedSegments: [VideoSpeedSegment] = []
    /// Freeze segments — point-in-time pauses. Each occupies a single
    /// source instant and spans `holdDuration` composition seconds. On
    /// the band they render as a narrow violet pill anchored at `atTime`
    /// with a snowflake icon. See `VideoFreezeSegment`.
    var freezeSegments: [VideoFreezeSegment] = []
    var selectedSegmentID: UUID? {
        didSet {
            if oldValue != selectedSegmentID {
                delegate?.effectsBand(self, didSelectSegment: selectedSegmentID)
                needsDisplay = true
            }
        }
    }

    // MARK: - Layout constants

    let rowH: CGFloat = 22
    let rowGap: CGFloat = 2
    var rowStride: CGFloat { rowH + rowGap }
    /// Horizontal padding inside the band. Pills are laid out within the
    /// inset rect, so they visually align with the trim timeline above;
    /// the inset itself gives the 6pt-wide handles room to poke over
    /// the pill edge without being clipped when a pill sits at
    /// startTime = 0 or endTime = duration. The enclosing scroll view
    /// extends 4pt past `timelinePad` on each side to match, so the
    /// overhanging handles actually render.
    let horizontalInset: CGFloat = 4
    /// Vertical padding around the stack so the topmost row's upper handle
    /// (and bottommost row's lower handle) don't get clipped by the scroll
    /// view's content bounds.
    let verticalInset: CGFloat = 4
    /// Visible rows above this count scroll via the enclosing scroll view.
    static let maxVisibleRows: Int = 4

    // MARK: - Private state

    var effectRowAssignment: [UUID: Int] = [:]
    var effectRowCount: Int = 1

    enum SegmentDragKind { case move, resizeStart, resizeEnd }
    var draggingSegmentID: UUID?
    var draggingSegmentKind: SegmentDragKind?
    var draggingSegmentAnchor: Double = 0

    var cursorOnBand: NSPoint? {
        didSet { if oldValue != cursorOnBand { needsDisplay = true } }
    }
    var trackingArea: NSTrackingArea?

    // MARK: - Public API for mutation from the parent

    /// Replace all segments. Used at init time.
    func setSegments(zoom: [VideoZoomSegment],
                     censor: [VideoCensorSegment],
                     cut: [VideoCutSegment] = [],
                     speed: [VideoSpeedSegment] = [],
                     freeze: [VideoFreezeSegment] = []) {
        self.zoomSegments = zoom
        self.censorSegments = censor
        self.cutSegments = cut
        self.speedSegments = speed
        self.freezeSegments = freeze
        relayoutAndNotify()
    }

    /// Remove segment by id regardless of type.
    func removeSegment(id: UUID) {
        zoomSegments.removeAll { $0.id == id }
        censorSegments.removeAll { $0.id == id }
        cutSegments.removeAll { $0.id == id }
        speedSegments.removeAll { $0.id == id }
        freezeSegments.removeAll { $0.id == id }
        if selectedSegmentID == id { selectedSegmentID = nil }
        relayoutAndNotify()
    }

    /// Commit a change the parent made to a segment's properties (e.g. the
    /// preview overlay resized a zoom rect). Triggers a re-layout + redraw
    /// without re-sending a mutation signal (caller already knows).
    func refreshAfterParentEdit() {
        layoutRows()
        needsDisplay = true
    }

    /// Clear the current selection. Safe to call when no segment is selected.
    func clearSelection() {
        if selectedSegmentID != nil {
            selectedSegmentID = nil
        }
    }

}
