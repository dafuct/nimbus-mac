import Foundation

/// A comparable macOS version, used to gate safety rules per OS release.
public struct OSVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static var current: OSVersion {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return OSVersion(v.majorVersion, v.minorVersion, v.patchVersion)
    }

    public static func < (lhs: OSVersion, rhs: OSVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    // Named anchors for rule gating.
    public static let sonoma = OSVersion(14)
    public static let sequoia = OSVersion(15)
    public static let tahoe = OSVersion(26)
}
