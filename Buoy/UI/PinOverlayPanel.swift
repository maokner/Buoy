import AppKit

@MainActor
final class PinOverlayPanel: NSPanel {
    let captureView = SampleBufferView(frame: .zero)
    var onClose: (() -> Void)?
    var onShowRealWindow: (() -> Void)?
    var onInterceptedMouseDown: (() -> Void)? {
        didSet {
            interactionView?.onInterceptedMouseDown = onInterceptedMouseDown
        }
    }

    private weak var interactionView: OverlayInteractionView?
    private weak var hoverStrip: NSView?
    private weak var pausedPill: NSView?
    private var pausedPillWorkItem: DispatchWorkItem?
    private var isHovering = false

    init(sourceFrame: CGRect, title: String, sourceAppName: String, mode: PinMode) {
        let isControlWindowRun = ProcessInfo.processInfo.arguments.contains("--control-window")
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
        // PinSession owns this panel strongly; enforce that close() never releases it.
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // Production overlays stay out of screenshots to avoid recursive capture.
        // The explicit control-window launch mode is an E2E surface and must remain
        // visible to Computer Use so the rendered capture can be verified.
        sharingType = isControlWindowRun ? .readOnly : .none
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

        configureContent(sourceAppName: sourceAppName, mode: mode)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setCaptureStalled(_ isStalled: Bool, baseOpacity: CGFloat) {
        alphaValue = isStalled ? baseOpacity * 0.78 : baseOpacity
        pausedPillWorkItem?.cancel()
        pausedPillWorkItem = nil

        guard isStalled else {
            pausedPill?.alphaValue = 0
            pausedPill?.isHidden = true
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                guard let pill = self.pausedPill else { return }
                pill.alphaValue = 0
                pill.isHidden = false
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    pill.animator().alphaValue = 1
                }
            }
        }
        pausedPillWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func configureContent(sourceAppName: String, mode: PinMode) {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.cornerRadius = 9
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        captureView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(captureView)

        let interactionView = OverlayInteractionView(mode: mode)
        interactionView.translatesAutoresizingMaskIntoConstraints = false
        interactionView.onInterceptedMouseDown = onInterceptedMouseDown
        interactionView.onDetachedBodyClick = { [weak self] in
            self?.onShowRealWindow?()
        }
        interactionView.onHoverChanged = { [weak self] isHovering in
            self?.setHovering(isHovering)
        }
        container.addSubview(interactionView)
        self.interactionView = interactionView

        let pausedPill = makePausedPill()
        pausedPill.translatesAutoresizingMaskIntoConstraints = false
        pausedPill.alphaValue = 0
        pausedPill.isHidden = true
        container.addSubview(pausedPill)
        self.pausedPill = pausedPill

        let hoverStrip = makeHoverStrip(sourceAppName: sourceAppName, mode: mode)
        hoverStrip.translatesAutoresizingMaskIntoConstraints = false
        hoverStrip.alphaValue = 0
        hoverStrip.isHidden = true
        container.addSubview(hoverStrip)
        self.hoverStrip = hoverStrip

        NSLayoutConstraint.activate([
            captureView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            captureView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            captureView.topAnchor.constraint(equalTo: container.topAnchor),
            captureView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            interactionView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            interactionView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            interactionView.topAnchor.constraint(equalTo: container.topAnchor),
            interactionView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            pausedPill.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            pausedPill.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            hoverStrip.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hoverStrip.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hoverStrip.topAnchor.constraint(equalTo: container.topAnchor),
            hoverStrip.heightAnchor.constraint(equalToConstant: 28),
        ])

        contentView = container
    }

