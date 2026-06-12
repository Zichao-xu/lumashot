import Cocoa
import Carbon
import ServiceManagement
import ScreenCaptureKit

extension SettingsWindowController {
    // MARK: - Uploads Tab

    func makeUploadsTabView() -> NSView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 16, right: 20)

        // ── Upload Provider ──
        stack.addArrangedSubview(sectionHeader(L("Upload Provider")))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        providerPopup = NSPopUpButton()
        providerPopup.addItems(withTitles: [L("imgbb (images only)"), L("Google Drive (images + videos)"), L("S3-Compatible (images + videos)")])
        let currentProvider = UserDefaults.standard.string(forKey: "uploadProvider") ?? "imgbb"
        switch currentProvider {
        case "gdrive": providerPopup.selectItem(at: 1)
        case "s3": providerPopup.selectItem(at: 2)
        default: providerPopup.selectItem(at: 0)
        }
        providerPopup.target = self
        providerPopup.action = #selector(uploadProviderChanged(_:))
        stack.addArrangedSubview(labeledRow(L("Provider:"), controls: [providerPopup]))
        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)

        // ── Google Drive ──
        stack.addArrangedSubview(sectionHeader(L("Google Drive")))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        gdriveStatusLabel = NSTextField(labelWithString: "")
        gdriveStatusLabel.font = NSFont.systemFont(ofSize: 11)
        gdriveStatusLabel.textColor = .secondaryLabelColor
        updateGDriveStatus()

        gdriveSignInBtn = NSButton(title: L("Sign In with Google"), target: self, action: #selector(gdriveSignInTapped(_:)))
        gdriveSignInBtn.bezelStyle = .rounded
        updateGDriveButton()

        stack.addArrangedSubview(labeledRow(L("Account:"), controls: [gdriveStatusLabel]))
        stack.addArrangedSubview(indented(gdriveSignInBtn))
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)

        let gdriveNote = NSTextField(wrappingLabelWithString: L("Files are uploaded to a \"Lumashot\" folder in your Google Drive. Everything stays private — nothing is shared publicly."))
        gdriveNote.font = NSFont.systemFont(ofSize: 10)
        gdriveNote.textColor = .secondaryLabelColor
        stack.addArrangedSubview(indented(gdriveNote))
        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)

        // ── S3-Compatible ──
        stack.addArrangedSubview(sectionHeader(L("S3-Compatible Storage")))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        s3EndpointField = NSTextField()
        s3EndpointField.placeholderString = "https://abc123.r2.cloudflarestorage.com"
        s3EndpointField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        s3EndpointField.stringValue = UserDefaults.standard.string(forKey: "s3Endpoint") ?? ""
        s3EndpointField.target = self
        s3EndpointField.action = #selector(s3FieldChanged(_:))
        stack.addArrangedSubview(labeledRow(L("Endpoint:"), controls: [s3EndpointField]))

        s3RegionField = NSTextField()
        s3RegionField.placeholderString = "auto"
        s3RegionField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        s3RegionField.stringValue = UserDefaults.standard.string(forKey: "s3Region") ?? "auto"
        s3RegionField.target = self
        s3RegionField.action = #selector(s3FieldChanged(_:))
        stack.addArrangedSubview(labeledRow(L("Region:"), controls: [s3RegionField]))

        s3BucketField = NSTextField()
        s3BucketField.placeholderString = "my-bucket"
        s3BucketField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        s3BucketField.stringValue = UserDefaults.standard.string(forKey: "s3Bucket") ?? ""
        s3BucketField.target = self
        s3BucketField.action = #selector(s3FieldChanged(_:))
        stack.addArrangedSubview(labeledRow(L("Bucket:"), controls: [s3BucketField]))

        s3AccessKeyField = NSTextField()
        s3AccessKeyField.placeholderString = "AKIAIOSFODNN7EXAMPLE"
        s3AccessKeyField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        s3AccessKeyField.stringValue = UserDefaults.standard.string(forKey: "s3AccessKeyID") ?? ""
        s3AccessKeyField.target = self
        s3AccessKeyField.action = #selector(s3FieldChanged(_:))
        stack.addArrangedSubview(labeledRow(L("Access Key:"), controls: [s3AccessKeyField]))

        s3SecretKeyField = NSSecureTextField()
        s3SecretKeyField.placeholderString = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        s3SecretKeyField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        s3SecretKeyField.stringValue = UserDefaults.standard.string(forKey: "s3SecretAccessKey") ?? ""
        s3SecretKeyField.target = self
        s3SecretKeyField.action = #selector(s3FieldChanged(_:))
        stack.addArrangedSubview(labeledRow(L("Secret Key:"), controls: [s3SecretKeyField]))

        s3PublicURLField = NSTextField()
        s3PublicURLField.placeholderString = "https://cdn.example.com"
        s3PublicURLField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        s3PublicURLField.stringValue = UserDefaults.standard.string(forKey: "s3PublicURLBase") ?? ""
        s3PublicURLField.target = self
        s3PublicURLField.action = #selector(s3FieldChanged(_:))
        stack.addArrangedSubview(labeledRow(L("Public URL:"), controls: [s3PublicURLField]))
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)

        let publicURLNote = NSTextField(wrappingLabelWithString: L("Base URL for public access. If empty, the S3 endpoint URL is used (may not be publicly accessible)."))
        publicURLNote.font = NSFont.systemFont(ofSize: 10)
        publicURLNote.textColor = .secondaryLabelColor
        stack.addArrangedSubview(indented(publicURLNote))

        s3PathPrefixField = NSTextField()
        s3PathPrefixField.placeholderString = "screenshots/"
        s3PathPrefixField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        s3PathPrefixField.stringValue = UserDefaults.standard.string(forKey: "s3PathPrefix") ?? ""
        s3PathPrefixField.target = self
        s3PathPrefixField.action = #selector(s3FieldChanged(_:))
        stack.addArrangedSubview(labeledRow(L("Path Prefix:"), controls: [s3PathPrefixField]))
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)

        s3TestBtn = NSButton(title: L("Test Connection"), target: self, action: #selector(s3TestTapped(_:)))
        s3TestBtn.bezelStyle = .rounded

        s3StatusLabel = NSTextField(labelWithString: "")
        s3StatusLabel.font = NSFont.systemFont(ofSize: 11)
        s3StatusLabel.textColor = .secondaryLabelColor
        s3StatusLabel.lineBreakMode = .byTruncatingTail

        let testRow = NSStackView(views: [s3TestBtn, s3StatusLabel])
        testRow.orientation = .horizontal
        testRow.spacing = 8
        stack.addArrangedSubview(indented(testRow))
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)

        let s3Note = NSTextField(wrappingLabelWithString: L("Works with AWS S3, Cloudflare R2, MinIO, DigitalOcean Spaces, Backblaze B2, and other S3-compatible services. Supports images and videos."))
        s3Note.font = NSFont.systemFont(ofSize: 10)
        s3Note.textColor = .secondaryLabelColor
        stack.addArrangedSubview(indented(s3Note))
        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)

        // ── imgbb ──
        stack.addArrangedSubview(sectionHeader("imgbb"))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        imgbbKeyField = NSTextField()
        imgbbKeyField.placeholderString = L("Leave empty to use default")
        imgbbKeyField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        imgbbKeyField.target = self
        imgbbKeyField.action = #selector(imgbbKeyChanged(_:))
        if let key = UserDefaults.standard.string(forKey: "imgbbAPIKey") {
            imgbbKeyField.stringValue = key
        }

        stack.addArrangedSubview(labeledRow(L("API key:"), controls: [imgbbKeyField]))
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)

        let imgbbNote = NSTextField(wrappingLabelWithString: L("A shared key is included — get your own free key at imgbb.com/api if you hit rate limits. Images only (no video support)."))
        imgbbNote.font = NSFont.systemFont(ofSize: 10)
        imgbbNote.textColor = .secondaryLabelColor
        stack.addArrangedSubview(indented(imgbbNote))
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        // ── Upload History ──
        stack.addArrangedSubview(sectionHeader(L("Upload History")))
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        // Placeholder for upload history rows
        let historyContainer = NSStackView()
        historyContainer.orientation = .vertical
        historyContainer.alignment = .width
        historyContainer.spacing = 6
        historyContainer.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(historyContainer)
        // Stretch to full stack width
        historyContainer.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        self.uploadsStack = historyContainer

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
