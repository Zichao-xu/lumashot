import Cocoa
import Carbon
import ServiceManagement
import ScreenCaptureKit

extension SettingsWindowController {
    // MARK: - About Tab

    func makeAboutTabView() -> NSView {
        let container = NSView()
        container.autoresizingMask = [.width, .height]

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 30),
            stack.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -40),
        ])

        // App icon
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 80).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 80).isActive = true
        stack.addArrangedSubview(icon)
        stack.setCustomSpacing(12, after: icon)

        // App name
        let name = NSTextField(labelWithString: "Lumashot")
        name.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        name.textColor = .labelColor
        stack.addArrangedSubview(name)

        // Version
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let versionLabel = NSTextField(labelWithString: String(format: L("Version %@ (%@)"), version, build))
        versionLabel.font = NSFont.systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(versionLabel)
        stack.setCustomSpacing(20, after: versionLabel)

        // Description
        let desc = NSTextField(wrappingLabelWithString: L("A free, open-source screenshot & screen recording tool for macOS.\nFully native — built with Swift and AppKit."))
        desc.font = NSFont.systemFont(ofSize: 13)
        desc.textColor = .labelColor
        desc.alignment = .center
        stack.addArrangedSubview(desc)
        stack.setCustomSpacing(20, after: desc)

        // License
        let license = NSTextField(labelWithString: L("Licensed under the GPLv3"))
        license.font = NSFont.systemFont(ofSize: 11)
        license.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(license)
        stack.setCustomSpacing(20, after: license)

        // Screen Info (debug) — gathers display & capture metadata, copies to clipboard
        let screenInfoBtn = NSButton(title: L("Copy Screen Info"), target: self, action: #selector(copyScreenInfo))
        screenInfoBtn.bezelStyle = .rounded
        screenInfoBtn.font = NSFont.systemFont(ofSize: 11)
        screenInfoBtn.tag = 9999  // tag for lookup in action handler
        stack.addArrangedSubview(screenInfoBtn)

        let screenInfoHint = NSTextField(labelWithString: L("Copies display and capture diagnostics to clipboard"))
        screenInfoHint.font = NSFont.systemFont(ofSize: 10)
        screenInfoHint.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(screenInfoHint)

        return container
    }

    @objc func copyScreenInfo() {
        if #available(macOS 14.0, *) {
            Task { @MainActor in
                var lines: [String] = []
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                lines.append("Lumashot \(version) (\(build))")
                lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                lines.append("")
                lines.append("=== NSScreen Info ===")
                for (i, screen) in NSScreen.screens.enumerated() {
                    let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
                    let cs = screen.colorSpace?.cgColorSpace
                    // CGDisplayCopyColorSpace reads the display ICC profile directly,
                    // bypassing NSScreen — helps diagnose DisplayLink/driver issues.
                    let cgCS = CGDisplayCopyColorSpace(id)
                    lines.append("Screen \(i): \(screen.localizedName) (ID: \(id))")
                    lines.append("  frame: \(screen.frame)")
                    lines.append("  backingScale: \(screen.backingScaleFactor)")
                    lines.append("  NSScreen.colorSpace: \(cs?.name as String? ?? "nil")")
                    lines.append("  CGDisplayCopyColorSpace: \(cgCS.name as String? ?? "nil")")
                    lines.append("  cs model: \(cs?.model.rawValue ?? -1)")
                    lines.append("")
                }
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                    lines.append("=== ScreenCaptureKit Capture Info ===")
                    for display in content.displays {
                        let filter = SCContentFilter(display: display, excludingWindows: [])
                        let config = SCStreamConfiguration()
                        config.width = display.width
                        config.height = display.height
                        config.captureResolution = .best
                        config.colorSpaceName = CGColorSpace.sRGB as CFString
                        if let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                            lines.append("Display \(display.displayID) (\(display.width)x\(display.height)):")
                            lines.append("  CGImage size: \(img.width)x\(img.height)")
                            lines.append("  bitsPerComponent: \(img.bitsPerComponent)")
                            lines.append("  bitsPerPixel: \(img.bitsPerPixel)")
                            lines.append("  bytesPerRow: \(img.bytesPerRow)")
                            lines.append("  bitmapInfo: \(img.bitmapInfo.rawValue)")
                            lines.append("  alphaInfo: \(img.alphaInfo.rawValue)")
                            lines.append("  colorSpace: \(img.colorSpace?.name as String? ?? "nil")")
                            lines.append("  cs model: \(img.colorSpace?.model.rawValue ?? -1)")
                            lines.append("")
                        }
                    }
                } catch {
                    lines.append("Capture error: \(error.localizedDescription)")
                }
                let result = lines.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result, forType: .string)
                // Flash the button title to confirm
                if let btn = self.window?.contentView?.viewWithTag(9999) as? NSButton {
                    btn.title = L("Copied!")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { btn.title = L("Copy Screen Info") }
                }
            }
        }
    }

    func updateGDriveStatus() {
        if GoogleDriveUploader.shared.isSignedIn {
            gdriveStatusLabel?.stringValue = GoogleDriveUploader.shared.userEmail ?? L("Signed in")
            gdriveStatusLabel?.textColor = .labelColor
        } else {
            gdriveStatusLabel?.stringValue = L("Not signed in")
            gdriveStatusLabel?.textColor = .secondaryLabelColor
        }
    }

    func updateGDriveButton() {
        if GoogleDriveUploader.shared.isSignedIn {
            gdriveSignInBtn?.title = L("Sign Out")
        } else {
            gdriveSignInBtn?.title = L("Sign In with Google")
        }
    }

    @objc func uploadProviderChanged(_ sender: NSPopUpButton) {
        let provider: String
        switch sender.indexOfSelectedItem {
        case 1: provider = "gdrive"
        case 2: provider = "s3"
        default: provider = "imgbb"
        }
        UserDefaults.standard.set(provider, forKey: "uploadProvider")
    }

    @objc func gdriveSignInTapped(_ sender: NSButton) {
        if GoogleDriveUploader.shared.isSignedIn {
            GoogleDriveUploader.shared.signOut()
            updateGDriveStatus()
            updateGDriveButton()
        } else {
            GoogleDriveUploader.shared.signIn(from: window) { [weak self] success in
                guard let self = self, success else {
                    self?.updateGDriveStatus()
                    self?.updateGDriveButton()
                    return
                }
                self.window?.makeKeyAndOrderFront(nil)
                self.updateGDriveButton()
                // Fetch email then update status label
                GoogleDriveUploader.shared.fetchUserEmail { [weak self] in
                    self?.updateGDriveStatus()
                }
            }
        }
    }

    @objc func s3FieldChanged(_ sender: NSTextField) {
        UserDefaults.standard.set(s3EndpointField.stringValue, forKey: "s3Endpoint")
        UserDefaults.standard.set(s3RegionField.stringValue, forKey: "s3Region")
        UserDefaults.standard.set(s3BucketField.stringValue, forKey: "s3Bucket")
        UserDefaults.standard.set(s3AccessKeyField.stringValue, forKey: "s3AccessKeyID")
        UserDefaults.standard.set(s3SecretKeyField.stringValue, forKey: "s3SecretAccessKey")
        UserDefaults.standard.set(s3PublicURLField.stringValue, forKey: "s3PublicURLBase")
        UserDefaults.standard.set(s3PathPrefixField.stringValue, forKey: "s3PathPrefix")
    }

    @objc func s3TestTapped(_ sender: NSButton) {
        // Save current field values first
        s3FieldChanged(s3EndpointField)

        guard S3Uploader.shared.isConfigured else {
            s3StatusLabel.stringValue = L("Fill in endpoint, bucket, and credentials first")
            s3StatusLabel.textColor = .systemOrange
            return
        }

        s3TestBtn.isEnabled = false
        s3StatusLabel.stringValue = L("Testing...")
        s3StatusLabel.textColor = .secondaryLabelColor

        // Upload a tiny test file
        let testData = Data("Lumashot connection test".utf8)
        let testKey = ".Lumashot_test_\(UUID().uuidString.prefix(8)).txt"
        S3Uploader.shared.upload(data: testData, filename: testKey, contentType: "text/plain") { [weak self] result in
            guard let self = self else { return }
            self.s3TestBtn.isEnabled = true
            switch result {
            case .success:
                self.s3StatusLabel.stringValue = L("Connection successful!")
                self.s3StatusLabel.textColor = .systemGreen
            case .failure(let error):
                self.s3StatusLabel.stringValue = error.localizedDescription
                self.s3StatusLabel.textColor = .systemRed
            }
        }
    }

    func reloadUploadsTab() {
        guard let stack = uploadsStack else { return }
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }

        let uploads = ((UserDefaults.standard.array(forKey: "imgbbUploads") as? [[String: String]]) ?? [])
            .reversed() as [[String: String]]

        if uploads.isEmpty {
            let lbl = NSTextField(labelWithString: L("No uploads yet."))
            lbl.font = NSFont.systemFont(ofSize: 13)
            lbl.textColor = .secondaryLabelColor
            lbl.alignment = .center
            lbl.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(lbl)
        } else {
            for (i, upload) in uploads.enumerated() {
                let row = makeUploadRow(index: uploads.count - i,
                                        link: upload["link"] ?? "",
                                        deleteURL: upload["deleteURL"] ?? "")
                stack.addArrangedSubview(row)
            }
        }
    }

    func makeUploadRow(index: Int, link: String, deleteURL: String) -> NSView {
        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.5).cgColor
        box.layer?.cornerRadius = 6
        box.layer?.borderWidth = 0.5
        box.layer?.borderColor = NSColor.separatorColor.cgColor

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 6
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        box.addSubview(inner)

        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: box.topAnchor),
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            inner.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])

        inner.addArrangedSubview(urlRow(tag: "URL", value: link, copyKey: "link::\(link)"))
        inner.addArrangedSubview(urlRow(tag: "DEL", value: deleteURL, copyKey: "link::\(deleteURL)"))

        return box
    }

    func urlRow(tag: String, value: String, copyKey: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let tagLbl = NSTextField(labelWithString: tag)
        tagLbl.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        tagLbl.textColor = .secondaryLabelColor
        tagLbl.translatesAutoresizingMaskIntoConstraints = false

        let field = NSTextField(labelWithString: value)
        field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        field.textColor = tag == "URL" ? .labelColor : .secondaryLabelColor
        field.lineBreakMode = .byTruncatingMiddle
        field.isSelectable = true
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let btn = NSButton(title: L("Copy"), target: self, action: #selector(copyUploadURL(_:)))
        btn.bezelStyle = .rounded
        btn.font = NSFont.systemFont(ofSize: 11)
        btn.identifier = NSUserInterfaceItemIdentifier(copyKey)
        btn.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(tagLbl)
        row.addSubview(field)
        row.addSubview(btn)

        NSLayoutConstraint.activate([
            tagLbl.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            tagLbl.widthAnchor.constraint(equalToConstant: 34),
            tagLbl.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            btn.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            btn.widthAnchor.constraint(equalToConstant: 52),
            btn.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            field.leadingAnchor.constraint(equalTo: tagLbl.trailingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: btn.leadingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        return row
    }

}
