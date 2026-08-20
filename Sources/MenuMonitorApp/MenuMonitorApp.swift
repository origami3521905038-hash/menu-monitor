import AppKit
import Darwin

@main
struct MenuMonitorApp {
    @MainActor
    static func main() {
        if let exitCode = AppCommand.executeIfRequested() {
            Darwin.exit(exitCode)
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
private enum AppCommand {
    static func executeIfRequested() -> Int32? {
        let arguments = Set(CommandLine.arguments.dropFirst())
        guard let command = ["--login-item-status", "--register-login-item", "--unregister-login-item"]
            .first(where: arguments.contains) else {
            return nil
        }

        let loginItem = LoginItemController()
        do {
            switch command {
            case "--login-item-status":
                let status = loginItem.status
                print(status.rawValue)
                return status == .enabled ? 0 : 1
            case "--register-login-item":
                try loginItem.register()
                let status = loginItem.status
                print(status.rawValue)
                return status == .enabled ? 0 : 2
            case "--unregister-login-item":
                let removed = try loginItem.unregisterAndWait()
                print(LoginItemController.currentStatus().rawValue)
                return removed ? 0 : 3
            default:
                return 64
            }
        } catch {
            fputs("MenuMonitor: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }
}
