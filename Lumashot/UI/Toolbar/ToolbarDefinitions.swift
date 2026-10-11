import Cocoa
import SwiftUI

extension Notification.Name {
    static let toolbarColorsDidChange = Notification.Name("toolbarColorsDidChange")
}

// Toolbar buttons drawn directly in the OverlayView (not a separate window).
// This avoids window-level z-order issues and matches Flameshot's look.

enum ToolbarButtonAction {
    case tool(AnnotationTool)
    case color
    case more
    case sizeDisplay
    case undo
    case redo
    case copy
    case save
    case pin
    case ocr
    case autoRedact
    case beautify
    case beautifyStyle
    case cancel
    case hdrToggle
    case moveSelection
    case delayCapture
    case upload
    case share
    case removeBackground
    case invertColors
    case loupe
    case translate
    case record  // enters recording mode (shows recording toolbar)
    case startRecord  // actually starts recording
    case stopRecord
    case mouseHighlight
    case systemAudio
    case micAudio
    case detach
    case scrollCapture
    case addCapture  // editor only: capture a new region and append to the canvas
    case showKeystrokes
    case webcam
    case recordSettings  // recording mode: open format/FPS/when-done popover
    case effects  // image effects (CIFilter adjustments + presets)
}

enum ToolbarButtonRole {
    case normal
    case auxiliary
    case primary
    case destructive
}

struct ToolbarButton {
    let action: ToolbarButtonAction
    let sfSymbol: String?
    let tooltip: String
    var textTitle: String? = nil
    var isSelected: Bool = false
    var tintColor: NSColor = ToolbarLayout.iconColor
    var bgColor: NSColor? = nil  // for color swatches
    var hasContextMenu: Bool = false  // draw small corner triangle to indicate right-click options
    var role: ToolbarButtonRole = .normal
}

class ToolbarLayout {

    // Default theme colors (Flameshot purple style)
    static let defaultAccentColor = NSColor(calibratedRed: 0.55, green: 0.30, blue: 0.85, alpha: 1.0)
    static let defaultIconColor = NSColor.white
    static let defaultBgColor = NSColor(white: 0.12, alpha: 1.0)

