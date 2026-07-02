import Foundation

public struct Leftover: Selectable, Hashable {
    public var id: URL { url }
    public let url: URL
    public let bytes: Int64
    public let kind: Kind
    public var removalBytes: Int64 { bytes }

    public enum Kind: String, Sendable, CaseIterable {
        case appBundle = "Application"
        case caches = "Caches"
        case preferences = "Preferences"
        case appSupport = "Application Support"
        case containers = "Containers"
        case savedState = "Saved State"
        case launchAgents = "Launch Agents"
        case logs = "Logs"
        case temp = "Temporary Files"
        case other = "Other"
    }
}

/// Resolves the on-disk footprint an app leaves across `~/Library` and the
/// per-user `/var/folders` cache/temp dirs from its bundle id and name. The
/// candidate locations are the well-known ones every macOS app uses; we check
/// existence and size each via the shared scanner — no bespoke directory walk
/// here.
public struct LeftoverResolver: Sendable {
    private let library: URL
    private let darwinCacheDir: URL?
    private let darwinTempDir: URL?

    public init() {
        self.init(
            library: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library"),
            darwinCacheDir: Self.darwinUserDir(_CS_DARWIN_USER_CACHE_DIR),
            darwinTempDir: Self.darwinUserDir(_CS_DARWIN_USER_TEMP_DIR)
        )
    }

    /// Injectable roots for tests.
    init(library: URL, darwinCacheDir: URL?, darwinTempDir: URL?) {
        self.library = library
        self.darwinCacheDir = darwinCacheDir
        self.darwinTempDir = darwinTempDir
    }

    /// Per-user dir under `/var/folders` (`getconf DARWIN_USER_CACHE_DIR` / `…_TEMP_DIR`).
    /// Sandbox-free apps drop `<bundle id>` folders there that a `~/Library`-only
    /// sweep misses.
    static func darwinUserDir(_ name: Int32) -> URL? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(name, &buffer, buffer.count)
        guard length > 0, length <= buffer.count else { return nil }
        return URL(fileURLWithPath: String(cString: buffer), isDirectory: true)
    }

    public func resolve(for app: InstalledApp) async -> [Leftover] {
        let lib = library
        let id = app.bundleID
        let name = app.name

        // (relativePath, kind). Both bundle-id and name variants are probed.
        var candidates: [(String, Leftover.Kind)] = [
            ("Caches/\(id)", .caches),
            ("Caches/\(name)", .caches),
            ("HTTPStorages/\(id)", .caches),
            ("Preferences/\(id).plist", .preferences),
            ("Application Support/\(id)", .appSupport),
            ("Application Support/\(name)", .appSupport),
            ("Containers/\(id)", .containers),
            ("Saved Application State/\(id).savedState", .savedState),
            ("Logs/\(name)", .logs),
            ("Logs/\(id)", .logs),
            ("WebKit/\(id)", .caches),
            ("Cookies/\(id).binarycookies", .other),
        ]
        candidates.append(("LaunchAgents/\(id).plist", .launchAgents))

        var probes: [(URL, Leftover.Kind)] = candidates.map { (lib.appendingPathComponent($0.0), $0.1) }
        if let dir = darwinCacheDir { probes.append((dir.appendingPathComponent(id), .caches)) }
        if let dir = darwinTempDir { probes.append((dir.appendingPathComponent(id), .temp)) }

        var leftovers: [Leftover] = []
        // The app bundle itself.
        leftovers.append(Leftover(url: app.url, bytes: await sizeOf(app.url), kind: .appBundle))

        for (url, kind) in probes {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let size = await sizeOf(url)
            leftovers.append(Leftover(url: url, bytes: size, kind: kind))
        }

        // Group Containers and LaunchAgents with the id embedded (e.g. group.<id>).
        leftovers.append(contentsOf: await fuzzyMatches(in: lib.appendingPathComponent("Group Containers"), containing: id, kind: .containers))

        return leftovers
    }

    private func fuzzyMatches(in dir: URL, containing needle: String, kind: Leftover.Kind) async -> [Leftover] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [Leftover] = []
        for url in entries where url.lastPathComponent.contains(needle) {
            result.append(Leftover(url: url, bytes: await sizeOf(url), kind: kind))
        }
        return result
    }

    /// Recursive on-disk size, reusing the single shared traversal.
    private func sizeOf(_ url: URL) async -> Int64 {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if !isDir.boolValue {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        let entries = (try? await FileSystemScanner.collect(root: url, options: ScanOptions(skipPackages: false))) ?? []
        return entries.reduce(0) { $0 + $1.size }
    }
}
