import Foundation
import Darwin

/// The OS-reported memory pressure level (the same notion Activity Monitor's
/// "Memory Pressure" graph reflects). We *read* this — Nimbus never calls `purge`
/// or pretends to "free" RAM.
public enum MemoryPressureLevel: Int, Sendable, Comparable {
    case normal = 1
    case warning = 2
    case critical = 4

    public static func < (lhs: MemoryPressureLevel, rhs: MemoryPressureLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A point-in-time memory snapshot built from `host_statistics64`.
public struct MemorySnapshot: Sendable, Equatable {
    public let total: Int64
    public let free: Int64
    public let active: Int64
    public let inactive: Int64
    public let wired: Int64
    public let compressed: Int64
    public let pressure: MemoryPressureLevel

    /// Roughly "Memory Used" as shown in Activity Monitor: app memory + wired +
    /// compressed. A read-only derived figure, not something we try to reduce.
    public var used: Int64 { max(0, total - free) }

    public var usedFraction: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }
}

/// Reads live memory statistics via the mach host APIs. No privileges required.
public struct MemoryStatisticsReader: Sendable {
    public init() {}

    public func snapshot() -> MemorySnapshot {
        let pageSize = Self.pageSize()
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        let vm = Self.vmStatistics()

        func bytes(_ pages: natural_t) -> Int64 { Int64(pages) * Int64(pageSize) }

        return MemorySnapshot(
            total: total,
            free: bytes(vm?.free_count ?? 0),
            active: bytes(vm?.active_count ?? 0),
            inactive: bytes(vm?.inactive_count ?? 0),
            wired: bytes(vm?.wire_count ?? 0),
            compressed: bytes(vm?.compressor_page_count ?? 0),
            pressure: Self.pressureLevel()
        )
    }

    private static func pageSize() -> vm_size_t {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return size == 0 ? 4096 : size
    }

    private static func vmStatistics() -> vm_statistics64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? stats : nil
    }

    private static func pressureLevel() -> MemoryPressureLevel {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            return MemoryPressureLevel(rawValue: Int(level)) ?? .normal
        }
        return .normal
    }
}
