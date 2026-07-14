import AppKit

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private enum WindowState {
        case loading
        case loaded([WindowDescriptor])
        case empty
        case permissionMissing
        case failed(String)
    }

    private let pinManager: PinManager
    private let permissionsManager: PermissionsManager
    private let windowEnumerator = WindowEnumerator()
    private let hotkeyManager = HotkeyManager()
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var availableWindows: [CGWindowID: WindowDescriptor] = [:]
    private var enumerationGeneration = 0
    private var windowState: WindowState = .loading

    var isHotkeyInstalled: Bool {
        hotkeyManager.isInstalled
    }

    init(pinManager: PinManager, permissionsManager: PermissionsManager) {
        self.pinManager = pinManager
        self.permissionsManager = permissionsManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        hotkeyManager.onHotkeyPressed = { [weak self] in
            self?.toggleFrontmostWindow()
        }
        hotkeyManager.install()
        pinManager.onSessionsChanged = { [weak self] in
            guard let self else { return }
            self.buildMenu(windowState: self.windowState)
        }
        pinManager.onUnexpectedCaptureFailure = { [weak self] in
            self?.presentCaptureFailure()
        }
        buildMenu(windowState: permissionsManager.hasScreenRecordingAccess ? .loading : .permissionMissing)
    }

    func menuWillOpen(_ menu: NSMenu) {
        enumerationGeneration += 1
        let generation = enumerationGeneration

        guard permissionsManager.hasScreenRecordingAccess else {
            availableWindows = [:]
            buildMenu(windowState: .permissionMissing)
            return
        }

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

    private func buildMenu(windowState: WindowState) {
        self.windowState = windowState
        menu.removeAllItems()
        updateStatusItem()

        let pinItem = NSMenuItem(title: "Pin a Window", action: nil, keyEquivalent: "")
        pinItem.image = menuSymbol("pin", description: "Pin a Window")
        let pinSubmenu = NSMenu(title: "Pin a Window")
        pinSubmenu.autoenablesItems = false
        populatePinSubmenu(pinSubmenu, state: windowState)
        pinItem.submenu = pinSubmenu
        menu.addItem(pinItem)

        menu.addItem(.separator())
        addActivePins()
        menu.addItem(.separator())

        let frontmostItem = NSMenuItem(
            title: "Pin Frontmost Window",
            action: #selector(toggleFrontmostWindow),
            keyEquivalent: "p"
        )
        frontmostItem.target = self
        frontmostItem.keyEquivalentModifierMask = [.option, .command]
        frontmostItem.image = menuSymbol("pin.badge.plus", description: "Pin Frontmost Window")
        menu.addItem(frontmostItem)

        menu.addItem(.separator())

        let permissionsItem = NSMenuItem(
            title: "Permissions…",
            action: #selector(showPermissions),
            keyEquivalent: ""
        )
        permissionsItem.target = self
        permissionsItem.image = menuSymbol("lock.shield", description: "Permissions")
        menu.addItem(permissionsItem)

        let aboutItem = NSMenuItem(
            title: "About Buoy",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.image = menuSymbol("info.circle", description: "About Buoy")
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit Buoy", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func populatePinSubmenu(_ submenu: NSMenu, state: WindowState) {
        submenu.addItem(disabledItem("Hold Option to float instead"))
        submenu.addItem(.separator())

        switch state {
        case .loading:
            submenu.addItem(disabledItem("Loading windows…"))
        case .empty:
            submenu.addItem(disabledItem("No windows to pin"))
        case .permissionMissing:
            submenu.addItem(disabledItem("Turn on Screen Recording to pin windows"))
            let settingsItem = NSMenuItem(
                title: "Open Screen Recording Settings…",
                action: #selector(openScreenRecordingSettings),
                keyEquivalent: ""
            )
            settingsItem.target = self
            settingsItem.image = menuSymbol("arrow.up.forward.app", description: "Open Screen Recording Settings")
            submenu.addItem(settingsItem)
        case .failed(let message):
            submenu.addItem(disabledItem(message))
        case .loaded(let windows):
            let pinnedIDs = Set(pinManager.sessions.map(\.source.windowID))
            for window in windows {
                let isPinned = pinnedIDs.contains(window.windowID)
                let item = NSMenuItem(
                    title: "\(window.owningAppName) - \(window.displayTitle)",
                    action: #selector(pinWindow(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = NSNumber(value: window.windowID)
                item.isEnabled = !isPinned
                item.state = isPinned ? .on : .off
                submenu.addItem(item)

                let alternateItem = NSMenuItem(
                    title: "Float \(window.owningAppName) - \(window.displayTitle)",
                    action: #selector(floatWindow(_:)),
                    keyEquivalent: ""
                )
                alternateItem.target = self
                alternateItem.representedObject = NSNumber(value: window.windowID)
                alternateItem.isEnabled = !isPinned
                alternateItem.isAlternate = true
                alternateItem.keyEquivalentModifierMask = [.option]
                submenu.addItem(alternateItem)
            }
        }
    }

    private func addActivePins() {
        menu.addItem(sectionHeader("Active Pins"))

        guard !pinManager.sessions.isEmpty else {
            let noneItem = disabledItem("None yet")
            noneItem.indentationLevel = 1
            menu.addItem(noneItem)
            return
        }

        for session in pinManager.sessions {
            let item = NSMenuItem(
                title: "\(session.source.owningAppName) - \(session.source.displayTitle)",
                action: nil,
                keyEquivalent: ""
            )
            item.indentationLevel = 1
            let symbolName = session.mode == .pinnedInPlace ? "pin.fill" : "rectangle.on.rectangle"
            item.image = menuSymbol(symbolName, description: session.mode.menuLabel)
            item.submenu = activePinSubmenu(for: session)
            menu.addItem(item)
        }
    }

    private func activePinSubmenu(for session: PinSession) -> NSMenu {
        let submenu = NSMenu(title: session.source.displayTitle)
        submenu.autoenablesItems = false

        submenu.addItem(sectionHeader("Opacity"))
        let opacityItem = NSMenuItem()
        opacityItem.view = OpacityMenuItemView(session: session)
        submenu.addItem(opacityItem)
        submenu.addItem(.separator())

        if session.mode == .detached {
            let clickThroughItem = NSMenuItem(
                title: "Click-Through",
                action: #selector(toggleClickThrough(_:)),
                keyEquivalent: ""
            )
            clickThroughItem.target = self
            clickThroughItem.representedObject = session.id.uuidString
            clickThroughItem.state = session.isClickThrough ? .on : .off
            clickThroughItem.image = menuSymbol("cursorarrow.rays", description: "Click-Through")
            submenu.addItem(clickThroughItem)
            submenu.addItem(.separator())
        }

        let showItem = NSMenuItem(
            title: "Show Real Window",
            action: #selector(showRealWindow(_:)),
            keyEquivalent: ""
        )
        showItem.target = self
        showItem.representedObject = session.id.uuidString
        showItem.image = menuSymbol("arrow.up.left.square", description: "Show Real Window")
        submenu.addItem(showItem)

        let unpinItem = NSMenuItem(
            title: "Unpin",
            action: #selector(unpinWindow(_:)),
            keyEquivalent: "\u{8}"
        )
        unpinItem.target = self
        unpinItem.keyEquivalentModifierMask = []
        unpinItem.representedObject = session.id.uuidString
        unpinItem.image = menuSymbol("pin.slash", description: "Unpin")
        submenu.addItem(unpinItem)
        return submenu
    }

    private func updateStatusItem() {
        let pinCount = pinManager.sessions.count
        let symbolName = pinCount == 0 ? "pin" : "pin.fill"
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Buoy"
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = pinCount == 0 ? "Buoy" : "Buoy - \(pinCount) pinned"
    }

    private func menuSymbol(_ name: String, description: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: description
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = disabledItem(title)
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        return item
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
            guard let self else { return }
            do {
                try await pinManager.pin(window, mode: mode)
            } catch {
                presentPinError(error)
            }
        }
    }

    @objc private func unpinWindow(_ sender: NSMenuItem) {
        guard let id = sessionID(from: sender) else { return }
        pinManager.unpin(sessionID: id)
    }

    @objc private func showRealWindow(_ sender: NSMenuItem) {
        guard let id = sessionID(from: sender), let session = pinManager.session(withID: id) else { return }
        session.showRealWindow()
    }

    @objc private func toggleClickThrough(_ sender: NSMenuItem) {
        guard let id = sessionID(from: sender),
              let session = pinManager.session(withID: id),
              session.mode == .detached else {
            return
        }
        let enabled = !session.isClickThrough
        session.setClickThrough(enabled)
        sender.state = enabled ? .on : .off
    }

    private func sessionID(from sender: NSMenuItem) -> UUID? {
        guard let string = sender.representedObject as? String else { return nil }
        return UUID(uuidString: string)
    }

    @objc private func toggleFrontmostWindow() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            presentFrontmostError()
            return
        }

        guard permissionsManager.hasAccessibilityAccess else {
            _ = permissionsManager.ensureAccessibilityAccess()
            return
        }
        guard let windowID = AccessibilityWindowResolver.focusedWindowID(
            for: application.processIdentifier
        ) else {
            presentFrontmostError()
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
                    presentFrontmostError()
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

    @objc private func openScreenRecordingSettings() {
        permissionsManager.openScreenRecordingSettings()
    }

    @objc private func showPermissions() {
        permissionsManager.presentPermissions()
    }

    @objc private func showAbout() {
        let credits = NSMutableAttributedString(
            string: "Keeps any window on top with a live mirror.\nFree and open source.\n"
        )
        let linkTitle = "github.com/maokner/Buoy"
        let link = NSAttributedString(
            string: linkTitle,
            attributes: [
                .link: URL(string: "https://github.com/maokner/Buoy")!,
                .foregroundColor: NSColor.linkColor,
            ]
        )
        credits.append(link)

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationIcon: BuoyGlyph.image(pointSize: 64),
            .credits: credits,
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func presentPinError(_ error: Error) {
        NSLog("Buoy could not start capture: %@", error.localizedDescription)
        presentAlert(
            style: .warning,
            message: "Could not pin that window",
            information: "Buoy could not start a live mirror for this window. It may have closed or blocked screen capture. Try another window."
        )
    }

    private func presentCaptureFailure() {
        presentAlert(
            style: .warning,
            message: "Lost the connection to that window",
            information: "Buoy stopped mirroring because the window is no longer available. Pin it again to bring it back."
        )
    }

    private func presentFrontmostError() {
        presentAlert(
            style: .informational,
            message: "Nothing to pin",
            information: "Buoy could not find a window to pin. Click the window you want on top, then press Option-Command-P."
        )
    }

    private func presentAlert(style: NSAlert.Style, message: String, information: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = message
        alert.informativeText = information
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
