import AppKit

@MainActor
final class WindowPickerController {
    var onPinError: ((Error) -> Void)?
    var onWindowUnavailable: (() -> Void)?

    fileprivate struct Target: Equatable {
        let windowID: CGWindowID
        let appName: String
        let windowTitle: String
        let frame: CGRect
    }

    private let pinManager: PinManager
    private let permissionsManager: PermissionsManager
    private let windowEnumerator = WindowEnumerator()
    private var panels: [PickerPanel] = []
    private var target: Target?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var previousFrontmostApplication: NSRunningApplication?
    private var isActive = false

    init(pinManager: PinManager, permissionsManager: PermissionsManager) {
        self.pinManager = pinManager
        self.permissionsManager = permissionsManager
    }

    func begin() {
        guard !isActive else { return }
        guard permissionsManager.ensureScreenRecordingAccess() else { return }
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           frontmostApplication.processIdentifier != ownProcessID {
            previousFrontmostApplication = frontmostApplication
        } else {
            previousFrontmostApplication = nil
        }
        isActive = true
        installPanels()
        NSApp.activate(ignoringOtherApps: true)
        makePickerPanelKey()
        installMonitors()
        updateTarget(at: NSEvent.mouseLocation)
        NSCursor.crosshair.set()
    }

    func cancel() {
        guard isActive else { return }
        tearDown(restorePreviousApplication: true)
    }

    private func installPanels() {
        panels.forEach { $0.close() }
        panels = NSScreen.screens.map { screen in
            let panel = PickerPanel(screen: screen)
            panel.pickerView.onMouseMoved = { [weak self] point in
                self?.updateTarget(at: point)
            }
            panel.pickerView.onMouseDown = { [weak self] point, modifiers in
                self?.select(at: point, modifiers: modifiers)
            }
            panel.orderFrontRegardless()
            return panel
        }
    }

