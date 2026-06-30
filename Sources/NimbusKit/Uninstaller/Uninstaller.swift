import Foundation

/// Orchestrates uninstalling an app: list apps, resolve leftovers, remove the
/// selected set through the shared `Remover` (Trash by default). The app bundle
/// is always offered; leftovers are pre-selected except the app's own documents.
public struct Uninstaller: Sendable {
    private let apps = InstalledAppsProvider()
    private let resolver = LeftoverResolver()
    private let remover: Remover

    public init(remover: Remover = Remover()) {
        self.remover = remover
    }

    public func installedApps() -> [InstalledApp] { apps.installedApps() }

    public func leftovers(for app: InstalledApp) async -> [Leftover] {
        await resolver.resolve(for: app)
    }

    /// Remove the chosen leftovers. Defaults to Trash; permanent requires the
    /// explicit confirmation flag, just like every other module.
    public func uninstall(
        _ leftovers: [Leftover],
        permanently: Bool = false,
        onProgress: ProgressHandler? = nil
    ) async -> RemovalReport {
        let items = leftovers.map { RemovalItem(url: $0.url, bytes: $0.bytes) }
        return await remover.remove(
            items,
            mode: permanently ? .permanentDelete : .trash,
            allowPermanent: permanently,
            onProgress: onProgress
        )
    }
}
