import AppKit
import ProcessorMonitorUI

// Entry point. Only the calls that cannot run inside tests (quitting, the About panel,
// activating the app, the run loop) live here; everything else is in ProcessorMonitorUI.
let app = NSApplication.shared
let actions = AppActions(
    activate: { app.activate() },
    showAbout: {
        app.activate()
        app.orderFrontStandardAboutPanel(nil)
    },
    quit: { app.terminate(nil) }
)
let delegate = AppDelegate(
    makeController: { AppController.live(actions: actions) },
    otherInstances: { SingleInstance.otherInstances() },
    terminate: { app.terminate(nil) }
)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
