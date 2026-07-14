import Foundation

enum PinMode {
    case detached
    case pinnedInPlace

    var menuLabel: String {
        switch self {
        case .detached: "Float"
        case .pinnedInPlace: "Pinned"
        }
    }
}

@MainActor
final class PinSession {
    let id = UUID()
    let source: WindowDescriptor
    let capture: WindowCapture
    let panel: PinOverlayPanel
    let mode: PinMode
    var onSourceClosed: (() -> Void)?

    private var windowTracker: WindowTracker?
    private var interactionRouter: InteractionRouter?
    private var stallTimer: Timer?
    private var lastFrameDate = Date()
    private var sourceIsMinimized = false
    private var captureIsStalled = false

    var opacity: CGFloat {
        didSet {
            opacity = min(max(opacity, 0.15), 1)
            panel.setCaptureStalled(captureIsStalled, baseOpacity: opacity)
        }
    }

    init(source: WindowDescriptor, opacity: CGFloat = 1, mode: PinMode = .pinnedInPlace) {
        self.source = source
        self.opacity = opacity
        self.mode = mode
        panel = PinOverlayPanel(
            sourceFrame: source.frame,
            title: "\(source.owningAppName) - \(source.displayTitle)",
            mode: mode
        )
        panel.alphaValue = opacity
        capture = WindowCapture(renderer: panel.captureView)
    }

    func start() async throws {
        capture.onFrameDelivered = { [weak self] in
            self?.handleFrameDelivered()
        }
        capture.onError = { [weak self] _ in
            self?.setCaptureStalled(true)
        }
        try await capture.start(window: source.window)

        let tracker = WindowTracker(source: source)
        if mode == .pinnedInPlace {
            tracker.onFrameChanged = { [weak self] frame in
                self?.panel.setFrame(frame, display: true)
            }
        }
        tracker.onMinimizedChanged = { [weak self] isMinimized in
            self?.handleMinimizedChanged(isMinimized)
        }
        tracker.onWindowClosed = { [weak self] in
            self?.onSourceClosed?()
        }
        tracker.startTracking()
        windowTracker = tracker

        if mode == .pinnedInPlace {
            let router = InteractionRouter(
                sourceProcessID: source.processID,
                panel: panel,
                tracker: tracker
            )
            router.startRouting()
            interactionRouter = router
        }

        panel.orderFrontRegardless()
    }

    func stop() async {
        stallTimer?.invalidate()
        stallTimer = nil
        interactionRouter?.stopRouting()
        interactionRouter = nil
        windowTracker?.stopTracking()
        windowTracker = nil
        capture.onFrameDelivered = nil
        capture.onError = nil
        panel.orderOut(nil)
        panel.close()
        await capture.stop()
    }

    private func handleFrameDelivered() {
        lastFrameDate = Date()
        if captureIsStalled {
            setCaptureStalled(false)
        }
    }

    private func handleMinimizedChanged(_ isMinimized: Bool) {
        sourceIsMinimized = isMinimized
        if isMinimized {
            startStallTimerIfNeeded()
        } else {
            stallTimer?.invalidate()
            stallTimer = nil
            setCaptureStalled(false)
        }
    }

    private func startStallTimerIfNeeded() {
        guard stallTimer == nil else { return }
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.sourceIsMinimized else { return }
                self.setCaptureStalled(Date().timeIntervalSince(self.lastFrameDate) > 0.45)
            }
        }
        stallTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func setCaptureStalled(_ isStalled: Bool) {
        guard captureIsStalled != isStalled else { return }
        captureIsStalled = isStalled
        panel.setCaptureStalled(isStalled, baseOpacity: opacity)
    }
}
