import Foundation
import MenuMonitorCore
import Observation

struct HistoryPoint: Identifiable {
    let id: UInt64
    let date: Date
    let value: Double
}

@MainActor
@Observable
final class MetricsStore {
    private(set) var snapshot: MetricsSnapshot?
    private(set) var memoryHistory: [HistoryPoint] = []
    private(set) var cpuHistory: [HistoryPoint] = []
    private(set) var powerHistory: [HistoryPoint] = []
    private(set) var chargingHistory: [HistoryPoint] = []
    private var acceptedGeneration: UInt64 = 0
    private var lastUpdateDate: Date?
    private var historyEnabled = false
    var onUpdate: (() -> Void)?

    func apply(_ update: MetricsUpdate) {
        guard update.generation >= acceptedGeneration else { return }
        if let lastUpdateDate,
           update.snapshot.timestamp.date.timeIntervalSince(lastUpdateDate) > 15 {
            clearHistory()
        }
        acceptedGeneration = update.generation
        lastUpdateDate = update.snapshot.timestamp.date
        snapshot = update.snapshot
        if historyEnabled {
            append(value: update.snapshot.memory.value.map { Double($0.usedBytes) },
                   at: update.snapshot.timestamp, to: &memoryHistory)
            append(value: update.snapshot.cpu.value?.utilizationPercent,
                   at: update.snapshot.timestamp, to: &cpuHistory)
            append(value: update.snapshot.power.value?.watts,
                   at: update.snapshot.timestamp, to: &powerHistory)
            append(value: update.snapshot.charging.value?.watts,
                   at: update.snapshot.timestamp, to: &chargingHistory)
        }
        onUpdate?()
    }

    func setHistoryEnabled(_ enabled: Bool) {
        historyEnabled = enabled
        if !enabled {
            clearHistory()
        }
    }

    private func append(value: Double?, at timestamp: MetricTimestamp, to history: inout [HistoryPoint]) {
        guard let value, value.isFinite else { return }
        history.append(HistoryPoint(id: timestamp.uptimeNanoseconds, date: timestamp.date, value: value))
        let cutoff = timestamp.date.addingTimeInterval(-60)
        history.removeAll { $0.date < cutoff }
    }

    private func clearHistory() {
        memoryHistory.removeAll(keepingCapacity: true)
        cpuHistory.removeAll(keepingCapacity: true)
        powerHistory.removeAll(keepingCapacity: true)
        chargingHistory.removeAll(keepingCapacity: true)
    }
}