    private func installMonitors() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.cancel()
                }
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.cancel()
            return nil
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                self.installPanels()
                self.makePickerPanelKey()
                self.updateTarget(at: NSEvent.mouseLocation)
            }
        }
    }

    private func updateTarget(at cocoaPoint: CGPoint) {
        guard isActive else { return }
        target = hitTestWindow(at: cocoaPoint)
        for panel in panels {
            panel.pickerView.update(target: target, cursorLocation: cocoaPoint)
        }
    }

    private func select(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        updateTarget(at: point)
        guard let target else {
            cancel()
            return
        }

        let mode: PinMode = modifiers.contains(.option) ? .detached : .pinnedInPlace
        let applicationToRestore = previousFrontmostApplication
        tearDown(restorePreviousApplication: false)
        if mode == .pinnedInPlace && !permissionsManager.ensureAccessibilityAccess() {
            Self.activate(applicationToRestore)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard let descriptor = try await windowEnumerator.window(withID: target.windowID) else {
                    onWindowUnavailable?()
                    return
                }
                let result = try await pinManager.pin(descriptor, mode: mode)
                switch result {
                case .created where mode == .pinnedInPlace:
                    pinManager.session(forWindowID: descriptor.windowID)?.showRealWindow()
                case .created, .alreadyPinned:
                    Self.activate(applicationToRestore)
                }
            } catch {
                Self.activate(applicationToRestore)
                onPinError?(error)
            }
        }
    }

    private func hitTestWindow(at cocoaPoint: CGPoint) -> Target? {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let quartzPoint = Self.quartzPoint(fromCocoaPoint: cocoaPoint)
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        for info in windowInfo {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != ownProcessID,
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0.01,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let boundsValue = info[kCGWindowBounds as String] else {
                continue
            }

            guard let boundsDictionary = boundsValue as? [String: Any],
                  let quartzFrame = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  quartzFrame.width >= 80,
                  quartzFrame.height >= 50,
                  quartzFrame.contains(quartzPoint) else {
                continue
            }

            let appName = (info[kCGWindowOwnerName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !appName.isEmpty else { continue }
            let rawTitle = (info[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Target(
                windowID: CGWindowID(number.uint32Value),
                appName: appName,
                windowTitle: rawTitle.isEmpty ? "Untitled Window" : rawTitle,
                frame: Self.cocoaFrame(fromQuartzFrame: quartzFrame)
            )
        }
        return nil
    }

    private func makePickerPanelKey() {
        let mouseLocation = NSEvent.mouseLocation
        let panel = panels.first(where: { $0.frame.contains(mouseLocation) }) ?? panels.first
        panel?.makeKeyAndOrderFront(nil)
        if let panel {
            panel.invalidateCursorRects(for: panel.pickerView)
        }
        NSCursor.crosshair.set()
    }

    private func tearDown(restorePreviousApplication: Bool) {
        guard isActive else { return }
        isActive = false
        target = nil
        let applicationToRestore = restorePreviousApplication ? previousFrontmostApplication : nil
        previousFrontmostApplication = nil
        panels.forEach {
            $0.orderOut(nil)
            $0.close()
        }
        panels.removeAll()
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        NSCursor.arrow.set()
        Self.activate(applicationToRestore)
    }

    private static func cocoaFrame(fromQuartzFrame frame: CGRect) -> CGRect {
        let primaryScreenTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(
            x: frame.minX,
            y: primaryScreenTop - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private static func quartzPoint(fromCocoaPoint point: CGPoint) -> CGPoint {
        let primaryScreenTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: point.x, y: primaryScreenTop - point.y)
    }

    private static func activate(_ application: NSRunningApplication?) {
        guard let application, !application.isTerminated else { return }
        application.activate(options: [.activateAllWindows])
    }
}

@MainActor
private final class PickerPanel: NSPanel {
    let pickerView: PickerOverlayView

    init(screen: NSScreen) {
        pickerView = PickerOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        sharingType = .readOnly
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        acceptsMouseMovedEvents = true
        pickerView.autoresizingMask = [.width, .height]
        contentView = pickerView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class PickerOverlayView: NSView {
    var onMouseMoved: ((CGPoint) -> Void)?
    var onMouseDown: ((CGPoint, NSEvent.ModifierFlags) -> Void)?

    private var targetFrame: CGRect?
    private let tagView = PickerTagView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(tagView)
        tagView.isHidden = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        onMouseMoved?(NSEvent.mouseLocation)
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
        onMouseMoved?(NSEvent.mouseLocation)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(NSEvent.mouseLocation, event.modifierFlags)
    }

    func update(target: WindowPickerController.Target?, cursorLocation: CGPoint) {
        guard let window else { return }
        targetFrame = target.map {
            CGRect(
                x: $0.frame.minX - window.frame.minX,
                y: $0.frame.minY - window.frame.minY,
                width: $0.frame.width,
                height: $0.frame.height
            )
        }
        if let target, window.frame.contains(cursorLocation) {
            tagView.update(appName: target.appName, windowTitle: target.windowTitle)
            tagView.isHidden = false
            let localPoint = window.convertPoint(fromScreen: cursorLocation)
            let size = NSSize(
                width: min(tagView.intrinsicContentSize.width, max(bounds.width - 20, 1)),
                height: tagView.intrinsicContentSize.height
            )
            var origin = CGPoint(x: localPoint.x + 14, y: localPoint.y - size.height - 14)
            origin.x = min(max(origin.x, 10), bounds.maxX - size.width - 10)
            origin.y = min(max(origin.y, 10), bounds.maxY - size.height - 10)
            tagView.frame = CGRect(origin: origin, size: size)
        } else {
            tagView.isHidden = true
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let targetFrame else { return }
        let visibleTarget = targetFrame.intersection(bounds).insetBy(dx: 2, dy: 2)
        guard visibleTarget.width > 0, visibleTarget.height > 0 else { return }
        let path = NSBezierPath(roundedRect: visibleTarget, xRadius: 10, yRadius: 10)
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 3
        path.stroke()
    }
}

@MainActor
private final class PickerTagView: NSVisualEffectView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "Click to pin - hold Option to float - Esc to cancel")

    override var intrinsicContentSize: NSSize {
        NSSize(width: 360, height: 48)
    }

    convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 360, height: 48))
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.masksToBounds = true

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        hintLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        addSubview(hintLabel)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(appName: String, windowTitle: String) {
        titleLabel.stringValue = "\(appName) - \(windowTitle)"
    }

    override func layout() {
        super.layout()
        let contentWidth = max(bounds.width - 24, 0)
        titleLabel.frame = NSRect(x: 12, y: 25, width: contentWidth, height: 16)
        hintLabel.frame = NSRect(x: 12, y: 8, width: contentWidth, height: 14)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
