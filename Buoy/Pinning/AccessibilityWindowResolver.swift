import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(
    _ element: AXUIElement,
    _ windowID: UnsafeMutablePointer<CGWindowID>
) -> AXError

enum AccessibilityWindowResolver {
    static func focusedWindowID(for processID: pid_t) -> CGWindowID? {
        let applicationElement = AXUIElementCreateApplication(processID)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &value
        ) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        let focusedWindow = value as! AXUIElement
        return windowID(of: focusedWindow)
    }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var identifier = CGWindowID(0)
        guard _AXUIElementGetWindow(element, &identifier) == .success else { return nil }
        return identifier
    }
}
