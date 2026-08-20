import CIOHIDTemperatureRuntime
import Foundation

/// Reads the Apple-vendor HID temperature services without opening SMC or a
/// privileged helper. The service layout is private and hardware-dependent, so
/// an absent or malformed layout is a supported unavailable result.
public final class TemperatureCollector: @unchecked Sendable {
    public init() {}

    public func sample() -> MetricReading<TemperatureMetrics> {
        var raw = MMHIDTemperatureSample()
        guard MMHIDTemperatureRuntimeRead(&raw) == 0 else {
            return .unavailable("Temperature sensors are unavailable")
        }

        let cpu = valid(raw.hasCPU ? raw.cpuCelsius : nil)
        let gpu = valid(raw.hasGPU ? raw.gpuCelsius : nil)
        guard cpu != nil || gpu != nil else {
            return .unavailable("Temperature sensors are unavailable")
        }
        return .available(TemperatureMetrics(cpuCelsius: cpu, gpuCelsius: gpu))
    }

    private func valid(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0 ... 150).contains(value) else {
            return nil
        }
        return value
    }
}
