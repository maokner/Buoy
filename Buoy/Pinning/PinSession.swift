import Foundation

enum PinMode {
    case detached
    case pinnedInPlace
}

@MainActor
final class PinSession {
    let id = UUID()
    let source: WindowDescriptor
    let capture: WindowCapture
    let panel: PinOverlayPanel
    let mode: PinMode

    var opacity: CGFloat {
        didSet {
            opacity = min(max(opacity, 0.15), 1)
            panel.alphaValue = opacity
        }
    }

    init(source: WindowDescriptor, opacity: CGFloat = 1, mode: PinMode = .detached) {
        self.source = source
        self.opacity = opacity
        self.mode = mode
        panel = PinOverlayPanel(
            sourceFrame: source.frame,
            title: "\(source.owningAppName) - \(source.displayTitle)"
        )
        panel.alphaValue = opacity
        capture = WindowCapture(renderer: panel.captureView)
    }

    func start() async throws {
        try await capture.start(window: source.window)
        panel.orderFrontRegardless()
    }

    func stop() async {
        panel.orderOut(nil)
        panel.close()
        await capture.stop()
    }
}

