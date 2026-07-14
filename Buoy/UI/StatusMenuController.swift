import AppKit

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let pinManager: PinManager
    private let permissionsManager: PermissionsManager
    private let windowEnumerator = WindowEnumerator()
    private let hotkeyManager = HotkeyManager()
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var availableWindows: [CGWindowID: WindowDescriptor] = [:]
    private var enumerationGeneration = 0

    init(pinManager: PinManager, permissionsManager: PermissionsManager) {
        self.pinManager = pinManager
        self.permissionsManager = permissionsManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "pin.circle", accessibilityDescription: "Buoy")
            button.image?.isTemplate = true
            button.toolTip = "Buoy"
        }

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        hotkeyManager.onHotkeyPressed = { [weak self] in
            self?.toggleFrontmostWindow()
        }
        hotkeyManager.install()
        pinManager.onSessionsChanged = { [weak self] in
            self?.buildMenu(windowState: .loading)
        }
        buildMenu(windowState: .loading)
    }

    func menuWillOpen(_ menu: NSMenu) {
        enumerationGeneration += 1
        let generation = enumerationGeneration
        buildMenu(windowState: .loading)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let windows = try await windowEnumerator.windows()
                guard generation == enumerationGeneration else { return }
                availableWindows = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowID, $0) })
                buildMenu(windowState: windows.isEmpty ? .empty : .loaded(windows))
            } catch {
                guard generation == enumerationGeneration else { return }
                availableWindows = [:]
                buildMenu(windowState: .failed(error.localizedDescription))
            }
        }
    }

    private enum WindowState {
        case loading
        case loaded([WindowDescriptor])
        case empty
        case failed(String)
    }

    private func buildMenu(windowState: WindowState) {
        menu.removeAllItems()

        let frontmostItem = NSMenuItem(
            title: "Pin Frontmost Window",
            action: #selector(toggleFrontmostWindow),
            keyEquivalent: "p"
        )
        frontmostItem.target = self
        frontmostItem.keyEquivalentModifierMask = [.command, .option]
        if !hotkeyManager.isInstalled {
            frontmostItem.toolTip = "The global shortcut is in use by another app. This menu action still works."
        }
        menu.addItem(frontmostItem)
        menu.addItem(.separator())

        let pinItem = NSMenuItem(title: "Pin a Window", action: nil, keyEquivalent: "")
        let pinSubmenu = NSMenu(title: "Pin a Window")
        populatePinSubmenu(pinSubmenu, state: windowState)
        pinItem.submenu = pinSubmenu
        menu.addItem(pinItem)

        menu.addItem(.separator())
        addActivePins()
        menu.addItem(.separator())

        let permissionsItem = NSMenuItem(
            title: "Permissions...",
            action: #selector(showPermissions),
            keyEquivalent: ""
        )
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Buoy", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func populatePinSubmenu(_ submenu: NSMenu, state: WindowState) {
        switch state {
        case .loading:
            submenu.addItem(disabledItem("Loading Windows..."))
        case .empty:
            let title = permissionsManager.hasScreenRecordingAccess
                ? "No Available Windows"
                : "Screen Recording Permission Required"
            submenu.addItem(disabledItem(title))
        case .failed(let message):
            submenu.addItem(disabledItem(message))
        case .loaded(let windows):
            let pinnedIDs = Set(pinManager.sessions.map(\.source.windowID))
            submenu.addItem(disabledItem("Hold Option for a Detached Float"))
            submenu.addItem(.separator())
            for window in windows {
                let item = NSMenuItem(
                    title: "\(window.owningAppName) - \(window.displayTitle)",
                    action: #selector(pinWindow(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = NSNumber(value: window.windowID)
                item.isEnabled = !pinnedIDs.contains(window.windowID)
                if pinnedIDs.contains(window.windowID) {
                    item.state = .on
                }
                submenu.addItem(item)

                let alternateItem = NSMenuItem(
                    title: "Float \(window.owningAppName) - \(window.displayTitle)",
                    action: #selector(floatWindow(_:)),
                    keyEquivalent: ""
                )
                alternateItem.target = self
                alternateItem.representedObject = NSNumber(value: window.windowID)
                alternateItem.isEnabled = !pinnedIDs.contains(window.windowID)
                alternateItem.isAlternate = true
                alternateItem.keyEquivalentModifierMask = [.option]
                submenu.addItem(alternateItem)
            }
        }
    }

    private func addActivePins() {
        menu.addItem(disabledItem("Active Pins"))

        guard !pinManager.sessions.isEmpty else {
            let noneItem = disabledItem("None")
            noneItem.indentationLevel = 1
            menu.addItem(noneItem)
            return
        }

        for session in pinManager.sessions {
            let item = NSMenuItem(
                title: "\(session.mode.menuLabel): \(session.source.owningAppName) - \(session.source.displayTitle)",
                action: nil,
                keyEquivalent: ""
            )
            item.indentationLevel = 1
            item.submenu = activePinSubmenu(for: session)
            menu.addItem(item)
        }
    }

    private func activePinSubmenu(for session: PinSession) -> NSMenu {
        let submenu = NSMenu(title: session.source.displayTitle)

        let opacityItem = NSMenuItem()
        opacityItem.view = OpacityMenuItemView(session: session)
        submenu.addItem(opacityItem)

        if session.mode == .detached {
            let clickThroughItem = NSMenuItem(
                title: "Click-Through",
                action: #selector(toggleClickThrough(_:)),
                keyEquivalent: ""
            )
            clickThroughItem.target = self
            clickThroughItem.representedObject = session.id.uuidString
            clickThroughItem.state = session.isClickThrough ? .on : .off
            submenu.addItem(clickThroughItem)
        }

        submenu.addItem(.separator())
        let unpinItem = NSMenuItem(
            title: "Unpin",
            action: #selector(unpinWindow(_:)),
            keyEquivalent: ""
        )
        unpinItem.target = self
        unpinItem.representedObject = session.id.uuidString
        submenu.addItem(unpinItem)
        return submenu
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func pinWindow(_ sender: NSMenuItem) {
        guard permissionsManager.ensureScreenRecordingAccess() else { return }
        guard permissionsManager.ensureAccessibilityAccess() else { return }
        startPin(from: sender, mode: .pinnedInPlace)
    }

    @objc private func floatWindow(_ sender: NSMenuItem) {
        guard permissionsManager.ensureScreenRecordingAccess() else { return }
        startPin(from: sender, mode: .detached)
    }

    private func startPin(from sender: NSMenuItem, mode: PinMode) {
        guard let number = sender.representedObject as? NSNumber,
              let window = availableWindows[CGWindowID(number.uint32Value)] else {
            return
        }

        Task { @MainActor [weak self] in
            do {
                try await self?.pinManager.pin(window, mode: mode)
            } catch {
                self?.presentPinError(error)
            }
        }
    }

    @objc private func unpinWindow(_ sender: NSMenuItem) {
        guard let string = sender.representedObject as? String, let id = UUID(uuidString: string) else {
            return
        }
        pinManager.unpin(sessionID: id)
    }

    @objc private func toggleClickThrough(_ sender: NSMenuItem) {
        guard let string = sender.representedObject as? String,
              let id = UUID(uuidString: string),
              let session = pinManager.session(withID: id),
              session.mode == .detached else {
            return
        }
        let enabled = !session.isClickThrough
        session.setClickThrough(enabled)
        sender.state = enabled ? .on : .off
    }

    @objc private func toggleFrontmostWindow() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            presentFrontmostError("No frontmost application window is available.")
            return
        }

        guard permissionsManager.hasAccessibilityAccess else {
            _ = permissionsManager.ensureAccessibilityAccess()
            return
        }
        guard let windowID = AccessibilityWindowResolver.focusedWindowID(
            for: application.processIdentifier
        ) else {
            presentFrontmostError("Buoy could not resolve the frontmost window. Check Accessibility access and try again.")
            return
        }

        if let session = pinManager.session(forWindowID: windowID) {
            pinManager.unpin(sessionID: session.id)
            return
        }

        guard permissionsManager.ensureScreenRecordingAccess() else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard let window = try await windowEnumerator.window(withID: windowID) else {
                    presentFrontmostError("The frontmost window is not available for capture.")
                    return
                }
                try await pinManager.pin(window, mode: .pinnedInPlace)
            } catch {
                presentPinError(error)
            }
        }
    }

    func shutdown() {
        hotkeyManager.uninstall()
    }

    @objc private func showPermissions() {
        permissionsManager.presentPermissions()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func presentPinError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could Not Pin Window"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func presentFrontmostError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Frontmost Window Unavailable"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
