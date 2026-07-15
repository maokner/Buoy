import AppKit

@MainActor
final class ShortcutRecorderControl: NSView {
    var binding: HotkeyBinding? {
        didSet {
            needsDisplay = true
            setAccessibilityValue(binding?.displayString ?? "No shortcut")
        }
    }
    var onBindingRecorded: ((HotkeyBinding) -> Void)?
    var onRecordingStateChanged: ((Bool) -> Void)?

    private var eventMonitor: Any?
    private(set) var isArmed = false {
        didSet {
            needsDisplay = true
            setAccessibilityHelp(isArmed ? "Press a shortcut, or Escape to cancel." : "Press to record a new global shortcut.")
            if oldValue != isArmed {
                onRecordingStateChanged?(isArmed)
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 190, height: 30)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        arm()
    }

    override func accessibilityPerformPress() -> Bool {
        window?.makeFirstResponder(self)
        arm()
        return true
    }

    override func resignFirstResponder() -> Bool {
        cancelRecording()
        return super.resignFirstResponder()
    }

    func cancelRecording() {
        disarm()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (isArmed ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isArmed ? 2 : 1
        path.stroke()

        let text = isArmed ? "Type Shortcut" : (binding?.displayString ?? "No Shortcut")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: isArmed ? .medium : .regular),
            .foregroundColor: isArmed ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func arm() {
        guard !isArmed else { return }
        isArmed = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.capture(event)
        }
        if eventMonitor == nil {
            disarm()
        }
    }

    private func disarm() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isArmed = false
    }

    private func capture(_ event: NSEvent) -> NSEvent? {
        guard isArmed else { return event }
        if event.keyCode == 53 {
            disarm()
            return nil
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !modifiers.isEmpty,
              let equivalent = event.charactersIgnoringModifiers?.lowercased(),
              !equivalent.isEmpty else {
            NSSound.beep()
            return nil
        }

        let binding = HotkeyBinding(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            keyEquivalent: equivalent
        )
        self.binding = binding
        disarm()
        onBindingRecorded?(binding)
        return nil
    }
}
