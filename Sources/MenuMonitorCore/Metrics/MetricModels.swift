import Foundation

public enum MetricReading<Value: Sendable>: Sendable {
    case calibrating
    case available(Value)
    case unavailable(String)

    public var value: Value? {
        guard case let .available(value) = self else { return nil }
        return value
    }

    public var statusText: String {
        switch self {
        case .calibrating:
            return "Calibrating"
        case .available:
            return "Available"
        case let .unavailable(reason):
            return reason
        }
    }
}

extension MetricReading: Equatable where Value: Equatable {}

public enum MemoryPressureLevel: String, Sendable, Equatable, CaseIterable {
    case normal
    case warning
    case critical

    public var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

public struct MemoryMetrics: Sendable, Equatable {
    public let pressure: MemoryPressureLevel
    public let physicalBytes: UInt64
    public let usedBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let swapUsedBytes: UInt64?

    public init(
        pressure: MemoryPressureLevel,
        physicalBytes: UInt64,
        usedBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        swapUsedBytes: UInt64?
    ) {
        self.pressure = pressure
        self.physicalBytes = physicalBytes
        self.usedBytes = usedBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.swapUsedBytes = swapUsedBytes
    }
}

public struct CPUMetrics: Sendable, Equatable {
    public let utilizationPercent: Double
    public let perCoreUtilizationPercent: [Double]
    public let loadAverage: [Double]

    public init(utilizationPercent: Double, perCoreUtilizationPercent: [Double], loadAverage: [Double]) {
        self.utilizationPercent = utilizationPercent
        self.perCoreUtilizationPercent = perCoreUtilizationPercent
        self.loadAverage = loadAverage
    }
}

public struct PowerComponent: Sendable, Equatable, Identifiable {
    public let name: String
    public let watts: Double

    public var id: String { name }

    public init(name: String, watts: Double) {
        self.name = name
        self.watts = watts
    }
}

public struct PowerMetrics: Sendable, Equatable {
    public let watts: Double
    public let components: [PowerComponent]
    public let sourceLabel: String

    public init(watts: Double, components: [PowerComponent], sourceLabel: String) {
        self.watts = watts
        self.components = components
        self.sourceLabel = sourceLabel
    }
}

public enum ChargingState: String, Sendable, Equatable {
    case charging
    /// External power is feeding the Mac while the battery is full and idle.
    case bypass
    case notCharging
    case unavailable
}

public struct ChargingMetrics: Sendable, Equatable {
    public let watts: Double
    public let state: ChargingState
    public let adapterRatedWatts: Double?

    public init(watts: Double, state: ChargingState, adapterRatedWatts: Double?) {
        self.watts = watts
        self.state = state
        self.adapterRatedWatts = adapterRatedWatts
    }
}

/// Read-only chip temperature telemetry. Either field may be unavailable on a
/// particular Mac; the UI keeps the missing side explicit instead of guessing.
public struct TemperatureMetrics: Sendable, Equatable {
    public let cpuCelsius: Double?
    public let gpuCelsius: Double?

    public init(cpuCelsius: Double?, gpuCelsius: Double?) {
        self.cpuCelsius = cpuCelsius
        self.gpuCelsius = gpuCelsius
    }
}

public struct MetricTimestamp: Sendable, Equatable {
    public let uptimeNanoseconds: UInt64
    public let date: Date

    public init(uptimeNanoseconds: UInt64, date: Date) {
        self.uptimeNanoseconds = uptimeNanoseconds
        self.date = date
    }
}

public struct MetricsSnapshot: Sendable, Equatable {
    public let timestamp: MetricTimestamp
    public let memory: MetricReading<MemoryMetrics>
    public let cpu: MetricReading<CPUMetrics>
    public let power: MetricReading<PowerMetrics>
    public let temperature: MetricReading<TemperatureMetrics>
    public let charging: MetricReading<ChargingMetrics>

    public init(
        timestamp: MetricTimestamp,
        memory: MetricReading<MemoryMetrics>,
        cpu: MetricReading<CPUMetrics>,
        power: MetricReading<PowerMetrics>,
        temperature: MetricReading<TemperatureMetrics>,
        charging: MetricReading<ChargingMetrics>
    ) {
        self.timestamp = timestamp
        self.memory = memory
        self.cpu = cpu
        self.power = power
        self.temperature = temperature
        self.charging = charging
    }
}

public struct MetricsUpdate: Sendable, Equatable {
    public let generation: UInt64
    public let snapshot: MetricsSnapshot

    public init(generation: UInt64, snapshot: MetricsSnapshot) {
        self.generation = generation
        self.snapshot = snapshot
    }
}
