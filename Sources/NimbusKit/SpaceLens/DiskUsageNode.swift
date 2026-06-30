import Foundation

/// An aggregated node in the disk-usage tree. `size` is the recursive total
/// (the node plus everything beneath it), which is what a treemap renders.
public struct DiskUsageNode: Identifiable, Sendable, Hashable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let size: Int64
    public let children: [DiskUsageNode]

    public init(url: URL, name: String, isDirectory: Bool, size: Int64, children: [DiskUsageNode]) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.children = children
    }

    public var isLeaf: Bool { children.isEmpty }
}

/// Folds the flat `FileEntry` stream (the single traversal) into an aggregated
/// tree. Keeping this separate from the walk means Space Lens reuses the exact
/// traversal every other module uses — no second directory walk just to size things.
public enum DiskUsageTreeBuilder {

    public static func build(root: URL, entries: [FileEntry]) -> DiskUsageNode {
        // Work on the path STRING, not URL.standardizedFileURL/pathComponents per
        // entry — those allocate heavily and made large homes (500k+ files) crawl.
        // The scanner already emits canonical paths under the resolved root, so a
        // string prefix + a single split per entry suffices.
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = canonicalRoot.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let rootNode = MutableNode(url: canonicalRoot, name: canonicalRoot.lastPathComponent, isDirectory: true)

        for entry in entries {
            let path = entry.url.path
            guard path.hasPrefix(prefix) else { continue }
            let parts = path.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: true)
            guard !parts.isEmpty else { continue }

            var node = rootNode
            let lastIndex = parts.count - 1
            for (index, part) in parts.enumerated() {
                let name = String(part)
                // The child URL is materialized only when a node is first created,
                // not on every entry that passes through it.
                let childNode = node.child(name: name, parentURL: node.url, isDirectory: index < lastIndex)
                if index == lastIndex {
                    childNode.ownSize += entry.size
                } else {
                    node = childNode
                }
            }
        }

        return rootNode.frozen()
    }

    final class MutableNode {
        let url: URL
        let name: String
        var isDirectory: Bool
        var ownSize: Int64 = 0
        var children: [String: MutableNode] = [:]

        init(url: URL, name: String, isDirectory: Bool) {
            self.url = url
            self.name = name
            self.isDirectory = isDirectory
        }

        func child(name: String, parentURL: URL, isDirectory: Bool) -> MutableNode {
            if let existing = children[name] {
                if isDirectory { existing.isDirectory = true }
                return existing
            }
            let node = MutableNode(url: parentURL.appendingPathComponent(name), name: name, isDirectory: isDirectory)
            children[name] = node
            return node
        }

        func frozen() -> DiskUsageNode {
            let kids = children.values
                .map { $0.frozen() }
                .sorted { $0.size != $1.size ? $0.size > $1.size : $0.name < $1.name }
            let total = ownSize + kids.reduce(0) { $0 + $1.size }
            return DiskUsageNode(
                url: url,
                name: name,
                isDirectory: isDirectory,
                size: total,
                children: kids
            )
        }
    }
}