    // User-customizable colors — read from UserDefaults with defaults matching the original look
    static var accentColor: NSColor {
        if let data = UserDefaults.standard.data(forKey: "toolbarAccentColor"),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            return color
        }
        return defaultAccentColor
    }
    static var iconColor: NSColor {
        if let data = UserDefaults.standard.data(forKey: "toolbarIconColor"),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            return color
        }
        return defaultIconColor
    }
    static var bgColor: NSColor {
        if let data = UserDefaults.standard.data(forKey: "toolbarBgColor"),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            return color
        }
        return defaultBgColor
    }
    static var handleColor: NSColor { accentColor }
    static let toolbarPadding: CGFloat = 5
    static let buttonCornerRadius: CGFloat = 12
    static let toolbarCornerRadius: CGFloat = outerCornerRadius(
        aroundInnerRadius: buttonCornerRadius,
        inset: toolbarPadding)
    static let optionsRowCornerRadius: CGFloat = 16
    static let popoverContentCornerRadius: CGFloat = 12
    static let popoverSelectionCornerRadius: CGFloat = 7
    static let swatchCornerRadius: CGFloat = 5
    static let cornerRadius: CGFloat = toolbarCornerRadius

    static func outerCornerRadius(aroundInnerRadius innerRadius: CGFloat, inset: CGFloat) -> CGFloat {
        max(0, innerRadius + inset)
    }

    static func insetCornerRadius(_ radius: CGFloat, by inset: CGFloat) -> CGFloat {
        max(0, radius - inset)
    }

    static func continuousRoundedPath(in rect: NSRect, radius: CGFloat) -> NSBezierPath {
        let clampedRadius = max(0, min(radius, min(rect.width, rect.height) / 2))
        let cgRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        let path = Path(roundedRect: cgRect, cornerRadius: clampedRadius, style: .continuous)
        return NSBezierPath.toolbarPath(from: path.cgPath)
    }

    static func continuousRoundedPath(in rect: NSRect, radius: CGFloat, inset: CGFloat) -> NSBezierPath {
        continuousRoundedPath(
            in: rect.insetBy(dx: inset, dy: inset),
            radius: insetCornerRadius(radius, by: inset))
    }

    static func circlePath(in rect: NSRect) -> NSBezierPath {
        NSBezierPath(ovalIn: rect)
    }

    static func applyContinuousCornerCurve(to layer: CALayer?) {
        if #available(macOS 10.15, *) {
            layer?.cornerCurve = .continuous
        }
    }

    /// Save accent color to UserDefaults.
    static func saveAccentColor(_ color: NSColor) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: "toolbarAccentColor")
        }
    }

    /// Save icon color to UserDefaults.
    static func saveIconColor(_ color: NSColor) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: "toolbarIconColor")
        }
    }

    /// Appearance matching the toolbar background brightness.
    /// Dark background → `.darkAqua`, light background → `.aqua`.
    static var appearance: NSAppearance? {
        let color = bgColor.usingColorSpace(.deviceRGB) ?? bgColor
        var brightness: CGFloat = 0
        color.getHue(nil, saturation: nil, brightness: &brightness, alpha: nil)
        return NSAppearance(named: brightness > 0.5 ? .aqua : .darkAqua)
    }

    /// Save background color to UserDefaults.
    static func saveBgColor(_ color: NSColor) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: "toolbarBgColor")
        }
    }

    /// Reset all colors to defaults.
    static func resetColors() {
        UserDefaults.standard.removeObject(forKey: "toolbarAccentColor")
        UserDefaults.standard.removeObject(forKey: "toolbarIconColor")
        UserDefaults.standard.removeObject(forKey: "toolbarBgColor")
    }

    private static let allKnownActionTags: [Int] = [
        1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011, 1012, 1013,
    ]

    private static let primaryTools: [AnnotationTool] = [
        .select, .rectangle, .ellipse, .stamp, .arrow, .pencil, .pixelate, .text,
    ]

    private static var drawingTools: [(AnnotationTool, String, String)] {
        [
            (.select, "arrow.up.and.down.and.arrow.left.and.right", L("Move Selection")),
            (.pencil, "scribble", L("Pencil (Draw)")),
            (.line, "line.diagonal", L("Line")),
            (.arrow, "arrow.up.right", L("Arrow")),
            (.rectangle, "rectangle", L("Rectangle")),
            (.ellipse, "oval", L("Ellipse")),
            (.marker, {
                if #available(macOS 14.0, *) { return "highlighter" }
                return "paintbrush.pointed.fill"
            }(), L("Marker")),
            (.text, "_custom.textbox", L("Text")),
            (.number, "1.circle.fill", L("Number")),
            (.pixelate, "_custom.checkerboard", L("Censor (Pixelate / Blur / Solid)")),
            (.loupe, "magnifyingglass", L("Magnify (Loupe)")),
            (.stamp, "face.smiling", L("Stamp / Emoji")),
            (.colorSampler, "eyedropper", L("Color Picker")),
            (.measure, "ruler", L("Measure (px)")),
        ]
    }

    private static func enabledToolRawValues() -> [Int]? {
        let allKnownToolRawValues = AnnotationTool.allCases
            .filter { $0 != .select && $0 != .translateOverlay }
            .map { $0.rawValue }
        var enabledRawValues = UserDefaults.standard.array(forKey: "enabledTools") as? [Int]
        let knownToolRawValues = UserDefaults.standard.array(forKey: "knownToolRawValues") as? [Int]
        let newToolRaws = allKnownToolRawValues.filter { !(knownToolRawValues ?? []).contains($0) }
        if !newToolRaws.isEmpty {
            if enabledRawValues == nil {
                enabledRawValues = allKnownToolRawValues
            } else if knownToolRawValues == nil {
                // Respect the existing enabledTools as-is; just mark all current tools as known.
            } else {
                enabledRawValues = (enabledRawValues! + newToolRaws)
            }
            UserDefaults.standard.set(enabledRawValues, forKey: "enabledTools")
            UserDefaults.standard.set(allKnownToolRawValues, forKey: "knownToolRawValues")
        }
        return enabledRawValues
    }

    private static func enabledActionTags() -> [Int]? {
        var enabledActions = UserDefaults.standard.array(forKey: "enabledActions") as? [Int]
        let knownActionTags = UserDefaults.standard.array(forKey: "knownActionTags") as? [Int]
        let newTags = allKnownActionTags.filter { !(knownActionTags ?? []).contains($0) }
        if !newTags.isEmpty {
            if enabledActions == nil {
                enabledActions = allKnownActionTags
            } else if knownActionTags == nil {
                // Respect existing enabledActions as-is; just mark all current action tags as known.
            } else {
                enabledActions = (enabledActions! + newTags)
            }
            UserDefaults.standard.set(enabledActions, forKey: "enabledActions")
            UserDefaults.standard.set(allKnownActionTags, forKey: "knownActionTags")
        }
        return enabledActions
    }

    private static func actionEnabled(_ tag: Int, enabledActions: [Int]?) -> Bool {
        enabledActions == nil || enabledActions!.contains(tag)
    }

    private static func buttonForTool(
        _ tool: AnnotationTool,
        symbol: String,
        tooltip: String,
        selectedTool: AnnotationTool
    ) -> ToolbarButton {
        var btn = ToolbarButton(action: .tool(tool), sfSymbol: symbol, tooltip: tooltip)
        btn.isSelected = (tool == selectedTool)
        return btn
    }

    // Bottom toolbar items (single primary strip: common tools + key output actions)
    static func bottomButtons(
        selectedTool: AnnotationTool, selectedColor: NSColor, beautifyEnabled: Bool = false,
        beautifyStyleIndex: Int = 0, hasAnnotations: Bool = false, isRecording: Bool = false,
        effectsActive: Bool = false, translateEnabled: Bool = false, isEditorMode: Bool = false,
        hdrEnabled: Bool = false
    ) -> [ToolbarButton] {
        // Hide the bottom bar entirely while recording
        if isRecording { return [] }

        var buttons: [ToolbarButton] = []

        let enabledRawValues = enabledToolRawValues()
        let enabledActions = enabledActionTags()

        for tool in primaryTools {
            guard let entry = drawingTools.first(where: { $0.0 == tool }) else { continue }
            if tool != .select, let enabledRawValues, !enabledRawValues.contains(tool.rawValue) {
                continue
            }
            buttons.append(buttonForTool(entry.0, symbol: entry.1, tooltip: entry.2, selectedTool: selectedTool))
        }

        // Color is still first-class, but kept visually quiet as a swatch.
        var colorBtn = ToolbarButton(action: .color, sfSymbol: nil, tooltip: L("Color"))
        colorBtn.bgColor = selectedColor
        buttons.append(colorBtn)

        if actionEnabled(1008, enabledActions: enabledActions) {
            var translateBtn = ToolbarButton(
                action: .translate, sfSymbol: "translate", tooltip: L("Translate"))
            translateBtn.isSelected = translateEnabled
            translateBtn.hasContextMenu = true
            buttons.append(translateBtn)
        }

        if !overflowButtons(
            selectedTool: selectedTool, beautifyEnabled: beautifyEnabled,
            beautifyStyleIndex: beautifyStyleIndex, hasAnnotations: hasAnnotations,
            translateEnabled: translateEnabled, isEditorMode: isEditorMode,
            effectsActive: effectsActive
        ).isEmpty {
            buttons.append(ToolbarButton(action: .more, sfSymbol: "ellipsis", tooltip: L("More")))
        }

        if !isEditorMode {
            var hdrBtn = ToolbarButton(
                action: .hdrToggle, sfSymbol: nil,
                tooltip: L("HDR capture applies to this screenshot on supported Macs."))
            hdrBtn.textTitle = L("HDR")
            hdrBtn.tintColor = .white
            hdrBtn.isSelected = hdrEnabled
            buttons.append(hdrBtn)
        }

        // Undo / Redo
        buttons.append(
            ToolbarButton(
                action: .undo, sfSymbol: "arrow.uturn.backward", tooltip: L("Undo")))
        buttons.append(
            ToolbarButton(
                action: .redo, sfSymbol: "arrow.uturn.forward", tooltip: L("Redo")))

        var saveBtn = ToolbarButton(
            action: .save, sfSymbol: "square.and.arrow.down",
            tooltip: L("Save to...")
        )
        saveBtn.hasContextMenu = true
        buttons.append(saveBtn)

        if actionEnabled(1002, enabledActions: enabledActions) {
            buttons.append(ToolbarButton(action: .pin, sfSymbol: "pin", tooltip: L("Pin")))
        }

        if actionEnabled(1012, enabledActions: enabledActions) {
            buttons.append(
                ToolbarButton(
                    action: .share, sfSymbol: "arrowshape.turn.up.right", tooltip: L("Share")))
        }

        if !isEditorMode {
            var cancelBtn = ToolbarButton(action: .cancel, sfSymbol: "xmark", tooltip: L("Cancel"))
            cancelBtn.role = .destructive
            cancelBtn.tintColor = .systemRed
            buttons.append(cancelBtn)
        }

        var doneBtn = ToolbarButton(action: .copy, sfSymbol: "checkmark", tooltip: L("Done"))
        doneBtn.role = .primary
        doneBtn.tintColor = .systemGreen
        buttons.append(doneBtn)

        return buttons
    }

    static func overflowButtons(
        selectedTool: AnnotationTool, beautifyEnabled: Bool = false,
        beautifyStyleIndex: Int = 0, hasAnnotations: Bool = false,
        translateEnabled: Bool = false, isEditorMode: Bool = false,
        effectsActive: Bool = false
    ) -> [ToolbarButton] {
        var buttons: [ToolbarButton] = []
        let enabledRawValues = enabledToolRawValues()
        let enabledActions = enabledActionTags()

        for (tool, symbol, tip) in drawingTools where !primaryTools.contains(tool) {
            if let enabledRawValues, !enabledRawValues.contains(tool.rawValue) {
                continue
            }
            buttons.append(buttonForTool(tool, symbol: symbol, tooltip: tip, selectedTool: selectedTool))
        }

        if actionEnabled(1011, enabledActions: enabledActions) {
            buttons.append(
                ToolbarButton(
                    action: .invertColors, sfSymbol: "circle.righthalf.filled.inverse",
                    tooltip: L("Invert Colors")))
        }

        if actionEnabled(1013, enabledActions: enabledActions) {
            var effectsBtn = ToolbarButton(
                action: .effects, sfSymbol: "slider.horizontal.3", tooltip: L("Adjust"))
            if effectsActive {
                effectsBtn.tintColor = NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.2, alpha: 1.0)
            }
            buttons.append(effectsBtn)
        }

        if actionEnabled(1004, enabledActions: enabledActions) {
            var beautifyBtn = ToolbarButton(
                action: .beautify, sfSymbol: "sparkles", tooltip: L("Beautify"))
            if beautifyEnabled {
                beautifyBtn.tintColor = NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.2, alpha: 1.0)
            }
            buttons.append(beautifyBtn)
        }

        if #available(macOS 14.0, *), actionEnabled(1005, enabledActions: enabledActions) {
            buttons.append(
                ToolbarButton(
                    action: .removeBackground, sfSymbol: "person.crop.circle.dashed",
                    tooltip: L("Remove Background")))
        }

        if actionEnabled(1006, enabledActions: enabledActions) {
            buttons.append(
                ToolbarButton(
                    action: .autoRedact, sfSymbol: "eye.slash",
                    tooltip: L("Auto-Redact sensitive data")))
        }

        if !isEditorMode {
            buttons.append(
                ToolbarButton(
                    action: .detach, sfSymbol: "arrow.up.forward.app",
                    tooltip: L("Open in Editor Window")))
        }

        if actionEnabled(1001, enabledActions: enabledActions) {
            var uploadBtn = ToolbarButton(
                action: .upload, sfSymbol: "icloud.and.arrow.up", tooltip: L("Upload"))
            uploadBtn.hasContextMenu = true
            buttons.append(uploadBtn)
        }

        if actionEnabled(1003, enabledActions: enabledActions) {
            buttons.append(
                ToolbarButton(
                    action: .ocr, sfSymbol: "doc.text.viewfinder", tooltip: L("OCR Text")))
        }

        if !isEditorMode && actionEnabled(1010, enabledActions: enabledActions) {
            buttons.append(
                ToolbarButton(
                    action: .scrollCapture, sfSymbol: "scroll",
                    tooltip: L("Scroll Capture")))
        }

        if !isEditorMode && actionEnabled(1009, enabledActions: enabledActions) {
            buttons.append(
                ToolbarButton(action: .record, sfSymbol: "video", tooltip: L("Record")))
        }

        return buttons
    }

    // Right toolbar items (output actions + cancel + delay)
    static func rightButtons(
        beautifyEnabled: Bool = false, beautifyStyleIndex: Int = 0, hasAnnotations: Bool = false,
        translateEnabled: Bool = false, isRecording: Bool = false,
        isEditorMode: Bool = false
    ) -> [ToolbarButton] {
        var buttons: [ToolbarButton] = []

        // Recording setup mode — show start button + toggles, then return early
        if isRecording {
            var startBtn = ToolbarButton(
                action: .startRecord, sfSymbol: "record.circle", tooltip: L("Start Recording"))
            startBtn.tintColor = .systemRed
            buttons.append(startBtn)

            // Stop/cancel button to exit recording mode without starting
            buttons.append(
                ToolbarButton(action: .stopRecord, sfSymbol: "xmark", tooltip: L("Cancel Recording")))

            let mouseHighlightOn = UserDefaults.standard.bool(forKey: "recordMouseHighlight")
            var mouseBtn = ToolbarButton(
                action: .mouseHighlight, sfSymbol: "cursorarrow.click.2", tooltip: L("Highlight Mouse Clicks"))
            mouseBtn.isSelected = mouseHighlightOn
            buttons.append(mouseBtn)

            let keystrokesOn = UserDefaults.standard.bool(forKey: "recordKeystroke")
            var keystrokeBtn = ToolbarButton(
                action: .showKeystrokes, sfSymbol: "keyboard", tooltip: L("Show Keystrokes"))
            keystrokeBtn.isSelected = keystrokesOn
            keystrokeBtn.hasContextMenu = true
            buttons.append(keystrokeBtn)

            let audioOn = UserDefaults.standard.bool(forKey: "recordSystemAudio")
            var audioBtn = ToolbarButton(
                action: .systemAudio, sfSymbol: audioOn ? "speaker.wave.2.fill" : "speaker.slash",
                tooltip: L("Record System Audio"))
            audioBtn.isSelected = audioOn
            buttons.append(audioBtn)

            let micOn = UserDefaults.standard.bool(forKey: "recordMicAudio")
            var micBtn = ToolbarButton(
                action: .micAudio, sfSymbol: micOn ? "mic.fill" : "mic.slash", tooltip: L("Record Microphone"))
            micBtn.isSelected = micOn
            micBtn.hasContextMenu = true
            buttons.append(micBtn)

            let webcamOn = UserDefaults.standard.bool(forKey: "recordWebcam")
            let webcamSymbol: String = {
                if #available(macOS 14.0, *) {
                    return webcamOn ? "web.camera.fill" : "web.camera"
                }
                return webcamOn ? "camera.fill" : "camera"
            }()
            var webcamBtn = ToolbarButton(
                action: .webcam, sfSymbol: webcamSymbol, tooltip: L("Webcam Overlay"))
            webcamBtn.isSelected = webcamOn
            webcamBtn.hasContextMenu = true
            buttons.append(webcamBtn)

            // Recording settings gear
            buttons.append(
                ToolbarButton(
                    action: .recordSettings, sfSymbol: "gearshape",
                    tooltip: L("Recording Settings")))

            // Allow moving the selection before starting
            buttons.append(
                ToolbarButton(
                    action: .moveSelection, sfSymbol: "arrow.up.and.down.and.arrow.left.and.right",
                    tooltip: L("Move Selection")))

            return buttons
        }

        _ = enabledActionTags()
        return []
    }
}

private extension NSBezierPath {
    static func toolbarPath(from cgPath: CGPath) -> NSBezierPath {
        let path = NSBezierPath()
        cgPath.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            let points = element.points

            switch element.type {
            case .moveToPoint:
                path.move(to: points[0])
            case .addLineToPoint:
                path.line(to: points[0])
            case .addQuadCurveToPoint:
                let current = path.currentPoint
                let control = points[0]
                let end = points[1]
                let controlPoint1 = NSPoint(
                    x: current.x + (control.x - current.x) * 2 / 3,
                    y: current.y + (control.y - current.y) * 2 / 3)
                let controlPoint2 = NSPoint(
                    x: end.x + (control.x - end.x) * 2 / 3,
                    y: end.y + (control.y - end.y) * 2 / 3)
                path.curve(to: end, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
            case .addCurveToPoint:
                path.curve(to: points[2], controlPoint1: points[0], controlPoint2: points[1])
            case .closeSubpath:
                path.close()
            @unknown default:
                break
            }
        }
        return path
    }
}
