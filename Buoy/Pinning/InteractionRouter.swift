import AppKit

@MainActor
protocol InteractionRouting: AnyObject {
    func startRouting()
    func stopRouting()
}

@MainActor
final class InteractionRouter: InteractionRouting {
    private let sourceProcessID: pid_t
    private weak var panel: PinOverlayPanel?
    private weak var tracker: WindowTracker?
    private var activationObserver: NSObjectProtocol?
    private var overlayIsHidden = true
    private var raiseInProgress = false

    init(sourceProcessID: pid_t, panel: PinOverlayPanel, tracker: WindowTracker) {
        self.sourceProcessID = sourceProcessID
        self.panel = panel
        self.tracker = tracker
    }

    func startRouting() {
        panel?.onInterceptedMouseDown = { [weak self] in
            self?.interceptMouseDown()
        }
        tracker?.onFocusChanged = { [weak self] sourceIsFocused in
            self?.handleFocusChange(sourceIsFocused: sourceIsFocused)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication else {
                    return
                }
                self.handleApplicationActivation(processID: application.processIdentifier)
            }
        }

        if tracker?.sourceWindowIsFocused() == true {
            overlayIsHidden = true
            panel?.orderOut(nil)
        } else {
            showOverlay()
        }
    }

    func stopRouting() {
        panel?.onInterceptedMouseDown = nil
        tracker?.onFocusChanged = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    private func interceptMouseDown() {
        guard !raiseInProgress else { return }
        raiseInProgress = true

        let application = NSRunningApplication(processIdentifier: sourceProcessID)
        application?.activate(options: [.activateAllWindows])
        _ = tracker?.raiseSourceWindow()
        hideOverlay()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.raiseInProgress = false
            if self.tracker?.sourceWindowIsFocused() == false {
                self.showOverlay()
            }
        }
    }

    private func handleApplicationActivation(processID: pid_t) {
        if processID != sourceProcessID {
            showOverlay()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            guard let sourceIsFocused = self.tracker?.sourceWindowIsFocused() else { return }
            self.handleFocusChange(sourceIsFocused: sourceIsFocused)
        }
    }

    private func handleFocusChange(sourceIsFocused: Bool) {
        if sourceIsFocused {
            hideOverlay()
        } else {
            showOverlay()
        }
    }

    private func hideOverlay() {
        guard !overlayIsHidden else { return }
        overlayIsHidden = true
        panel?.orderOut(nil)
    }

    private func showOverlay() {
        guard overlayIsHidden else { return }
        if let frame = tracker?.currentFrame {
            panel?.setFrame(frame, display: true)
        }
        overlayIsHidden = false
        panel?.orderFrontRegardless()
    }
}
