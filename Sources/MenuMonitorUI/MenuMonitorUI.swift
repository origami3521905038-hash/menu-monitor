import AppKit
import Charts
import Foundation
import Observation
import SwiftUI

private enum UIEvent {
    static let openSettings = Notification.Name("com.local.menumonitor.openSettings")
    static let metricChanged = Notification.Name("com.local.menumonitor.metricChanged")
    static let displayModeChanged = Notification.Name("com.local.menumonitor.displayModeChanged")
    static let languageChanged = Notification.Name("com.local.menumonitor.languageChanged")
    static let loginItemToggle = Notification.Name("com.local.menumonitor.loginItemToggle")
}

private enum UILanguage: String {
    case chinese = "zh-Hans"
    case english = "en"

    init(rawValue: String?) {
        self = UILanguage(rawValue: rawValue ?? "") ?? .chinese
    }

    func text(_ chinese: String, _ english: String) -> String {
        self == .chinese ? chinese : english
    }
}

private struct PluginHistoryPoint: Identifiable {
    let id: Double
    let time: Date
    let value: Double
}

private struct PluginMetric: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
    let value: String
    let history: [PluginHistoryPoint]
    let severity: PluginMetricSeverity
}

private enum PluginMetricSeverity: String {
    case normal
    case warning
    case critical

