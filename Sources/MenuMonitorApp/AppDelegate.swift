import AppKit
import Darwin
import MenuMonitorCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = MetricsStore()
    let preferences = Preferences()
    let loginItem = LoginItemController()

    private var coordinator: MetricsSamplingCoordinator?
    private var statusItem: StatusItemController?
    private var preferencesWindow: PreferencesWindowController?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var uiEventObservers: [NSObjectProtocol] = []
    private var loginMessage = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let store = store
        let coordinator = MetricsSamplingCoordinator { update in
            await MainActor.run {
                store.apply(update)
            }
        }
        self.coordinator = coordinator
        let preferencesWindow = PreferencesWindowController { [weak self] in
            self?.preferencesPayload() ?? [:]
        }
        self.preferencesWindow = preferencesWindow
        statusItem = StatusItemController(
            store: store,
            preferences: preferences,
            coordinator: coordinator
        )
        store.onUpdate = { [weak self] in self?.statusItem?.update() }
        preferences.onChange = { [weak self] in
            self?.statusItem?.update()
            self?.preferencesWindow?.refresh()
        }
        observeSleepWake()
        observeUIEvents()

        Task { await coordinator.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeSleepWakeObservers()
        removeUIEventObservers()
        statusItem?.shutdown()
        if let coordinator {
            Task { await coordinator.stop() }
        }
    }

    private func observeSleepWake() {
        guard let coordinator else { return }
        let notifications = NSWorkspace.shared.notificationCenter
        sleepObserver = notifications.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { await coordinator.handleWillSleep() }
        }
        wakeObserver = notifications.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { await coordinator.handleDidWake() }
        }
    }

    private func removeSleepWakeObservers() {
        let notifications = NSWorkspace.shared.notificationCenter
        if let sleepObserver {
            notifications.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        if let wakeObserver {
            notifications.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    private func observeUIEvents() {
        let notifications = NotificationCenter.default
        uiEventObservers = [
            notifications.addObserver(
                forName: Notification.Name("com.local.menumonitor.openSettings"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.preferencesWindow?.show() }
            },
            notifications.addObserver(
                forName: Notification.Name("com.local.menumonitor.metricChanged"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let metricValue = notification.userInfo?["metric"] as? String
                let enabled = notification.userInfo?["enabled"] as? Bool
                Task { @MainActor in
                    guard let metricValue,
                          let metric = MenuBarMetric(rawValue: metricValue),
                          let enabled else {
                        return
                    }
                    self?.preferences.setMetric(metric, enabled: enabled)
                }
            },
            notifications.addObserver(
                forName: Notification.Name("com.local.menumonitor.displayModeChanged"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let rawValue = notification.userInfo?["mode"] as? String
                Task { @MainActor in
                    guard let rawValue,
                          let mode = MenuBarDisplayMode(rawValue: rawValue) else {
                        return
                    }
                    self?.preferences.displayMode = mode
                }
            },
            notifications.addObserver(
                forName: Notification.Name("com.local.menumonitor.languageChanged"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let rawValue = notification.userInfo?["language"] as? String
                Task { @MainActor in
                    guard let rawValue,
                          let language = AppLanguage(rawValue: rawValue) else {
                        return
                    }
                    self?.preferences.language = language
                }
            },
            notifications.addObserver(
                forName: Notification.Name("com.local.menumonitor.loginItemToggle"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.toggleLoginItem() }
            }
        ]
    }

    private func removeUIEventObservers() {
        let notifications = NotificationCenter.default
        for observer in uiEventObservers {
            notifications.removeObserver(observer)
        }
        uiEventObservers.removeAll()
    }

    private func toggleLoginItem() {
        do {
            if loginItem.status == .enabled {
                loginMessage = try loginItem.unregisterAndWait()
                    ? preferences.language.text("已关闭", "Disabled")
                    : preferences.language.text("正在等待移除", "Waiting for removal")
            } else {
                try loginItem.register()
                loginMessage = loginItem.status.title(for: preferences.language)
            }
        } catch {
            // ServiceManagement may return an English system error. Keep the
            // settings surface consistently Chinese while retaining the failure
            // in the process log for local troubleshooting.
            fputs("MenuMonitor login-item error: \(error.localizedDescription)\n", stderr)
            loginMessage = preferences.language.text(
                "登录项操作失败，请稍后重试。",
                "Login item operation failed. Try again later."
            )
        }
        preferencesWindow?.refresh()
    }

    private func preferencesPayload() -> NSDictionary {
        [
            "selectedMetrics": preferences.selectedMetrics.map(\.rawValue).sorted(),
            "displayMode": preferences.displayMode.rawValue,
            "language": preferences.language.rawValue,
            "loginStatus": loginItem.status.title(for: preferences.language),
            "loginEnabled": loginItem.status == .enabled,
            "canChangeLogin": loginItem.isInstalledCopy,
            "loginMessage": loginMessage
        ] as NSDictionary
    }
}
