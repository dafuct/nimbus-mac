import Foundation

// Data-driven safety catalog: rules can ship/override as JSON so the safe-to-delete
// knowledge updates without an app release. The built-in `SafetyCatalog.standard()`
// is the fallback and the seed for export.

extension SafetyDisposition {
    var jsonName: String {
        switch self {
        case .autoSelectable: return "autoSelectable"
        case .selectableManually: return "selectableManually"
        case .protected: return "protected"
        }
    }
    init?(jsonName: String) {
        switch jsonName {
        case "autoSelectable": self = .autoSelectable
        case "selectableManually": self = .selectableManually
        case "protected": self = .protected
        default: return nil
        }
    }
}

/// On-disk rule representation.
public struct SafetyRuleDTO: Codable, Equatable {
    public var id: String
    public var category: String
    public var disposition: String
    public var reason: String
    public var globs: [String]
    public var minOS: [Int]?
    public var maxOS: [Int]?
    public var requiresApp: String?
}

public struct SafetyCatalogDocument: Codable, Equatable {
    public var version: Int
    public var rules: [SafetyRuleDTO]
    public init(version: Int = 1, rules: [SafetyRuleDTO]) {
        self.version = version
        self.rules = rules
    }
}

public extension SafetyCatalog {

    /// Where a user-overridable catalog lives.
    static var defaultURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nimbus", isDirectory: true)
            .appendingPathComponent("safety-catalog.json")
    }

    /// Effective rules: the JSON override if present and valid, else the built-in set.
    static func rules(overrideURL: URL? = defaultURL) -> [SafetyRule] {
        if let overrideURL, let loaded = try? load(from: overrideURL), !loaded.isEmpty {
            return loaded
        }
        return standard()
    }

    /// Decode rules from a JSON document.
    static func load(from url: URL) throws -> [SafetyRule] {
        let data = try Data(contentsOf: url)
        let doc = try JSONDecoder().decode(SafetyCatalogDocument.self, from: data)
        return doc.rules.map { dto in
            SafetyRule(
                id: dto.id,
                category: CleanupCategory(rawValue: dto.category) ?? .unknown,
                disposition: SafetyDisposition(jsonName: dto.disposition) ?? .protected,
                reason: dto.reason,
                matcher: PathMatcher(globs: dto.globs),
                minOS: dto.minOS.map { OSVersion(($0.first ?? 0), ($0.count > 1 ? $0[1] : 0), ($0.count > 2 ? $0[2] : 0)) },
                maxOS: dto.maxOS.map { OSVersion(($0.first ?? 0), ($0.count > 1 ? $0[1] : 0), ($0.count > 2 ? $0[2] : 0)) },
                requiresApp: dto.requiresApp
            )
        }
    }

    /// Encode a rule set to a JSON document (used to seed a user-editable file).
    static func document(from rules: [SafetyRule]) -> SafetyCatalogDocument {
        SafetyCatalogDocument(rules: rules.map { rule in
            SafetyRuleDTO(
                id: rule.id,
                category: rule.category.rawValue,
                disposition: rule.disposition.jsonName,
                reason: rule.reason,
                globs: rule.matcher.globs,
                minOS: rule.minOS.map { [$0.major, $0.minor, $0.patch] },
                maxOS: rule.maxOS.map { [$0.major, $0.minor, $0.patch] },
                requiresApp: rule.requiresApp
            )
        })
    }
}
