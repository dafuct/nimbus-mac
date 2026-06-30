import Foundation

/// Domain-level errors. Service/domain code throws these; the presentation layer
/// maps them to user-facing copy. We never leak `HTTP`/servlet/UI types here.
public enum NimbusError: Error, Equatable, Sendable {
    /// A root path could not be read at all (often missing Full Disk Access).
    case rootUnreadable(URL, underlying: String)
    /// The user (or a parent `Task`) cancelled a long-running scan.
    case cancelled
    /// A destructive operation was blocked because the target isn't on a
    /// known-safe path and wasn't explicitly confirmed.
    case refusedUnsafePath(URL)
    /// The privileged helper is required but not installed/approved.
    case privilegedHelperUnavailable
    /// A system tool (mdutil, dscacheutil, …) exited non-zero.
    case systemTaskFailed(tool: String, status: Int32, message: String)

    public var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

extension NimbusError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .rootUnreadable(url, underlying):
            return "Couldn’t read “\(url.path)”. \(underlying)"
        case .cancelled:
            return "The operation was cancelled."
        case let .refusedUnsafePath(url):
            return "Refused to remove “\(url.path)”: it isn’t on a known-safe path."
        case .privilegedHelperUnavailable:
            return "This action needs the Nimbus privileged helper, which isn’t installed yet."
        case let .systemTaskFailed(tool, status, message):
            return "\(tool) failed (exit \(status)). \(message)"
        }
    }
}
