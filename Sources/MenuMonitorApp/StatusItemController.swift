import AppKit
import Foundation
import MenuMonitorCore

private enum MetricAlert: String {
    case normal
    case warning
    case critical
}

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store: MetricsStore
    private let preferences: Preferences
    private let coordinator: MetricsSamplingCoordinator
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var panelController: UIPluginController?
    private var lastMenuBarText: String?
    private var outsideClickMonitors: [Any] = []
    private var lifecycleObservers: [(NotificationCenter, NSObjectProtocol)] = []

    init(
        store: MetricsStore,
        preferences: Preferences,
        coordinator: MetricsSamplingCoordinator
    ) {
        self.store = store
        self.preferences = preferences
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .transient
        // The system glass still provides its material transition; removing the
        // extra AppKit animation makes the status-item click feel immediate.
        popover.animates = false
        popover.delegate = self
        installOutsideClickMonitors()
        installLifecycleObservers()
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.image = NSImage(
            systemSymbolName: "waveform.path.ecg",
            accessibilityDescription: nil
        )
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        suppressStatusItemHelpTag(button)
        update()
    }

    func shutdown() {
        for (center, observer) in lifecycleObservers {
            center.removeObserver(observer)
        }
        lifecycleObservers.removeAll()
        for monitor in outsideClickMonitors {
            NSEvent.removeMonitor(monitor)
        }
        outsideClickMonitors.removeAll()
    }

    func update() {
        guard let button = statusItem.button else { return }
        let text = menuBarText()
        if text != lastMenuBarText {
            button.title = text
            lastMenuBarText = text
        }
        // Tahoe can recreate the status-item help tag after changing its title.
        suppressStatusItemHelpTag(button)
        panelController?.update(payload: panelPayload())
    }

    /// Prevents macOS Tahoe from showing a grey tooltip synthesized from the
    /// status-item title. The status item remains accessible through its image,
    /// title, and action; only the transient hover help tag is suppressed.
    private func suppressStatusItemHelpTag(_ button: NSStatusBarButton) {
        button.removeAllToolTips()
        button.toolTip = ""
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard preparePopoverContent() else { return }
        popover.show(
            relativeTo: positioningRect(for: button),
            of: button,
            preferredEdge: .minY
        )
    }

    func popoverDidShow(_ notification: Notification) {
        store.setHistoryEnabled(true)
        Task { await coordinator.setPanelVisible(true) }
    }

    func popoverDidClose(_ notification: Notification) {
        store.setHistoryEnabled(false)
        Task { await coordinator.setPanelVisible(false) }
        popover.contentViewController = nil
        panelController = nil
        UIPluginLoader.shared.releaseController()
    }

    private func preparePopoverContent() -> Bool {
        if let panelController {
            panelController.update(payload: panelPayload())
            updatePopoverContentSize(from: panelController.viewController)
            return true
        }
        guard let panel = UIPluginLoader.shared.makePanel(payload: panelPayload()) else {
            return false
        }
        panelController = panel
        popover.contentViewController = panel.viewController
        updatePopoverContentSize(from: panel.viewController)
        return true
    }

    private func installOutsideClickMonitors() {
        let mouseDownMask: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]

        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDownMask, handler: { [weak self] _ in
            Task { @MainActor [weak self] in self?.closePopover() }
        }) {
            outsideClickMonitors.append(globalMonitor)
        }

        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDownMask, handler: { [weak self] event in
            Task { @MainActor [weak self] in
                self?.closePopoverIfOutside(location: NSEvent.mouseLocation)
            }
            return event
        }) {
            outsideClickMonitors.append(localMonitor)
        }
    }

    private func installLifecycleObservers() {
        let applicationCenter = NotificationCenter.default
        let resignObserver = applicationCenter.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.closePopover() }
        }
        lifecycleObservers.append((applicationCenter, resignObserver))

        let windowObserver = applicationCenter.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let resignedWindowID = (notification.object as? NSWindow).map(ObjectIdentifier.init)
            Task { @MainActor [weak self, resignedWindowID] in
                guard let self,
                      let popoverWindow = self.popover.contentViewController?.view.window,
                      resignedWindowID == ObjectIdentifier(popoverWindow) else {
                    return
                }
                self.closePopover()
            }
        }
        lifecycleObservers.append((applicationCenter, windowObserver))

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.bundleIdentifier != Bundle.main.bundleIdentifier else {
                return
            }
            Task { @MainActor [weak self] in self?.closePopover() }
        }
        lifecycleObservers.append((workspaceCenter, workspaceObserver))
    }

    private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    private func closePopoverIfOutside(location: NSPoint) {
        guard popover.isShown else { return }
        let popoverFrame = popover.contentViewController?.view.window?.frame ?? .zero
        let statusFrame = statusItem.button.flatMap { button -> NSRect? in
            guard let window = button.window else { return nil }
            return window.convertToScreen(button.frame)
        } ?? .zero
        guard !popoverFrame.contains(location), !statusFrame.contains(location) else { return }
        closePopover()
    }

    private func positioningRect(for button: NSStatusBarButton) -> NSRect {
        guard let cell = button.cell else { return button.bounds }
        let imageRect = cell.imageRect(forBounds: button.bounds)
        return imageRect.isEmpty ? button.bounds : imageRect
    }

    private func updatePopoverContentSize(from viewController: NSViewController) {
        let view = viewController.view
        view.layoutSubtreeIfNeeded()
        let fitting = view.fittingSize
        let height = fitting.height.isFinite && fitting.height > 0 ? fitting.height : 240
        popover.contentSize = NSSize(width: 328, height: height)
    }

    private func menuBarText() -> String {
        let metrics = preferences.selectedMetrics
        guard !metrics.isEmpty, let snapshot = store.snapshot else { return "" }
        let parts = MenuBarMetric.allCases.compactMap { metric -> String? in
            guard metrics.contains(metric) else { return nil }
            return formatted(metric: metric, snapshot: snapshot)
        }
        return parts.joined(separator: "  ")
    }

    private func formatted(metric: MenuBarMetric, snapshot: MetricsSnapshot) -> String {
        let prefix: String
        switch metric {
        case .memory: prefix = preferences.displayMode == .labeled ? "\(MenuBarMetric.memory.localizedTitle(for: preferences.language)) " : ""
        case .cpu: prefix = preferences.displayMode == .labeled ? "\(MenuBarMetric.cpu.localizedTitle(for: preferences.language)) " : ""
        case .power: prefix = preferences.displayMode == .labeled ? "\(MenuBarMetric.power.localizedTitle(for: preferences.language)) " : ""
        case .charging: prefix = preferences.displayMode == .labeled ? "\(MenuBarMetric.charging.localizedTitle(for: preferences.language)) " : ""
        }
        switch metric {
        case .memory:
            return prefix + (snapshot.memory.value.map { MetricFormatting.bytes($0.usedBytes) } ?? "--")
        case .cpu:
            return prefix + (snapshot.cpu.value.map { MetricFormatting.percent($0.utilizationPercent) } ?? "--")
        case .power:
            return prefix + (snapshot.power.value.map { MetricFormatting.watts($0.watts) } ?? "--")
        case .charging:
            return prefix + (snapshot.charging.value.map { MetricFormatting.watts($0.watts) } ?? "--")
        }
    }

    private func panelPayload() -> NSDictionary {
        let snapshot = store.snapshot
        return [
            "language": preferences.language.rawValue,
            "timestamp": snapshot.map { Self.timeFormatter.string(from: $0.timestamp.date) } ?? "",
            "memory": metricPayload(
                value: snapshot.map { memoryValue($0.memory) } ?? "--",
                detail: snapshot.map { memoryDetail($0.memory) } ?? preferences.language.text("等待采样", "Waiting for sample"),
                history: store.memoryHistory,
                transform: { $0 / 1_073_741_824.0 },
                severity: snapshot.map { memoryAlert($0.memory) } ?? .normal
            ),
            "cpu": metricPayload(
                value: snapshot.map { cpuValue($0.cpu) } ?? "--",
                detail: snapshot.map { cpuDetail($0.cpu) } ?? preferences.language.text("等待采样", "Waiting for sample"),
                history: store.cpuHistory,
                severity: snapshot.map { cpuAlert($0.cpu) } ?? .normal
            ),
            "power": metricPayload(
                value: snapshot.map { powerValue($0.power) } ?? "--",
                detail: snapshot.map { powerDetail($0.power, temperatures: $0.temperature) } ?? preferences.language.text("等待采样", "Waiting for sample"),
                history: store.powerHistory,
                severity: snapshot.map { powerAlert($0.power, temperatures: $0.temperature) } ?? .normal
            ),
            "charging": metricPayload(
                value: snapshot.map { chargingValue($0.charging) } ?? "--",
                detail: snapshot.map { chargingDetail($0.charging) } ?? preferences.language.text("等待采样", "Waiting for sample"),
                history: store.chargingHistory,
                severity: snapshot.map { chargingAlert($0.charging) } ?? .normal
            )
        ] as NSDictionary
    }

    private func metricPayload(
        value: String,
        detail: String,
        history: [HistoryPoint],
        transform: (Double) -> Double = { $0 },
        severity: MetricAlert = .normal
    ) -> [String: Any] {
        let serializedHistory: [[String: Any]] = history.compactMap { point -> [String: Any]? in
            let value = transform(point.value)
            guard value.isFinite else { return nil }
            return ["time": point.date.timeIntervalSince1970, "value": value]
        }
        return [
            "value": value,
            "detail": detail,
            "history": serializedHistory,
            "severity": severity.rawValue
        ]
    }

    private func memoryValue(_ reading: MetricReading<MemoryMetrics>) -> String {
        valueText(reading) { MetricFormatting.bytes($0.usedBytes) }
    }

    private func memoryDetail(_ reading: MetricReading<MemoryMetrics>) -> String {
        switch reading {
        case .calibrating: return preferences.language.text("正在校准", "Calibrating")
        case let .available(value):
            let swap = value.swapUsedBytes.map(MetricFormatting.bytes) ?? preferences.language.text("不可用", "Unavailable")
            return "\(preferences.language.text("交换", "Swap")) \(swap)"
        case let .unavailable(reason): return localizedReason(reason)
        }
    }

    private func cpuValue(_ reading: MetricReading<CPUMetrics>) -> String {
        valueText(reading) { MetricFormatting.percent($0.utilizationPercent) }
    }

    private func cpuDetail(_ reading: MetricReading<CPUMetrics>) -> String {
        switch reading {
        case .calibrating: return preferences.language.text("正在校准", "Calibrating")
        case let .available(value):
            let load = value.loadAverage.first.map {
                "\(preferences.language.text("负载", "Load")) \(MetricFormatting.decimal($0, maximumFractionDigits: 2))"
            } ?? preferences.language.text("负载--", "Load --")
            let cores = preferences.language == .chinese
                ? "\(value.perCoreUtilizationPercent.count)核"
                : "\(value.perCoreUtilizationPercent.count) cores"
            return "\(cores) · \(load)"
        case let .unavailable(reason): return localizedReason(reason)
        }
    }

    private func powerValue(_ reading: MetricReading<PowerMetrics>) -> String {
        valueText(reading) { MetricFormatting.watts($0.watts) }
    }

    private func powerDetail(
        _ reading: MetricReading<PowerMetrics>,
        temperatures: MetricReading<TemperatureMetrics>
    ) -> String {
        switch reading {
        case .calibrating:
            return preferences.language.text("正在校准", "Calibrating")
        case .available:
            // The collector retains its source label for diagnostics and the
            // command-line probe. The compact panel instead uses this line for
            // the CPU and GPU temperatures requested by the user.
            return temperatureDetail(temperatures)
        case let .unavailable(reason):
            return localizedReason(reason)
        }
    }

    private func chargingValue(_ reading: MetricReading<ChargingMetrics>) -> String {
        valueText(reading) { MetricFormatting.watts($0.watts) }
    }

    private func chargingDetail(_ reading: MetricReading<ChargingMetrics>) -> String {
        switch reading {
        case .calibrating: return preferences.language.text("正在校准", "Calibrating")
        case let .available(value):
            let state: String
            switch value.state {
            case .charging:
                state = preferences.language.text("正在充电", "Charging")
            case .bypass:
                state = preferences.language.text("旁路供电", "Power bypass")
            case .notCharging, .unavailable:
                state = preferences.language.text("未充电", "Not charging")
            }
            let adapter = value.adapterRatedWatts.map(MetricFormatting.watts)
            guard let adapter else { return state }
            let adapterLabel = preferences.language == .chinese ? "适配器 " : ""
            return "\(state) · \(adapterLabel)\(adapter)"
        case let .unavailable(reason): return localizedReason(reason)
        }
    }

    private func valueText<Value>(_ reading: MetricReading<Value>, transform: (Value) -> String) -> String where Value: Sendable {
        switch reading {
        case .calibrating: return preferences.language == .chinese ? "..." : "..."
        case let .available(value): return transform(value)
        case .unavailable: return preferences.language == .chinese ? "--" : "--"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private func temperatureDetail(_ reading: MetricReading<TemperatureMetrics>) -> String {
        let missing = preferences.language.text("--", "--")
        switch reading {
        case .calibrating:
            return "CPU \(missing)·GPU \(missing)"
        case let .available(value):
            let cpu = value.cpuCelsius.map(formatTemperature) ?? missing
            let gpu = value.gpuCelsius.map(formatTemperature) ?? missing
            return "CPU \(cpu)·GPU \(gpu)"
        case .unavailable:
            return "CPU \(missing)·GPU \(missing)"
        }
    }

    private func formatTemperature(_ value: Double) -> String {
        "\(MetricFormatting.decimal(value, maximumFractionDigits: 0))°C"
    }

    // Alert thresholds are deliberately conservative UI cues, not thermal
    // protection. The collector remains the source of truth and unavailable
    // readings never become an alert.
    private func memoryAlert(_ reading: MetricReading<MemoryMetrics>) -> MetricAlert {
        guard case let .available(value) = reading else { return .normal }
        switch value.pressure {
        case .normal: return .normal
        case .warning: return .warning
        case .critical: return .critical
        }
    }

    private func cpuAlert(_ reading: MetricReading<CPUMetrics>) -> MetricAlert {
        guard case let .available(value) = reading, value.utilizationPercent.isFinite else {
            return .normal
        }
        if value.utilizationPercent >= 95 { return .critical }
        if value.utilizationPercent >= 80 { return .warning }
        return .normal
    }

    private func powerAlert(
        _ reading: MetricReading<PowerMetrics>,
        temperatures: MetricReading<TemperatureMetrics>
    ) -> MetricAlert {
        var watts = 0.0
        if case let .available(value) = reading, value.watts.isFinite {
            watts = value.watts
        }
        if case let .available(value) = temperatures {
            let highestTemperature = max(value.cpuCelsius ?? 0, value.gpuCelsius ?? 0)
            if highestTemperature >= 95 { return .critical }
            if highestTemperature >= 85 { return .warning }
        }
        if watts >= 45 { return .critical }
        if watts >= 25 { return .warning }
        return .normal
    }

    private func chargingAlert(_ reading: MetricReading<ChargingMetrics>) -> MetricAlert {
        guard case let .available(value) = reading, value.state == .charging,
              value.watts.isFinite else { return .normal }
        if let rated = value.adapterRatedWatts, rated > 0 {
            let ratio = value.watts / rated
            if ratio >= 0.95 { return .critical }
            if ratio >= 0.85 { return .warning }
        } else {
            if value.watts >= 120 { return .critical }
            if value.watts >= 90 { return .warning }
        }
        return .normal
    }

    private func localizedReason(_ reason: String) -> String {
        guard preferences.language == .chinese else {
            switch reason {
            case "Waiting to sample": return "Waiting for sample"
            case "IOReport disabled by request": return "Power disabled"
            case "IOReport runtime is unavailable": return "Power unavailable"
            case "Required IOReport energy channels are unavailable": return "Power channels missing"
            case "IOReport channel schema is ambiguous": return "Power channels unclear"
            case "IOReport energy unit is unsupported": return "Power unit unsupported"
            case "IOReport sample is unavailable": return "Power sample unavailable"
            case "IOReport sample count is invalid": return "Power sample invalid"
            case "IOReport power delta is implausible": return "Power change invalid"
            case "IOReport total power is implausible": return "Power total invalid"
            case "CPU tick counters are unavailable": return "CPU data unavailable"
            case "CPU tick delta is invalid": return "CPU data invalid"
            case "CPU utilization is invalid": return "CPU load invalid"
            case "Host page size is unavailable", "VM statistics are unavailable":
                return "Memory unavailable"
            case "VM page counters are invalid": return "Memory data invalid"
            case "Internal battery state is unavailable": return "Battery unavailable"
            case "Battery charging telemetry is unavailable": return "Charging unavailable"
            case "Charging state sources disagree": return "Charging state unclear"
            case "Charging values are invalid": return "Charging data invalid"
            case "Charging power is implausible": return "Charging power invalid"
            case "Non-charging values are invalid": return "Charging data invalid"
            case "Temperature sensors are unavailable": return "Temperature unavailable"
            default: return "Unavailable"
            }
        }
        switch reason {
        case "Waiting to sample": return "等待采样"
        case "IOReport disabled by request": return "功耗采集未启用"
        case "IOReport runtime is unavailable": return "功耗接口不可用"
        case "Required IOReport energy channels are unavailable": return "功耗通道不可用"
        case "IOReport channel schema is ambiguous": return "功耗通道不明确"
        case "IOReport energy unit is unsupported": return "功耗单位不支持"
        case "IOReport sample is unavailable": return "功耗采样不可用"
        case "IOReport sample count is invalid": return "功耗采样无效"
        case "IOReport power delta is implausible": return "功耗变化异常"
        case "IOReport total power is implausible": return "总功耗异常"
        case "CPU tick counters are unavailable": return "处理器计数器不可用"
        case "CPU tick delta is invalid": return "处理器计数变化无效"
        case "CPU utilization is invalid": return "处理器负载无效"
        case "Host page size is unavailable": return "内存页大小不可用"
        case "VM statistics are unavailable": return "内存统计不可用"
        case "VM page counters are invalid": return "内存页计数无效"
        case "Internal battery state is unavailable": return "电池状态不可用"
        case "Battery charging telemetry is unavailable": return "充电数据不可用"
        case "Charging state sources disagree": return "充电状态不一致"
        case "Charging values are invalid": return "充电数据无效"
        case "Charging power is implausible": return "充电功率异常"
        case "Non-charging values are invalid": return "未充电数据无效"
        default:
            return reason.range(of: "[\\u{4E00}-\\u{9FFF}]", options: .regularExpression) != nil
                ? reason
                : "不可用"
        }
    }
}
