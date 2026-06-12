import AVFoundation
import Cocoa
import UniformTypeIdentifiers

extension OverlayView {
    // MARK: - Mic Permission & Toggle

    func toggleMicAudio() {
        let current = UserDefaults.standard.bool(forKey: "recordMicAudio")
        if current {
            // Turning off — no permission needed
            UserDefaults.standard.set(false, forKey: "recordMicAudio")
            stopMicLevelMonitor()
            rebuildToolbarLayout()
            return
        }
        // Turning on — check mic permission first
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            UserDefaults.standard.set(true, forKey: "recordMicAudio")
            rebuildToolbarLayout()
            startMicLevelMonitor()
        case .notDetermined:
            // Lower overlay so the system permission dialog is clickable
            let savedLevel = window?.level
            window?.level = .normal
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if let saved = savedLevel { self?.window?.level = saved }
                    if granted {
                        UserDefaults.standard.set(true, forKey: "recordMicAudio")
                        self?.startMicLevelMonitor()
                    }
                    self?.rebuildToolbarLayout()
                }
            }
        case .denied, .restricted:
            showMicPermissionAlert()
        @unknown default:
            break
        }
    }

    func showMicPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = L("Microphone Access Required")
        alert.informativeText =
            L("Lumashot needs microphone permission to record voice audio. Open System Settings to grant access.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Open Settings"))
        alert.addButton(withTitle: L("Cancel"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            ) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Mic Level Monitor

    func startMicLevelMonitor() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        stopMicLevelMonitor()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 && format.channelCount > 0 else { return }

        var peakLevel: Float = 0
        let lock = NSLock()

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            var peak: Float = 0
            for i in 0..<frames {
                let val = abs(channelData[0][i])
                if val > peak { peak = val }
            }
            lock.lock()
            peakLevel = peak
            lock.unlock()
        }

        do {
            try engine.start()
        } catch {
            return
        }
        micLevelEngine = engine

        // Poll level at ~20fps and drive the mic button's built-in level meter
        var displayLevel: Float = 0
        micLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            lock.lock()
            let level = peakLevel
            peakLevel = 0
            lock.unlock()
            // Smooth: fast attack, slow release
            displayLevel = level > displayLevel ? level : displayLevel * 0.8 + level * 0.2
            self?.setMicButtonLevel(displayLevel)
        }
    }

    func stopMicLevelMonitor() {
        micLevelTimer?.invalidate()
        micLevelTimer = nil
        micLevelEngine?.inputNode.removeTap(onBus: 0)
        micLevelEngine?.stop()
        micLevelEngine = nil
        setMicButtonLevel(0)
    }

    func setMicButtonLevel(_ level: Float) {
        // Find mic button in both toolbar strips
        let strips: [ToolbarStripView?] = [bottomStripView, rightStripView]
        for strip in strips {
            if let btn = strip?.buttonViews.first(where: {
                if case .micAudio = $0.action { return true }; return false
            }) {
                btn.micLevel = level
            }
        }
    }

}