    var titleColor: Color? {
        switch self {
        case .normal: return nil
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

private enum UIStyle {
    static let panelWidth: CGFloat = 328
    static let preferencesWidth: CGFloat = 344
    static let glassCornerRadius: CGFloat = 16
}

@MainActor
@Observable
private final class PanelModel {
    var timestamp = ""
    var language = UILanguage.chinese
    var metrics: [PluginMetric] = []

    init(payload: NSDictionary) {
        apply(payload)
    }

    func apply(_ payload: NSDictionary) {
        timestamp = payload["timestamp"] as? String ?? ""
        language = UILanguage(rawValue: payload["language"] as? String)
        metrics = [
            metric(id: "memory", symbol: "memorychip", title: language.text("内存", "Memory"), payload: payload),
            metric(id: "cpu", symbol: "cpu", title: language.text("处理器", "CPU"), payload: payload),
            metric(id: "power", symbol: "bolt", title: language.text("系统功耗", "System Power"), payload: payload),
            metric(id: "charging", symbol: "battery.100.bolt", title: language.text("充电功率", "Charging Power"), payload: payload)
        ]
    }

    private func metric(id: String, symbol: String, title: String, payload: NSDictionary) -> PluginMetric {
        let values = payload[id] as? [String: Any] ?? [:]
        let points = (values["history"] as? [[String: Any]] ?? []).compactMap { value -> PluginHistoryPoint? in
            guard let time = value["time"] as? Double,
                  let sample = value["value"] as? Double,
                  time.isFinite, sample.isFinite else {
                return nil
            }
            return PluginHistoryPoint(id: time, time: Date(timeIntervalSince1970: time), value: sample)
        }.sorted { $0.time < $1.time }
        return PluginMetric(
            id: id,
            symbol: symbol,
            title: title,
            detail: values["detail"] as? String ?? language.text("等待采样", "Waiting for sample"),
            value: values["value"] as? String ?? "--",
            history: points,
            severity: PluginMetricSeverity(rawValue: values["severity"] as? String ?? "normal") ?? .normal
        )
    }
}

@MainActor
@Observable
private final class PreferencesModel {
    var selectedMetrics: Set<String> = []
    var displayMode = "compact"
    var language = UILanguage.chinese
    var loginStatus = "未知"
    var loginEnabled = false
    var canChangeLogin = false
    var loginMessage = ""

    init(payload: NSDictionary) {
        apply(payload)
    }

    func apply(_ payload: NSDictionary) {
        selectedMetrics = Set(payload["selectedMetrics"] as? [String] ?? [])
        displayMode = payload["displayMode"] as? String ?? "compact"
        language = UILanguage(rawValue: payload["language"] as? String)
        loginStatus = payload["loginStatus"] as? String ?? language.text("未知", "Unknown")
        loginEnabled = payload["loginEnabled"] as? Bool ?? false
        canChangeLogin = payload["canChangeLogin"] as? Bool ?? false
        loginMessage = payload["loginMessage"] as? String ?? ""
    }

    func setMetric(_ metric: String, enabled: Bool) {
        if enabled {
            selectedMetrics.insert(metric)
        } else {
            selectedMetrics.remove(metric)
        }
        NotificationCenter.default.post(
            name: UIEvent.metricChanged,
            object: nil,
            userInfo: ["metric": metric, "enabled": enabled]
        )
    }

    func setDisplayMode(_ value: String) {
        displayMode = value
        NotificationCenter.default.post(
            name: UIEvent.displayModeChanged,
            object: nil,
            userInfo: ["mode": value]
        )
    }

    func setLanguage(_ value: String) {
        language = UILanguage(rawValue: value)
        NotificationCenter.default.post(
            name: UIEvent.languageChanged,
            object: nil,
            userInfo: ["language": language.rawValue]
        )
    }

    func toggleLoginItem() {
        NotificationCenter.default.post(name: UIEvent.loginItemToggle, object: nil)
    }
}

@MainActor
@objc(MenuMonitorUIFactory)
public final class MenuMonitorUIFactory: NSObject {
    @objc(makePanelWithPayload:)
    public class func makePanel(withPayload payload: NSDictionary) -> NSObject {
        PanelController(payload: payload)
    }

    @objc(makePreferencesWithPayload:)
    public class func makePreferences(withPayload payload: NSDictionary) -> NSObject {
        PreferencesController(payload: payload)
    }
}

@MainActor
@objc(MenuMonitorPanelController)
public final class PanelController: NSObject {
    private let model: PanelModel
    private let controller: NSHostingController<PluginPopoverView>

    init(payload: NSDictionary) {
        let model = PanelModel(payload: payload)
        self.model = model
        controller = NSHostingController(rootView: PluginPopoverView(model: model))
        super.init()
    }

    @objc(contentViewController)
    public func contentViewController() -> NSViewController {
        controller
    }

    @objc(updateWithPayload:)
    public func update(withPayload payload: NSDictionary) {
        model.apply(payload)
    }
}

@MainActor
@objc(MenuMonitorPreferencesController)
public final class PreferencesController: NSObject {
    private let model: PreferencesModel
    private let controller: NSHostingController<PluginPreferencesView>

    init(payload: NSDictionary) {
        let model = PreferencesModel(payload: payload)
        self.model = model
        controller = NSHostingController(rootView: PluginPreferencesView(model: model))
        super.init()
    }

    @objc(contentViewController)
    public func contentViewController() -> NSViewController {
        controller
    }

    @objc(updateWithPayload:)
    public func update(withPayload payload: NSDictionary) {
        model.apply(payload)
    }
}

private struct PluginPopoverView: View {
    @Bindable var model: PanelModel

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.language.text("性能简读", "Menu Monitor"))
                        .font(.headline)
                    Spacer()
                    Text(model.timestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                ForEach(model.metrics) { metric in
                    PluginMetricRow(metric: metric)
                }

                Divider()

                HStack(spacing: 10) {
                    Button {
                        NotificationCenter.default.post(name: UIEvent.openSettings, object: nil)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.borderless)
                    .help(model.language.text("设置", "Settings"))

                    Button {
                        NSApp.orderFrontStandardAboutPanel(options: [
                            .applicationName: model.language.text("性能简读", "Menu Monitor"),
                            .applicationVersion: "1.0.0",
                            .credits: NSAttributedString(
                                string: model.language.text(
                                    "\n开发者\n郑州市郑东新区蓝屿知行信息技术工作室",
                                    "\nDeveloper\n郑州市郑东新区蓝屿知行信息技术工作室"
                                ),
                                attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
                            )
                        ])
                        NSApp.activate(ignoringOtherApps: true)
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(model.language.text("关于性能简读", "About Menu Monitor"))

                    Spacer()

                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        Image(systemName: "power")
                    }
                    .buttonStyle(.borderless)
                    .help(model.language.text("退出性能简读", "Quit Menu Monitor"))
                }
                .font(.body)
            }
            .padding(11)
            .frame(width: UIStyle.panelWidth)
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: UIStyle.glassCornerRadius, style: .continuous)
            )
        }
    }
}

