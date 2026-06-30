import Foundation

public struct CleanupItem: Selectable, Hashable {
    public var id: URL { url }
    public let url: URL
    public let bytes: Int64
    public let category: CleanupCategory
    public let reason: String
    public let autoSelected: Bool
    public var removalBytes: Int64 { bytes }
}

public struct CleanupGroup: Identifiable, Sendable {
    public var id: String { category.rawValue }
    public let category: CleanupCategory
    public let items: [CleanupItem]
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}

/// Finds removable system/user junk by enumerating known cleanable base
/// directories one level deep and asking the `SafetyRuleEngine` about each entry.
/// Nothing is included unless a rule deems it removable; auto-selectable items
/// are pre-ticked, manual ones are listed but unticked. Removal goes through the
/// shared `Remover` (Trash by default), so Cleanup adds no destructive logic.
public struct CleanupScanner: Sendable {
    private let engine: SafetyRuleEngine

    public init(engine: SafetyRuleEngine) {
        self.engine = engine
    }

    /// Base directories whose direct children are candidate cleanup items.
    public static func defaultBases() -> [URL] {
        let lib = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            lib.appendingPathComponent("Caches"),
            lib.appendingPathComponent("Logs"),
            home.appendingPathComponent(".Trash"),
            lib.appendingPathComponent("Developer/Xcode/DerivedData"),
            lib.appendingPathComponent("Developer/Xcode/iOS DeviceSupport"),
            lib.appendingPathComponent("Developer/CoreSimulator/Caches"),
            lib.appendingPathComponent("Containers/com.apple.mail/Data/Library/Mail Downloads"),
        ]
    }

    public func scan(
        bases: [URL] = CleanupScanner.defaultBases(),
        onProgress: ProgressHandler? = nil
    ) async throws -> [CleanupGroup] {
        var byCategory: [CleanupCategory: [CleanupItem]] = [:]
        var progress = ScanProgress.zero

        for base in bases {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: base, includingPropertiesForKeys: nil, options: []
            ) else { continue }

            for child in children {
                try Task.checkCancellation()
                let decision = engine.evaluate(child)
                guard decision.isRemovable else { continue }

                let size = await sizeOf(child)
                let item = CleanupItem(
                    url: child,
                    bytes: size,
                    category: decision.category,
                    reason: decision.reason,
                    autoSelected: decision.isAutoSelectable
                )
                byCategory[decision.category, default: []].append(item)

                progress.filesSeen += 1
                progress.bytesSeen += size
                progress.currentPath = child.path
                onProgress?(progress)
            }
        }

        return byCategory
            .map { CleanupGroup(category: $0.key, items: $0.value.sorted { $0.bytes > $1.bytes }) }
            .sorted { $0.totalBytes > $1.totalBytes }
    }

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
