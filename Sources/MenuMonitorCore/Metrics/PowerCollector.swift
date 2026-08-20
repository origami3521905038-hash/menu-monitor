import CIOReportRuntime
import Foundation

/// A narrow runtime wrapper over private IOReport energy counters. It is deliberately
/// schema-bound: an unrecognized hardware layout is unavailable rather than guessed.
public final class PowerCollector: @unchecked Sendable {
    private struct Baseline {
        let timestamp: MetricTimestamp
        let joulesByName: [String: Double]
    }

    private enum DecodeResult {
        case success([String: Double])
        case failure(String)
    }

    private static let requiredChannels: Set<String> = ["CPU Energy", "GPU Energy"]
    private static let optionalChannels: Set<String> = ["DRAM Energy"]
    private var runtime: OpaquePointer?
    private var baseline: Baseline?
    private var disabledReason: String?

    public init(enableIOReport: Bool = true) {
        guard enableIOReport else {
            disabledReason = "IOReport disabled by request"
            return
        }
        runtime = MMIOReportRuntimeCreate()
        if runtime == nil {
            disabledReason = "IOReport runtime is unavailable"
        } else if let runtime, let reason = runtimeFailure(runtime), !reason.isEmpty {
            disabledReason = reason
        }
    }

    deinit {
        if let runtime {
            MMIOReportRuntimeDestroy(runtime)
        }
    }

    public func reset() {
        baseline = nil
    }

    public func sample(at timestamp: MetricTimestamp) -> MetricReading<PowerMetrics> {
        if let disabledReason {
            return .unavailable(disabledReason)
        }
        guard let runtime else {
            return .unavailable("IOReport runtime is unavailable")
        }

        var records = Array(repeating: MMIOReportChannel(), count: 32)
        var count: size_t = 0
        let result = records.withUnsafeMutableBufferPointer { buffer in
            MMIOReportRuntimeRead(runtime, buffer.baseAddress, buffer.count, &count)
        }
        guard result == MMIOReportResultOK else {
            let reason = runtimeFailure(runtime) ?? "IOReport sample is unavailable"
            disable(reason)
            return .unavailable(reason)
        }
        guard count <= records.count else {
            disable("IOReport sample count is invalid")
            return .unavailable("IOReport sample count is invalid")
        }

        let decoded = decode(records.prefix(Int(count)))
        switch decoded {
        case let .failure(reason):
            disable(reason)
            return .unavailable(reason)
        case let .success(current):
            guard let previous = baseline else {
                baseline = Baseline(timestamp: timestamp, joulesByName: current)
                return .calibrating
            }
            guard previous.joulesByName.keys == current.keys,
                  let elapsed = MetricClock.elapsedSeconds(from: previous.timestamp, to: timestamp),
                  elapsed >= 0.1,
                  // The hidden sampler intentionally reads IOReport every 30 seconds.
                  // Leave room for ordinary scheduler delay, while rejecting a stalled
                  // or missed sleep/wake transition rather than presenting stale power.
                  elapsed <= 90 else {
                baseline = Baseline(timestamp: timestamp, joulesByName: current)
                return .calibrating
            }

            var components: [PowerComponent] = []
            var totalWatts = 0.0
            for name in current.keys.sorted() {
                guard let oldEnergy = previous.joulesByName[name],
                      let newEnergy = current[name],
                      newEnergy >= oldEnergy else {
                    baseline = Baseline(timestamp: timestamp, joulesByName: current)
                    return .calibrating
                }
                let watts = (newEnergy - oldEnergy) / elapsed
                guard watts.isFinite, watts >= 0, watts <= 150 else {
                    disable("IOReport power delta is implausible")
                    return .unavailable("IOReport power delta is implausible")
                }
                components.append(PowerComponent(name: componentLabel(for: name), watts: watts))
                totalWatts += watts
            }
            baseline = Baseline(timestamp: timestamp, joulesByName: current)
            guard totalWatts.isFinite, totalWatts >= 0, totalWatts <= 250 else {
                disable("IOReport total power is implausible")
                return .unavailable("IOReport total power is implausible")
            }
            let orderedNames = components.map(\.name).joined(separator: " + ")
            return .available(
                PowerMetrics(
                    watts: totalWatts,
                    components: components,
                    sourceLabel: "\(orderedNames) SoC estimate"
                )
            )
        }
    }

    private func decode(_ records: ArraySlice<MMIOReportChannel>) -> DecodeResult {
        var energies: [String: Double] = [:]
        let allowed = Self.requiredChannels.union(Self.optionalChannels)
        for record in records {
            let name = cString(record.name)
            guard allowed.contains(name) else { continue }
            guard energies[name] == nil else {
                return .failure("IOReport channel schema is ambiguous")
            }
            guard let joules = joules(value: record.cumulativeValue, unit: cString(record.unit)) else {
                return .failure("IOReport energy unit is unsupported")
            }
            energies[name] = joules
        }
        guard Self.requiredChannels.isSubset(of: Set(energies.keys)) else {
            return .failure("Required IOReport energy channels are unavailable")
        }
        return .success(energies)
    }

    private func joules(value: Int64, unit: String) -> Double? {
        guard value != .min, value >= 0 else { return nil }
        let scale: Double
        switch unit {
        case "nJ": scale = 1e-9
        case "uJ": scale = 1e-6
        case "mJ": scale = 1e-3
        default: return nil
        }
        let result = Double(value) * scale
        return result.isFinite && result >= 0 ? result : nil
    }

    private func cString<T>(_ value: T) -> String {
        withUnsafeBytes(of: value) { buffer in
            guard let base = buffer.bindMemory(to: CChar.self).baseAddress else { return "" }
            return String(cString: base)
        }
    }

    private func componentLabel(for channelName: String) -> String {
        channelName.replacingOccurrences(of: " Energy", with: "")
    }

    private func runtimeFailure(_ runtime: OpaquePointer) -> String? {
        guard let pointer = MMIOReportRuntimeFailure(runtime) else { return nil }
        return String(cString: pointer)
    }

    private func disable(_ reason: String) {
        disabledReason = reason
        baseline = nil
    }
}
