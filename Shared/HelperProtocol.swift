import Foundation

/// XPC contract between the app (client) and the privileged helper (daemon).
/// Compiled into BOTH targets (shared file membership in Xcode). Uses `@objc` +
/// reply blocks because NSXPC requires Objective-C-compatible signatures; the
/// app wraps these in async/await (see XPCHelperClient).
///
/// The mach service name must match the helper's launchd plist `MachServices`
/// key and the helper bundle identifier.
@objc public protocol NimbusHelperProtocol {
    /// Liveness/handshake — returns the helper's version string.
    func version(reply: @escaping (String) -> Void)

    /// Flush DNS cache. reply error is nil on success.
    func flushDNSCache(reply: @escaping (String?) -> Void)

    /// Reindex Spotlight on a volume. reply error is nil on success.
    func reindexSpotlight(volume: String, reply: @escaping (String?) -> Void)

    /// Remove system-owned paths. The helper re-validates every path against its
    /// OWN safety guard before acting — it never blindly trusts the client.
    /// Replies with the list of paths actually removed, plus an optional error.
    func removeSystemPaths(_ paths: [String], permanently: Bool, reply: @escaping ([String], String?) -> Void)
}

public enum NimbusHelperInfo {
    /// Keep in sync with the helper bundle id and its launchd plist name.
    public static let machServiceName = "com.nimbus.app.helper"
    public static let version = "1.0.0"
}
