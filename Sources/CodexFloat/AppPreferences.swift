import Foundation
import Observation

/// Non-secret user preferences for MVP surfaces.
@MainActor
@Observable
final class AppPreferences {
    private let defaults: UserDefaults

    private enum Key {
        static let floatingWidgetVisible = "floatingWidgetVisible"
        static let launchAtLogin = "launchAtLogin"
        static let hasCompletedFirstLaunch = "hasCompletedFirstLaunch"
    }

    var floatingWidgetVisible: Bool {
        didSet { defaults.set(floatingWidgetVisible, forKey: Key.floatingWidgetVisible) }
    }

    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Key.hasCompletedFirstLaunch) == nil {
            // First launch: menu bar + floating widget both on.
            defaults.set(true, forKey: Key.floatingWidgetVisible)
            defaults.set(false, forKey: Key.launchAtLogin)
            defaults.set(true, forKey: Key.hasCompletedFirstLaunch)
        }

        self.floatingWidgetVisible = defaults.object(forKey: Key.floatingWidgetVisible) as? Bool ?? true
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
    }
}
