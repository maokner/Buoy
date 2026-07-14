import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let preferences: PinPreferences
    private let recorder = ShortcutRecorderControl()

    init(preferences: PinPreferences) {
        self.preferences = preferences
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 170),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Buoy Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        configureContent()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        recorder.binding = preferences.hotkeyBinding
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Pin Frontmost Window")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        let detail = NSTextField(labelWithString: "Click the field, then press a shortcut.")
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byWordWrapping
        detail.maximumNumberOfLines = 2

        recorder.binding = preferences.hotkeyBinding
        recorder.setAccessibilityElement(true)
        recorder.setAccessibilityRole(.button)
        recorder.setAccessibilityLabel("Global shortcut")
        recorder.setAccessibilityIdentifier("globalShortcutRecorder")
        recorder.setAccessibilityHelp("Press to record a new global shortcut.")
        recorder.focusRingType = .none
        recorder.onBindingRecorded = { [weak self] binding in
            self?.preferences.setHotkeyBinding(binding)
        }

        let resetButton = NSButton(
            title: "Reset to Default",
            target: self,
            action: #selector(resetToDefault)
        )
        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearShortcut))
        let buttons = NSStackView(views: [resetButton, clearButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [title, detail, recorder, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -22),
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor),
            recorder.widthAnchor.constraint(equalToConstant: 190),
            recorder.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    @objc private func resetToDefault() {
        recorder.binding = .defaultBinding
        preferences.setHotkeyBinding(.defaultBinding)
    }

    @objc private func clearShortcut() {
        recorder.binding = nil
        preferences.setHotkeyBinding(nil)
    }
}
