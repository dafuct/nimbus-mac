import Foundation
import Observation
import NimbusKit

/// App language. Ukrainian is the source language (keys ARE the Ukrainian
/// strings), English is the translation.
public enum AppLanguage: String, Sendable, CaseIterable {
    case uk, en
    public var displayName: String { self == .uk ? "Українська" : "English" }
}

/// Central localization. Call `loc("<ukrainian>")` anywhere — it returns the
/// English translation when the language is English, and the Ukrainian source
/// otherwise (safe fallback for any untranslated string). `@Observable`, so
/// changing `language` instantly re-renders every view that called `loc`.
///
/// View models keep producing Ukrainian strings; the views localize them via
/// `loc(...)` since the Ukrainian text is the dictionary key. Enums whose raw
/// values are English (CleanupCategory, Leftover.Kind) use the dedicated maps.
@MainActor
@Observable
public final class Localizer {
    public var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }

    public init() {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"),
           let lang = AppLanguage(rawValue: saved) {
            language = lang
        } else {
            let sys = Locale.preferredLanguages.first ?? "en"
            language = sys.hasPrefix("uk") ? .uk : .en
        }
    }

    /// Static string.
    public func callAsFunction(_ uk: String) -> String { resolve(uk) }

    /// Format string with arguments (e.g. `loc("%lld копій · %@ кожна", n, size)`).
    public func callAsFunction(_ ukFormat: String, _ args: CVarArg...) -> String {
        String(format: resolve(ukFormat), arguments: args)
    }

    private func resolve(_ uk: String) -> String {
        language == .en ? (Self.en[uk] ?? uk) : uk
    }

    /// Cleanup category display (enum raw values are English).
    public func category(_ c: CleanupCategory) -> String {
        let map: [CleanupCategory: String] = [
            .userCaches: "Кеші застосунків", .systemLogs: "Системні логи",
            .languageFiles: "Невикористовувані мови", .mailAttachments: "Поштові вкладення",
            .xcodeJunk: "Xcode-сміття", .trash: "Кошик", .browserData: "Дані браузера",
            .appLeftovers: "Залишки застосунків", .unknown: "Інше",
        ]
        return resolve(map[c] ?? c.rawValue)
    }

    /// Uninstaller leftover-kind display (enum raw values are English).
    public func leftoverKind(_ k: Leftover.Kind) -> String {
        let map: [Leftover.Kind: String] = [
            .appBundle: "Застосунок", .caches: "Кеші", .preferences: "Налаштування",
            .appSupport: "Application Support", .containers: "Контейнери",
            .savedState: "Збережений стан", .launchAgents: "Агенти запуску",
            .logs: "Логи", .other: "Інше",
        ]
        return resolve(map[k] ?? k.rawValue)
    }

    // MARK: - Translation table (Ukrainian → English)

    static let en: [String: String] = [
        // Sidebar / chrome
        "Догляд за Mac": "Mac care",
        "Очищення": "Cleanup",
        "Стан системи": "System Health",
        "Налаштування": "Settings",
        "Системний мотлох": "System Junk",
        "Дублікати та фото": "Duplicates & Photos",
        "Застосунки": "Applications",
        "Обслуговування": "Maintenance",
        "12.4 ГБ": "12.4 GB",
        "8.7 ГБ": "8.7 GB",

        // Smart Scan
        "Готово до сканування": "Ready to scan",
        "Сканувати": "Scan",
        "Перевірити весь Mac": "Check your whole Mac",
        "Готові оглянути ваш Mac": "Ready to review your Mac",
        "Nimbus перевірить усі модулі й покаже, що можна безпечно прибрати. Нічого не видаляється без вашого підтвердження.":
            "Nimbus checks every module and shows what's safe to remove. Nothing is deleted without your confirmation.",
        "Сканування…": "Scanning…",
        "Скасувати": "Cancel",
        "Перевірку завершено": "Scan complete",
        "Знайдено ": "Found ",
        ", які можна безпечно прибрати": " that's safe to reclaim",
        "Знайдено X": "Found X",
        "Сканувати знову": "Scan again",
        "Кеші, логи, тимчасові файли — безпечні до видалення": "Caches, logs, temp files — safe to remove",
        "Переглянути": "Review",
        "%lld елементів": "%lld items",
        "Великі та старі файли": "Large & old files",
        "Мапа диску — що займає найбільше місця": "Disk map — what takes the most space",
        "мапа диску": "disk map",
        "Огляд": "Overview",
        "Відкрити Space Lens": "Open Space Lens",
        "Дублікати та схожі фото": "Duplicate & similar photos",
        "Точні дублікати (BLAKE3) і візуально схожі фото": "Exact duplicates (BLAKE3) and look-alike photos",
        "сканувати на вимогу": "scan on demand",
        "Видалення разом із прихованими залишками": "Removal with hidden leftovers",
        "%lld застосунків": "%lld apps",
        "%lld рідко": "%lld rare",
        "Рекомендовані задачі для плавнішої роботи": "Recommended tasks for smoother performance",
        "напр. переіндексація Spotlight": "e.g. Spotlight reindex",
        "%lld задачі": "%lld tasks",
        "Запустити": "Run",
        "Тиск пам'яті в реальному часі": "Real-time memory pressure",
        "моніторинг у реальному часі": "real-time monitoring",
        "Деталі": "Details",

        // Space Lens
        "Що займає місце на диску": "What's using disk space",
        "Використано": "Used",
        "%@ вільно": "%@ free",
        "Скануйте, щоб побачити мапу диску": "Scan to see the disk map",
        "Без привілеїв — Space Lens читає вашу домівку.": "No privileges needed — Space Lens reads your home folder.",
        "%lld файлів · %@": "%lld files · %@",
        "Сканування не вдалося": "Scan failed",
        "Вибрати теку для аналізу": "Choose a folder to analyze",
        "Аналізувати": "Analyze",
        "ТЕКА": "FOLDER",
        "ФАЙЛ / ГРУПА": "FILE / GROUP",
        "Перемістити в Кошик": "Move to Trash",
        "Показати у Finder": "Show in Finder",
        "Натисніть на блок, щоб заглибитись у теку, або оберіть файл, щоб діяти з ним. Розмір блоку = розмір на диску.":
            "Tap a block to drill into a folder, or pick a file to act on it. Block size = size on disk.",

        // Duplicates
        "Дублікати файлів": "Duplicate files",
        "Схожі фото": "Similar photos",
        "Знайти": "Find",
        "Авто-вибір залишає найкращу копію": "Auto-select keeps the best copy",
        "Знайдіть дублікати файлів": "Find duplicate files",
        "Сканує домівку, потім звіряє схожі файли в Rust для точного збігу.":
            "Scans your home folder, then verifies look-alikes in Rust for an exact match.",
        "%lld файлів перевірено": "%lld files examined",
        "Дублікатів не знайдено": "No duplicates found",
        "%lld копій · %@ кожна": "%lld copies · %@ each",
        "Звільнити %@": "Reclaim %@",
        "Знайдіть схожі фото": "Find similar photos",
        "Perceptual-хешування (Rust) групує візуально схожі знімки.": "Perceptual hashing (Rust) groups visually similar shots.",
        "Хешування фото…": "Hashing photos…",
        "Схожих фото не знайдено": "No similar photos found",
        "Серія %lld": "Series %lld",
        "%lld фото · %lld до видалення": "%lld photos · %lld to remove",
        "Залишити": "Keep",
        "Видаляти остаточно": "Delete permanently",
        "%lld вибрано · %@": "%lld selected · %@",
        "Видалити…": "Delete…",
        "Видалити вибране остаточно? Дію не можна скасувати.": "Permanently delete the selection? This can't be undone.",
        "Видалити остаточно": "Delete permanently",

        // Cleanup
        "Безпечно прибрати системні файли": "Safely remove system files",
        "Усе видаляється в Кошик · «Перевірте» залишаємо невибраним": "Everything goes to Trash · 'Review' stays unchecked",
        "Скануйте, щоб знайти мотлох": "Scan to find junk",
        "Кеші, логи, Xcode-сміття та інше — лише з відомо-безпечних шляхів.":
            "Caches, logs, Xcode junk and more — only from known-safe paths.",
        "Нічого прибирати": "Nothing to clean",
        "Безпечно": "Safe",
        "Перевірте": "Review",
        "%lld / %lld вибрано": "%lld / %lld selected",
        "До переміщення в Кошик": "To move to Trash",
        "%@ · %lld елементів": "%@ · %lld items",
        "Перемістити вибране в Кошик?": "Move the selection to Trash?",
        "Файли не зникнуть одразу — їх можна відновити з Кошика.": "Files don't vanish immediately — you can restore them from Trash.",

        // Uninstaller
        "Видалення разом із залишками": "Removal with leftovers",
        "Пошук застосунків": "Search apps",
        "Усі %lld": "All %lld",
        "Рідко вживані %lld": "Rarely used %lld",
        "За розміром": "By size",
        "Оберіть застосунок": "Select an app",
        "Останнє відкриття: %@": "Last opened: %@",
        "Ви давно не відкривали цей застосунок. Видалення безпечне — за потреби його можна перевстановити.":
            "You haven't opened this app in a while. Removal is safe — you can reinstall it later.",
        "ЩО БУДЕ ВИДАЛЕНО": "WHAT WILL BE REMOVED",
        "Звичайне перетягування в Кошик залишає приховані файли. Nimbus прибирає їх разом із застосунком.":
            "Dragging to Trash leaves hidden files behind. Nimbus removes them with the app.",
        "Видалити повністю": "Remove completely",
        "сьогодні": "today",
        "%lld дн тому": "%lld d ago",
        "%lld міс тому": "%lld mo ago",
        "%lld р тому": "%lld y ago",
        "невідомо": "unknown",
        "рідко": "rare",

        // Performance
        "Задачі обслуговування": "Maintenance tasks",
        "Безпечні операції, які macOS зазвичай виконує сама. Запустіть вручну за потреби.":
            "Safe operations macOS usually does itself. Run them manually when needed.",
        "Запустити обрані · %lld": "Run selected · %lld",
        "Виконання…": "Running…",
        "Елементи входу та фонові процеси": "Login items & background processes",
        "Запускаються разом із системою. Керування — у Системних налаштуваннях.":
            "Launch with the system. Manage them in System Settings.",
        "Виявлено": "Found",
        "Nimbus під час входу": "Nimbus at login",
        "Єдиний елемент, яким Nimbus керує напряму.": "The only item Nimbus manages directly.",
        "Відкрити в Системних налаштуваннях": "Open in System Settings",
        "рекомендовано": "recommended",
        "виконано": "done",
        "Привілейовані задачі потребують помічника": "Privileged tasks need a helper",
        "Очищення DNS і переіндексація Spotlight виконуються root-демоном через SMAppService.":
            "DNS flush and Spotlight reindex run via a root daemon through SMAppService.",
        "Увімкнути": "Enable",
        "Не вдалося встановити помічник: %@. Потрібен підпис Developer ID.":
            "Couldn't install the helper: %@. A Developer ID signature is required.",
        "Очистити кеш DNS": "Flush DNS cache",
        "Допомагає, коли сайти не відкриваються після зміни мережі.": "Helps when sites won't load after a network change.",
        "Перебудувати індекс Spotlight": "Rebuild Spotlight index",
        "Виправляє неточний або повільний пошук.": "Fixes inaccurate or slow search.",
        "Скинути кеш шрифтів": "Reset font caches",
        "Усуває проблеми з відображенням шрифтів.": "Fixes font rendering issues.",
        "Перебудувати Launch Services": "Rebuild Launch Services",
        "Прибирає дублікати в меню «Відкрити за допомогою».": "Removes duplicates in the 'Open With' menu.",
        "Очистити кеш QuickLook": "Clear QuickLook cache",
        "Оновлює прев'ю файлів у Finder.": "Refreshes file previews in Finder.",
        "~2 с": "~2s", "~3 с": "~3s", "~5 с": "~5s", "~10 с": "~10s", "5–30 хв": "5–30 min",
        "Користувацький агент": "User agent",
        "Системний агент": "System agent",
        "Системний демон": "System daemon",

        // Health
        "Реальний стан вашого Mac": "Your Mac's real status",
        "Тиск пам'яті": "Memory pressure",
        "Пам'ять": "Memory",
        "Диск": "Disk",
        "%@ зайнято": "%@ used",
        "Норма": "Normal",
        "Помірний": "Moderate",
        "Високий": "High",
        "Добре": "Good",
        "Пам'ять — тиск, а не «вільні гігабайти»": "Memory — pressure, not 'free gigabytes'",
        "Порожня RAM — це змарнована RAM. macOS навмисно тримає її зайнятою кешем. Ми показуємо тиск пам'яті — наскільки системі бракує ресурсу.":
            "Empty RAM is wasted RAM. macOS deliberately keeps it busy with caches. We show memory pressure — how much the system lacks resources.",
        "НАЙБІЛЬШІ СПОЖИВАЧІ ПАМ'ЯТІ": "TOP MEMORY CONSUMERS",
        "%@: %@, %lld відсотків": "%@: %@, %lld percent",
        "Найбільші споживачі": "Top consumers",
        "Відкрити Моніторинг системи": "Open Activity Monitor",
        "Тиск пам'яті: %@": "Memory pressure: %@",

        // Settings
        "Преференції та винятки": "Preferences & exclusions",
        "Загальне": "General",
        "Компаньйон у menu bar": "Menu bar companion",
        "Живий індикатор стану та швидке сканування з рядка меню.": "Live status indicator and quick scan from the menu bar.",
        "Запускати під час входу": "Launch at login",
        "Nimbus стартує разом із системою (фоново, без вікна).": "Nimbus starts with the system (in the background, no window).",
        "Мова": "Language",
        "Інтерфейс перемикається миттєво.": "The interface switches instantly.",
        "Сканування й безпека": "Scanning & safety",
        "Безпечне видалення (у Кошик)": "Safe delete (to Trash)",
        "Усе видалене спершу йде в Кошик. Вимкнення дозволяє остаточне видалення — обережно.":
            "Everything deleted goes to Trash first. Turning this off allows permanent deletion — be careful.",
        "Сканувати поштові вкладення": "Scan mail attachments",
        "Вимкнено за замовчуванням — це ваші особисті дані.": "Off by default — this is your personal data.",
        "Глибина пошуку дублікатів": "Duplicate search depth",
        "«Глибоко» порівнює вміст байт у байт — повільніше, але точніше.": "'Deep' compares content byte-by-byte — slower but more accurate.",
        "Швидко": "Fast", "Звичайно": "Normal", "Глибоко": "Deep",
        "Які модулі включати у Smart Scan": "Which modules to include in Smart Scan",
        "Space Lens": "Space Lens",
        "Список винятків": "Exclusion list",
        "Файли, теки та застосунки тут Nimbus ніколи не торкається — навіть під час Smart Scan.":
            "Nimbus never touches the files, folders and apps here — even during Smart Scan.",
        "Перетягніть або введіть шлях…": "Drag or type a path…",
        "Додати": "Add",
        "Знайомство з Nimbus": "Nimbus walkthrough",
        "Переглянути привітання й пояснення дозволів знову.": "See the welcome and permission explanations again.",
        "Показати онбординг": "Show onboarding",
        "ШЛЯХ": "PATH",

        // Onboarding
        "Вітаємо в Nimbus": "Welcome to Nimbus",
        "Спокійний догляд за вашим Mac. Більше вільного місця й менше турбот — без жодних трюків і страшилок.":
            "Calm care for your Mac. More free space and fewer worries — no tricks, no scare tactics.",
        "Почати": "Get started",
        "Пропустити налаштування": "Skip setup",
        "Три обіцянки Nimbus": "Nimbus's three promises",
        "Чому вашій системі з нами безпечно": "Why your system is safe with us",
        "Перегляд перед видаленням": "Review before deletion",
        "Ви завжди бачите, що саме буде прибрано. Нічого не зникає без вашого підтвердження.":
            "You always see exactly what will be removed. Nothing disappears without your confirmation.",
        "Усе оборотне": "Everything is reversible",
        "За замовчуванням файли йдуть у Кошик. Передумали — відновіть одним кліком.":
            "By default files go to the Trash. Changed your mind? Restore with one click.",
        "Працює локально": "Works locally",
        "Жодних даних не залишає ваш Mac. Сканування й хешування — повністю на пристрої.":
            "No data leaves your Mac. Scanning and hashing happen entirely on-device.",
        "Назад": "Back",
        "Далі": "Next",
        "Повний доступ до диска": "Full Disk Access",
        "Щоб знаходити кеші Пошти, Safari та інших застосунків, Nimbus потребує Повного доступу до диска. Це дозвіл системи — ви надаєте його в Системних налаштуваннях.":
            "To find caches from Mail, Safari and other apps, Nimbus needs Full Disk Access. It's a system permission — you grant it in System Settings.",
        "Відкрити Системні налаштування": "Open System Settings",
        "Зробити пізніше": "Do it later",
        "Завершити": "Finish",

        // Modals
        "Вивільнено %@": "Freed %@",
        "Файли у Кошику — можна відновити будь-коли. Очистіть Кошик, щоб остаточно повернути місце.":
            "Files are in the Trash — restore them anytime. Empty the Trash to reclaim the space for good.",
        "Готово": "Done",

        // Placeholder
        "Цей модуль готується… (домен реалізовано й покрито тестами в NimbusKit)":
            "This module is in progress… (domain implemented and tested in NimbusKit)",
    ]
}
