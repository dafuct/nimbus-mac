import Foundation

public struct InstalledApp: Identifiable, Sendable, Hashable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public let url: URL
    public let version: String?

    public init(bundleID: String, name: String, url: URL, version: String?) {
        self.bundleID = bundleID
        self.name = name
        self.url = url
        self.version = version
    }
}

/// Discovers installed applications by scanning the standard app directories and
/// reading each bundle's Info.plist. The set of bundle IDs also feeds the safety
/// engine's app-gating (so Xcode rules only activate when Xcode is present).
public struct InstalledAppsProvider: Sendable {
    public init() {}

    public func searchLocations() -> [URL] {
        let fm = FileManager.default
        var dirs = [URL(fileURLWithPath: "/Applications"),
                    URL(fileURLWithPath: "/Applications/Utilities")]
        dirs.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"))
        return dirs
    }

    public func installedApps() -> [InstalledApp] {
        let fm = FileManager.default
        var apps: [String: InstalledApp] = [:]
        for dir in searchLocations() {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for url in entries where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                apps[id] = InstalledApp(bundleID: id, name: name, url: url, version: version)
            }
        }
        return apps.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func installedBundleIDs() -> Set<String> {
        Set(installedApps().map(\.bundleID))
    }
}
