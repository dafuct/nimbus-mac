import Foundation

/// What a module is allowed to do with a candidate path. The ordering encodes
/// caution: a stricter disposition always wins when multiple rules match.
public enum SafetyDisposition: Int, Sendable, Comparable {
    /// Known-safe and low-risk: may be pre-selected by default.
    case autoSelectable = 0
    /// Listed and removable, but the user must opt in — never pre-selected.
    case selectableManually = 1
    /// Never offered for removal (system-critical or actively in use).
    case protected = 2

    public static func < (lhs: SafetyDisposition, rhs: SafetyDisposition) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Categories of removable junk. Drives grouping in the Cleanup UI and lets the
/// catalog be reasoned about per area.
public enum CleanupCategory: String, Sendable, CaseIterable {
    case userCaches = "User Caches"
    case systemLogs = "Logs"
    case languageFiles = "Unused Languages"
    case mailAttachments = "Mail Downloads"
    case xcodeJunk = "Xcode Junk"
    case trash = "Trash"
    case browserData = "Browser Data"
    case appLeftovers = "Application Leftovers"
    case unknown = "Other"
}

/// The engine's verdict for one path. Carries the matched rule id + a
/// human-readable reason so every decision is auditable in the UI.
public struct SafetyDecision: Sendable, Equatable {
    public let disposition: SafetyDisposition
    public let category: CleanupCategory
    public let ruleID: String
    public let reason: String

    public init(disposition: SafetyDisposition, category: CleanupCategory, ruleID: String, reason: String) {
        self.disposition = disposition
        self.category = category
        self.ruleID = ruleID
        self.reason = reason
    }

    public var isRemovable: Bool { disposition != .protected }
    public var isAutoSelectable: Bool { disposition == .autoSelectable }
}
