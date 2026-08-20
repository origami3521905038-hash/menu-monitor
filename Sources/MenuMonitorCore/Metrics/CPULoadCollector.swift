import Darwin
import Foundation

public final class CPULoadCollector: @unchecked Sendable {
    private struct RawTicks {
        let processorCount: Int
        let ticks: [[UInt64]]
    }

    private struct Baseline {
        let timestamp: MetricTimestamp
        let ticks: RawTicks
    }

    private var baseline: Baseline?

    public init() {}

    public func reset() {
        baseline = nil
    }

    public func sample(at timestamp: MetricTimestamp) -> MetricReading<CPUMetrics> {
        guard let current = readTicks() else {
            baseline = nil
            return .unavailable("CPU tick counters are unavailable")
        }
        guard let previous = baseline else {
            baseline = Baseline(timestamp: timestamp, ticks: current)
            return .calibrating
        }
        guard previous.ticks.processorCount == current.processorCount,
              previous.ticks.ticks.count == current.ticks.count else {
            baseline = Baseline(timestamp: timestamp, ticks: current)
            return .calibrating
        }
        guard MetricClock.elapsedSeconds(from: previous.timestamp, to: timestamp) != nil else {
            baseline = Baseline(timestamp: timestamp, ticks: current)
            return .calibrating
        }

        var totalTicks: UInt64 = 0
        var idleTicks: UInt64 = 0
        var perCore: [Double] = []
        for (oldTicks, newTicks) in zip(previous.ticks.ticks, current.ticks) {
            guard oldTicks.count == Int(CPU_STATE_MAX), newTicks.count == Int(CPU_STATE_MAX) else {
                baseline = Baseline(timestamp: timestamp, ticks: current)
                return .calibrating
            }
            var deltas: [UInt64] = []
            for (oldValue, newValue) in zip(oldTicks, newTicks) {
                guard newValue >= oldValue else {
                    baseline = Baseline(timestamp: timestamp, ticks: current)
                    return .calibrating
                }
                deltas.append(newValue.subtractingReportingOverflow(oldValue).partialValue)
            }
            let coreTotal = deltas.reduce(0, &+)
            guard coreTotal > 0 else {
                baseline = Baseline(timestamp: timestamp, ticks: current)
                return .calibrating
            }
            let coreIdle = deltas[Int(CPU_STATE_IDLE)]
            totalTicks &+= coreTotal
            idleTicks &+= coreIdle
            perCore.append(100 * Double(coreTotal - coreIdle) / Double(coreTotal))
        }
        baseline = Baseline(timestamp: timestamp, ticks: current)

        guard totalTicks > 0, idleTicks <= totalTicks else {
            return .unavailable("CPU tick delta is invalid")
        }
        let utilization = 100 * Double(totalTicks - idleTicks) / Double(totalTicks)
        guard utilization.isFinite, utilization >= 0, utilization <= 100,
              perCore.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 100 }) else {
            return .unavailable("CPU utilization is invalid")
        }
        return .available(
            CPUMetrics(
                utilizationPercent: utilization,
                perCoreUtilizationPercent: perCore,
                loadAverage: readLoadAverage()
            )
        )
    }

    private func readTicks() -> RawTicks? {
        var processorCount: natural_t = 0
        var information: processor_info_array_t?
        var informationCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &information,
            &informationCount
        )
        guard result == KERN_SUCCESS, let information else {
            return nil
        }
        // The kernel owns this allocation regardless of whether its returned shape
        // matches our expected processor layout, so release it before validating.
        defer {
            let address = vm_address_t(UInt(bitPattern: information))
            let byteCount = vm_size_t(informationCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            _ = vm_deallocate(mach_task_self_, address, byteCount)
        }

        let expectedCount = processorCount.multipliedReportingOverflow(
            by: natural_t(CPU_STATE_MAX)
        )
        guard processorCount > 0,
              !expectedCount.overflow,
              informationCount == mach_msg_type_number_t(expectedCount.partialValue) else {
            return nil
        }

        var ticks: [[UInt64]] = []
        ticks.reserveCapacity(Int(processorCount))
        for processor in 0 ..< Int(processorCount) {
            let offset = processor * Int(CPU_STATE_MAX)
            let values = (0 ..< Int(CPU_STATE_MAX)).map { state in
                UInt64(UInt32(bitPattern: information[offset + state]))
            }
            ticks.append(values)
        }
        return RawTicks(processorCount: Int(processorCount), ticks: ticks)
    }

    private func readLoadAverage() -> [Double] {
        var values = [Double](repeating: 0, count: 3)
        guard getloadavg(&values, Int32(values.count)) == values.count else { return [] }
        return values.filter { $0.isFinite && $0 >= 0 }
    }
}
