import Foundation
import ServiceManagement
import NimbusKit

/// The real, XPC-backed `PrivilegedHelperClient`. Manages the helper's lifecycle
/// via `SMAppService.daemon` and bridges the reply-block XPC protocol to async/await.
public final class XPCHelperClient: PrivilegedHelperClient, @unchecked Sendable {
    private let plistName: String
    private let machServiceName: String

    public init(
        plistName: String = "com.nimbus.app.helper.plist",
        machServiceName: String = NimbusHelperInfo.machServiceName
    ) {
        self.plistName = plistName
        self.machServiceName = machServiceName
    }

    private var service: SMAppService { SMAppService.daemon(plistName: plistName) }

    /// Register (and prompt for approval). Requires a Developer ID-signed build.
    public func install() async throws {
        try service.register()
    }

    public func uninstall() async throws {
        try await service.unregister()
    }

    public func isInstalled() async -> Bool {
        service.status == .enabled
    }

    public func flushDNSCache() async throws {
        try await withProxy { proxy, continuation in
            proxy.flushDNSCache { error in
                if let error { continuation.resume(throwing: NimbusError.systemTaskFailed(tool: "dscacheutil", status: -1, message: error)) }
                else { continuation.resume() }
            }
        }
    }

    public func reindexSpotlight(volume: String) async throws {
        try await withProxy { proxy, continuation in
            proxy.reindexSpotlight(volume: volume) { error in
                if let error { continuation.resume(throwing: NimbusError.systemTaskFailed(tool: "mdutil", status: -1, message: error)) }
                else { continuation.resume() }
            }
        }
    }

    public func removeSystemPaths(_ paths: [String], permanently: Bool) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let connection = makeConnection()
            connection.resume()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ err in
                continuation.resume(throwing: err)
            }) as? NimbusHelperProtocol else {
                continuation.resume(throwing: NimbusError.privilegedHelperUnavailable)
                return
            }
            proxy.removeSystemPaths(paths, permanently: permanently) { removed, error in
                if let error { continuation.resume(throwing: NimbusError.systemTaskFailed(tool: "remove", status: -1, message: error)) }
                else { continuation.resume(returning: removed) }
                connection.invalidate()
            }
        }
    }

    // MARK: - XPC plumbing

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: NimbusHelperProtocol.self)
        return connection
    }

    private func withProxy(
        _ body: @escaping (NimbusHelperProtocol, CheckedContinuation<Void, Error>) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let connection = makeConnection()
            connection.resume()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ err in
                continuation.resume(throwing: err)
            }) as? NimbusHelperProtocol else {
                continuation.resume(throwing: NimbusError.privilegedHelperUnavailable)
                return
            }
            body(proxy, continuation)
        }
    }
}
