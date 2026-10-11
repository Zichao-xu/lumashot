import AppKit
import Foundation

@MainActor
final class GitHubReleaseUpdateChecker {
    static let automaticChecksEnabledKey = "githubReleaseChecksEnabled"

    private static let checkInterval: TimeInterval = 10 * 60
    private let releasesURL = URL(string: "https://api.github.com/repos/Zichao-xu/lumashot/releases")!

    private var timer: Timer?
    private var task: URLSessionDataTask?
    private var isChecking = false
    private var lastAutomaticallyPresentedTag: String?

    var automaticChecksEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.automaticChecksEnabledKey) as? Bool ?? true
    }

    func start() {
        guard timer == nil else { return }
        if automaticChecksEnabled {
            checkNow(presentNoUpdate: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.automaticChecksEnabled {
                self.checkNow(presentNoUpdate: false)
            }
        }
    }

    func checkNow(presentNoUpdate: Bool) {
        guard !isChecking else { return }
        isChecking = true

        var request = URLRequest(url: releasesURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        task?.cancel()
        task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            Task { @MainActor [weak self] in
                self?.finishCheck(data: data, error: error, presentNoUpdate: presentNoUpdate)
            }
        }
        task?.resume()
    }

    private var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        return "Lumashot/\(version)"
    }

    private var currentVersion: ReleaseVersion? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }
        return ReleaseVersion(raw)
    }

    private func finishCheck(data: Data?, error: Error?, presentNoUpdate: Bool) {
        isChecking = false

        if let error = error as NSError?, error.code != NSURLErrorCancelled {
            if presentNoUpdate {
                showMessage(title: L("Unable to Check for Updates"), text: error.localizedDescription)
            }
            return
        }

        guard let data else {
            if presentNoUpdate {
                showMessage(title: L("Unable to Check for Updates"), text: L("GitHub did not return update information."))
            }
            return
        }

        do {
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            if let update = newestUpdate(in: releases) {
                if presentNoUpdate || update.release.tagName != lastAutomaticallyPresentedTag {
                    lastAutomaticallyPresentedTag = update.release.tagName
                    showUpdate(update)
                }
            } else if presentNoUpdate {
                showMessage(title: L("Lumashot is Up to Date"), text: L("You are using the latest available Lumashot release."))
            }
        } catch {
            if presentNoUpdate {
                showMessage(title: L("Unable to Check for Updates"), text: error.localizedDescription)
            }
        }
    }

    private func newestUpdate(in releases: [GitHubRelease]) -> ReleaseCandidate? {
        guard let currentVersion else { return nil }
        let includePrereleases = currentVersion.isPrerelease

        return releases.compactMap { release -> ReleaseCandidate? in
            guard !release.draft else { return nil }
            guard includePrereleases || !release.prerelease else { return nil }
            guard let version = ReleaseVersion(release.tagName), version > currentVersion else { return nil }
            guard let asset = release.preferredDMGAsset(forVersion: version.rawWithoutLeadingV) else { return nil }
            return ReleaseCandidate(release: release, version: version, asset: asset)
        }
        .max { $0.version < $1.version }
    }

    private func showUpdate(_ update: ReleaseCandidate) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(format: L("Lumashot %@ is Available"), update.release.tagName)
        alert.informativeText = L("A newer Lumashot release is available on GitHub. Download the DMG to install it manually.")
        alert.addButton(withTitle: L("Download DMG"))
        alert.addButton(withTitle: L("Later"))

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(update.asset.browserDownloadURL)
        }
    }

    private func showMessage(title: String, text: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: L("OK"))
        alert.runModal()
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAsset]

    func preferredDMGAsset(forVersion version: String) -> GitHubReleaseAsset? {
        let exactName = "Lumashot-darwin-arm64-\(version).dmg"
        if let exact = assets.first(where: { $0.name == exactName }) {
            return exact
        }
        return assets.first { asset in
            asset.name.hasSuffix(".dmg") &&
            asset.name.localizedCaseInsensitiveContains("Lumashot") &&
            asset.name.contains(version)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case draft
        case prerelease
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private struct ReleaseCandidate {
    let release: GitHubRelease
    let version: ReleaseVersion
    let asset: GitHubReleaseAsset
}

private struct ReleaseVersion: Comparable {
    let rawWithoutLeadingV: String
    let numbers: [Int]
    let prereleaseIdentifiers: [String]

    init?(_ raw: String) {
        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("v") || normalized.hasPrefix("V") {
            normalized.removeFirst()
        }
        let parts = normalized.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numericParts = parts[0].split(separator: ".").compactMap { Int($0) }
        guard numericParts.count >= 3 else { return nil }

        rawWithoutLeadingV = normalized
        numbers = numericParts
        prereleaseIdentifiers = parts.count > 1
            ? parts[1].split(separator: ".").map(String.init)
            : []
    }

    var isPrerelease: Bool {
        !prereleaseIdentifiers.isEmpty
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        let count = max(lhs.numbers.count, rhs.numbers.count)
        for index in 0..<count {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right { return left < right }
        }

        if lhs.prereleaseIdentifiers.isEmpty && rhs.prereleaseIdentifiers.isEmpty { return false }
        if lhs.prereleaseIdentifiers.isEmpty { return false }
        if rhs.prereleaseIdentifiers.isEmpty { return true }

        return comparePrerelease(lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers) < 0
    }

    private static func comparePrerelease(_ lhs: [String], _ rhs: [String]) -> Int {
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            guard index < lhs.count else { return -1 }
            guard index < rhs.count else { return 1 }

            let left = lhs[index]
            let right = rhs[index]
            if left == right { continue }

            let leftNumber = Int(left)
            let rightNumber = Int(right)
            switch (leftNumber, rightNumber) {
            case let (l?, r?):
                return l == r ? 0 : (l < r ? -1 : 1)
            case (_?, nil):
                return -1
            case (nil, _?):
                return 1
            case (nil, nil):
                return left.localizedStandardCompare(right) == .orderedAscending ? -1 : 1
            }
        }
        return 0
    }
}
