import Cocoa
import Carbon
import UniformTypeIdentifiers
import AVFoundation
import WebP

extension AppDelegate {
    // MARK: - Upload

    func uploadImage(_ image: NSImage) {
        showUploadProgress(image: image)
    }

    @objc func pinFromHistory(_ notification: Notification) {
        guard let image = notification.object as? NSImage else { return }
        showPin(image: image)
    }

    func showPin(image: NSImage) {
        let pin = PinWindowController(image: image)
        pin.delegate = self
        pin.show()
        pinControllers.append(pin)
    }

    func showUploadProgress(image: NSImage) {
        uploadToastController?.dismiss()
        let toast = UploadToastController()
        uploadToastController = toast
        toast.onDismiss = { [weak self] in
            self?.uploadToastController = nil
        }
        toast.show(status: "Uploading...")

        let provider = UserDefaults.standard.string(forKey: "uploadProvider") ?? "imgbb"

        if provider == "gdrive" && !GoogleDriveUploader.shared.isSignedIn {
            toast.showError(message: "Google Drive not signed in")
            return
        }

        if provider == "s3" && !S3Uploader.shared.isConfigured {
            toast.showError(message: "S3 not configured — check Settings")
            return
        }

        if provider == "gdrive" {
            GoogleDriveUploader.shared.uploadImage(image) { result in
                switch result {
                case .success(let link):
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(link, forType: .string)
                    toast.showSuccess(link: link, deleteURL: "")
                case .failure(let error):
                    toast.showError(message: error.localizedDescription)
                }
            }
        } else if provider == "s3" {
            S3Uploader.shared.onProgress = { fraction in
                toast.updateProgress(fraction)
            }
            S3Uploader.shared.uploadImage(image) { result in
                switch result {
                case .success(let link):
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(link, forType: .string)
                    toast.showSuccess(link: link, deleteURL: "")
                case .failure(let error):
                    toast.showError(message: error.localizedDescription)
                }
            }
        } else {
            ImageUploader.upload(image: image) { result in
                switch result {
                case .success(let uploadResult):
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(uploadResult.link, forType: .string)

                    var uploads = UserDefaults.standard.array(forKey: "imgbbUploads") as? [[String: String]] ?? []
                    uploads.append([
                        "deleteURL": uploadResult.deleteURL,
                        "link": uploadResult.link,
                    ])
                    UserDefaults.standard.set(uploads, forKey: "imgbbUploads")

                    toast.showSuccess(link: uploadResult.link, deleteURL: uploadResult.deleteURL)
                case .failure(let error):
                    toast.showError(message: error.localizedDescription)
                }
            }
        }
    }

}
