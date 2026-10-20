import Foundation
import IOKit
import ProcessorMonitorCore

/// Reads GPU load from the graphics driver's IORegistry entry (`AGXAccelerator`), which keeps its own
/// utilization statistics current. A read is one property copy (about 0.02 ms) and wakes nothing.
public final class GPUReader: Sendable {
    /// The registry calls, so tests can stand in for the GPU a VM does not have.
    public struct Source: Sendable {
        let service: @Sendable () -> io_service_t
        let property: @Sendable (io_service_t, String) -> Any?
        let release: @Sendable (io_object_t) -> Void

        public static let live = Source(
            service: { IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator")) },
            property: { IORegistryEntryCreateCFProperty($0, $1 as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() },
            release: RegistryAccess.live.release
        )
    }

    private let source: Source
    /// Looked up once; 0 (no GPU entry, as in a VM) makes every read return nil.
    private let service: io_service_t

    public init(source: Source = .live) {
        self.source = source
        service = source.service()
    }

    deinit {
        source.release(service)
    }

    /// The chip's name and GPU core count. They never change, so this is read once at launch.
    public func info() -> GPUInfo? {
        guard let name = source.property(service, "model") as? String,
              let cores = source.property(service, "gpu-core-count") as? Int else { return nil }
        return GPUInfo(name: name, coreCount: cores)
    }

    public func read() -> GPULoad? {
        GPUStatisticsParser.load(from: source.property(service, "PerformanceStatistics"))
    }
}

/// Reads the driver's `PerformanceStatistics` dictionary, whose shares are whole percents.
enum GPUStatisticsParser {
    static func load(from statistics: Any?) -> GPULoad? {
        guard let statistics = statistics as? [String: Any],
              let device = statistics["Device Utilization %"] as? Int,
              let renderer = statistics["Renderer Utilization %"] as? Int,
              let tiler = statistics["Tiler Utilization %"] as? Int else { return nil }
        return GPULoad(device: Double(device) / 100, renderer: Double(renderer) / 100, tiler: Double(tiler) / 100)
    }
}
