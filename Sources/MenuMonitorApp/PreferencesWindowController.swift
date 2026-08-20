import AppKit
import Foundation

@MainActor
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    private let payload: () -> NSDictionary
    private var pluginController: UIPluginController?
    private var window: NSPanel?

    init(payload: @escaping () -> NSDictionary) {
        self.payload = payload
    }

    func show() {
        let currentPayload = payload()
        if pluginController == nil {
            pluginController = UIPluginLoader.shared.makePreferences(payload: currentPayload)
        }
        guard let pluginController else { return }
        pluginController.update(payload: currentPayload)
        let language = AppLanguage(rawValue: (currentPayload["language"] as? String) ?? "") ?? .chinese

        if window == nil {
            let window = NSPanel(contentViewController: pluginController.viewController)
            window.title = language.text("性能简读设置", "Menu Monitor Settings")
            window.styleMask = [.titled, .closable, .utilityWindow]
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 344, height: 300))
            window.minSize = NSSize(width: 344, height: 300)
            window.delegate = self
            self.window = window
        } else {
            // The retained window intentionally drops its controller on close so the
            // SwiftUI bundle can unload. Reattach the fresh controller on reopen.
            window?.contentViewController = pluginController.viewController
            window?.title = language.text("性能简读设置", "Menu Monitor Settings")
        }
        window?.center()
        window?.orderFrontRegardless()
        window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        let currentPayload = payload()
        pluginController?.update(payload: currentPayload)
        let language = AppLanguage(rawValue: (currentPayload["language"] as? String) ?? "") ?? .chinese
        window?.title = language.text("性能简读设置", "Menu Monitor Settings")
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        pluginController = nil
        UIPluginLoader.shared.releaseController()
    }
}
