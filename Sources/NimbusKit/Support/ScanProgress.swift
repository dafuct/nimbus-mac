import Foundation

/// Progress snapshot emitted during long scans so view models can drive a
/// determinate-ish UI without the scanner knowing anything about SwiftUI.
public struct ScanProgress: Sendable, Equatable {
    public var filesSeen: Int
    public var bytesSeen: Int64
    public var currentPath: String?

    public init(filesSeen: Int = 0, bytesSeen: Int64 = 0, currentPath: String? = nil) {
        self.filesSeen = filesSeen
        self.bytesSeen = bytesSeen
        self.currentPath = currentPath
    }

    public static let zero = ScanProgress()
}

/// A `Sendable` progress sink. Callers pass a closure; scanners call it from a
/// background context, so it must tolerate being invoked off the main actor.
public typealias ProgressHandler = @Sendable (ScanProgress) -> Void