    private func makeHoverStrip(sourceAppName: String, mode: PinMode) -> NSView {
        let strip = NSVisualEffectView()
        strip.material = .hudWindow
        strip.blendingMode = .withinWindow
        strip.state = .active
        strip.wantsLayer = true
        strip.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        strip.layer?.cornerRadius = 9
        strip.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        strip.layer?.masksToBounds = true

        let closeButton = overlayButton(
            symbolName: "xmark.circle.fill",
            pointSize: 18,
            accessibilityDescription: "Unpin",
            toolTip: "Unpin",
            action: #selector(closePressed)
        )
        strip.addSubview(closeButton)

        let glyphView = NSImageView(image: BuoyGlyph.image(pointSize: 12))
        glyphView.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        glyphView.translatesAutoresizingMaskIntoConstraints = false

        let sourceLabel = NSTextField(labelWithString: "Buoy - \(sourceAppName)")
        sourceLabel.font = .systemFont(ofSize: 11, weight: .medium)
        sourceLabel.textColor = NSColor.white.withAlphaComponent(0.9)
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false

        let wordmark = NSStackView(views: [glyphView, sourceLabel])
        wordmark.orientation = .horizontal
        wordmark.alignment = .centerY
        wordmark.spacing = 5
        wordmark.translatesAutoresizingMaskIntoConstraints = false
        strip.addSubview(wordmark)

        var constraints = [
            closeButton.leadingAnchor.constraint(equalTo: strip.leadingAnchor, constant: 10),
            closeButton.centerYAnchor.constraint(equalTo: strip.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),
            glyphView.widthAnchor.constraint(equalToConstant: 12),
            glyphView.heightAnchor.constraint(equalToConstant: 12),
            wordmark.centerXAnchor.constraint(equalTo: strip.centerXAnchor),
            wordmark.centerYAnchor.constraint(equalTo: strip.centerYAnchor),
            wordmark.leadingAnchor.constraint(greaterThanOrEqualTo: closeButton.trailingAnchor, constant: 6),
        ]

        if mode == .detached {
            let showButton = overlayButton(
                symbolName: "arrow.up.left.square",
                pointSize: 16,
                accessibilityDescription: "Show real window",
                toolTip: "Show real window",
                action: #selector(showRealWindowPressed)
            )
            strip.addSubview(showButton)
            constraints += [
                showButton.trailingAnchor.constraint(equalTo: strip.trailingAnchor, constant: -10),
                showButton.centerYAnchor.constraint(equalTo: strip.centerYAnchor),
                showButton.widthAnchor.constraint(equalToConstant: 22),
                showButton.heightAnchor.constraint(equalToConstant: 22),
                wordmark.trailingAnchor.constraint(lessThanOrEqualTo: showButton.leadingAnchor, constant: -6),
            ]
        } else {
            constraints.append(wordmark.trailingAnchor.constraint(lessThanOrEqualTo: strip.trailingAnchor, constant: -10))
        }
        NSLayoutConstraint.activate(constraints)
        return strip
    }

    private func makePausedPill() -> NSView {
        let pill = NSVisualEffectView()
        pill.material = .hudWindow
        pill.blendingMode = .withinWindow
        pill.state = .active
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 8
        pill.layer?.masksToBounds = true

        let image = NSImage(
            systemSymbolName: "pause.fill",
            accessibilityDescription: "Paused"
        )?.withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        let imageView = NSImageView(image: image ?? NSImage())
        imageView.contentTintColor = .white

        let label = NSTextField(labelWithString: "Paused")
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white

        let stack = NSStackView(views: [imageView, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(stack)

        NSLayoutConstraint.activate([
            pill.heightAnchor.constraint(equalToConstant: 24),
            stack.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
        return pill
    }

    private func overlayButton(
        symbolName: String,
        pointSize: CGFloat,
        accessibilityDescription: String,
        toolTip: String,
        action: Selector
    ) -> NSButton {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(configuration) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .white
        button.toolTip = toolTip
        return button
    }

    private func setHovering(_ isHovering: Bool) {
        self.isHovering = isHovering
        guard let hoverStrip else { return }

        if isHovering {
            hoverStrip.isHidden = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                hoverStrip.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                hoverStrip.animator().alphaValue = 0
            }, completionHandler: { [weak self, weak hoverStrip] in
                MainActor.assumeIsolated {
                    guard let self, !self.isHovering else { return }
                    hoverStrip?.isHidden = true
                }
            })
        }
    }

    @objc private func closePressed() {
        onClose?()
    }

    @objc private func showRealWindowPressed() {
        onShowRealWindow?()
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
    var onDetachedBodyClick: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private var trackingAreaReference: NSTrackingArea?

    init(mode: PinMode) {
        self.mode = mode
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        if mode == .pinnedInPlace {
            onInterceptedMouseDown?()
        } else {
            let startingOrigin = window?.frame.origin
            window?.performDrag(with: event)
            if let startingOrigin, let endingOrigin = window?.frame.origin,
               hypot(endingOrigin.x - startingOrigin.x, endingOrigin.y - startingOrigin.y) < 1 {
                onDetachedBodyClick?()
            }
        }
    }
}
