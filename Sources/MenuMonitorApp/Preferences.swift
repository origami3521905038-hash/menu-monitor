import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    var appName: String {
        switch self {
        case .chinese: return "性能简读"
        case .english: return "Menu Monitor"
        }
    }

    func text(_ chinese: String, _ english: String) -> String {
        self == .chinese ? chinese : english
    }
}

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case memory
    case cpu
    case power
    case charging

    var id: String { rawValue }

    var title: String {
        localizedTitle(for: .chinese)
    }

    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .memory: return language.text("内存", "Memory")
        case .cpu: return language.text("处理器", "CPU")
        case .power: return language.text("系统功耗", "System Power")
        case .charging: return language.text("充电功率", "Charging Power")
        }
    }
}

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case compact
    case labeled

    var id: String { rawValue }

    var title: String {
        localizedTitle(for: .chinese)
    }

    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .compact: return language.text("紧凑", "Compact")
        case .labeled: return language.text("带标签", "Labeled")
        }
    }
}

@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let selectedMetrics = "menuBar.selectedMetrics"
        static let displayMode = "menuBar.displayMode"
        static let language = "interface.language"
    }

    var selectedMetrics: Set<MenuBarMetric> {
        didSet {
            UserDefaults.standard.set(selectedMetrics.map(\.rawValue).sorted(), forKey: Key.selectedMetrics)
            onChange?()
        }
    }

    var displayMode: MenuBarDisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: Key.displayMode)
            onChange?()
        }
    }

    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Key.language)
            onChange?()
        }
    }

    var onChange: (() -> Void)?

    init() {
        if let rawMetrics = UserDefaults.standard.object(forKey: Key.selectedMetrics) as? [String] {
            // An empty stored array is a deliberate user choice, distinct from a
            // first launch where this preference has never been written.
            selectedMetrics = Set(rawMetrics.compactMap(MenuBarMetric.init(rawValue:)))
        } else {
            selectedMetrics = [.cpu, .power]
        }
        displayMode = MenuBarDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: Key.displayMode) ?? ""
        ) ?? .compact
        language = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: Key.language) ?? ""
        ) ?? .chinese
    }

    func setMetric(_ metric: MenuBarMetric, enabled: Bool) {
        if enabled {
            selectedMetrics.insert(metric)
        } else {
            selectedMetrics.remove(metric)
        }
    }
}
