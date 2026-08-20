import Darwin
import Dispatch
import Foundation

/// Reads VM statistics and owns the pressure event source. The source callback is
/// intentionally limited to a lock-protected enum so it cannot race actor state.
public final class MemoryPressureCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.menumonitor.memory-pressure", qos: .utility)
    private var pressure: MemoryPressureLevel = .normal
    private var source: DispatchSourceMemoryPressure?
    private let pageSize: UInt64?
    private let physicalBytes: UInt64

    public init() {
        var rawPageSize: vm_size_t = 0
        let result = host_page_size(mach_host_self(), &rawPageSize)
        if result == KERN_SUCCESS, rawPageSize > 0, rawPageSize <= 1 << 20 {
            self.pageSize = UInt64(rawPageSize)
        } else {
            self.pageSize = nil
        }
        self.physicalBytes = ProcessInfo.processInfo.physicalMemory
    }

    deinit {
        stop()
    }

    public func start() {
        lock.lock()
        guard source == nil else {
            lock.unlock()
            return
        }
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: queue
        )
        self.source = source
        lock.unlock()

        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            self.updatePressure(from: source.data)
        }
        source.resume()
    }

    public func stop() {
        lock.lock()
        let activeSource = source
        source = nil
        lock.unlock()

        activeSource?.setEventHandler {}
        activeSource?.cancel()
    }

    public func sample() -> MetricReading<MemoryMetrics> {
        guard let pageSize else {
            return .unavailable("Host page size is unavailable")
        }

        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return .unavailable("VM statistics are unavailable")
        }

        let activePages = UInt64(statistics.active_count)
        let inactivePages = UInt64(statistics.inactive_count)
        let purgeablePages = UInt64(statistics.purgeable_count)
        let wiredPages = UInt64(statistics.wire_count)
        let compressedPages = UInt64(statistics.compressor_page_count)
        guard inactivePages >= purgeablePages,
              let activeBytes = bytes(for: activePages, pageSize: pageSize),
              let inactiveBytes = bytes(for: inactivePages - purgeablePages, pageSize: pageSize),
              let wiredBytes = bytes(for: wiredPages, pageSize: pageSize),
              let compressedBytes = bytes(for: compressedPages, pageSize: pageSize),
              let usedBytes = checkedSum([activeBytes, inactiveBytes, wiredBytes, compressedBytes]),
              physicalBytes > 0,
              usedBytes <= physicalBytes else {
            return .unavailable("VM page counters are invalid")
        }

        return .available(
            MemoryMetrics(
                pressure: currentPressure(),
                physicalBytes: physicalBytes,
                usedBytes: usedBytes,
                wiredBytes: wiredBytes,
                compressedBytes: compressedBytes,
                swapUsedBytes: currentSwapUsedBytes()
            )
        )
    }

    private func updatePressure(from events: DispatchSource.MemoryPressureEvent) {
        let next: MemoryPressureLevel
        if events.contains(.critical) {
            next = .critical
        } else if events.contains(.warning) {
            next = .warning
        } else if events.contains(.normal) {
            next = .normal
        } else {
            return
        }

        lock.lock()
        pressure = next
        lock.unlock()
    }

    private func currentPressure() -> MemoryPressureLevel {
        lock.lock()
        defer { lock.unlock() }
        return pressure
    }

    private func bytes(for pages: UInt64, pageSize: UInt64) -> UInt64? {
        let product = pages.multipliedReportingOverflow(by: pageSize)
        return product.overflow ? nil : product.partialValue
    }

    private func checkedSum(_ values: [UInt64]) -> UInt64? {
        var total: UInt64 = 0
        for value in values {
            let result = total.addingReportingOverflow(value)
            guard !result.overflow else { return nil }
            total = result.partialValue
        }
        return total
    }

    private func currentSwapUsedBytes() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            sysctlbyname("vm.swapusage", pointer, &size, nil, 0)
        }
        guard status == 0, size == MemoryLayout<xsw_usage>.size else { return nil }
        return usage.xsu_used
    }
}
