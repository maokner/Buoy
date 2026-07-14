import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissionsManager = PermissionsManager.shared
    private let pinManager = PinManager.shared
    private var statusMenuController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusMenuController = StatusMenuController(
            pinManager: pinManager,
            permissionsManager: permissionsManager
        )
        permissionsManager.offerFirstLaunchScreenRecordingSetup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusMenuController?.shutdown()
        pinManager.stopAll()
    }
}