private struct PluginMetricRow: View {
    let metric: PluginMetric

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: metric.symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(metric.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(metric.severity.titleColor ?? .primary)
                    .lineLimit(1)
                Text(metric.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.9)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .layoutPriority(1)

            PluginSparkline(metricID: metric.id, points: metric.history)
                .frame(width: 72, height: 22)
                .accessibilityHidden(true)

            Text(metric.value)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .frame(width: 58, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title), \(metric.detail), \(metric.value)")
    }
}

private struct PluginSparkline: View {
    let metricID: String
    let points: [PluginHistoryPoint]

    private var xDomain: ClosedRange<Date> {
        let latest = points.map(\.time).max() ?? Date()
        return latest.addingTimeInterval(-60)...latest
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value).filter(\.isFinite)
        guard let maximum = values.max(), maximum.isFinite else { return 0...1 }
        if metricID == "cpu" { return 0...100 }
        let upper = max(maximum * 1.15, 1)
        return 0...upper
    }

    var body: some View {
        Group {
            if points.count >= 2 {
                Chart(points) { point in
                    LineMark(
                        x: .value("time", point.time),
                        y: .value("value", point.value)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
                .chartXScale(domain: xDomain)
                .chartYScale(domain: yDomain)
            } else {
                Capsule(style: .continuous)
                    .fill(.secondary.opacity(0.45))
                    .frame(maxWidth: .infinity, minHeight: 2, maxHeight: 2)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            plotArea.background(.clear)
        }
    }
}

private struct PluginPreferencesView: View {
    @Bindable var model: PreferencesModel
    private let metricIDs = [
        "memory",
        "cpu",
        "power",
        "charging"
    ]

    private func metricTitle(_ id: String) -> String {
        switch id {
        case "memory": return model.language.text("内存", "Memory")
        case "cpu": return model.language.text("处理器", "CPU")
        case "power": return model.language.text("系统功耗", "System Power")
        case "charging": return model.language.text("充电功率", "Charging Power")
        default: return id
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.language.text("菜单栏显示", "Menu Bar Metrics"))
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(metricIDs, id: \.self) { metric in
                        Toggle(metricTitle(metric), isOn: Binding(
                            get: { model.selectedMetrics.contains(metric) },
                            set: { model.setMetric(metric, enabled: $0) }
                        ))
                    }
                }

                Divider()

                Picker(model.language.text("显示模式", "Display Mode"), selection: Binding(
                    get: { model.displayMode },
                    set: { model.setDisplayMode($0) }
                )) {
                    Text(model.language.text("紧凑", "Compact")).tag("compact")
                    Text(model.language.text("带标签", "Labeled")).tag("labeled")
                }
                .pickerStyle(.segmented)

                Divider()

                Picker(model.language.text("语言", "Language"), selection: Binding(
                    get: { model.language.rawValue },
                    set: { model.setLanguage($0) }
                )) {
                    Text("中文").tag("zh-Hans")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.language.text("登录时启动", "Launch at Login"))
                        Text(model.loginStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.loginEnabled
                        ? model.language.text("关闭", "Disable")
                        : model.language.text("开启", "Enable")) {
                        model.toggleLoginItem()
                    }
                    .disabled(!model.canChangeLogin && !model.loginEnabled)
                }

                if !model.loginMessage.isEmpty {
                    Text(model.loginMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(width: UIStyle.preferencesWidth)
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: UIStyle.glassCornerRadius, style: .continuous)
            )
        }
    }
}
