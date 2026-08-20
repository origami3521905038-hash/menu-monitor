import Foundation

/// The only mutable owner of collector sampling. UI receives immutable updates tagged
/// with a generation, so a cancelled pre-sleep or pre-visibility task cannot overwrite
/// newer data after an asynchronous handoff.
public actor MetricsSamplingCoordinator {
    public typealias UpdateSink = @Sendable (MetricsUpdate) async -> Void

    private let updateSink: UpdateSink
    private let memory = MemoryPressureCollector()
    private let cpu = CPULoadCollector()
    private let power: PowerCollector
    private let temperature = TemperatureCollector()
    private let charging = ChargingCollector()

    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var isRunning = false
    private var panelVisible = false
    private var memoryReading: MetricReading<MemoryMetrics> = .unavailable("Waiting to sample")
    private var cpuReading: MetricReading<CPUMetrics> = .unavailable("Waiting to sample")
    private var powerReading: MetricReading<PowerMetrics> = .unavailable("Waiting to sample")
    private var temperatureReading: MetricReading<TemperatureMetrics> = .unavailable("Waiting to sample")
    private var chargingReading: MetricReading<ChargingMetrics> = .unavailable("Waiting to sample")
    private var nextMemorySample: UInt64 = 0
    private var nextCPUSample: UInt64 = 0
    private var nextPowerSample: UInt64 = 0
    private var nextChargingSample: UInt64 = 0

    public init(enableIOReport: Bool = true, updateSink: @escaping UpdateSink) {
        self.power = PowerCollector(enableIOReport: enableIOReport)
        self.updateSink = updateSink
    }

    public func start() async {
        guard !isRunning else { return }
        isRunning = true
        memory.start()
        await replaceTask(resetSchedule: true)
    }

    public func stop() async {
        guard isRunning else { return }
        isRunning = false
        generation &+= 1
        let oldTask = task
        task = nil
        oldTask?.cancel()
        if let oldTask {
            await oldTask.value
        }
        memory.stop()
        cpu.reset()
        power.reset()
        temperatureReading = .unavailable("Waiting to sample")
    }

    public func setPanelVisible(_ visible: Bool) async {
        guard panelVisible != visible else { return }
        panelVisible = visible
        guard isRunning else { return }
        await replaceTask(resetSchedule: true)
    }

    public func handleWillSleep() async {
        await stop()
    }

    public func handleDidWake() async {
        guard !isRunning else { return }
        cpu.reset()
        power.reset()
        await start()
    }

    private func replaceTask(resetSchedule: Bool) async {
        generation &+= 1
        let currentGeneration = generation
        let oldTask = task
        task = nil
        oldTask?.cancel()
        if let oldTask {
            await oldTask.value
        }
        guard isRunning, generation == currentGeneration else { return }
        if resetSchedule {
            nextMemorySample = 0
            nextCPUSample = 0
            nextPowerSample = 0
            nextChargingSample = 0
        }
        task = Task { [weak self] in
            await self?.sampleLoop(generation: currentGeneration)
        }
    }

    private func sampleLoop(generation taskGeneration: UInt64) async {
        while !Task.isCancelled {
            let timestamp = MetricClock.now()
            let update = collectIfDue(timestamp: timestamp, generation: taskGeneration)
            guard generation == taskGeneration, isRunning, !Task.isCancelled else { return }
            await updateSink(update)
            guard generation == taskGeneration, isRunning, !Task.isCancelled else { return }

            let sleepNanoseconds = sleepDuration(after: timestamp)
            do {
                try await Task.sleep(nanoseconds: sleepNanoseconds)
            } catch {
                return
            }
        }
    }

    private func collectIfDue(timestamp: MetricTimestamp, generation: UInt64) -> MetricsUpdate {
        let now = timestamp.uptimeNanoseconds
        if now >= nextMemorySample {
            memoryReading = memory.sample()
            nextMemorySample = deadline(after: now, seconds: panelVisible ? 1 : 15)
        }
        if now >= nextCPUSample {
            cpuReading = cpu.sample(at: timestamp)
            nextCPUSample = deadline(after: now, seconds: panelVisible ? 1 : 5)
        }
        if now >= nextPowerSample {
            powerReading = power.sample(at: timestamp)
            temperatureReading = temperature.sample()
            nextPowerSample = deadline(after: now, seconds: panelVisible ? 2 : 30)
        }
        if now >= nextChargingSample {
            chargingReading = charging.sample()
            nextChargingSample = deadline(after: now, seconds: panelVisible ? 2 : 15)
        }
        return MetricsUpdate(
            generation: generation,
            snapshot: MetricsSnapshot(
                timestamp: timestamp,
                memory: memoryReading,
                cpu: cpuReading,
                power: powerReading,
                temperature: temperatureReading,
                charging: chargingReading
            )
        )
    }

    private func sleepDuration(after timestamp: MetricTimestamp) -> UInt64 {
        let nextDeadline = min(nextMemorySample, nextCPUSample, nextPowerSample, nextChargingSample)
        let remaining = nextDeadline > timestamp.uptimeNanoseconds
            ? nextDeadline - timestamp.uptimeNanoseconds
            : 100_000_000
        // Clamp scheduling wakeups so a clock anomaly never turns into a tight loop.
        return min(max(remaining, 100_000_000), 5_000_000_000)
    }

    private func deadline(after uptimeNanoseconds: UInt64, seconds: UInt64) -> UInt64 {
        let duration = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !duration.overflow else { return UInt64.max }
        let deadline = uptimeNanoseconds.addingReportingOverflow(duration.partialValue)
        return deadline.overflow ? UInt64.max : deadline.partialValue
    }
}
