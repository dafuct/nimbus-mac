import Foundation

/// The user-editable exclusion list. Persisted as JSON, surfaced in Settings,
/// and converted to an `ExclusionMatcher` that *every* module's scan honors —
/// so "never touch this" means never, everywhere.
public struct ExclusionList: Codable, Sendable, Equatable {
    public var paths: [String]
    public var globs: [String]

    public init(paths: [String] = [], globs: [String] = []) {
        self.paths = paths
        self.globs = globs
    }

    /// The matcher consumed by scanners and the safety engine.
    public var matcher: ExclusionMatcher {
        ExclusionMatcher(literals: paths, globs: globs)
    }

    public mutating func add(path: String) {
        let normalized = (path as NSString).expandingTildeInPath
        if !paths.contains(normalized) { paths.append(normalized) }
    }

    public mutating func remove(path: String) {
        let normalized = (path as NSString).expandingTildeInPath
        paths.removeAll { $0 == normalized }
    }

    // MARK: - Persistence

    public static func load(from url: URL) -> ExclusionList {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode(ExclusionList.self, from: data)
        else { return ExclusionList() }
        return list
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// Default location: ~/Library/Application Support/Nimbus/exclusions.json
    public static var defaultURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nimbus", isDirectory: true)
        return base.appendingPathComponent("exclusions.json")
    }
}
