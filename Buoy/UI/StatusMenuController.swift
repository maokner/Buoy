import AppKit

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let pinManager: PinManager
    private let permissionsManager: PermissionsManager
    private let windowEnumerator = WindowEnumerator()
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
                title: "Unpin \(session.source.owningAppName) - \(session.source.displayTitle)",
                action: #selector(unpinWindow(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = session.id.uuidString
            item.indentationLevel = 1
            menu.addItem(item)
        }
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func pinWindow(_ sender: NSMenuItem) {
        guard permissionsManager.ensureScreenRecordingAccess() else { return }
        guard let number = sender.representedObject as? NSNumber else { return }
        let windowID = CGWindowID(number.uint32Value)
        guard let window = availableWindows[windowID] else { return }

        Task { @MainActor [weak self] in
            do {
                try await self?.pinManager.pin(window)
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
}
