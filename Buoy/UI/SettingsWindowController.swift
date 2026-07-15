import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let preferences: PinPreferences
    private let onRecordingStateChanged: (Bool) -> Void
    private let pinRecorder = ShortcutRecorderControl()
    private let unpinRecorder = ShortcutRecorderControl()
    private let validationLabel = NSTextField(labelWithString: "")
    private var validationResetWorkItem: DispatchWorkItem?
    private var recordingIsActive = false

    init(
        preferences: PinPreferences,
        onRecordingStateChanged: @escaping (Bool) -> Void
    ) {
        self.preferences = preferences
        self.onRecordingStateChanged = onRecordingStateChanged
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 270),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Buoy Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        configureContent()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        cancelAllRecording()
        refreshRecorders()
        clearValidationMessage()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        cancelAllRecording()
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Keyboard Shortcuts")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        let detail = NSTextField(labelWithString: "Click a field, then press a shortcut. Clear disables that shortcut.")
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byWordWrapping
        detail.maximumNumberOfLines = 2

        configureRecorder(
            pinRecorder,
            label: "Pin frontmost shortcut",
            identifier: "pinFrontmostShortcutRecorder"
        )
        pinRecorder.onBindingRecorded = { [weak self] binding in
            self?.savePinBinding(binding)
        }
        pinRecorder.onRecordingStateChanged = { [weak self, weak pinRecorder] isArmed in
            guard let self, let pinRecorder else { return }
            self.recordingStateChanged(for: pinRecorder, isArmed: isArmed)
        }
        configureRecorder(
            unpinRecorder,
            label: "Unpin shortcut",
            identifier: "unpinShortcutRecorder"
        )
        unpinRecorder.onBindingRecorded = { [weak self] binding in
            self?.saveUnpinBinding(binding)
        }
        unpinRecorder.onRecordingStateChanged = { [weak self, weak unpinRecorder] isArmed in
            guard let self, let unpinRecorder else { return }
            self.recordingStateChanged(for: unpinRecorder, isArmed: isArmed)
        }

        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        validationLabel.isHidden = true
        validationLabel.setAccessibilityLabel("Shortcut validation message")

        let stack = NSStackView(views: [
            title,
            detail,
            shortcutSection(
                title: "Pin frontmost",
                recorder: pinRecorder,
                resetAction: #selector(resetPinToDefault),
                clearAction: #selector(clearPinShortcut)
            ),
            shortcutSection(
                title: "Unpin",
                recorder: unpinRecorder,
                resetAction: #selector(resetUnpinToDefault),
                clearAction: #selector(clearUnpinShortcut)
            ),
            validationLabel,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -18),
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        refreshRecorders()
    }

    private func configureRecorder(
        _ recorder: ShortcutRecorderControl,
        label: String,
        identifier: String
    ) {
        recorder.setAccessibilityElement(true)
        recorder.setAccessibilityRole(.button)
        recorder.setAccessibilityLabel(label)
        recorder.setAccessibilityIdentifier(identifier)
        recorder.setAccessibilityHelp("Press to record a new global shortcut.")
        recorder.focusRingType = .none
        recorder.widthAnchor.constraint(equalToConstant: 170).isActive = true
        recorder.heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    private func shortcutSection(
        title: String,
        recorder: ShortcutRecorderControl,
        resetAction: Selector,
        clearAction: Selector
    ) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        let resetButton = NSButton(title: "Reset to Default", target: self, action: resetAction)
        let clearButton = NSButton(title: "Clear", target: self, action: clearAction)
        let controls = NSStackView(views: [recorder, resetButton, clearButton])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8
        let section = NSStackView(views: [label, controls])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 5
        return section
    }

    private func refreshRecorders() {
        pinRecorder.binding = preferences.pinHotkeyBinding
        unpinRecorder.binding = preferences.unpinHotkeyBinding
    }

    private func recordingStateChanged(
        for recorder: ShortcutRecorderControl,
        isArmed: Bool
    ) {
        if isArmed {
            let otherRecorder = recorder === pinRecorder ? unpinRecorder : pinRecorder
            otherRecorder.cancelRecording()
        }
        updateRecordingState()
    }

    private func cancelAllRecording() {
        pinRecorder.cancelRecording()
        unpinRecorder.cancelRecording()
        updateRecordingState()
    }

    private func updateRecordingState() {
        let anyRecorderIsArmed = pinRecorder.isArmed || unpinRecorder.isArmed
        guard anyRecorderIsArmed != recordingIsActive else { return }
        recordingIsActive = anyRecorderIsArmed
        onRecordingStateChanged(anyRecorderIsArmed)
    }

    private func savePinBinding(_ binding: HotkeyBinding) {
        guard preferences.setPinHotkeyBinding(binding) else {
            pinRecorder.binding = preferences.pinHotkeyBinding
            showConflict(with: "Unpin")
            return
        }
        clearValidationMessage()
    }

    private func saveUnpinBinding(_ binding: HotkeyBinding) {
        guard preferences.setUnpinHotkeyBinding(binding) else {
            unpinRecorder.binding = preferences.unpinHotkeyBinding
            showConflict(with: "Pin frontmost")
            return
        }
        clearValidationMessage()
    }

    private func showConflict(with otherShortcut: String) {
        validationResetWorkItem?.cancel()
        validationLabel.stringValue = "That shortcut is already used by \(otherShortcut)."
        validationLabel.isHidden = false
        NSSound.beep()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.clearValidationMessage()
            }
        }
        validationResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }

    private func clearValidationMessage() {
        validationResetWorkItem?.cancel()
        validationResetWorkItem = nil
        validationLabel.stringValue = ""
        validationLabel.isHidden = true
    }

    @objc private func resetPinToDefault() {
        cancelAllRecording()
        guard preferences.setPinHotkeyBinding(.defaultPinBinding) else {
            showConflict(with: "Unpin")
            return
        }
        refreshRecorders()
        clearValidationMessage()
    }

    @objc private func clearPinShortcut() {
        cancelAllRecording()
        _ = preferences.setPinHotkeyBinding(nil)
        refreshRecorders()
        clearValidationMessage()
    }

    @objc private func resetUnpinToDefault() {
        cancelAllRecording()
        guard preferences.setUnpinHotkeyBinding(.defaultUnpinBinding) else {
            showConflict(with: "Pin frontmost")
            return
        }
        refreshRecorders()
        clearValidationMessage()
    }

    @objc private func clearUnpinShortcut() {
        cancelAllRecording()
        _ = preferences.setUnpinHotkeyBinding(nil)
        refreshRecorders()
        clearValidationMessage()
    }
}
