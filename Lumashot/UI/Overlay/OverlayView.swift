import AVFoundation
import Cocoa
import UniformTypeIdentifiers

@MainActor
protocol OverlayViewDelegate: AnyObject {
    func overlayViewDidFinishSelection(_ rect: NSRect)
    func overlayViewSelectionDidChange(_ rect: NSRect)
    func overlayViewDidCancel()
    func overlayViewDidConfirm()
    func overlayViewDidRequestSave()
    func overlayViewDidRequestPin()
    func overlayViewDidRequestOCR()
    func overlayViewDidRequestQuickSave()
    func overlayViewDidRequestFileSave()
    func overlayViewDidRequestUpload()
    func overlayViewDidRequestShare(anchorView: NSView?)
    @available(macOS 14.0, *)
    func overlayViewDidRequestRemoveBackground()
    func overlayViewDidRequestEnterRecordingMode()
    func overlayViewDidRequestStartRecording(rect: NSRect)
    func overlayViewDidRequestStopRecording()
    func overlayViewDidRequestDetach()
    func overlayViewDidRequestScrollCapture(rect: NSRect)
    func overlayViewDidRequestStopScrollCapture()
    func overlayViewDidRequestToggleAutoScroll()
    func overlayViewDidRequestAccessibilityPermission()
    func overlayViewDidRequestInputMonitoringPermission()
    func overlayViewDidBeginSelection()
    func overlayViewRemoteSelectionDidChange(_ rect: NSRect)
    func overlayViewDidChangeWindowSnapState()
    func overlayViewRemoteSelectionDidFinish(_ rect: NSRect)
    func overlayViewDidRequestAddCapture()
}

/// An entry in the undo/redo history.
enum UndoEntry {
    case added(Annotation)  // annotation was added; undo removes it
    case deleted(Annotation, Int)  // annotation was deleted at index; undo re-inserts it
    /// Image transform (crop/flip): stores the previous image and annotation offsets to restore.
    case imageTransform(previousImage: NSImage, annotationOffsets: [(Annotation, CGFloat, CGFloat)])
    /// Property change: stores the annotation and a snapshot taken before the edit.
    case propertyChange(annotation: Annotation, snapshot: Annotation)

    var annotation: Annotation {
        switch self {
        case .added(let a), .deleted(let a, _): return a
        case .propertyChange(let a, _): return a
        case .imageTransform:
            return Annotation(
                tool: .measure, startPoint: .zero, endPoint: .zero, color: .clear, strokeWidth: 0)  // dummy
        }
    }
}

/// Snapshot of the mutable editor state.
struct OverlayEditorState {
    var screenshotImage: NSImage?
    var selectionRect: NSRect
    var annotations: [Annotation]
    var undoStack: [UndoEntry]
    var redoStack: [UndoEntry]
    var currentTool: AnnotationTool
    var currentColor: NSColor
    var currentStrokeWidth: CGFloat
    var currentMarkerSize: CGFloat
    var currentNumberSize: CGFloat
    var numberCounter: Int
    var beautifyEnabled: Bool
    var beautifyStyleIndex: Int
    var effectsPreset: ImageEffectPreset
    var effectsBrightness: Float
    var effectsContrast: Float
    var effectsSaturation: Float
    var effectsSharpness: Float
}

class OverlayView: NSView {

    // MARK: - Properties

    weak var overlayDelegate: OverlayViewDelegate?

    /// When true, hides overlay-only toolbar buttons (record, delay, cancel, move, scroll capture).
    /// Override point for subclasses. EditorView returns true.
    var isEditorMode: Bool { false }
    /// When true, NSScrollView handles zoom/pan/centering. Coordinate transforms become identity.
    var isInsideScrollView: Bool { false }
    /// When in scroll view mode, toolbar strips are added to this view (window content) instead of self.
    weak var chromeParentView: NSView?

    var screenshotImage: NSImage? {
        didSet {
            needsDisplay = true
            // Screenshot just arrived (async capture) — enable snap queries now.
            if screenshotImage != nil && windowSnapCooldown {
                windowSnapCooldown = false
                if state == .idle && windowSnapEnabled && !windowSnapQueryInFlight {
                    queryWindowSnap(at: NSEvent.mouseLocation)
                }
            }
        }
    }

    // State
    enum State {
        case idle
        case selecting
        case selected
    }

    var state: State = .idle

    // Zoom
    var zoomLevel: CGFloat = 1.0
    // The canvas point that stays pinned to zoomAnchorView on screen.
    // Both default to selection center; updated on each scroll/pinch to be the cursor position.
    var zoomAnchorCanvas: NSPoint = .zero
    var zoomAnchorView: NSPoint = .zero
    var zoomFadingOut: Bool = false
    var zoomLabelOpacity: CGFloat = 0.0
    var zoomFadeTimer: Timer?
    var zoomMin: CGFloat { 1.0 }
    let zoomMax: CGFloat = 8.0

    // Selection
    var selectionRect: NSRect = .zero {
        didSet {
            if selectionRect != oldValue { scheduleTranslatePrewarmIfNeeded() }
        }
    }
    /// Selection rect from another overlay (in this view's local coords), drawn during cross-screen drag.
    var remoteSelectionRect: NSRect = .zero

    // MARK: - Speculative translate pre-warm (translate-ahead while selecting)
    var translatePrewarmTimer: Timer?
    var translatePrewarmToken: Int = 0
    var prewarmedTranslateRect: NSRect = .zero
    var prewarmedTranslateAnnotations: [Annotation]?

    // Editor zoom state (used by OverlayView+ZoomResize) — stored properties must
    // live on the class, not in the extension.
    var editorZoomRedrawTimer: Timer?
    var editorZoomTarget: CGFloat = 1.0
    var editorZoomAnimTimer: Timer?
    var editorZoomCursorDoc: NSPoint = .zero

    /// The full (unclipped) remote selection in this view's local coords — used for resize anchor calculation.
    var remoteSelectionFullRect: NSRect = .zero
    var isResizingRemoteSelection: Bool = false
    var remoteResizeHandle: ResizeHandle = .none
    var remoteResizeAnchor: NSPoint = .zero  // the fixed corner during remote resize
    var selectionStart: NSPoint = .zero
    /// Trackpad/mouse QoL: when the user right-clicks in the empty overlay
    /// (state == .idle), we anchor a selection at that point and let the
    /// cursor resize it with no button held. A subsequent left-click
    /// finalizes, ESC cancels. This mirrors the drag flow but removes the
    /// need to keep pressing — big usability win for large selections on
    /// trackpads.
    var isAnchoredSelecting: Bool = false
    var isDraggingSelection: Bool = false
    var isResizingSelection: Bool = false
    var resizeHandle: ResizeHandle = .none
    var dragOffset: NSPoint = .zero
    var lastDragPoint: NSPoint?  // for shift constraint on flagsChanged
    var spaceRepositioning: Bool = false  // Space held during drag to reposition
    var spaceRepositionLast: NSPoint = .zero  // last mouse position when space reposition started

    // Annotations
    var annotations: [Annotation] = [] {
        didSet {
            cachedCompositedImage = nil
            cachedEffectsScreenshot = nil
            // Update move button enabled state when annotations change
            if showToolbars { rebuildToolbarLayout() }
        }
    }
    var undoStack: [UndoEntry] = []
    var redoStack: [UndoEntry] = []
    var currentAnnotation: Annotation?
    /// Whether the user is actively drawing/dragging a new annotation.
    var isActivelyDrawing: Bool { currentAnnotation != nil }

    // MARK: - Tool handlers
    lazy var toolHandlers: [AnnotationTool: AnnotationToolHandler] = {
        let handlers: [AnnotationToolHandler] = [
            PencilToolHandler(),
            MarkerToolHandler(),
            LineToolHandler(),
            ArrowToolHandler(),
            RectangleToolHandler(),
            FilledRectangleToolHandler(),
            EllipseToolHandler(),
            PixelateToolHandler(),
            LoupeToolHandler(),
            MeasureToolHandler(),
            NumberToolHandler(),
            StampToolHandler(),
        ]
        return Dictionary(uniqueKeysWithValues: handlers.map { ($0.tool, $0) })
    }()
    /// Last tool the user explicitly picked — persisted across app launches.
    static var lastUsedTool: AnnotationTool = {
        if let raw = UserDefaults.standard.object(forKey: "lastUsedTool") as? Int,
           let tool = AnnotationTool(rawValue: raw) {
            return tool
        }
        return .arrow
    }()
    var currentTool: AnnotationTool = {
        let remember = UserDefaults.standard.object(forKey: "rememberLastTool") as? Bool ?? true
        return remember ? OverlayView.lastUsedTool : .arrow
    }() {
        didSet {
            // Persist drawing tool choices; skip transient/mode tools
            if currentTool != .select && currentTool != .loupe {
                OverlayView.lastUsedTool = currentTool
                UserDefaults.standard.set(currentTool.rawValue, forKey: "lastUsedTool")
            }
        }
    }

