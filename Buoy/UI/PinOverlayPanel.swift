import AppKit

@MainActor
final class PinOverlayPanel: NSPanel {
    let captureView = SampleBufferView(frame: .zero)
    var onClose: (() -> Void)?

    init(sourceFrame: CGRect, title: String) {
        let initialFrame = Self.initialPanelFrame(for: sourceFrame)
        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        self.title = title
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        isMovableByWindowBackground = true
        minSize = NSSize(width: 240, height: 135)
        contentMinSize = minSize
        contentAspectRatio = sourceFrame.size
        animationBehavior = .utilityWindow

        configureContent()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func configureContent() {
        let container = DraggableContainerView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.cornerRadius = 9
        container.layer?.masksToBounds = true

        captureView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(captureView)

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

    private static func initialPanelFrame(for sourceFrame: CGRect) -> CGRect {
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

private final class DraggableContainerView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}
