import Foundation

/// Thin async wrapper around `Process` for the handful of places macOS only
/// exposes functionality via a CLI tool (mdutil, dscacheutil, ps). Kept in one
/// place so error handling and the run contract aren't duplicated per call site.
public struct ProcessRunner: Sendable {
    public struct Result: Sendable {
        public let status: Int32
        public let stdout: String
        public let stderr: String
    }

    public init() {}

    public func run(_ launchPath: String, _ arguments: [String]) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            // Run on a background queue and DRAIN the pipes with readToEnd() before
            // waitUntilExit(). Reading only in terminationHandler deadlocks once a
            // child's stdout exceeds the ~64 KiB pipe buffer (e.g. `ps -ax`): the
            // child blocks on a full pipe, so it never terminates and the handler
            // never fires.
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = arguments
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let outData = (try? out.fileHandleForReading.readToEnd()) ?? Data()
                let errData = (try? err.fileHandleForReading.readToEnd()) ?? Data()
                process.waitUntilExit()

                continuation.resume(returning: Result(
                    status: process.terminationStatus,
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errData, as: UTF8.self)
                ))
            }
        }
    }
}
