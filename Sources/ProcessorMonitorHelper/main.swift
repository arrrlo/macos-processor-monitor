import Foundation
import ProcessorMonitorSystem

// Root LaunchDaemon. launchd starts it on the first XPC message to its Mach service and it
// exits after 30 s without requests, so it only exists while the menu or dashboard is open.
let daemon = HelperDaemon(
    listener: NSXPCListener(machServiceName: HelperWire.machServiceName),
    sampler: .live(),
    scheduler: DispatchScheduler(queue: DispatchQueue(label: "io.github.arrrlo.macos-processor-monitor.helper.idle")),
    idleTimeout: 30,
    onIdle: { exit(0) }
)
daemon.start()
dispatchMain()
