import Foundation
import ServiceManagement

@MainActor
final class LoginItemController {
    enum Status: String {
        case enabled
        case notRegistered
        case requiresApproval
        case notFound
        case unknown

        var title: String {
            title(for: .chinese)
        }

        func title(for language: AppLanguage) -> String {
            switch self {
            case .enabled: return language.text("已启用", "Enabled")
            case .notRegistered: return language.text("未注册", "Not registered")
            case .requiresApproval: return language.text("需要批准", "Approval required")
            case .notFound: return language.text("不可用", "Unavailable")
            case .unknown: return language.text("未知", "Unknown")
            }
        }
    }

    var status: Status { Self.currentStatus() }

    var isInstalledCopy: Bool {
        let expected = URL(fileURLWithPath: "/Applications/MenuMonitor.app", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL == expected
    }

    func register() throws {
        guard isInstalledCopy else {
            throw LoginItemError.notInstalled
        }
        try SMAppService.mainApp.register()
    }

    func unregisterAndWait(timeout: TimeInterval = 8) throws -> Bool {
        try SMAppService.mainApp.unregister()
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if Self.currentStatus() == .notRegistered {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return Self.currentStatus() == .notRegistered
    }

    static func currentStatus() -> Status {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .unknown
        }
    }
}

enum LoginItemError: LocalizedError {
    case notInstalled

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "只有从 /Applications/MenuMonitor.app 运行时才能注册登录项。"
        }
    }
}
