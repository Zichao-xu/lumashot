import Cocoa
import Carbon
import ServiceManagement
import ScreenCaptureKit

extension SettingsWindowController {
    // MARK: - Tools Tab

    func makeToolsTabView() -> NSView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 16, right: 20)

        // ── Annotation Tools ─────────────────────────────────
        stack.addArrangedSubview(sectionHeader(L("Annotation Tools")))
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)

        let noteA = NSTextField(labelWithString: L("Hidden tools are removed from the bottom toolbar."))
        noteA.font = NSFont.systemFont(ofSize: 11)
        noteA.textColor = .secondaryLabelColor
        stack.addArrangedSubview(noteA)
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        let annotationTools: [(AnnotationTool, String)] = [
            (.pencil, L("Pencil")), (.line, L("Line")), (.arrow, L("Arrow")),
            (.rectangle, L("Rectangle")),
            (.ellipse, L("Ellipse")), (.marker, L("Marker")), (.text, L("Text")),
            (.number, L("Number / Counter")), (.pixelate, L("Censor")),
            (.loupe, L("Magnify (Loupe)")), (.stamp, L("Stamp / Emoji")), (.colorSampler, L("Color Picker")), (.measure, L("Measure")),
        ]
        let enabledTools = UserDefaults.standard.array(forKey: "enabledTools") as? [Int]
        let toolsGrid = makeToggleGrid(items: annotationTools.map { (tag: $0.rawValue, label: $1) },
                                       defaultsKey: "enabledTools", enabledValues: enabledTools)
        stack.addArrangedSubview(toolsGrid)
        toolsGrid.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        // ── Bottom Toolbar Actions ───────────────────────────
        stack.addArrangedSubview(sectionHeader(L("Bottom Toolbar Actions")))
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)

        let noteB = NSTextField(labelWithString: L("Hidden actions are removed from the bottom toolbar."))
        noteB.font = NSFont.systemFont(ofSize: 11)
        noteB.textColor = .secondaryLabelColor
        stack.addArrangedSubview(noteB)
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        let bottomActionItems: [(tag: Int, label: String)] = [
            (1011, L("Invert Colors")),
            (1013, L("Adjust (Image Effects)")),
            (1004, L("Beautify")),
            (1005, L("Remove Background")),
        ]
        let enabledActions = UserDefaults.standard.array(forKey: "enabledActions") as? [Int]
        let bottomActionsGrid = makeToggleGrid(items: bottomActionItems,
                                               defaultsKey: "enabledActions", enabledValues: enabledActions)
        stack.addArrangedSubview(bottomActionsGrid)
        bottomActionsGrid.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        // ── Right Toolbar Actions ────────────────────────────
        stack.addArrangedSubview(sectionHeader(L("Right Toolbar Actions")))
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)

        let noteC = NSTextField(labelWithString: L("Hidden actions are removed from the right toolbar."))
        noteC.font = NSFont.systemFont(ofSize: 11)
        noteC.textColor = .secondaryLabelColor
        stack.addArrangedSubview(noteC)
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        let rightActionItems: [(tag: Int, label: String)] = [
            (1001, L("Upload")), (1002, L("Pin (floating window)")),
            (1003, L("OCR (extract text)")), (1006, L("Auto-Redact sensitive data")),
            (1008, L("Translate")),
            (1009, L("Record screen")),
            (1010, L("Scroll Capture")),
            (1012, L("Share")),
        ]
        let rightActionsGrid = makeToggleGrid(items: rightActionItems,
                                              defaultsKey: "enabledActions", enabledValues: enabledActions)
        stack.addArrangedSubview(rightActionsGrid)
        rightActionsGrid.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true

        let clipView = scroll.contentView
        scroll.documentView = stack

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: clipView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
        ])

        return scroll
    }

}
