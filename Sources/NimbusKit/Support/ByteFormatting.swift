import Foundation

public enum ByteFormatting {
    /// Shared byte formatter with Ukrainian units (Б/КБ/МБ/ГБ/ТБ) to match the
    /// Nimbus UI. `ByteCountFormatter` localizes units to the system locale, which
    /// would print "GB" on an English system — so we format explicitly.
    public static func string(_ bytes: Int64) -> String {
        let value = Double(max(0, bytes))
        let kb = 1024.0, mb = kb * 1024, gb = mb * 1024, tb = gb * 1024
        switch value {
        case tb...: return format(value / tb, "ТБ")
        case gb...: return format(value / gb, "ГБ")
        case mb...: return format(value / mb, "МБ")
        case kb...: return format(value / kb, "КБ")
        default: return "\(Int(value)) Б"
        }
    }

    /// One decimal place, trailing ".0" stripped (e.g. "12.4 ГБ", "401 ГБ", "4 КБ").
    private static func format(_ value: Double, _ unit: String) -> String {
        let rounded = (value * 10).rounded() / 10
        let text = rounded == rounded.rounded()
            ? String(format: "%.0f", rounded)
            : String(format: "%.1f", rounded)
        return "\(text) \(unit)"
    }
}

public extension Int64 {
    var formattedBytes: String { ByteFormatting.string(self) }
}
