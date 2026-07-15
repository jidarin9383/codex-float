import Foundation
import Observation

/// Shared app state for menu bar, preferences, and the floating panel.
@MainActor
@Observable
final class AppModel {
    let viewModel: QuotaViewModel
    let preferences: AppPreferences

    @ObservationIgnored
    private(set) lazy var panelController = FloatingPanelController(viewModel: viewModel)

    init(
        viewModel: QuotaViewModel = QuotaViewModel(),
        preferences: AppPreferences = AppPreferences()
    ) {
        self.viewModel = viewModel
        self.preferences = preferences
        self.viewModel.floatingWidgetVisible = preferences.floatingWidgetVisible
    }

    func bootstrap() {
        // Prefer system truth for login item over a stale UserDefaults flag.
        preferences.launchAtLogin = LaunchAtLoginService.isEnabled

        viewModel.floatingWidgetVisible = preferences.floatingWidgetVisible
        if preferences.floatingWidgetVisible {
            panelController.show()
        }
        viewModel.start()
    }

    func setFloatingWidgetVisible(_ visible: Bool) {
        preferences.floatingWidgetVisible = visible
        viewModel.setFloatingWidgetVisible(visible)
        panelController.setVisible(visible)
    }

    /// Toggle launch-at-login and report success / failure to the user.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            preferences.launchAtLogin = LaunchAtLoginService.isEnabled
            if preferences.launchAtLogin {
                UserAlerts.showLaunchAtLoginEnabled()
            } else {
                UserAlerts.showLaunchAtLoginDisabled()
            }
        } catch {
            preferences.launchAtLogin = LaunchAtLoginService.isEnabled
            UserAlerts.showLaunchAtLoginFailed(error.localizedDescription)
        }
    }

    func checkForUpdates() {
        Task { @MainActor in
            let outcome = await UpdateChecker.checkLatest()
            switch outcome {
            case .upToDate(let current):
                UserAlerts.showAlreadyUpToDate(version: current)
            case .updateAvailable(let current, let latest, let releaseURL):
                UserAlerts.showUpdateAvailable(current: current, latest: latest, releaseURL: releaseURL)
            case .notConfigured:
                UserAlerts.showUpdateNotConfigured()
            case .failure(let message):
                UserAlerts.showUpdateCheckFailed(message)
            }
        }
    }
}
