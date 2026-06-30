import Foundation

/// The last line of defense. Even an *explicitly user-confirmed* removal is
/// refused for these paths — this is what separates a safe cleaner from one that
/// bricks the OS. Consulted by `Remover` before every destructive operation,
/// regardless of which module requested it.
public struct CriticalPathGuard: Sendable {

    /// Roots that must never be removed (or have their direct children removed).
    private static let protectedRoots: [String] = [
        "/",
        "/System",
        "/usr",            // /usr/local is fine, handled below as an exception
        "/bin",
        "/sbin",
        "/Library/Apple",
        "/private/var/db",
        "/cores",
        "/Applications",   // an app *bundle* may be removed; the folder may not
    ]

    /// Exceptions carved out of the protected roots above.
    private static let allowedExceptions: [String] = [
        "/usr/local",
    ]

    public init() {}

    /// Home directory and its top-level Library are protected as *containers*:
    /// you may delete things inside ~/Library/Caches, never ~/Library itself.
    private var homeProtected: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [home, "\(home)/Library", "\(home)/Documents", "\(home)/Desktop"]
    }

    /// Returns true if `url` is too dangerous to remove under any circumstances.
    public func isProtected(_ url: URL) -> Bool {
        let path = PathCanonical.firmlink(url.path)

        if path == "/" { return true }

        for exception in Self.allowedExceptions where path == exception || path.hasPrefix(exception + "/") {
            return false
        }

        for root in Self.protectedRoots {
            // The root itself, or a *direct child* of certain roots, is protected.
            if path == root { return true }
        }
        for root in Self.protectedRoots where path.hasPrefix(root + "/") {
            // Inside /System, /usr, /bin, /sbin: always protected.
            if ["/System", "/usr", "/bin", "/sbin", "/Library/Apple", "/private/var/db"].contains(root) {
                return true
            }
        }
        if homeProtected.contains(path) { return true }

        return false
    }
}
