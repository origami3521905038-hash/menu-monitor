import Foundation

public enum MetricFormatting {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    public static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var number = Double(value)
        var unitIndex = 0
        while number >= 1_024, unitIndex < units.count - 1 {
            number /= 1_024
            unitIndex += 1
        }

        let digits: Int
        if unitIndex == 0 || number >= 100 { digits = 0 }
        else if number >= 10 { digits = 1 }
        else { digits = 2 }
        return "\(decimal(number, maximumFractionDigits: digits)) \(units[unitIndex])"
    }

    public static func watts(_ value: Double) -> String {
        guard value.isFinite else { return "不可用" }
        if value < 10 {
            return "\(decimal(value, maximumFractionDigits: 1)) W"
        }
        return "\(decimal(value, maximumFractionDigits: 0)) W"
    }

    public static func percent(_ value: Double) -> String {
        guard value.isFinite else { return "不可用" }
        return "\(decimal(value, maximumFractionDigits: 0))%"
    }

    public static func decimal(_ value: Double, maximumFractionDigits: Int = 2) -> String {
        guard value.isFinite else { return "--" }
        let format = "%.*f"
        let fixed = String(format: format, locale: posixLocale, maximumFractionDigits, value)
        guard maximumFractionDigits > 0 else { return fixed }
        return fixed
            .replacingOccurrences(of: "(\\.[0-9]*?)0+$", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }
}
