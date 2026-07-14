import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissionsManager = PermissionsManager.shared
    private let pinManager = PinManager.shared
    private var statusMenuController: StatusMenuController?
    private var controlWindowController: ControlWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let showsControlWindow = ProcessInfo.processInfo.arguments.contains("--control-window")
        NSApp.setActivationPolicy(showsControlWindow ? .regular : .accessory)
        let statusController = StatusMenuController(
            pinManager: pinManager,
            permissionsManager: permissionsManager
        )
        statusMenuController = statusController

        if showsControlWindow {
            let controller = ControlWindowController(
                pinManager: pinManager,
                permissionsManager: permissionsManager,
                hotkeyStatus: { [weak statusController] in
                    statusController?.hotkeyStatusText ?? "Unavailable"
                }
            )
            controlWindowController = controller
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            permissionsManager.offerFirstLaunchScreenRecordingSetup()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusMenuController?.shutdown()
        pinManager.stopAll()
    }
}
