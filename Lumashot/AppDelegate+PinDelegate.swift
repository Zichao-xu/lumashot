import Cocoa
import Carbon
import UniformTypeIdentifiers
import AVFoundation
import WebP

extension AppDelegate: PinWindowControllerDelegate {
    func pinWindowDidClose(_ controller: PinWindowController) {
        pinControllers.removeAll { $0 === controller }
    }
}

// MARK: - NSMenuDelegate (Recent Captures)

