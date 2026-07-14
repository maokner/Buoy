import AppKit

@MainActor
final class PinOverlayPanel: NSPanel {
    let captureView = SampleBufferView(frame: .zero)
    var onClose: (() -> Void)?
    var onInterceptedMouseDown: (() -> Void)? {
        didSet {
            interactionView?.onInterceptedMouseDown = onInterceptedMouseDown
        }
    }

    private weak var interactionView: OverlayInteractionView?

    init(sourceFrame: CGRect, title: String, mode: PinMode) {
        let initialFrame = Self.initialPanelFrame(for: sourceFrame, mode: mode)
        let styleMask: NSWindow.StyleMask = mode == .detached
            ? [.borderless, .nonactivatingPanel, .resizable]
            : [.borderless, .nonactivatingPanel]
        super.init(
            contentRect: initialFrame,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        self.title = title
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        sharingType = .none
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        ignoresMouseEvents = false
        isMovableByWindowBackground = mode == .detached
        minSize = NSSize(width: 240, height: 135)
        contentMinSize = minSize
        if mode == .detached {
            contentAspectRatio = sourceFrame.size
        }
        animationBehavior = .utilityWindow

        configureContent(mode: mode)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setCaptureStalled(_ isStalled: Bool, baseOpacity: CGFloat) {
        alphaValue = isStalled ? baseOpacity * 0.78 : baseOpacity
    }

    private func configureContent(mode: PinMode) {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.cornerRadius = 9
        container.layer?.masksToBounds = true

        captureView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(captureView)

        let interactionView = OverlayInteractionView(mode: mode)
        interactionView.translatesAutoresizingMaskIntoConstraints = false
        interactionView.onInterceptedMouseDown = onInterceptedMouseDown
        container.addSubview(interactionView)
        self.interactionView = interactionView

        let closeButton = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Unpin window")!,
            target: self,
            action: #selector(closePressed)
        )
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.imageScaling = .scaleProportionallyUpOrDown
        closeButton.contentTintColor = .white
        closeButton.toolTip = "Unpin"
        container.addSubview(closeButton)

        NSLayoutConstraint.activate([
            captureView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            captureView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            captureView.topAnchor.constraint(equalTo: container.topAnchor),
            captureView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            interactionView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            interactionView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            interactionView.topAnchor.constraint(equalTo: container.topAnchor),
            interactionView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            closeButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            closeButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),
        ])

        contentView = container
    }

    @objc private func closePressed() {
        onClose?()
    }

    private static func initialPanelFrame(for sourceFrame: CGRect, mode: PinMode) -> CGRect {
        if mode == .pinnedInPlace {
            let primaryScreenTop = NSScreen.screens.first?.frame.maxY ?? 0
            return CGRect(
                x: sourceFrame.minX,
                y: primaryScreenTop - sourceFrame.maxY,
                width: sourceFrame.width,
                height: sourceFrame.height
            )
        }

        let sourceWidth = max(sourceFrame.width, 1)
        let sourceHeight = max(sourceFrame.height, 1)
        let scale = min(720 / sourceWidth, 480 / sourceHeight, 1)
        let size = NSSize(width: sourceWidth * scale, height: sourceHeight * scale)

        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let sourceInAppKit = CGRect(
            x: sourceFrame.minX,
            y: primaryTop - sourceFrame.maxY,
            width: sourceFrame.width,
            height: sourceFrame.height
        )
        var origin = NSPoint(x: sourceInAppKit.minX + 28, y: sourceInAppKit.minY - 28)

        let candidate = CGRect(origin: origin, size: size)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(candidate) }) ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width)
            origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        }

        return CGRect(origin: origin, size: size)
    }
}

private final class OverlayInteractionView: NSView {
    let mode: PinMode
    var onInterceptedMouseDown: (() -> Void)?

    init(mode: PinMode) {
        self.mode = mode
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if mode == .pinnedInPlace {
            onInterceptedMouseDown?()
        } else {
            window?.performDrag(with: event)
        }
    }
}
