import Dispatch
import Foundation

public enum MetricClock {
    public static func now() -> MetricTimestamp {
        MetricTimestamp(
            uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            date: Date()
        )
    }

    public static func elapsedSeconds(from earlier: MetricTimestamp, to later: MetricTimestamp) -> Double? {
        guard later.uptimeNanoseconds > earlier.uptimeNanoseconds else { return nil }
        return Double(later.uptimeNanoseconds - earlier.uptimeNanoseconds) / 1_000_000_000
    }
}