    func useMoveSelectionToolForNewOverlaySelection() {
        guard !isEditorMode else { return }
        currentTool = .select
    }
    var currentColor: NSColor = {
        if let data = UserDefaults.standard.data(forKey: "lastUsedColor"),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            return color
        }
        return .systemRed
    }() {
        didSet {
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: currentColor, requiringSecureCoding: true) {
                UserDefaults.standard.set(data, forKey: "lastUsedColor")
            }
            updateToolbarColorSwatch()
        }
    }
    /// currentColor with opacity applied — used for all tools except marker, loupe, measure, pixelate, blur
    var annotationColor: NSColor { currentColor.withAlphaComponent(currentColorOpacity) }
    var currentStrokeWidth: CGFloat = {
        let saved = UserDefaults.standard.object(forKey: "currentStrokeWidth") as? Double
        return saved != nil ? CGFloat(saved!) : 3.0
    }()
    var currentNumberSize: CGFloat = {
        let saved = UserDefaults.standard.object(forKey: "numberStrokeWidth") as? Double
        return saved != nil ? CGFloat(saved!) : 3.0
    }()
    var currentMarkerSize: CGFloat = {
        let saved = UserDefaults.standard.object(forKey: "markerStrokeWidth") as? Double
        return saved != nil ? CGFloat(saved!) : 3.0
    }()
    var numberCounter: Int = 0
    var numberStartAt: Int = {
        UserDefaults.standard.object(forKey: "numberStartAt") as? Int ?? 1
    }()
    var currentNumberFormat: NumberFormat = {
        NumberFormat(rawValue: UserDefaults.standard.integer(forKey: "numberFormat")) ?? .decimal
    }()

    // Select/move mode
    /// All currently selected annotations (supports multi-select via Shift+Click).
    var selectedAnnotations: [Annotation] = [] {
        didSet {
            let oldSingle = oldValue.first
            let newSingle = selectedAnnotations.first
            if newSingle !== oldSingle || oldValue.count != selectedAnnotations.count {
                toolOptionsRowView?.clearEditingAnnotation()

                if selectedAnnotations.count == 1, let ann = newSingle {
                    // Load text annotation properties into textEditor so toolbar shows correct state
                    if ann.tool == .text {
                        textEditor.restoreState(from: ann)
                    }
                    toolOptionsRowView?.rebuild(forAnnotation: ann)
                    repositionToolbars()
                } else if selectedAnnotations.isEmpty {
                    if let tool = currentTool as AnnotationTool? {
                        toolOptionsRowView?.rebuild(for: tool)
                        repositionToolbars()
                    }
                } else {
                    // Multi-select: revert to tool options (no per-annotation editing)
                    if let tool = currentTool as AnnotationTool? {
                        toolOptionsRowView?.rebuild(for: tool)
                        repositionToolbars()
                    }
                }
            }
        }
    }

    /// Convenience: the single selected annotation (nil if 0 or 2+ selected).
    var selectedAnnotation: Annotation? {
        get { selectedAnnotations.count == 1 ? selectedAnnotations.first : nil }
        set {
            if let ann = newValue {
                selectedAnnotations = [ann]
            } else {
                selectedAnnotations = []
            }
        }
    }

    /// Whether an annotation is in the current selection.
    func isSelected(_ annotation: Annotation) -> Bool {
        selectedAnnotations.contains(where: { $0 === annotation })
    }
    var isDraggingAnnotation: Bool = false
    var didMoveAnnotation: Bool = false
    var annotationDragStart: NSPoint = .zero
    /// When ctrl+clicking an already-selected annotation, defer the deselect
    /// to mouseUp so the user can still drag the full multi-selection.
    weak var shiftClickPendingDeselect: Annotation?
    /// Lasso selection: Ctrl+drag on empty space draws a marquee rectangle.
    var isLassoSelecting: Bool = false
    var lassoStart: NSPoint = .zero
    var lassoRect: NSRect = .zero
    // Long-press-to-select for pencil/marker tools
    var longPressTimer: Timer?
    var longPressPoint: NSPoint = .zero
    var longPressTriggered: Bool = false
    /// Annotation under the cursor when using a non-select drawing tool — enables on-the-fly move without switching tools.
    var hoveredAnnotation: Annotation?
    /// Delays clearing hoveredAnnotation so the cursor can travel to handles/buttons that sit outside the hit area.
    var hoveredAnnotationClearTimer: Timer?

    // Text editing — state managed by TextEditingController
    let textEditor = TextEditingController()
    var textEditView: NSTextView? { textEditor.textView }

    // Text box resize state (stays here — tied to mouse drag handling)
    var isResizingTextBox: Bool = false
    var textBoxResizeHandle: ResizeHandle = .none
    var textBoxResizeStart: NSPoint = .zero
    var textBoxOrigFrame: NSRect = .zero
    // (Text box move handle removed — standard annotation chrome handles movement)

    // Toolbars (drawn inline)
    var bottomButtons: [ToolbarButton] = []
    var rightButtons: [ToolbarButton] = []
    var bottomBarRect: NSRect = .zero
    var rightBarRect: NSRect = .zero
    var showToolbars: Bool = false {
        didSet {
            if showToolbars && !oldValue {
                rebuildToolbarLayout()
            } else if !showToolbars && oldValue {
                bottomStripView?.isHidden = true
                rightStripView?.isHidden = true
                toolOptionsRowView?.isHidden = true
            }
        }
    }
    var bottomStripView: ToolbarStripView?
    var rightStripView: ToolbarStripView?
    var toolOptionsRowView: ToolOptionsRowView?

    // Size label
    var sizeLabelRect: NSRect = .zero
    var sizeInputField: NSTextField?

    // Zoom label
    var zoomLabelRect: NSRect = .zero
    var zoomInputField: NSTextField?

    // Beautify
    var beautifyEnabled: Bool = UserDefaults.standard.bool(forKey: "beautifyEnabled")
    var beautifyStyleIndex: Int = UserDefaults.standard.integer(
        forKey: "beautifyStyleIndex")
    var beautifyMode: BeautifyMode =
        BeautifyMode(rawValue: UserDefaults.standard.integer(forKey: "beautifyMode")) ?? .window
    var beautifyPadding: CGFloat = {
        let v = UserDefaults.standard.object(forKey: "beautifyPadding") as? Double
        return v != nil ? CGFloat(v!) : 48
    }()
    var beautifyCornerRadius: CGFloat = {
        let v = UserDefaults.standard.object(forKey: "beautifyCornerRadius") as? Double
        return v != nil ? CGFloat(v!) : 10
    }()
    var beautifyShadowRadius: CGFloat = {
        let v = UserDefaults.standard.object(forKey: "beautifyShadowRadius") as? Double
        return v != nil ? CGFloat(v!) : 20
    }()
    var beautifyBgRadius: CGFloat = {
        let v = UserDefaults.standard.object(forKey: "beautifyBgRadius") as? Double
        return v != nil ? CGFloat(v!) : 8
    }()

    var customBeautifyBackground: NSImage? {
        didSet { cachedBeautifyBgCGImage = nil }
    }
    var beautifyBackgroundBlur: CGFloat = UserDefaults.standard.object(forKey: "beautifyBgBlur") as? CGFloat ?? 0 {
        didSet {
            cachedBeautifyBgCGImage = nil
            prepareBeautifyBackgroundCache()
        }
    }
    var cachedBeautifyBgCGImage: CGImage?

    func prepareBeautifyBackgroundCache() {
        guard let bg = customBeautifyBackground else { return }
        var cfg = BeautifyConfig(customBackgroundImage: bg, backgroundBlur: beautifyBackgroundBlur)
        cfg.prepareBackgroundCache()
        cachedBeautifyBgCGImage = cfg.cachedBackgroundCGImage
    }

    var beautifyConfig: BeautifyConfig {
        // Lazy-load custom background from UserDefaults if needed
        if beautifyStyleIndex == -1 && customBeautifyBackground == nil {
            if let data = UserDefaults.standard.data(forKey: "beautifyCustomBgImageData"),
               let img = NSImage(data: data) {
                customBeautifyBackground = img
                prepareBeautifyBackgroundCache()
            }
        }
        return BeautifyConfig(
            mode: beautifyMode,
            styleIndex: beautifyStyleIndex,
            padding: beautifyPadding,
            cornerRadius: beautifyCornerRadius,
            shadowRadius: beautifyShadowRadius,
            bgRadius: 0,
            isWindowSnap: selectionIsWindowSnap,
            customBackgroundImage: beautifyStyleIndex == -1 ? customBeautifyBackground : nil,
            backgroundBlur: beautifyBackgroundBlur,
            cachedBackgroundCGImage: beautifyStyleIndex == -1 ? cachedBeautifyBgCGImage : nil
        )
    }

    var showBeautifyInOptionsRow: Bool = false

    // Image effects
    var effectsPreset: ImageEffectPreset =
        ImageEffectPreset(rawValue: UserDefaults.standard.integer(forKey: "effectsPreset")) ?? .none
    var effectsBrightness: Float = {
        let v = UserDefaults.standard.object(forKey: "effectsBrightness") as? Double
        return v != nil ? Float(v!) : 0
    }()
    var effectsContrast: Float = {
        let v = UserDefaults.standard.object(forKey: "effectsContrast") as? Double
        return v != nil ? Float(v!) : 1.0
    }()
    var effectsSaturation: Float = {
        let v = UserDefaults.standard.object(forKey: "effectsSaturation") as? Double
        return v != nil ? Float(v!) : 1.0
    }()
    var effectsSharpness: Float = {
        let v = UserDefaults.standard.object(forKey: "effectsSharpness") as? Double
        return v != nil ? Float(v!) : 0
    }()

    var effectsConfig: ImageEffectsConfig {
        ImageEffectsConfig(
            preset: effectsPreset,
            brightness: effectsBrightness,
            contrast: effectsContrast,
            saturation: effectsSaturation,
            sharpness: effectsSharpness
        )
    }
    var effectsActive: Bool { !effectsConfig.isIdentity }

    /// Cached effects-processed screenshot for live preview. Invalidated when effects or annotations change.
    var cachedEffectsScreenshot: NSImage?

    // Color picker target
    enum ColorPickerTarget { case drawColor, textBg, textOutline, textGlyphStroke, annotationOutline }
    var colorPickerTarget: ColorPickerTarget = .drawColor

    // Beautify toolbar animation
    var beautifyToolbarAnimProgress: CGFloat = 1.0  // 0..1, 1 = fully settled
    var beautifyToolbarAnimTimer: Timer?
    var beautifyToolbarAnimTarget: Bool = false  // target beautify state

    // Tool options row (second row below bottom bar)
    var currentMeasureInPoints: Bool = UserDefaults.standard.bool(forKey: "measureInPoints")
    var currentLineStyle: LineStyle =
        LineStyle(rawValue: UserDefaults.standard.integer(forKey: "currentLineStyle")) ?? .solid
    var currentArrowStyle: ArrowStyle =
        ArrowStyle(rawValue: UserDefaults.standard.integer(forKey: "currentArrowStyle")) ?? .single
    var arrowReversed: Bool =
        UserDefaults.standard.bool(forKey: "arrowReversed")
    var currentRectFillStyle: RectFillStyle =
        RectFillStyle(rawValue: UserDefaults.standard.integer(forKey: "currentRectFillStyle"))
        ?? .stroke
    var currentStampImage: NSImage?  // selected emoji/image for stamp tool
    var currentStampEmoji: String?  // emoji string for highlight tracking
    var stampPreviewPoint: NSPoint?  // mouse position for stamp cursor preview
    var currentRectCornerRadius: CGFloat = {
        let v = UserDefaults.standard.object(forKey: "currentRectCornerRadius") as? Double
        return v != nil ? CGFloat(v!) : 0
    }()

    // Stroke width picker popover

    var pencilSmoothMode: Int = {
        // Migrate old bool to new mode: true → 1 (Smooth), false → 0 (None)
        if let old = UserDefaults.standard.object(forKey: "pencilSmoothEnabled") as? Bool {
            UserDefaults.standard.removeObject(forKey: "pencilSmoothEnabled")
            let mode = old ? 1 : 0
            UserDefaults.standard.set(mode, forKey: "pencilSmoothMode")
            return mode
        }
        return UserDefaults.standard.object(forKey: "pencilSmoothMode") as? Int ?? 1
    }()
    var pencilPressureEnabled: Bool =
        UserDefaults.standard.object(forKey: "pencilPressureEnabled") as? Bool ?? false
    var currentPressure: CGFloat = 1.0
    var smartMarkerEnabled: Bool =
        UserDefaults.standard.object(forKey: "smartMarkerEnabled") as? Bool ?? false


    var currentLoupeSize: CGFloat = {
        let saved = UserDefaults.standard.object(forKey: "loupeSize") as? Double
        return saved != nil ? CGFloat(saved!) : 120.0
    }()
    var loupeCursorPoint: NSPoint = .zero
    var drawingCursorPoint: NSPoint = .zero
    var smartMarkerLineHeight: CGFloat?  // detected text line height at cursor (smart marker)
    var colorSamplerPoint: NSPoint = .zero  // canvas space, for color picker tool
    var colorSamplerBitmap: NSBitmapImageRep?  // cached bitmap for fast pixel sampling
    // Auto-measure preview (live while holding 1 or 2 key)
    var autoMeasurePreview: Annotation?  // temporary, drawn but not in annotations[]
    var autoMeasureVertical: Bool = true  // true = "1" key, false = "2" key
    var autoMeasureKeyHeld: Bool = false  // true while 1 or 2 is held down
    var autoMeasureBitmapCtx: CGContext?  // cached pixel data for fast scanning
    var autoMeasureBitmapW: Int = 0
    var autoMeasureBitmapH: Int = 0
    // Snap/alignment guides
    var snapGuideX: CGFloat? = nil  // vertical guide line X
    var snapGuideY: CGFloat? = nil  // horizontal guide line Y
    let snapThreshold: CGFloat = 5
    var snapGuidesEnabled: Bool {
        UserDefaults.standard.object(forKey: "snapGuidesEnabled") as? Bool ?? true
    }

    var cachedCompositedImage: NSImage? = nil {  // invalidated when annotations change
        didSet { if !isDraggingAnnotation && !isResizingAnnotation && !isRotatingAnnotation { cachedAnnotationLayer = nil } }
    }
    /// Cached transparent image of committed annotations only (no screenshot).
    /// Drawn with applyCanvasTransform so zoom works correctly. Invalidated alongside cachedCompositedImage.
    var cachedAnnotationLayer: NSImage? = nil
    /// During drag/resize, this holds a cache of all annotations EXCEPT the ones being manipulated.
    var cachedAnnotationLayerExcludingSelected: NSImage? = nil
    var cachedOpaqueRect: NSRect?  // cached opaque content bounds of screenshotImage

    var isTranslating: Bool = false
    var translateEnabled: Bool = false

    // Crop tool state
    var isCropDragging: Bool = false
    var cropDragStart: NSPoint = .zero
    var cropDragRect: NSRect = .zero

    // Annotation selection/resize controls
    var isResizingAnnotation: Bool = false
    var annotationResizeHandle: ResizeHandle = .none
    var annotationResizeAnchorIndex: Int = -1  // index into anchorPoints for multi-anchor drag
    var isRotatingAnnotation: Bool = false
    var rotationStartAngle: CGFloat = 0
    var rotationOriginal: CGFloat = 0
    var annotationRotateHandleRect: NSRect = .zero
    var annotationResizeOrigStart: NSPoint = .zero
    var annotationResizeOrigEnd: NSPoint = .zero
    var annotationResizeOrigTextOrigin: NSPoint = .zero
    var annotationResizeOrigControlPoint: NSPoint = .zero
    var annotationResizeMouseStart: NSPoint = .zero
    var annotationDeleteButtonRect: NSRect = .zero
    var annotationEditButtonRect: NSRect = .zero
    var annotationResizeHandleRects: [(ResizeHandle, NSRect)] = []
    var multiSelectDeleteButtonRect: NSRect = .zero  // consolidated delete for multi-selection

    // Overlay error message
    var overlayErrorMessage: String? = nil

    // Instant tooltip for hovered toolbar button
    var hoveredTooltip: String?
    var hoveredTooltipButtonView: ToolbarButtonView?
    var editorTooltipView: NSView?
    var overlayErrorTimer: Timer? = nil

    // Barcode / QR detection
    let barcodeDetector = BarcodeDetector()

    // Recording state
    var isRecording: Bool = false {  // true when recording toolbar is shown (pre-recording setup)
        didSet {
            if isRecording {
                // Clear drawing previews so they don't linger from screenshot mode
                commitTextFieldIfNeeded()
                stampPreviewPoint = nil
                loupeCursorPoint = .zero
                drawingCursorPoint = .zero
                autoMeasurePreview = nil
                hoveredAnnotation = nil
                selectedAnnotation = nil
                needsDisplay = true
                // Pre-check Input Monitoring permission if keystroke overlay is enabled
                if UserDefaults.standard.bool(forKey: "recordKeystroke") && !KeystrokeOverlay.hasInputMonitoringPermission {
                    UserDefaults.standard.set(false, forKey: "recordKeystroke")
                    rebuildToolbarLayout()
                    overlayDelegate?.overlayViewDidRequestInputMonitoringPermission()
                }

                // Pre-check mic + camera permissions sequentially so dialogs don't overlap
                preCheckRecordingPermissions()
            } else {
                stopMicLevelMonitor()
                dismissWebcamSetupPreview()
            }
        }
    }
    var autoEnterRecordingMode: Bool = false  // set by "Record Screen" menu — enters recording mode after selection
    var autoOCRMode: Bool = false  // set by "Capture OCR" menu — triggers OCR immediately after selection
    var autoQuickSaveMode: Bool = false  // set by "Quick Capture" menu — quick-saves immediately after selection
    var autoScrollCaptureMode: Bool = false  // set by "Scroll Capture" menu — triggers scroll capture immediately after selection
    var autoConfirmMode: Bool = false  // set by "Add Capture" — auto-confirms selection (no toolbars, no save)
    var isHDRCaptureMode: Bool = UserDefaults.standard.object(forKey: "captureHDREnabled") as? Bool ?? false {
        didSet {
            if bottomStripView != nil {
                rebuildToolbarLayout()
            }
            needsDisplay = true
        }
    }

    // Recording session overrides (popover settings — nil means use UserDefaults default)
    var sessionRecordingFPS: Int?
    var sessionRecordingOnStop: String?
    var sessionRecordingDelay: Int?
    var sessionHideRecordingHUD: Bool?

    // Scroll capture state
    var isScrollCapturing: Bool = false
    var scrollCaptureStripCount: Int = 0
    var scrollCapturePixelSize: CGSize = .zero
    var scrollCaptureMaxHeight: Int = 0
    var scrollCaptureAutoScrolling: Bool = false
    var scrollCaptureHUDPanel: ScrollCaptureHUDPanel?
    var scrollCaptureMouseTap: CFMachPort?
    var scrollCaptureMouseTapSource: CFRunLoopSource?
    var scrollCaptureKeyMonitor: Any?
    var scrollCaptureLocalKeyMonitor: Any?
    /// Activate the app visible under the selection rect so the user doesn't need a warmup click.
    func activateAppUnderSelection() {
        guard selectionRect.width > 0, let win = window else { return }
        // Convert selection center to global screen coords
        let centerLocal = NSPoint(x: selectionRect.midX, y: selectionRect.midY)
        let centerScreen = win.convertToScreen(NSRect(origin: centerLocal, size: .zero)).origin

        guard
            let windowList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
            ) as? [[String: Any]]
        else { return }

        let overlayWindowNumber = win.windowNumber
        let screenH = NSScreen.screens.first?.frame.height ?? 0

        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                let winNum = info[kCGWindowNumber as String] as? Int,
                let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                winNum != overlayWindowNumber
            else { continue }

            let cgX = boundsDict["X"] ?? 0
            let cgY = boundsDict["Y"] ?? 0
            let cgW = boundsDict["Width"] ?? 0
            let cgH = boundsDict["Height"] ?? 0
            let appKitRect = NSRect(x: cgX, y: screenH - cgY - cgH, width: cgW, height: cgH)

            if appKitRect.contains(centerScreen) {
                NSRunningApplication(processIdentifier: pid)?.activate(options: [])
                return
            }
        }
    }

    func startScrollCaptureMode() {
        isScrollCapturing = true
        scrollCaptureStripCount = 0
        scrollCapturePixelSize = .zero
        scrollCaptureAutoScrolling = false

        activateAppUnderSelection()
        window?.ignoresMouseEvents = true

        // Suppress mouse-moved events via CGEvent tap so hover effects in the
        // target app don't break stitch detection. Requires Accessibility permission
        // (checked before entering scroll capture mode).
        if AXIsProcessTrusted() {
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(1 << CGEventType.mouseMoved.rawValue),
                callback: { _, _, _, _ in nil },
                userInfo: nil)
            if let tap = tap {
                let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                scrollCaptureMouseTap = tap
                scrollCaptureMouseTapSource = source
            }
        }

        // Escape key monitor — global catches when another app has focus; local when Lumashot has focus.
        let handleScrollKey: (NSEvent) -> Void = { [weak self] event in
            guard let self = self, self.isScrollCapturing else { return }
            if event.keyCode == 53 {  // Escape
                self.overlayDelegate?.overlayViewDidRequestStopScrollCapture()
            }
        }
        scrollCaptureKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            handleScrollKey(event)
        }
        scrollCaptureLocalKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleScrollKey(event)
            if event.keyCode == 53 { return nil }  // consume
            return event
        }

        // Show real NSPanel-based HUD (receives clicks independently of overlay window)
        let panel = ScrollCaptureHUDPanel()
        panel.hudView.onStop = { [weak self] in
            self?.overlayDelegate?.overlayViewDidRequestStopScrollCapture()
        }
        panel.hudView.onToggleAutoScroll = { [weak self] in
            self?.overlayDelegate?.overlayViewDidRequestToggleAutoScroll()
        }
        panel.hudView.update(
            stripCount: 0, pixelSize: .zero,
            backingScale: window?.backingScaleFactor ?? 2,
            maxScrollHeight: scrollCaptureMaxHeight,
            autoScrolling: scrollCaptureAutoScrolling)
        if let win = window {
            panel.position(relativeTo: selectionRect, in: win)
        }
        panel.orderFront(nil)
        scrollCaptureHUDPanel = panel

        needsDisplay = true
    }

    func stopScrollCaptureMode() {
        isScrollCapturing = false
        scrollCaptureStripCount = 0
        scrollCapturePixelSize = .zero
        scrollCaptureAutoScrolling = false

        if let m = scrollCaptureKeyMonitor { NSEvent.removeMonitor(m); scrollCaptureKeyMonitor = nil }
        if let m = scrollCaptureLocalKeyMonitor { NSEvent.removeMonitor(m); scrollCaptureLocalKeyMonitor = nil }
        if let tap = scrollCaptureMouseTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = scrollCaptureMouseTapSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            scrollCaptureMouseTap = nil
            scrollCaptureMouseTapSource = nil
        }
        scrollCaptureHUDPanel?.close()
        scrollCaptureHUDPanel = nil
        window?.ignoresMouseEvents = false

        needsDisplay = true
    }

    /// Update the scroll capture HUD with new strip count and pixel size.
    func updateScrollCaptureHUD() {
        scrollCaptureHUDPanel?.hudView.update(
            stripCount: scrollCaptureStripCount,
            pixelSize: scrollCapturePixelSize,
            backingScale: window?.backingScaleFactor ?? 2,
            maxScrollHeight: scrollCaptureMaxHeight,
            autoScrolling: scrollCaptureAutoScrolling)
        if let win = window {
            scrollCaptureHUDPanel?.position(relativeTo: selectionRect, in: win)
        }
    }

    // Window snapping
    var windowSnapEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "windowSnapEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "windowSnapEnabled") }
    }
    var hoveredWindowRect: NSRect? = nil
    var hoveredWindowID: CGWindowID? = nil
    var windowSnapCooldown: Bool = true  // true until overlay has rendered
    /// True when the current selection was made via window snap (click without drag).
    /// Cleared when the user manually resizes the selection.
    var selectionIsWindowSnap: Bool = false
    var snappedWindowID: CGWindowID? = nil
    /// Independently captured window image (with transparent corners) for beautify snap mode.
    var snappedWindowImage: NSImage? = nil
    var windowSnapQueryInFlight: Bool = false

    /// Perform a window snap query at the given screen point (AppKit screen coordinates).
    func queryWindowSnap(at screenPoint: NSPoint) {
        guard !windowSnapQueryInFlight,
            state == .idle && windowSnapEnabled,
            !(remoteSelectionRect.width >= 1 && remoteSelectionRect.height >= 1),
            let viewWindow = window
        else { return }
        let overlayWindowNumber = viewWindow.windowNumber
        let windowOrigin = viewWindow.frame.origin
        let viewBounds = bounds
        let screenH = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
        windowSnapQueryInFlight = true
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let result = Self.windowRectOnBackground(
                screenPoint: screenPoint,
                overlayWindowNumber: overlayWindowNumber,
                windowOrigin: windowOrigin,
                viewBounds: viewBounds,
                screenH: screenH
            )
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.windowSnapQueryInFlight = false
                let newRect = result?.rect
                if newRect != self.hoveredWindowRect {
                    self.hoveredWindowRect = newRect
                    self.hoveredWindowID = result?.windowID
                    self.needsDisplay = true
                }
            }
        }
    }

    // Mic level monitor (volume meter shown when mic is enabled before recording)
    var micLevelEngine: AVAudioEngine?
    var micLevelTimer: Timer?

    var customColors: [NSColor?] = Array(repeating: nil, count: 7)
    var selectedColorSlot: Int = 0  // which custom slot is selected for saving colors
    static var lastUsedOpacity: CGFloat = {
        let saved = UserDefaults.standard.object(forKey: "lastUsedColorOpacity") as? Double
        return saved != nil ? CGFloat(saved!) : 1.0
    }()
    var currentColorOpacity: CGFloat = OverlayView.lastUsedOpacity

    // Radial color wheel (right-click in drawing mode)
    let colorWheel = ColorWheelRenderer()

    // Webcam setup preview (shown during recording setup when webcam is enabled)
    var webcamSetupPreview: WebcamOverlay?

    // Handle
    let handleSize: CGFloat = 10

    enum ResizeHandle {
        case none
        case topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, left, right
        case move
    }

    // MARK: - Setup

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        window?.acceptsMouseMovedEvents = true
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)

        // Don't run the initial snap query here — it fires before the screenshot
        // arrives (async capture). The snap query is triggered when screenshotImage
        // is set (via didSet → needsDisplay → mouseMoved), or we kick it off
        // explicitly in the screenshotImage setter below.
        // Skip cooldown in editor mode — screenshotImage is set before the view
        // moves to the window, so the didSet won't clear it. Window snap is
        // irrelevant in editor anyway.
        if !isEditorMode {
            windowSnapCooldown = true
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleToolbarColorsChanged),
            name: .toolbarColorsDidChange, object: nil)
    }

    @objc func handleToolbarColorsChanged() {
        // Rebuild toolbars and options row with new colors
        toolOptionsRowView?.layer?.backgroundColor = ToolbarLayout.bgColor.cgColor
        toolOptionsRowView?.appearance = ToolbarLayout.appearance
        rebuildToolbarLayout()
        if let tool = toolOptionsRowView?.currentTool {
            toolOptionsRowView?.rebuild(for: tool)
        }
        needsDisplay = true
    }

    /// Invalidate only the rect around a cursor preview (old + new position) instead of the whole view.
    func invalidateCursorPreview(oldCanvas: NSPoint, newCanvas: NSPoint, radius: CGFloat) {
        let margin: CGFloat = 4
        // Scale canvas-space radius to view-space pixels (zoom factor)
        let r = (radius + margin) * zoomLevel
        if oldCanvas != .zero {
            let oldView = canvasToView(oldCanvas)
            setNeedsDisplay(NSRect(x: oldView.x - r, y: oldView.y - r, width: r * 2, height: r * 2))
        }
        let newView = canvasToView(newCanvas)
        setNeedsDisplay(NSRect(x: newView.x - r, y: newView.y - r, width: r * 2, height: r * 2))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Anchored selection (right-click in idle → track cursor without
        // holding a button). Shares all modifier behaviour with drag-based
        // selection via `updateAnchoredSelection` so Shift-constrain and
        // the snap fallback in mouseUp still apply when the user commits.
        if isAnchoredSelecting {
            updateAnchoredSelection(to: point, event: event)
            updateCursorForPoint(point)
            return
        }

        // Sticky color wheel: track hover with mouse movement
        if colorWheel.isVisible && colorWheel.isSticky {
            colorWheel.updateHover(at: point)
            needsDisplay = true
            return
        }

        // Stamp cursor preview — track in view coords (same as annotations)
        if currentTool == .stamp && currentStampImage != nil && state == .selected && !isRecording
            && !showBeautifyInOptionsRow
        {
            let canvasStampPt = viewToCanvas(point)
            if stampPreviewPoint == nil
                || hypot(
                    canvasStampPt.x - (stampPreviewPoint?.x ?? 0),
                    canvasStampPt.y - (stampPreviewPoint?.y ?? 0)) > 0.5
            {
                let oldPt = stampPreviewPoint ?? .zero
                stampPreviewPoint = canvasStampPt
                invalidateCursorPreview(oldCanvas: oldPt, newCanvas: canvasStampPt, radius: 40)
            }
        } else if stampPreviewPoint != nil {
            let oldPt = stampPreviewPoint!
            stampPreviewPoint = nil
            invalidateCursorPreview(oldCanvas: oldPt, newCanvas: oldPt, radius: 40)
        }

        // Update cursor on every mouse move
        updateCursorForPoint(point)

        // Auto-measure: update preview as cursor moves while key is held
        if autoMeasureKeyHeld {
            updateAutoMeasurePreview()
        }

        // Window snap: highlight hovered window in idle state.
        // CGWindowListCopyWindowInfo is expensive — run it on a background thread,
        // skipping new queries while one is already in flight.
        // Delay window snap queries briefly after overlay appears so the overlay
        // renders without competing with CGWindowListCopyWindowInfo for the window server
        if windowSnapCooldown { return }
        if state == .idle && windowSnapEnabled && !windowSnapQueryInFlight
            && !(remoteSelectionRect.width >= 1 && remoteSelectionRect.height >= 1)
        {
            guard
                let screenPoint = window.map({
                    NSPoint(x: $0.frame.origin.x + point.x, y: $0.frame.origin.y + point.y)
                })
            else { return }
            queryWindowSnap(at: screenPoint)
        }

        // Track cursor for loupe live preview (use canvas space for zoom correctness)
        if state == .selected && currentTool == .loupe && !isRecording && !showBeautifyInOptionsRow {
            let newPoint = viewToCanvas(convert(event.locationInWindow, from: nil))
            if newPoint != loupeCursorPoint {
                let oldPt = loupeCursorPoint
                loupeCursorPoint = newPoint
                let r = currentLoupeSize / 2 + 4
                invalidateCursorPreview(oldCanvas: oldPt, newCanvas: newPoint, radius: r)
            }
        }

        // Track cursor for pencil/marker dot preview (canvas space so it scales with zoom)
        let showDrawingCursor = state == .selected && !isRecording
            && (currentTool == .pencil || currentTool == .marker)
        if showDrawingCursor {
            let canvasPoint = viewToCanvas(point)
            if canvasPoint != drawingCursorPoint {
                let oldPt = drawingCursorPoint
                let oldR = drawingCursorRadius
                drawingCursorPoint = canvasPoint
                // Smart marker: query line height at cursor and update preview size
                if currentTool == .marker && smartMarkerEnabled {
                    if let handler = toolHandlers[.marker] as? MarkerToolHandler {
                        handler.ensureOCRCache(canvas: self)
                        smartMarkerLineHeight = handler.textLineHeight(at: canvasPoint, canvas: self)
                    }
                }
                // Invalidate both old and new positions with the larger radius
                let newR = drawingCursorRadius
                let r = max(oldR, newR) + 4
                invalidateCursorPreview(oldCanvas: oldPt, newCanvas: canvasPoint, radius: r)
            }
        } else if drawingCursorPoint != .zero {
            let oldPt = drawingCursorPoint
            let r = drawingCursorRadius + 4
            drawingCursorPoint = .zero
            smartMarkerLineHeight = nil
            invalidateCursorPreview(oldCanvas: oldPt, newCanvas: oldPt, radius: r)
        }

        // Track cursor for color sampler tool (canvas space)
        if state == .selected && currentTool == .colorSampler && !isRecording {
            let canvasPoint = viewToCanvas(point)
            if canvasPoint != colorSamplerPoint {
                let oldPt = colorSamplerPoint
                colorSamplerPoint = canvasPoint
                invalidateCursorPreview(oldCanvas: oldPt, newCanvas: canvasPoint, radius: 200)
            }
        } else if colorSamplerPoint != .zero {
            let oldPt = colorSamplerPoint
            colorSamplerPoint = .zero
            colorSamplerBitmap = nil
            invalidateCursorPreview(oldCanvas: oldPt, newCanvas: oldPt, radius: 200)
        }

        // Toolbar hover handled by ToolbarButtonView (real NSView subviews)
    }

    // Custom cursors
    /// Transparent 1x1 cursor used to hide the system cursor while the drawing dot preview is shown.
    static let invisibleCursor: NSCursor = {
        let img = NSImage(size: NSSize(width: 1, height: 1))
        return NSCursor(image: img, hotSpot: .zero)
    }()

    // Diagonal resize cursors (macOS doesn't provide these publicly)
    static let nwseCursor: NSCursor = {
        // Top-left <-> Bottom-right (backslash direction)
        if let cursor = NSCursor.perform(
            NSSelectorFromString("_windowResizeNorthWestSouthEastCursor"))?.takeUnretainedValue()
            as? NSCursor
        {
            return cursor
        }
        return .crosshair
    }()

    static let neswCursor: NSCursor = {
        // Top-right <-> Bottom-left (slash direction)
        if let cursor = NSCursor.perform(
            NSSelectorFromString("_windowResizeNorthEastSouthWestCursor"))?.takeUnretainedValue()
            as? NSCursor
        {
            return cursor
        }
        return .crosshair
    }()

    override func cursorUpdate(with event: NSEvent) {
        // Intentionally empty — cursor management is handled imperatively in mouseMoved
        // via updateCursorForPoint(). Overriding prevents AppKit's default cursorUpdate
        // from resetting our custom cursors.
    }

    override func resetCursorRects() {
        // Handled imperatively in mouseMoved
    }

    /// Imperative cursor management. Called from mouseMoved and a 30fps timer.
    /// Simplified: arrow for chrome, resize cursors for handles, tool cursor for canvas.
    func updateCursorForPoint(_ point: NSPoint) {
        // Arrow cursor when mouse is over an open popover
        if PopoverHelper.isMouseInsidePopover {
            NSCursor.arrow.set()
            return
        }

        // Non-interactive states — simple cursors
        if textEditView != nil {
            NSCursor.arrow.set()
            return
        }
        if state == .idle || state == .selecting {
            // Recording mode: arrow cursor (no selection interaction)
            if isRecording {
                NSCursor.arrow.set()
                return
            }
            // Show resize cursor for remote selection handles
            if state == .idle && remoteSelectionRect.width >= 1 && remoteSelectionRect.height >= 1 {
                let remoteHandle = hitTestRemoteHandle(at: point)
                if remoteHandle != .none {
                    cursorForHandle(remoteHandle).set()
                    return
                }
            }
            NSCursor.crosshair.set()
            return
        }
        guard state == .selected else { return }

        // Chrome areas — arrow
        if isPointOnChrome(point) {
            NSCursor.arrow.set()
            return
        }

        // Selection resize handles (overlay only, not during scroll capture)
        if !isEditorMode && !isScrollCapturing, let handleCursor = resizeHandleCursor(at: point) {
            handleCursor.set()
            return
        }

        if currentTool == .select && !isEditorMode && pointIsInSelection(point) {
            let canvasPoint = viewToCanvas(point)
            let hitsAnnotation = annotations.reversed().contains {
                $0.isMovable && $0.hitTest(point: canvasPoint)
            }
            if !hitsAnnotation {
                NSCursor.openHand.set()
                return
            }
        }

        // Annotation control cursors (resize handles, rotation, delete, body)
        if state == .selected && !isDraggingAnnotation && !isResizingAnnotation && !isRotatingAnnotation {
            // Check selected annotation's handles first
            if selectedAnnotation != nil {
                // Unrotate point for handle hit test
                let handlePoint: NSPoint
                if let ann = selectedAnnotation, ann.rotation != 0 && ann.supportsRotation {
                    let center = NSPoint(x: ann.boundingRect.midX, y: ann.boundingRect.midY)
                    let cos_r = cos(-ann.rotation)
                    let sin_r = sin(-ann.rotation)
                    let dx = point.x - center.x
                    let dy = point.y - center.y
                    handlePoint = NSPoint(x: center.x + dx * cos_r - dy * sin_r,
                                          y: center.y + dx * sin_r + dy * cos_r)
                } else {
                    handlePoint = point
                }

                // Resize handles — directional cursors for shapes, open hand for line/arrow points
                let isShapeTool = [AnnotationTool.rectangle, .filledRectangle, .ellipse, .text,
                                   .number, .pixelate, .stamp].contains(selectedAnnotation?.tool)
                for (_, handleEntry) in annotationResizeHandleRects.enumerated() {
                    let (handle, rect) = handleEntry
                    if rect.insetBy(dx: -4, dy: -4).contains(handlePoint) {
                        if isShapeTool {
                            switch handle {
                            case .topLeft, .bottomRight: Self.nwseCursor.set()
                            case .topRight, .bottomLeft: Self.neswCursor.set()
                            case .top, .bottom: NSCursor.resizeUpDown.set()
                            case .left, .right: NSCursor.resizeLeftRight.set()
                            default: NSCursor.openHand.set()
                            }
                        } else {
                            NSCursor.openHand.set()
                        }
                        return
                    }
                }

                // Rotation handle
                if annotationRotateHandleRect != .zero
                    && annotationRotateHandleRect.insetBy(dx: -6, dy: -6).contains(point) {
                    // Use a rotation-style cursor (crosshair works as a generic grab indicator)
                    NSCursor.openHand.set()
                    return
                }

                // Delete button
                if annotationDeleteButtonRect.contains(point) {
                    NSCursor.arrow.set()
                    return
                }

                // Edit button
                if annotationEditButtonRect != .zero && annotationEditButtonRect.contains(point) {
                    NSCursor.arrow.set()
                    return
                }
            }

            // Multi-select delete button
            if selectedAnnotations.count > 1 && multiSelectDeleteButtonRect.contains(point) {
                NSCursor.arrow.set()
                return
            }

            // Body hover — open hand (skip for pencil/marker where click always draws)
            if currentTool != .pencil && currentTool != .marker {
                let canvasPoint = viewToCanvas(point)
                if let selected = selectedAnnotation, selected.hitTest(point: canvasPoint) {
                    NSCursor.openHand.set()
                    return
                }
                if annotations.reversed().contains(where: { $0.isMovable && $0.hitTest(point: canvasPoint) }) {
                    NSCursor.openHand.set()
                    return
                }
            }
        }

        // Tool cursor — use handler's state-aware cursor if available, else legacy switch
        // Pencil/marker: hide system cursor when dot preview is active (the dot IS the cursor)
        if (currentTool == .pencil || currentTool == .marker)
            && state == .selected && drawingCursorPoint != .zero {
            Self.invisibleCursor.set()
        } else if let handler = toolHandlers[currentTool], let cursor = handler.cursorForCanvas(self) {
            cursor.set()
        } else {
            switch currentTool {
            case .select: NSCursor.arrow.set()
            default: NSCursor.crosshair.set()
            }
        }
    }

    /// Re-evaluate the cursor for the current tool (e.g. after toggling smart marker).
    /// Find the EditorTopBarView in the chrome parent (for updating zoom label from keyboard shortcuts).
    func findTopBar() -> EditorTopBarView? {
        chromeParentView?.subviews.compactMap { $0 as? EditorTopBarView }.first
    }

    func updateCursorForCurrentTool() {
        guard let win = window else { return }
        let point = convert(win.mouseLocationOutsideOfEventStream, from: nil)
        updateCursorForPoint(point)
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Let real NSView subviews (toolbar strips, options row) handle their own events.
        // This prevents our mouseDown override from intercepting slider drags etc.
        // In editor mode the strips live in chromeParentView (a sibling container), not in
        // this view — AppKit's normal hit testing on the container handles them. Routing them
        // here would compare coordinates in different spaces and cause false matches.
        if !isEditorMode {
            let localPoint = convert(point, from: superview)
            if let strip = bottomStripView, !strip.isHidden, strip.containsPointInSuperview(localPoint) {
                return strip.hitTest(convert(point, to: strip.superview))
            }
            if let strip = rightStripView, !strip.isHidden, strip.containsPointInSuperview(localPoint) {
                return strip.hitTest(convert(point, to: strip.superview))
            }
            if let row = toolOptionsRowView, !row.isHidden, row.frame.contains(localPoint) {
                return row.hitTest(convert(point, to: row.superview))
            }
        }
        return super.hitTest(point)
    }

    /// Returns true if the point is over any chrome element (toolbars, options row, popovers, labels).
    func isPointOnChrome(_ point: NSPoint) -> Bool {
        // In editor mode, strips are in chromeParentView — different coordinate space.
        // Don't check them here; they handle their own hit testing as container subviews.
        if showToolbars && !isEditorMode {
            if let strip = bottomStripView, !strip.isHidden, strip.containsPointInSuperview(point) {
                return true
            }
            if let strip = rightStripView, !strip.isHidden, strip.containsPointInSuperview(point) {
                return true
            }
            if let row = toolOptionsRowView, !row.isHidden, row.frame.contains(point) {
                return true
            }
        }
        if updateCursorForChrome(at: point) { return true }
        if sizeLabelRect.contains(point) && sizeInputField == nil { return true }
        if zoomLabelRect.contains(point) && zoomLabelOpacity > 0 && zoomInputField == nil {
            return true
        }
        return false
    }

    /// Returns the appropriate resize cursor if the point is on a selection handle, nil otherwise.
    func resizeHandleCursor(at point: NSPoint) -> NSCursor? {
        let r = selectionRect
        let hs = handleSize + 4
        let edgeT: CGFloat = 6
        // Corner handles
        if NSRect(x: r.minX - hs / 2, y: r.maxY - hs / 2, width: hs, height: hs).contains(point)
            || NSRect(x: r.maxX - hs / 2, y: r.minY - hs / 2, width: hs, height: hs).contains(point)
        {
            return Self.nwseCursor
        }
        if NSRect(x: r.maxX - hs / 2, y: r.maxY - hs / 2, width: hs, height: hs).contains(point)
            || NSRect(x: r.minX - hs / 2, y: r.minY - hs / 2, width: hs, height: hs).contains(point)
        {
            return Self.neswCursor
        }
        // Edge handles
        if NSRect(x: r.minX + hs / 2, y: r.maxY - edgeT / 2, width: r.width - hs, height: edgeT)
            .contains(point)
            || NSRect(x: r.minX + hs / 2, y: r.minY - edgeT / 2, width: r.width - hs, height: edgeT)
                .contains(point)
        {
            return .resizeUpDown
        }
        if NSRect(x: r.minX - edgeT / 2, y: r.minY + hs / 2, width: edgeT, height: r.height - hs)
            .contains(point)
            || NSRect(
                x: r.maxX - edgeT / 2, y: r.minY + hs / 2, width: edgeT, height: r.height - hs
            ).contains(point)
        {
            return .resizeLeftRight
        }
        return nil
    }

    func cursorForHandle(_ handle: ResizeHandle) -> NSCursor {
        switch handle {
        case .topLeft, .bottomRight: return Self.nwseCursor
        case .topRight, .bottomLeft: return Self.neswCursor
        case .top, .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        case .none, .move: return .arrow
        }
    }

    // MARK: - Subclass override points

    /// Override to handle cursor for editor chrome (top bar). Base returns false.
    func updateCursorForChrome(at point: NSPoint) -> Bool { return false }

    /// Check if a view-space point is within the image/selection area.
    /// In overlay mode, compares directly. In editor mode, converts to canvas space first.
    func pointIsInSelection(_ viewPoint: NSPoint) -> Bool {
        if isEditorMode {
            let canvasPoint = viewToCanvas(viewPoint)
            return selectionRect.contains(canvasPoint)
        }
        return selectionRect.contains(viewPoint)
    }

    /// Override point for editor background drawing. Base does nothing (overlay has no editor background).
    func drawEditorBackground(context: NSGraphicsContext) {
    }

    /// Override to clip the selection image in overlay mode. Base returns true when not in editor mode.
    func shouldClipSelectionImage() -> Bool { !isEditorMode }

    /// Override to control selection border drawing. Base returns true when not in editor mode.
    func shouldDrawSelectionBorder() -> Bool { !isEditorMode }

    /// Override to control size label drawing. Base returns true when not recording/scrolling/editing.
    func shouldDrawSizeLabel() -> Bool { !isRecording && !isScrollCapturing && !isEditorMode }

    /// Override to draw top chrome (e.g. editor top bar). Base draws editor top bar when in editor mode.    /// Override to adjust a view-space point for editor canvas offset. Base returns point unchanged.
    func adjustPointForEditor(_ p: NSPoint) -> NSPoint { p }

    /// Override point for editor-specific graphics context transform. Base does nothing.
    func applyEditorTransform(to context: NSGraphicsContext) {}

    /// Override to control whether selection resize handles are active. Base returns true when not in editor mode or scroll capturing.
    func shouldAllowSelectionResize() -> Bool { !isEditorMode && !isScrollCapturing }

    /// Override to control whether a new selection can be started. Base returns true when not recording and not in editor mode.
    func shouldAllowNewSelection() -> Bool { !isRecording && !isEditorMode }

    /// Override to allow panning at 1x zoom. Base returns false.
    func canPanAtOneX() -> Bool { false }

    /// Override point for editor-specific zoom clamping. Base does nothing.
    func clampZoomAnchorForEditor(r: NSRect, z: CGFloat, ac: NSPoint, av: inout NSPoint) {}

    /// Override to change the rect used when drawing the screenshot in `captureSelectedRegion`. Base returns bounds.
    var captureDrawRect: NSRect { isEditorMode ? selectionRect : bounds }

    /// Override to position toolbars for editor mode. Base pins bottom bar centered at bottom, right bar at top-right.    /// Override to control whether detach (open in editor) is allowed. Base returns true when not in editor mode.
    func shouldAllowDetach() -> Bool { !isEditorMode }

    /// Override to handle clicks on chrome areas. Base returns false.
    func handleTopChromeClick(at point: NSPoint) -> Bool { false }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current else { return }

        // In editor mode: dark background, draw image centered at natural size (no stretch).
        // selectionRect stays at (0, 0, imgW, imgH) — annotations always use image-relative coords.
        if isEditorMode {
            drawEditorBackground(context: context)
        } else if isScrollCapturing {
            // During scroll capture: make the entire window transparent so the user sees
            // live screen content everywhere (not just inside the selection).
            context.cgContext.clear(bounds)
        } else if !isRecording {
            if let image = screenshotImage {
                // Screenshot ready — draw it with dark overlay
                image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
                NSColor.black.withAlphaComponent(0.45).setFill()
                NSBezierPath(rect: bounds).fill()
            } else {
                // No screenshot yet — fully transparent. User sees live desktop
                // through the overlay and can start selecting immediately.
                context.cgContext.clear(bounds)
            }
        }

        // Window snap highlight (drawn before helper text so text appears on top)
        drawWindowSnapHighlight()

        // Helper text
        if state == .idle {
            if screenshotImage != nil {
                drawIdleHelperText()
            }
        } else if state == .selecting {
            drawSelectingHelperText()
        }

        // HDR output mode: draw HUD banner at the top
        if isHDRCaptureMode {
            drawHDRCaptureModeHUD(context: context)
        }

        // Draw remote selection region (cross-screen drag from another overlay)
        if remoteSelectionRect.width >= 1 && remoteSelectionRect.height >= 1 {
            if shouldClipSelectionImage() {
                context.saveGraphicsState()
                NSBezierPath(rect: remoteSelectionRect).setClip()
                if let image = screenshotImage {
                    image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
                }
                context.restoreGraphicsState()
            }
            // Purple border for remote selection
            let remoteBorder = NSBezierPath(rect: remoteSelectionRect)
            remoteBorder.lineWidth = 2.0
            ToolbarLayout.accentColor.setStroke()
            remoteBorder.stroke()

            // Resize handles for remote selection
            drawRemoteResizeHandles()
        }

        // Draw clear selection region
        if state != .idle && selectionRect.width >= 1 && selectionRect.height >= 1 {
            // During scroll capture: punch a fully-transparent hole so the live screen
            // content underneath shows through the overlay window.
            if isScrollCapturing {
                context.saveGraphicsState()
                context.cgContext.clear(selectionRect)
                context.restoreGraphicsState()
            }

            // Draw screenshot clipped to selection (image never bleeds outside).
            // In editor mode this is already handled by the detached draw block above.
            if shouldClipSelectionImage() {
                context.saveGraphicsState()
                NSBezierPath(rect: selectionRect).setClip()
                applyZoomTransform(to: context)
                if !isScrollCapturing, !isRecording, let image = screenshotImage {
                    image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
                }
                context.restoreGraphicsState()
            }

            // Skip annotation drawing if the editor already drew them via the cached composite.
            let editorDrawnFromCache = (self as? EditorView)?.drewFromCompositeCache ?? false

            if !editorDrawnFromCache {
                // Use cached annotation layer whenever possible — even during active
                // drawing. Committed annotations don't change while a new stroke is
                // being drawn, so re-iterating them every frame wastes CPU and causes
                // event coalescing (fewer mouse events → over-smoothed strokes).
                if !annotations.isEmpty && !isEditorMode {
                    if (isDraggingAnnotation || isResizingAnnotation || isRotatingAnnotation),
                       let staticLayer = cachedAnnotationLayerExcludingSelected {
                        // During drag/resize: draw cached static annotations + selected ones live
                        context.saveGraphicsState()
                        applyCanvasTransform(to: context)
                        staticLayer.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
                        for annotation in selectedAnnotations {
                            annotation.draw(in: context)
                        }
                    } else {
                        let layer = annotationLayerImage()
                        context.saveGraphicsState()
                        applyCanvasTransform(to: context)
                        layer.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
                    }
                } else if !annotations.isEmpty {
                    // Editor mode: no annotation layer cache, draw individually.
                    // Draw translate overlays clipped to selection (they must stay inside).
                    context.saveGraphicsState()
                    applyCanvasTransform(to: context)
                    NSBezierPath(rect: selectionRect).setClip()
                    for annotation in annotations where annotation.tool == .translateOverlay {
                        annotation.draw(in: context)
                    }
                    context.restoreGraphicsState()

                    // Draw user annotations unclipped — strokes can continue past the selection border.
                    // Censor annotations (pixelate/blur) render first so other annotations
                    // always appear on top of blurred regions.
                    context.saveGraphicsState()
                    applyCanvasTransform(to: context)
                    for annotation in annotations where annotation.tool != .translateOverlay && annotation.tool == .pixelate {
                        annotation.draw(in: context)
                    }
                    for annotation in annotations where annotation.tool != .translateOverlay && annotation.tool != .pixelate {
                        annotation.draw(in: context)
                    }
                }
            } else {
                // Still need the canvas transform for active drawing and overlays below
                context.saveGraphicsState()
                applyCanvasTransform(to: context)
            }
            currentAnnotation?.draw(in: context)
            autoMeasurePreview?.draw(in: context)

            // Crop selection rectangle preview
            if isCropDragging && cropDragRect.width > 1 && cropDragRect.height > 1 {
                drawCropPreview()

                // Crop border
                NSColor.white.setStroke()
                let cropBorder = NSBezierPath(rect: cropDragRect)
                cropBorder.lineWidth = 1.5
                cropBorder.stroke()

                // Rule of thirds grid
                NSColor.white.withAlphaComponent(0.3).setStroke()
                let thirdW = cropDragRect.width / 3
                let thirdH = cropDragRect.height / 3
                for i in 1...2 {
                    let gridLine = NSBezierPath()
                    gridLine.move(
                        to: NSPoint(
                            x: cropDragRect.minX + thirdW * CGFloat(i), y: cropDragRect.minY))
                    gridLine.line(
                        to: NSPoint(
                            x: cropDragRect.minX + thirdW * CGFloat(i), y: cropDragRect.maxY))
                    gridLine.lineWidth = 0.5
                    gridLine.stroke()
                    let hLine = NSBezierPath()
                    hLine.move(
                        to: NSPoint(
                            x: cropDragRect.minX, y: cropDragRect.minY + thirdH * CGFloat(i)))
                    hLine.line(
                        to: NSPoint(
                            x: cropDragRect.maxX, y: cropDragRect.minY + thirdH * CGFloat(i)))
                    hLine.lineWidth = 0.5
                    hLine.stroke()
                }
            }

            // Live loupe preview when loupe tool is active
            if currentTool == .loupe && selectionRect.contains(loupeCursorPoint)
                && loupeCursorPoint != .zero
            {
                drawLoupePreview(at: loupeCursorPoint)
            }
            if currentTool == .colorSampler && colorSamplerPoint != .zero {
                drawColorSamplerPreview(at: colorSamplerPoint)
            }

            // Draw selection highlight for selected annotations
            // Suppressed during recording so annotations are purely visual overlays.
            if !isRecording {
                for selected in selectedAnnotations {
                    // Only draw full controls (handles, buttons) for single selection
                    drawAnnotationControls(for: selected, fullControls: selectedAnnotations.count == 1)
                }
                // Consolidated delete button for multi-selection
                drawMultiSelectDeleteButton()
            }

            // Pencil/marker cursor dot preview inside zoom transform so it scales with zoom
            if (currentTool == .pencil || currentTool == .marker) && drawingCursorPoint != .zero && currentAnnotation == nil && !isDraggingAnnotation && !isResizingAnnotation && !isRotatingAnnotation {
                drawDrawingCursorPreview(at: drawingCursorPoint)
            }

            // Snap alignment guides
            drawSnapGuides()

            // Lasso selection marquee (drawn in canvas space — same as annotations)
            if isLassoSelecting && lassoRect.width > 0 && lassoRect.height > 0 {
                NSColor.systemBlue.withAlphaComponent(0.1).setFill()
                NSBezierPath(rect: lassoRect).fill()
                NSColor.systemBlue.withAlphaComponent(0.6).setStroke()
                let border = NSBezierPath(rect: lassoRect)
                border.lineWidth = 1.0
                let pattern: [CGFloat] = [4, 3]
                border.setLineDash(pattern, count: 2, phase: 0)
                border.stroke()
            }

            context.restoreGraphicsState()

            // (Text move handle removed — standard annotation chrome handles movement)

            // Live beautify preview — draw gradient background, shadow, and rounded image around selection
            let showBeautifyPreview = beautifyEnabled && state == .selected && !isScrollCapturing && !isRecording
            let showEffectsPreview = effectsActive && state == .selected && !isScrollCapturing && !isRecording && !beautifyEnabled

            if showBeautifyPreview {
                context.saveGraphicsState()
                applyCanvasTransform(to: context)
                drawBeautifyPreview(context: context)
                context.restoreGraphicsState()

                // Re-draw in-progress annotation on top of beautify so it stays visible
                if currentAnnotation != nil || autoMeasurePreview != nil {
                    context.saveGraphicsState()
                    applyCanvasTransform(to: context)
                    currentAnnotation?.draw(in: context)
                    autoMeasurePreview?.draw(in: context)
                    context.restoreGraphicsState()
                }

                // Re-draw annotation controls on top of the beautify preview so they stay visible.
                if !isRecording && !selectedAnnotations.isEmpty {
                    context.saveGraphicsState()
                    applyCanvasTransform(to: context)
                    for selected in selectedAnnotations {
                        drawAnnotationControls(for: selected, fullControls: selectedAnnotations.count == 1)
                    }
                    drawMultiSelectDeleteButton()
                    context.restoreGraphicsState()
                }

                // Re-draw loupe preview on top of beautify so it stays visible
                if currentTool == .loupe && selectionRect.contains(loupeCursorPoint)
                    && loupeCursorPoint != .zero
                {
                    context.saveGraphicsState()
                    applyCanvasTransform(to: context)
                    drawLoupePreview(at: loupeCursorPoint)
                    context.restoreGraphicsState()
                }

                // Re-draw color sampler preview on top of beautify
                if currentTool == .colorSampler && colorSamplerPoint != .zero {
                    context.saveGraphicsState()
                    applyCanvasTransform(to: context)
                    drawColorSamplerPreview(at: colorSamplerPoint)
                    context.restoreGraphicsState()
                }

                // Re-draw snap guides on top of beautify
                if snapGuideX != nil || snapGuideY != nil {
                    context.saveGraphicsState()
                    applyCanvasTransform(to: context)
                    drawSnapGuides()
                    context.restoreGraphicsState()
                }

                // Re-draw drawing cursor dot preview on top of beautify
                if (currentTool == .pencil || currentTool == .marker) && drawingCursorPoint != .zero && currentAnnotation == nil && !isDraggingAnnotation && !isResizingAnnotation && !isRotatingAnnotation
                {
                    context.saveGraphicsState()
                    applyCanvasTransform(to: context)
                    drawDrawingCursorPreview(at: drawingCursorPoint)
                    context.restoreGraphicsState()
                }

                // Re-draw crop preview on top of beautify
                if isCropDragging && cropDragRect.width > 1 && cropDragRect.height > 1 {
                    context.saveGraphicsState()
                    applyCanvasTransform(to: context)
                    drawCropPreview()
                    NSColor.white.setStroke()
                    let cropBorder = NSBezierPath(rect: cropDragRect)
                    cropBorder.lineWidth = 1.5
                    cropBorder.stroke()
                    context.restoreGraphicsState()
                }
            }

            // Effects-only preview (no beautify) — draw effects-processed screenshot in selection
            if showEffectsPreview, let screenshot = screenshotImage {
                context.saveGraphicsState()
                applyCanvasTransform(to: context)
                NSBezierPath(rect: selectionRect).setClip()
                let effectsImage = effectsProcessedScreenshot(screenshot)
                effectsImage.draw(in: captureDrawRect, from: .zero, operation: .copy, fraction: 1.0)
                // Re-draw annotations on top (censor first, then everything else)
                for annotation in annotations where annotation.tool == .pixelate { annotation.draw(in: context) }
                for annotation in annotations where annotation.tool != .pixelate { annotation.draw(in: context) }
                currentAnnotation?.draw(in: context)
                context.restoreGraphicsState()

                // Re-draw overlays on top of effects preview
                if !selectedAnnotations.isEmpty {
                    context.saveGraphicsState()
                    applyCanvasTransform(to: context)
                    for selected in selectedAnnotations {
                        drawAnnotationControls(for: selected, fullControls: selectedAnnotations.count == 1)
                    }
                    drawMultiSelectDeleteButton()
                    context.restoreGraphicsState()
                }
                if currentTool == .loupe && selectionRect.contains(loupeCursorPoint) && loupeCursorPoint != .zero {
                    context.saveGraphicsState()
                    applyCanvasTransform(to: context)
                    drawLoupePreview(at: loupeCursorPoint)
                    context.restoreGraphicsState()
                }
                if currentTool == .colorSampler && colorSamplerPoint != .zero {
                    context.saveGraphicsState()
                    applyCanvasTransform(to: context)
                    drawColorSamplerPreview(at: colorSamplerPoint)
                    context.restoreGraphicsState()
                }
                if (currentTool == .pencil || currentTool == .marker) && drawingCursorPoint != .zero && currentAnnotation == nil && !isDraggingAnnotation && !isResizingAnnotation && !isRotatingAnnotation {
                    context.saveGraphicsState()
                    applyCanvasTransform(to: context)
                    drawDrawingCursorPreview(at: drawingCursorPoint)
                    context.restoreGraphicsState()
                }
                if snapGuideX != nil || snapGuideY != nil {
                    context.saveGraphicsState()
                    applyCanvasTransform(to: context)
                    drawSnapGuides()
                    context.restoreGraphicsState()
                }
            }

            // Selection border — hidden in editor mode and when beautify/effects preview is active,
            // red during scroll capture, purple otherwise
            if shouldDrawSelectionBorder()
                && !showBeautifyPreview && !showEffectsPreview
            {
                let borderPath = NSBezierPath(rect: selectionRect)
                borderPath.lineWidth = isScrollCapturing ? 2.5 : 2.0
                (isScrollCapturing ? NSColor.systemRed : ToolbarLayout.accentColor).setStroke()
                borderPath.stroke()
            }

            if shouldDrawSizeLabel() {
                // Size label above/below selection
                drawSizeLabel()

                // Zoom label (fades in/out beside the size label)
                if zoomLabelOpacity > 0 {
                    drawZoomLabel()
                }
            }

            // Resize handles (drawn even in recording setup mode, but not during scroll capture)
            if state == .selected && !isEditorMode && !isScrollCapturing {
                drawResizeHandles()
            }

            // Hide the text view when color picker is open for bg/outline (so picker isn't behind it)
            if let sv = textEditor.scrollView {
                let shouldHide = false
                sv.isHidden = shouldHide
            }

            // Live text box (bg/outline + resize handles)
            if let sv = textEditor.scrollView, textEditView != nil {
                let pad: CGFloat = 4
                let pillRect = sv.frame.insetBy(dx: -pad, dy: -pad)
                let cornerR: CGFloat = 4

                // Background fill
                if textEditor.bgEnabled {
                    textEditor.bgColor.setFill()
                    NSBezierPath(roundedRect: pillRect, xRadius: cornerR, yRadius: cornerR).fill()
                }

                // Text outline
                if textEditor.outlineEnabled {
                    textEditor.outlineColor.setStroke()
                    let outlinePath = NSBezierPath(
                        roundedRect: pillRect, xRadius: cornerR, yRadius: cornerR)
                    outlinePath.lineWidth = 2
                    outlinePath.stroke()
                }

                // Draw text content when scroll view is hidden (color picker open)
                if sv.isHidden, let tv = textEditView, let attrStr = tv.textStorage,
                    attrStr.length > 0
                {
                    let inset = tv.textContainerInset
                    let textRect = NSRect(
                        x: sv.frame.minX + inset.width, y: sv.frame.minY + inset.height,
                        width: sv.frame.width - inset.width * 2,
                        height: sv.frame.height - inset.height * 2)
                    context.saveGraphicsState()
                    let flipped = NSAffineTransform()
                    flipped.translateX(by: 0, yBy: sv.frame.maxY + sv.frame.minY)
                    flipped.scaleX(by: 1, yBy: -1)
                    flipped.concat()
                    attrStr.draw(in: textRect)
                    context.restoreGraphicsState()
                }

                // Box border (always visible while editing)
                NSColor.white.withAlphaComponent(0.4).setStroke()
                let borderPath = NSBezierPath(rect: sv.frame)
                borderPath.lineWidth = 1
                let pattern: [CGFloat] = [4, 3]
                borderPath.setLineDash(pattern, count: 2, phase: 0)
                borderPath.stroke()

                // Resize handles on the text box
                let hs: CGFloat = 6
                let handleColor = NSColor.white
                let handleRects = [
                    NSRect(
                        x: sv.frame.minX - hs / 2, y: sv.frame.minY - hs / 2, width: hs, height: hs),  // bottom-left
                    NSRect(
                        x: sv.frame.maxX - hs / 2, y: sv.frame.minY - hs / 2, width: hs, height: hs),  // bottom-right
                    NSRect(
                        x: sv.frame.minX - hs / 2, y: sv.frame.maxY - hs / 2, width: hs, height: hs),  // top-left
                    NSRect(
                        x: sv.frame.maxX - hs / 2, y: sv.frame.maxY - hs / 2, width: hs, height: hs),  // top-right
                    NSRect(
                        x: sv.frame.midX - hs / 2, y: sv.frame.minY - hs / 2, width: hs, height: hs),  // bottom
                    NSRect(
                        x: sv.frame.midX - hs / 2, y: sv.frame.maxY - hs / 2, width: hs, height: hs),  // top
                    NSRect(
                        x: sv.frame.minX - hs / 2, y: sv.frame.midY - hs / 2, width: hs, height: hs),  // left
                    NSRect(
                        x: sv.frame.maxX - hs / 2, y: sv.frame.midY - hs / 2, width: hs, height: hs),  // right
                ]
                for hr in handleRects {
                    handleColor.setFill()
                    NSBezierPath(roundedRect: hr, xRadius: 1, yRadius: 1).fill()
                    NSColor.black.withAlphaComponent(0.3).setStroke()
                    NSBezierPath(roundedRect: hr, xRadius: 1, yRadius: 1).stroke()
                }
            }

            // Stamp cursor preview
            if let previewPt = stampPreviewPoint, let img = currentStampImage,
                currentTool == .stamp, !isRecording
            {
                let stampSize: CGFloat = 64
                let aspect = img.size.width / max(img.size.height, 1)
                let w = aspect >= 1 ? stampSize : stampSize * aspect
                let h = aspect >= 1 ? stampSize / aspect : stampSize
                let previewRect = NSRect(
                    x: previewPt.x - w / 2, y: previewPt.y - h / 2, width: w, height: h)
                context.saveGraphicsState()
                applyCanvasTransform(to: context)
                img.draw(
                    in: previewRect, from: .zero, operation: .sourceOver, fraction: 0.5,
                    respectFlipped: true, hints: nil)
                context.restoreGraphicsState()
            }

            // Toolbars — reposition only when selection/layout changes (not every draw).
            // In editor mode toolbars have autoresizingMask, so they only need repositioning
            // on explicit layout changes (handled by rebuildToolbarLayout).
            // In overlay mode the selection rect moves, so we must reposition here.
            if showToolbars && state == .selected && !isScrollCapturing {
                if !isEditorMode { repositionToolbars() }
                // Toolbars are real NSView subviews (ToolbarStripView) — no custom drawing needed.
                // Tool options row handled by ToolOptionsRowView (real NSView subview)
                if !toolHasOptionsRow || isRecording {
                    // options row rect managed by ToolOptionsRowView
                }

                // Color picker popover

                // Beautify style picker popover

                // Stroke width picker popover

                // Loupe size picker

                // Upload confirm picker

                // Redact type picker

            }

            // Radial color wheel
            if colorWheel.isVisible {
                colorWheel.draw(currentColor: currentColor)
            }
        }

        // Overlay error message
        if let errorMsg = overlayErrorMessage {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            let str = errorMsg as NSString
            let strSize = str.size(withAttributes: attrs)
            let padding: CGFloat = 12
            let msgW = strSize.width + padding * 2
            let msgH = strSize.height + padding
            let msgX = bounds.midX - msgW / 2
            let msgY = bounds.maxY - msgH - 40
            let msgRect = NSRect(x: msgX, y: msgY, width: msgW, height: msgH)
            NSColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 0.9).setFill()
            NSBezierPath(roundedRect: msgRect, xRadius: 8, yRadius: 8).fill()
            str.draw(
                at: NSPoint(x: msgRect.minX + padding, y: msgRect.minY + padding / 2),
                withAttributes: attrs)
        }

        // Barcode / QR badge
        if state == .selected {
            barcodeDetector.draw(
                selectionRect: selectionRect, bottomBarRect: bottomBarRect, viewBounds: bounds)
        }


        // Instant tooltip for hovered toolbar button
        drawHoveredTooltip()

    }
    static let helperFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let helperSmallFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let helperSmallBoldFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let helperDimColor = NSColor.white.withAlphaComponent(0.7)

    func drawIdleHelperText() {
        let line1 =
            windowSnapEnabled
            ? L("Click a window  ·  Drag for custom area  ·  F for full screen")
            : L("Drag to select  ·  Click for full screen")
        let snapOn = windowSnapEnabled
        let line3prefix = L("Window snap: ")
        let line3state = snapOn ? L("ON") : L("OFF")
        let line3suffix = L("  (Tab to toggle)")

        let snapColor = snapOn ? NSColor.systemGreen : NSColor.systemOrange

        let attrs1: [NSAttributedString.Key: Any] = [.font: Self.helperFont, .foregroundColor: NSColor.white]
        let attrs2prefix: [NSAttributedString.Key: Any] = [
            .font: Self.helperSmallFont, .foregroundColor: Self.helperDimColor,
        ]
        let attrs2state: [NSAttributedString.Key: Any] = [
            .font: Self.helperSmallBoldFont, .foregroundColor: snapColor,
        ]
        let attrs2suffix: [NSAttributedString.Key: Any] = [
            .font: Self.helperSmallFont, .foregroundColor: Self.helperDimColor,
        ]

        let size1 = (line1 as NSString).size(withAttributes: attrs1)
        let size2pre = (line3prefix as NSString).size(withAttributes: attrs2prefix)
        let size2state = (line3state as NSString).size(withAttributes: attrs2state)
        let size2suf = (line3suffix as NSString).size(withAttributes: attrs2suffix)
        let size2total = CGSize(
            width: size2pre.width + size2state.width + size2suf.width,
            height: max(size2pre.height, size2state.height, size2suf.height))

        let lineSpacing: CGFloat = 6
        let padding: CGFloat = 14
        let totalTextHeight = size1.height + lineSpacing + size2total.height
        let bgWidth = max(size1.width, size2total.width) + padding * 2
        let bgHeight = totalTextHeight + padding * 2

        let bgX = bounds.midX - bgWidth / 2
        let bgY = bounds.midY - bgHeight / 2
        let bgRect = NSRect(x: bgX, y: bgY, width: bgWidth, height: bgHeight)

        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 8, yRadius: 8).fill()

        let textY1 = bgY + padding + size2total.height + lineSpacing
        let textY2 = bgY + padding

        (line1 as NSString).draw(
            at: NSPoint(x: bounds.midX - size1.width / 2, y: textY1), withAttributes: attrs1)

        // Draw snap line as three segments with different colors
        let line2startX = bounds.midX - size2total.width / 2
        let line2Y = textY2 + (size2total.height - size2pre.height) / 2
        (line3prefix as NSString).draw(
            at: NSPoint(x: line2startX, y: line2Y), withAttributes: attrs2prefix)
        (line3state as NSString).draw(
            at: NSPoint(x: line2startX + size2pre.width, y: line2Y), withAttributes: attrs2state)
        (line3suffix as NSString).draw(
            at: NSPoint(x: line2startX + size2pre.width + size2state.width, y: line2Y),
            withAttributes: attrs2suffix)
    }

    static let helperTextAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    func drawSelectingHelperText() {
        guard selectionRect.width >= 1, selectionRect.height >= 1 else { return }

        let text = L("Release to annotate and edit")
        let attrs = Self.helperTextAttrs
        let size = (text as NSString).size(withAttributes: attrs)
        let padding: CGFloat = 10
        let bgWidth = size.width + padding * 2
        let bgHeight = size.height + padding

        // Position below the selection, centered
        var labelX = selectionRect.midX - bgWidth / 2
        var labelY = selectionRect.minY - bgHeight - 8

        // If below screen, put above
        if labelY < bounds.minY + 4 {
            labelY = selectionRect.maxY + 8
        }
        // Clamp horizontal
        labelX = max(bounds.minX + 4, min(labelX, bounds.maxX - bgWidth - 4))

        let bgRect = NSRect(x: labelX, y: labelY, width: bgWidth, height: bgHeight)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 6, yRadius: 6).fill()

        (text as NSString).draw(
            at: NSPoint(x: bgRect.minX + padding, y: bgRect.minY + padding / 2),
            withAttributes: attrs)
    }

}

