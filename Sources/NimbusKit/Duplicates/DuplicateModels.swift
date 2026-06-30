import Foundation

/// One file inside a duplicate group. `Selectable`, so the shared
/// `SelectionStore` drives "keep one, remove the rest" identically to Cleanup.
public struct DuplicateFile: Selectable, Hashable {
    public var id: URL { url }
    public let url: URL
    public let size: Int64
    public let modificationDate: Date?

    public var removalBytes: Int64 { size }

    public init(url: URL, size: Int64, modificationDate: Date? = nil) {
        self.url = url
        self.size = size
        self.modificationDate = modificationDate
    }
}

public struct DuplicateGroup: Identifiable, Sendable, Hashable {
    public var id: String { digest }
    public let digest: String
    public let fileSize: Int64
    public let files: [DuplicateFile]

    /// Bytes freed if all but one copy is removed.
    public var reclaimableBytes: Int64 {
        fileSize * Int64(max(0, files.count - 1))
    }

    public init(digest: String, fileSize: Int64, files: [DuplicateFile]) {
        self.digest = digest
        self.fileSize = fileSize
        self.files = files
    }
}

public struct SimilarPhoto: Selectable, Hashable {
    public var id: URL { url }
    public let url: URL
    public let size: Int64
    public var removalBytes: Int64 { size }
    public init(url: URL, size: Int64) {
        self.url = url
        self.size = size
    }
}

public struct SimilarPhotoGroup: Identifiable, Sendable, Hashable {
    public let id: String
    public let photos: [SimilarPhoto]

    /// Reclaimable if you keep the single largest photo and drop the rest.
    public var reclaimableBytes: Int64 {
        let total = photos.reduce(0) { $0 + $1.size }
        let largest = photos.map(\.size).max() ?? 0
        return total - largest
    }

    public init(id: String, photos: [SimilarPhoto]) {
        self.id = id
        self.photos = photos
    }
}
