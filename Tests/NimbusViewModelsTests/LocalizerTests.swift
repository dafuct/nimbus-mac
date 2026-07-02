import XCTest
@testable import NimbusViewModels
import NimbusKit

@MainActor
final class LocalizerTests: XCTestCase {
    private var savedLanguage: String?

    override func setUp() {
        super.setUp()
        savedLanguage = UserDefaults.standard.string(forKey: "appLanguage")
    }
    override func tearDown() {
        if let savedLanguage {
            UserDefaults.standard.set(savedLanguage, forKey: "appLanguage")
        } else {
            UserDefaults.standard.removeObject(forKey: "appLanguage")
        }
        super.tearDown()
    }

    /// The en table must cover every label: an untranslated string falls back
    /// to the Ukrainian source, which this catches as leftover Cyrillic.
    private func assertEnglish(_ s: String, _ context: String) {
        XCTAssertNil(
            s.range(of: "\\p{Cyrillic}", options: .regularExpression),
            "\(context) has no EN translation, shows: \(s)"
        )
    }

    func test_leftoverKinds_allTranslated_inEnglishMode() {
        let loc = Localizer()
        loc.language = .en
        for kind in Leftover.Kind.allCases {
            assertEnglish(loc.leftoverKind(kind), "leftoverKind(.\(kind))")
        }
    }

    func test_cleanupCategories_allTranslated_inEnglishMode() {
        let loc = Localizer()
        loc.language = .en
        for category in CleanupCategory.allCases {
            assertEnglish(loc.category(category), "category(.\(category))")
        }
    }

    func test_ukrainianStaysSourceLanguage() {
        let loc = Localizer()
        loc.language = .uk
        XCTAssertEqual(loc.leftoverKind(.caches), "Кеші")
        XCTAssertEqual(loc.category(.trash), "Кошик")
    }

    func test_languageSwitch_takesEffectImmediately() {
        let loc = Localizer()
        loc.language = .uk
        XCTAssertEqual(loc.leftoverKind(.appBundle), "Застосунок")
        loc.language = .en
        XCTAssertEqual(loc.leftoverKind(.appBundle), "Application")
    }
}