// MARK: - NSTextFieldDelegate

extension OverlayView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
        -> Bool
    {
        if control.tag == 888 {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                commitSizeInputIfNeeded()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                sizeInputField?.removeFromSuperview()
                sizeInputField = nil
                window?.makeFirstResponder(self)
                needsDisplay = true
                return true
            }
        }
        if control.tag == 889 {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                commitZoomInputIfNeeded()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                zoomInputField?.removeFromSuperview()
                zoomInputField = nil
                window?.makeFirstResponder(self)
                needsDisplay = true
                return true
            }
        }
        return false
    }
}

// MARK: - NSTextViewDelegate

extension OverlayView: NSTextViewDelegate {
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            textView.insertNewlineIgnoringFieldEditor(self)
            textDidChange(Notification(name: NSText.didChangeNotification))
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelTextEditing()
            return true
        }
        return false
    }

    func textDidChange(_ notification: Notification) {
        textEditor.resizeToFit()
        needsDisplay = true
    }
}

// MARK: - AnnotationCanvas conformance

// MARK: - Image Effects helpers

extension OverlayView {
    /// Returns the effects-processed screenshot, cached for performance during draw().
    func effectsProcessedScreenshot(_ screenshot: NSImage) -> NSImage {
        if let cached = cachedEffectsScreenshot { return cached }
        let config = effectsConfig
        guard !config.isIdentity else { return screenshot }
        let processed = ImageEffects.apply(to: screenshot, config: config)
        cachedEffectsScreenshot = processed
        return processed
    }
}

extension OverlayView: AnnotationCanvas {
    var activeAnnotation: Annotation? {
        get { currentAnnotation }
        set { currentAnnotation = newValue }
    }

    func setNeedsDisplay() {
        needsDisplay = true
    }
}

// MARK: - TextEditingCanvas conformance

extension OverlayView: TextEditingCanvas {}

/// Small rounded-rect tooltip view used for editor mode toolbar hover labels.
class TooltipBackgroundView: NSView {
    var text: String = ""

    override func draw(_ dirtyRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: ToolbarLayout.iconColor,
        ]
        ToolbarLayout.bgColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        let pad: CGFloat = 6
        (text as NSString).draw(at: NSPoint(x: pad, y: pad / 2), withAttributes: attrs)
    }
}
