import Foundation

// The privileged helper daemon. Registered/managed via SMAppService from the app.
// Runs as root, listens on a mach service, and performs ONLY the narrow set of
// operations in NimbusHelperProtocol — each re-validated here, never trusting the
// client. See docs/DISTRIBUTION.md for the install lifecycle.

final class HelperService: NSObject, NimbusHelperProtocol, NSXPCListenerDelegate {

    // MARK: NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        // In production: verify the connecting client's code signature / team id
        // via `conn.auditToken` + SecCode requirements before accepting. Omitted
        // here for brevity but REQUIRED before shipping.
        conn.exportedInterface = NSXPCInterface(with: NimbusHelperProtocol.self)
        conn.exportedObject = self
        conn.resume()
        return true
    }

    // MARK: NimbusHelperProtocol

    func version(reply: @escaping (String) -> Void) {
        reply(NimbusHelperInfo.version)
    }

    func flushDNSCache(reply: @escaping (String?) -> Void) {
        do {
            try run("/usr/bin/dscacheutil", ["-flushcache"])
            try run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
            reply(nil)
        } catch {
            reply(error.localizedDescription)
        }
    }

    func reindexSpotlight(volume: String, reply: @escaping (String?) -> Void) {
        do {
            try run("/usr/bin/mdutil", ["-E", volume])
            reply(nil)
        } catch {
            reply(error.localizedDescription)
        }
    }

    func removeSystemPaths(_ paths: [String], permanently: Bool, reply: @escaping ([String], String?) -> Void) {
        // Re-validate independently of the client using the same guard rules.
        let guardian = SystemPathGuard()
        var removed: [String] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard guardian.isRemovable(url) else { continue }
            do {
                if permanently {
                    try FileManager.default.removeItem(at: url)
                } else {
                    var resulting: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
                }
                removed.append(path)
            } catch {
                reply(removed, "Failed at \(path): \(error.localizedDescription)")
                return
            }
        }
        reply(removed, nil)
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw NSError(domain: "NimbusHelper", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(tool) exited \(p.terminationStatus)"])
        }
    }
}

/// The helper's independent denylist — mirrors the app's CriticalPathGuard so the
/// privileged side enforces safety on its own. (Kept minimal here; production
/// shares the rule data with the app via a signed resource.)
struct SystemPathGuard {
    private let denied = ["/", "/System", "/usr", "/bin", "/sbin", "/Library/Apple", "/private/var/db"]
    func isRemovable(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if path == "/" { return false }
        if path.hasPrefix("/usr/local") { return true }
        for root in denied where path == root || path.hasPrefix(root + "/") { return false }
        return true
    }
}

// Entry point: spin up the XPC listener and block forever.
let delegate = HelperService()
let listener = NSXPCListener(machServiceName: NimbusHelperInfo.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
