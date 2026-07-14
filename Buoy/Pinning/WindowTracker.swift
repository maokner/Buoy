import AppKit
import ApplicationServices

@MainActor
protocol WindowTracking: AnyObject {
    func startTracking()
    func stopTracking()
}

@MainActor
final class WindowTracker: WindowTracking {
    var onFrameChanged: ((CGRect) -> Void)?
    var onMinimizedChanged: ((Bool) -> Void)?
    var onFocusChanged: ((Bool) -> Void)?
    var onWindowClosed: (() -> Void)?

    private(set) var currentFrame: CGRect

    private let source: WindowDescriptor
    private let applicationElement: AXUIElement
    private var windowElement: AXUIElement?
    private var observer: AXObserver?
    private var pollingTimer: Timer?
    private var terminationObserver: NSObjectProtocol?
    private var isStopped = true
    private var hasReportedClosure = false
    private var consecutiveMissingPolls = 0

    init(source: WindowDescriptor) {
        self.source = source
        applicationElement = AXUIElementCreateApplication(source.processID)
        currentFrame = Self.cocoaFrame(fromQuartzFrame: source.frame)
    }

    func startTracking() {
        guard isStopped else { return }
        isStopped = false
        hasReportedClosure = false
        consecutiveMissingPolls = 0

        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication,
                      application.processIdentifier == self.source.processID else {
                    return
                }
                self.reportWindowClosed()
            }
        }

        guard let element = findSourceWindowElement() else {
            startPolling()
            return
        }

        windowElement = element
        if let frame = axFrame(of: element) {
            updateFrame(Self.cocoaFrame(fromAXFrame: frame))
        }

        guard installObserver(for: element) else {
            startPolling()
            return
        }

        onMinimizedChanged?(isAXWindowMinimized(element))
    }

    func stopTracking() {
        guard !isStopped else { return }
        isStopped = true

        pollingTimer?.invalidate()
        pollingTimer = nil

        if let observer {
            if let windowElement {
                for notification in Self.windowNotifications {
                    AXObserverRemoveNotification(observer, windowElement, notification)
                }
            }
            AXObserverRemoveNotification(
                observer,
                applicationElement,
                kAXFocusedWindowChangedNotification as CFString
            )
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observer = nil
        windowElement = nil

        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
    }

    @discardableResult
    func raiseSourceWindow() -> Bool {
        if windowElement == nil {
            windowElement = findSourceWindowElement()
        }
        guard let windowElement else { return false }
        return AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString) == .success
    }

    func sourceWindowIsFocused() -> Bool? {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processID else {
            return false
        }
        guard let focusedElement = copyElementAttribute(
            applicationElement,
            attribute: kAXFocusedWindowAttribute as CFString
        ) else {
            return nil
        }
        guard let focusedWindowID = AccessibilityWindowResolver.windowID(of: focusedElement) else {
            return nil
        }
        return focusedWindowID == source.windowID
    }

    fileprivate func handleAXNotification(element: AXUIElement, notification: CFString) {
        guard !isStopped else { return }

        switch notification as String {
        case kAXMovedNotification, kAXResizedNotification:
            guard let windowElement, CFEqual(element, windowElement),
                  let frame = axFrame(of: windowElement) else {
                return
            }
            updateFrame(Self.cocoaFrame(fromAXFrame: frame))
        case kAXWindowMiniaturizedNotification:
            guard isSourceElement(element) else { return }
            onMinimizedChanged?(true)
        case kAXWindowDeminiaturizedNotification:
            guard isSourceElement(element) else { return }
            if let frame = windowElement.flatMap(axFrame(of:)) {
                updateFrame(Self.cocoaFrame(fromAXFrame: frame))
            }
            onMinimizedChanged?(false)
        case kAXUIElementDestroyedNotification:
            guard isSourceElement(element) else { return }
            reportWindowClosed()
        case kAXFocusedWindowChangedNotification:
            if let sourceIsFocused = sourceWindowIsFocused() {
                onFocusChanged?(sourceIsFocused)
            }
        default:
            break
        }
    }

    private static let windowNotifications: [CFString] = [
        kAXMovedNotification as CFString,
        kAXResizedNotification as CFString,
        kAXWindowMiniaturizedNotification as CFString,
        kAXWindowDeminiaturizedNotification as CFString,
        kAXUIElementDestroyedNotification as CFString,
    ]

    private func installObserver(for element: AXUIElement) -> Bool {
        var observer: AXObserver?
        let creationResult = AXObserverCreate(
            source.processID,
            windowTrackerObserverCallback,
            &observer
        )
        guard creationResult == .success, let observer else { return false }

        var addedNotifications: [CFString] = []
        for notification in Self.windowNotifications {
            let result = AXObserverAddNotification(
                observer,
                element,
                notification,
                Unmanaged.passUnretained(self).toOpaque()
            )
            guard result == .success else {
                removeNotifications(addedNotifications, from: element, observer: observer)
                return false
            }
            addedNotifications.append(notification)
        }

        let focusResult = AXObserverAddNotification(
            observer,
            applicationElement,
            kAXFocusedWindowChangedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
        guard focusResult == .success else {
            removeNotifications(addedNotifications, from: element, observer: observer)
            return false
        }

        self.observer = observer
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        return true
    }

    private func removeNotifications(
        _ notifications: [CFString],
        from element: AXUIElement,
        observer: AXObserver
    ) {
        for notification in notifications {
            AXObserverRemoveNotification(observer, element, notification)
        }
    }

    private func findSourceWindowElement() -> AXUIElement? {
        guard let windows = copyElementArrayAttribute(
            applicationElement,
            attribute: kAXWindowsAttribute as CFString
        ) else {
            return nil
        }

        if let exactMatch = windows.first(where: {
            AccessibilityWindowResolver.windowID(of: $0) == source.windowID
        }) {
            return exactMatch
        }

        return windows.first { element in
            guard let frame = axFrame(of: element) else { return false }
            let title = copyStringAttribute(element, attribute: kAXTitleAttribute as CFString) ?? ""
            let titleMatches = title == source.displayTitle || source.displayTitle == "Untitled Window"
            let frameMatches = abs(frame.minX - source.frame.minX) < 5
                && abs(frame.minY - source.frame.minY) < 5
                && abs(frame.width - source.frame.width) < 5
                && abs(frame.height - source.frame.height) < 5
            return titleMatches && frameMatches
        }
    }

    private func startPolling() {
        observer = nil
        pollWindowInfo()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.pollWindowInfo()
            }
        }
        pollingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func pollWindowInfo() {
        guard !isStopped else { return }
        guard let windowInfo = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
                as? [[String: Any]] else {
            return
        }
        guard let info = windowInfo.first(where: {
                  ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == source.windowID
              }) else {
            consecutiveMissingPolls += 1
            if consecutiveMissingPolls >= 3 {
                reportWindowClosed()
            }
            return
        }
        consecutiveMissingPolls = 0

        if let bounds = info[kCGWindowBounds as String] {
            let boundsDictionary = bounds as! CFDictionary
            if let quartzFrame = CGRect(dictionaryRepresentation: boundsDictionary) {
                updateFrame(Self.cocoaFrame(fromQuartzFrame: quartzFrame))
            }
        }

        let isOnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
        onMinimizedChanged?(!isOnScreen)

        if let sourceIsFocused = sourceWindowIsFocused()
            ?? approximateFocusState(from: windowInfo) {
            onFocusChanged?(sourceIsFocused)
        }
    }

    private func updateFrame(_ frame: CGRect) {
        guard frame.width > 1, frame.height > 1 else { return }
        currentFrame = frame
        onFrameChanged?(frame)
    }

    private func reportWindowClosed() {
        guard !hasReportedClosure else { return }
        hasReportedClosure = true
        onWindowClosed?()
    }

    private func isSourceElement(_ element: AXUIElement) -> Bool {
        guard let windowElement else { return false }
        return CFEqual(element, windowElement)
    }

    private func isAXWindowMinimized(_ element: AXUIElement) -> Bool {
        copyBoolAttribute(element, attribute: kAXMinimizedAttribute as CFString) ?? false
    }

    private func approximateFocusState(from windowInfo: [[String: Any]]) -> Bool? {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processID else {
            return false
        }
        let frontWindow = windowInfo.first { info in
            let processID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue
            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue
            return processID == source.processID && layer == 0 && isOnScreen == true
        }
        guard let frontWindow else { return nil }
        return (frontWindow[kCGWindowNumber as String] as? NSNumber)?.uint32Value == source.windowID
    }

    private func axFrame(of element: AXUIElement) -> CGRect? {
        guard let position = copyPointAttribute(
            element,
            attribute: kAXPositionAttribute as CFString
        ), let size = copySizeAttribute(
            element,
            attribute: kAXSizeAttribute as CFString
        ) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private static func cocoaFrame(fromAXFrame frame: CGRect) -> CGRect {
        cocoaFrame(fromQuartzFrame: frame)
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
}

private func windowTrackerObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ reference: UnsafeMutableRawPointer?
) {
    guard let reference else { return }
    let tracker = Unmanaged<WindowTracker>.fromOpaque(reference).takeUnretainedValue()
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            tracker.handleAXNotification(element: element, notification: notification)
        }
    }
}

private func copyElementArrayAttribute(
    _ element: AXUIElement,
    attribute: CFString
) -> [AXUIElement]? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
    return value as? [AXUIElement]
}

private func copyElementAttribute(
    _ element: AXUIElement,
    attribute: CFString
) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
          let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return nil
    }
    return unsafeDowncast(value, to: AXUIElement.self)
}

private func copyStringAttribute(
    _ element: AXUIElement,
    attribute: CFString
) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
    return value as? String
}

private func copyBoolAttribute(
    _ element: AXUIElement,
    attribute: CFString
) -> Bool? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
    return (value as? NSNumber)?.boolValue
}

private func copyPointAttribute(
    _ element: AXUIElement,
    attribute: CFString
) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
          let value, CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = value as! AXValue
    var point = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
    return point
}

private func copySizeAttribute(
    _ element: AXUIElement,
    attribute: CFString
) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
          let value, CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = value as! AXValue
    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
    return size
}
