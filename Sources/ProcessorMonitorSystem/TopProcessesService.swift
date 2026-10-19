import Darwin
import Dispatch
import ProcessorMonitorCore

extension ProcessUsageSampler {
    /// Samples the local process table: 250 ms first window, baselines reused for up to 5 s.
    public static func live(reader: ProcessTableReader = ProcessTableReader()) -> ProcessUsageSampler {
        ProcessUsageSampler(
            timebase: ProcessTableReader.liveTimebase(),
            minimumWindow: 250_000_000,
            maximumBaselineAge: 5_000_000_000,
            snapshot: reader.snapshot,
            sleep: { nanoseconds in usleep(useconds_t(nanoseconds / 1_000)) }
        )
    }
}

/// Asks the privileged helper first; if it is not installed or not running, measures the
/// processes this user can see in-process instead.
public final class TopProcessesService: TopProcessesProviding {
    public typealias HelperCall = @Sendable (_ limit: Int, _ completion: @escaping @Sendable ([ProcessUsage]?) -> Void) -> Void

    private let helper: HelperCall
    private let local: ProcessUsageSampler
    private let queue = DispatchQueue(label: "io.github.arrrlo.macos-processor-monitor.local-processes", qos: .utility)

    public init(helper: @escaping HelperCall, local: ProcessUsageSampler) {
        self.helper = helper
        self.local = local
    }

    public static func live() -> TopProcessesService {
        TopProcessesService(helper: HelperClient.privileged().topProcesses, local: .live())
    }

    public func topProcesses(limit: Int, completion: @escaping @Sendable (TopProcessesResult) -> Void) {
        let local = local
        let queue = queue
        helper(limit) { processes in
            guard let processes else {
                queue.async { completion(TopProcessesResult(processes: local.top(limit: limit), scope: .currentUser)) }
                return
            }
            completion(TopProcessesResult(processes: processes, scope: .allProcesses))
        }
    }
}
