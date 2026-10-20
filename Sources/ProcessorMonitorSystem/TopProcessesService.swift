import Darwin
import Dispatch
import ProcessorMonitorCore

extension ProcessUsageSampler {
    /// Waits out the rest of a measurement window.
    static let pause: @Sendable (UInt64) -> Void = { nanoseconds in usleep(useconds_t(nanoseconds / 1_000)) }

    /// Samples the local process table: 250 ms first window, baselines reused for up to 5 s.
    public static func live(reader: ProcessTableReader = ProcessTableReader()) -> ProcessUsageSampler {
        ProcessUsageSampler(
            timebase: ProcessTableReader.liveTimebase(),
            minimumWindow: 250_000_000,
            maximumBaselineAge: 5_000_000_000,
            snapshot: reader.snapshot,
            sleep: pause
        )
    }
}

/// Asks the privileged helper first; if it is not installed or not running, measures the
/// processes this user can see in-process instead.
public final class TopProcessesService: TopProcessesProviding {
    public typealias HelperCall = @Sendable (_ limit: Int, _ completion: @escaping @Sendable ([ProcessUsage]?) -> Void) -> Void

    private let helper: HelperCall
    private let local: ProcessUsageSampler
    private let executablePath: @Sendable (Int32) -> String?
    private let queue = DispatchQueue(label: "io.github.arrrlo.macos-processor-monitor.local-processes", qos: .utility)

    public init(helper: @escaping HelperCall, local: ProcessUsageSampler, executablePath: @escaping @Sendable (Int32) -> String?) {
        self.helper = helper
        self.local = local
        self.executablePath = executablePath
    }

    public static func live() -> TopProcessesService {
        TopProcessesService(helper: HelperClient.privileged().topProcesses, local: .live(), executablePath: ProcessNames.liveExecutablePath)
    }

    public func topProcesses(limit: Int, completion: @escaping @Sendable (TopProcessesResult) -> Void) {
        let local = local
        let queue = queue
        let executablePath = executablePath
        helper(limit) { processes in
            guard let processes else {
                queue.async {
                    let mine = ProcessNames.refine(local.top(limit: limit), executablePath: executablePath)
                    completion(TopProcessesResult(processes: mine, scope: .currentUser))
                }
                return
            }
            completion(TopProcessesResult(processes: ProcessNames.refine(processes, executablePath: executablePath), scope: .allProcesses))
        }
    }
}
