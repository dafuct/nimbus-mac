import Foundation

/// The privileged operations Nimbus delegates to its SMAppService helper daemon.
/// NimbusKit depends only on this protocol; the app injects an XPC-backed
/// implementation (see Helper/ and docs/DISTRIBUTION.md). Tests inject a fake.
///
/// Every method is something that genuinely needs root and cannot be done from
/// the sandboxed/user context — flushing the DNS cache, reindexing Spotlight on
/// the boot volume, removing system-owned caches/logs.
public protocol PrivilegedHelperClient: Sendable {
    /// Is the helper installed and approved?
    func isInstalled() async -> Bool

    /// Register the helper (SMAppService). Prompts the user for approval. Requires
    /// a Developer ID-signed build — fails on ad-hoc/unsigned builds.
    func install() async throws

    /// Unregister the helper.
    func uninstall() async throws

    /// Flush the DNS cache (`dscacheutil -flushcache` + signal mDNSResponder).
    func flushDNSCache() async throws

    /// Reindex Spotlight on a volume (`mdutil -E`). `/` requires root.
    func reindexSpotlight(volume: String) async throws

    /// Remove system-owned paths the user account can't touch. The helper applies
    /// the *same* safety guard before acting — it never blindly trusts the client.
    func removeSystemPaths(_ paths: [String], permanently: Bool) async throws -> [String]
}

/// A no-privilege fallback used until the helper is installed: privileged actions
/// throw `.privilegedHelperUnavailable` so the UI can prompt for installation,
/// while non-privileged callers can still detect availability.
public struct UnavailableHelperClient: PrivilegedHelperClient {
    public init() {}
    public func isInstalled() async -> Bool { false }
    public func install() async throws { throw NimbusError.privilegedHelperUnavailable }
    public func uninstall() async throws { throw NimbusError.privilegedHelperUnavailable }
    public func flushDNSCache() async throws { throw NimbusError.privilegedHelperUnavailable }
    public func reindexSpotlight(volume: String) async throws { throw NimbusError.privilegedHelperUnavailable }
    public func removeSystemPaths(_ paths: [String], permanently: Bool) async throws -> [String] {
        throw NimbusError.privilegedHelperUnavailable
    }
}
