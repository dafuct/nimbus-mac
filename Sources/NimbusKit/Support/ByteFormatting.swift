import Foundation

public enum ByteFormatting {
    /// Shared, language-aware byte formatter. Units follow the app language
    /// (Б/КБ/МБ/ГБ/ТБ in Ukrainian, B/KB/MB/GB/TB in English). We format explicitly
    /// because `ByteCountFormatter` keys off the system locale, not the in-app one.
    ///
    /// The language is read from the same `appLanguage` UserDefaults key the
    /// presentation-layer Localizer writes, falling back to the system language —
    /// so a live language switch re-renders views and they re-call this with the
    /// new units.
    public static func string(_ bytes: Int64) -> String {
        let units = isEnglish() ? ["B", "KB", "MB", "GB", "TB"] : ["Б", "КБ", "МБ", "ГБ", "ТБ"]
        let value = Double(max(0, bytes))
        let kb = 1024.0, mb = kb * 1024, gb = mb * 1024, tb = gb * 1024
        switch value {
        case tb...: return format(value / tb, units[4])
        case gb...: return format(value / gb, units[3])
        case mb...: return format(value / mb, units[2])
        case kb...: return format(value / kb, units[1])
        default: return "\(Int(value)) \(units[0])"
        }
    }

    private static func isEnglish() -> Bool {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage") {
            return saved == "en"
        }
        return !(Locale.preferredLanguages.first ?? "en").hasPrefix("uk")
    }

    /// One decimal place, trailing ".0" stripped (e.g. "12.4 GB", "401 GB", "4 KB").
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
