import AppKit
import Foundation

/// Keeps SwiftUI out of the sampling process until a user actually opens a visual
/// surface. The bundle has no data-collection capability and receives display payloads
/// only through Objective-C runtime messages.
@MainActor
final class UIPluginLoader {
    static let shared = UIPluginLoader()

    private var bundle: Bundle?
    private var activeControllers = 0
    private(set) var lastError: String?

    func makePanel(payload: NSDictionary) -> UIPluginController? {
        makeController(selectorName: "makePanelWithPayload:", payload: payload)
    }

    func makePreferences(payload: NSDictionary) -> UIPluginController? {
        makeController(selectorName: "makePreferencesWithPayload:", payload: payload)
    }

    func releaseController() {
        activeControllers = max(0, activeControllers - 1)
        guard activeControllers == 0 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.unloadIfIdle()
        }
    }

    private func makeController(selectorName: String, payload: NSDictionary) -> UIPluginController? {
        guard loadBundle(),
              let factory = NSClassFromString("MenuMonitorUIFactory") as? NSObject.Type else {
            lastError = lastError ?? "界面组件不可用"
            return nil
        }
        let selector = NSSelectorFromString(selectorName)
        guard factory.responds(to: selector),
              let object = factory.perform(selector, with: payload)?.takeUnretainedValue() as? NSObject,
              let viewController = object.perform(NSSelectorFromString("contentViewController"))?
                .takeUnretainedValue() as? NSViewController else {
            lastError = "界面组件未能创建视图"
            return nil
        }
        activeControllers += 1
        return UIPluginController(object: object, viewController: viewController)
    }

    private func loadBundle() -> Bool {
        if bundle != nil { return true }
        guard let url = Bundle.main.builtInPlugInsURL?
            .appendingPathComponent("MenuMonitorUI.bundle", isDirectory: true),
              let bundle = Bundle(url: url),
              bundle.load() else {
            lastError = "界面组件加载失败"
            return false
        }
        self.bundle = bundle
        lastError = nil
        return true
    }

    private func unloadIfIdle() {
        guard activeControllers == 0, let bundle else { return }
        bundle.unload()
        self.bundle = nil
    }
}

@MainActor
final class UIPluginController {
    let object: NSObject
    let viewController: NSViewController

    init(object: NSObject, viewController: NSViewController) {
        self.object = object
        self.viewController = viewController
    }

    func update(payload: NSDictionary) {
        _ = object.perform(NSSelectorFromString("updateWithPayload:"), with: payload)
    }
}
