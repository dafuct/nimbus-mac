import Foundation
import ServiceManagement

/// Login / background-item management via `SMAppService`. The modern API lets an
/// app manage *its own* launch-at-login registration and bundled agents/daemons;
/// it can't enumerate every third-party login item (that's deliberately gated by
/// the OS), so for the full list we deep-link into System Settings.
public struct LoginItemsService: Sendable {
    public init() {}

    public enum State: String, Sendable {
        case enabled, notRegistered, requiresApproval, notFound, unknown
    }

    /// Register the main app to launch at login.
    public func enableLaunchAtLogin() throws {
        try SMAppService.mainApp.register()
    }

    public func disableLaunchAtLogin() throws {
        try SMAppService.mainApp.unregister()
    }

    public func launchAtLoginState() -> State {
        Self.map(SMAppService.mainApp.status)
    }

    /// Manage a bundled helper daemon (by its plist name in Contents/Library/LaunchDaemons).
    public func registerDaemon(plistName: String) throws {
        try SMAppService.daemon(plistName: plistName).register()
    }

    public func daemonState(plistName: String) -> State {
        Self.map(SMAppService.daemon(plistName: plistName).status)
    }

    /// Open the Login Items pane so the user can review every background item.
    @MainActor
    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func map(_ status: SMAppService.Status) -> State {
        switch status {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .unknown
        }
    }
}
