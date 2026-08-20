import Foundation
import MenuMonitorCore

@main
struct MenuMonitorProbe {
    private struct Options {
        var samples = 4
        var interval = 2.0
        var enableIOReport = true
    }

    static func main() {
        do {
            let options = try parse(CommandLine.arguments.dropFirst())
            run(options: options)
        } catch {
            fputs("MenuMonitorProbe: \(error.localizedDescription)\n", stderr)
            fputs("Usage: MenuMonitorProbe [--samples N] [--interval SECONDS] [--no-ioreport]\n", stderr)
            Foundation.exit(64)
        }
    }

    private static func run(options: Options) {
        let memory = MemoryPressureCollector()
        let cpu = CPULoadCollector()
        let power = PowerCollector(enableIOReport: options.enableIOReport)
        let temperature = TemperatureCollector()
        let charging = ChargingCollector()
        memory.start()
        defer { memory.stop() }

        for index in 0 ..< options.samples {
            let timestamp = MetricClock.now()
            let line = [
                "sample=\(index + 1)/\(options.samples)",
                "time=\(ISO8601DateFormatter().string(from: timestamp.date))",
                describeMemory(memory.sample()),
                describeCPU(cpu.sample(at: timestamp)),
                describePower(power.sample(at: timestamp)),
                describeTemperature(temperature.sample()),
                describeCharging(charging.sample())
            ].joined(separator: " | ")
            print(line)

            if index + 1 < options.samples {
                Thread.sleep(forTimeInterval: options.interval)
            }
        }
    }

    private static func parse(_ arguments: ArraySlice<String>) throws -> Options {
        enum ParseError: LocalizedError {
            case invalid(String)

            var errorDescription: String? {
                switch self {
                case let .invalid(message): return message
                }
            }
        }

        var options = Options()
        var index = arguments.startIndex
        while index < arguments.endIndex {
            switch arguments[index] {
            case "--samples":
                let valueIndex = arguments.index(after: index)
                guard valueIndex < arguments.endIndex,
                      let value = Int(arguments[valueIndex]), (1 ... 120).contains(value) else {
                    throw ParseError.invalid("--samples must be between 1 and 120")
                }
                options.samples = value
                index = arguments.index(after: valueIndex)
            case "--interval":
                let valueIndex = arguments.index(after: index)
                guard valueIndex < arguments.endIndex,
                      let value = Double(arguments[valueIndex]), value.isFinite,
                      (0.1 ... 30).contains(value) else {
                    throw ParseError.invalid("--interval must be between 0.1 and 30 seconds")
                }
                options.interval = value
                index = arguments.index(after: valueIndex)
            case "--no-ioreport":
                options.enableIOReport = false
                index = arguments.index(after: index)
            case "--help", "-h":
                throw ParseError.invalid("help requested")
            default:
                throw ParseError.invalid("unknown option \(arguments[index])")
            }
        }
        return options
    }

    private static func describeMemory(_ reading: MetricReading<MemoryMetrics>) -> String {
        switch reading {
        case .calibrating:
            return "memory=calibrating"
        case let .unavailable(reason):
            return "memory=unavailable(\(reason))"
        case let .available(value):
            let swap = value.swapUsedBytes.map(MetricFormatting.bytes) ?? "unavailable"
            return "memory=\(value.pressure.rawValue),used=\(MetricFormatting.bytes(value.usedBytes)),wired=\(MetricFormatting.bytes(value.wiredBytes)),compressed=\(MetricFormatting.bytes(value.compressedBytes)),swap=\(swap)"
        }
    }

    private static func describeCPU(_ reading: MetricReading<CPUMetrics>) -> String {
        switch reading {
        case .calibrating:
            return "cpu=calibrating"
        case let .unavailable(reason):
            return "cpu=unavailable(\(reason))"
        case let .available(value):
            let load = value.loadAverage.map { MetricFormatting.decimal($0, maximumFractionDigits: 2) }.joined(separator: ",")
            return "cpu=\(MetricFormatting.percent(value.utilizationPercent)),load=\(load),cores=\(value.perCoreUtilizationPercent.count)"
        }
    }

    private static func describePower(_ reading: MetricReading<PowerMetrics>) -> String {
        switch reading {
        case .calibrating:
            return "power=calibrating"
        case let .unavailable(reason):
            return "power=unavailable(\(reason))"
        case let .available(value):
            let components = value.components.map {
                "\($0.name):\(MetricFormatting.watts($0.watts))"
            }.joined(separator: ",")
            return "power=\(MetricFormatting.watts(value.watts)),source=\(value.sourceLabel),components=\(components)"
        }
    }

    private static func describeCharging(_ reading: MetricReading<ChargingMetrics>) -> String {
        switch reading {
        case .calibrating:
            return "charging=calibrating"
        case let .unavailable(reason):
            return "charging=unavailable(\(reason))"
        case let .available(value):
            let rated = value.adapterRatedWatts.map(MetricFormatting.watts) ?? "unavailable"
            return "charging=\(MetricFormatting.watts(value.watts)),state=\(value.state.rawValue),adapter=\(rated)"
        }
    }

    private static func describeTemperature(_ reading: MetricReading<TemperatureMetrics>) -> String {
        switch reading {
        case .calibrating:
            return "temperature=calibrating"
        case let .unavailable(reason):
            return "temperature=unavailable(\(reason))"
        case let .available(value):
            let cpu = value.cpuCelsius.map { "\(MetricFormatting.decimal($0, maximumFractionDigits: 1)) C" } ?? "unavailable"
            let gpu = value.gpuCelsius.map { "\(MetricFormatting.decimal($0, maximumFractionDigits: 1)) C" } ?? "unavailable"
            return "temperature=cpu:\(cpu),gpu:\(gpu)"
        }
    }
}
