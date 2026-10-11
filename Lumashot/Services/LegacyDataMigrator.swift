import Foundation

/// One-time migration from the pre-rename bundle ID (`com.sw33tlie.macshot.macshot`).
///
/// A sandboxed app's preferences and Application Support live in a container keyed
/// by bundle ID, so renaming to `com.zichao.lumashot` starts with an empty container.
/// On first launch we copy the old container's preferences and data directories
/// over. Reading the old container is allowed by the read-only
/// `temporary-exception.files.home-relative-path` entitlement.
///
/// Not migrated: security-scoped bookmarks (bound to the old app, users re-pick the
/// save folder) and TCC permissions (granted per app by the system).
enum LegacyDataMigrator {
    static let legacyBundleID = "com.sw33tlie.macshot.macshot"
    private static let doneKey = "legacyContainerMigrated"

    /// Application Support subdirectories that hold user data (history, Drive token, local model).
    private static let dataDirectories = ["com.sw33tlie.macshot", "Lumashot"]

    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        // NSHomeDirectory() points inside our own container; resolve the real home.
        guard let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir else { return }
        let legacyData = URL(fileURLWithPath: String(cString: home))
            .appendingPathComponent("Library/Containers/\(legacyBundleID)/Data/Library", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyData.path) else { return }

        // Preferences: copy keys we don't already have.
        let legacyPrefs = legacyData.appendingPathComponent("Preferences/\(legacyBundleID).plist")
        if let data = try? Data(contentsOf: legacyPrefs),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for (key, value) in dict where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
            NSLog("[Lumashot] Migrated \(dict.count) preferences from \(legacyBundleID)")
        }

        // Data directories: copy (APFS clones, so the model doesn't double disk usage).
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        for name in dataDirectories {
            let src = legacyData.appendingPathComponent("Application Support/\(name)", isDirectory: true)
            let dst = appSupport.appendingPathComponent(name, isDirectory: true)
            guard fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) else { continue }
            do {
                try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
                try fm.copyItem(at: src, to: dst)
                NSLog("[Lumashot] Migrated \(name) from \(legacyBundleID)")
            } catch {
                NSLog("[Lumashot] Failed to migrate \(name): \(error.localizedDescription)")
            }
        }
    }
}
