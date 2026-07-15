import AppKit

@MainActor
final class ControlWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private enum TableKind: String {
        case available
        case active
    }

    private let pinManager: PinManager
    private let permissionsManager: PermissionsManager
    private let hotkeyStatus: () -> String
    private let windowEnumerator = WindowEnumerator()

    private var availableWindows: [WindowDescriptor] = []
    private var sessions: [PinSession] { pinManager.sessions }

    private let screenPermissionLabel = NSTextField(labelWithString: "")
    private let accessibilityPermissionLabel = NSTextField(labelWithString: "")
    private let hotkeyStatusLabel = NSTextField(labelWithString: "")
    private let availableTable = NSTableView()
    private let activeTable = NSTableView()
    private let modeControl = NSSegmentedControl(
        labels: ["Pin in Place", "Float"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let opacitySlider = NSSlider(value: 1, minValue: 0.15, maxValue: 1, target: nil, action: nil)
    private let opacityLabel = NSTextField(labelWithString: "100%")
    private let clickThroughButton = NSButton(checkboxWithTitle: "Click-Through", target: nil, action: nil)
    private let showButton = NSButton(title: "Show Real Window", target: nil, action: nil)
    private let unpinButton = NSButton(title: "Unpin", target: nil, action: nil)
    private let statusLabel = NSTextField(wrappingLabelWithString: "Ready")

    private var sessionObserver: NSObjectProtocol?
    private var hotkeyObserver: NSObjectProtocol?

    init(
        pinManager: PinManager,
        permissionsManager: PermissionsManager,
        hotkeyStatus: @escaping () -> String
    ) {
        self.pinManager = pinManager
        self.permissionsManager = permissionsManager
        self.hotkeyStatus = hotkeyStatus

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Buoy Control Center"
        window.minSize = NSSize(width: 680, height: 580)
        window.isReleasedWhenClosed = false
        super.init(window: window)

        configureWindow()
        sessionObserver = NotificationCenter.default.addObserver(
            forName: .buoySessionsChanged,
            object: pinManager,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadActivePins()
            }
        }
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .buoyHotkeyChanged,
            object: PinPreferences.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissionState()
            }
        }
        refreshPermissionState()
        refreshWindows()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let sessionObserver {
            NotificationCenter.default.removeObserver(sessionObserver)
        }
        if let hotkeyObserver {
            NotificationCenter.default.removeObserver(hotkeyObserver)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView.identifier?.rawValue == TableKind.available.rawValue
            ? availableWindows.count
            : sessions.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        if tableView.identifier?.rawValue == TableKind.available.rawValue {
            guard availableWindows.indices.contains(row) else { return cell }
            let descriptor = availableWindows[row]
            label.stringValue = "\(descriptor.owningAppName) - \(descriptor.displayTitle)"
            cell.setAccessibilityLabel("\(descriptor.owningAppName), \(descriptor.displayTitle)")
        } else {
            guard sessions.indices.contains(row) else { return cell }
            let session = sessions[row]
            label.stringValue = "\(session.mode.menuLabel): \(session.source.owningAppName) - \(session.source.displayTitle)"
            cell.setAccessibilityLabel(label.stringValue)
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView else { return }
        if table === activeTable {
            updateActiveControls()
        }
    }

    private func configureWindow() {
        guard let contentView = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Buoy Control Center")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: "Pin a real window using Buoy's production capture and interaction pipeline.")
        subtitle.textColor = .secondaryLabelColor

        let permissionsTitle = sectionTitle("Permissions")
        let permissionsStack = NSStackView(views: [
            screenPermissionLabel,
            accessibilityPermissionLabel,
            hotkeyStatusLabel,
        ])
        permissionsStack.orientation = .vertical
        permissionsStack.alignment = .leading
        permissionsStack.spacing = 6

        let requestScreenButton = NSButton(title: "Request Screen Recording", target: self, action: #selector(requestScreenRecording))
        requestScreenButton.setAccessibilityLabel("Request Screen Recording permission")
        let requestAccessibilityButton = NSButton(title: "Request Accessibility", target: self, action: #selector(requestAccessibility))
        requestAccessibilityButton.setAccessibilityLabel("Request Accessibility permission")
        let permissionButtons = NSStackView(views: [requestScreenButton, requestAccessibilityButton])
        permissionButtons.orientation = .horizontal
        permissionButtons.spacing = 8

        configureTable(availableTable, kind: .available)
        let availableScroll = scrollView(for: availableTable)
        availableScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        modeControl.selectedSegment = 0
        modeControl.setAccessibilityLabel("Pin mode")
        let refreshButton = NSButton(title: "Refresh Windows", target: self, action: #selector(refreshPressed))
        let pinButton = NSButton(title: "Pin Selected Window", target: self, action: #selector(pinSelected))
        pinButton.keyEquivalent = "\r"
        let availableActions = NSStackView(views: [modeControl, refreshButton, pinButton])
        availableActions.orientation = .horizontal
        availableActions.spacing = 8

        configureTable(activeTable, kind: .active)
        let activeScroll = scrollView(for: activeTable)
        activeScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true

        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged)
        opacitySlider.isContinuous = true
        opacitySlider.setAccessibilityLabel("Selected pin opacity")
        opacityLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        opacityLabel.alignment = .right
        opacityLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        clickThroughButton.target = self
        clickThroughButton.action = #selector(clickThroughChanged)
        showButton.target = self
        showButton.action = #selector(showRealWindow)
        unpinButton.target = self
        unpinButton.action = #selector(unpinSelected)
        let activeActions = NSStackView(views: [opacitySlider, opacityLabel, clickThroughButton, showButton, unpinButton])
        activeActions.orientation = .horizontal
        activeActions.spacing = 8

        let inspectOverlayButton = NSButton(
            title: "Inspect Active Overlay",
            target: self,
            action: #selector(inspectActiveOverlay)
        )
        inspectOverlayButton.setAccessibilityLabel("Hide the control window and inspect the active Buoy overlay")

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setAccessibilityLabel("Status")

        let stack = NSStackView(views: [
            title,
            subtitle,
            permissionsTitle,
            permissionsStack,
            permissionButtons,
            sectionTitle("Available Windows"),
            availableScroll,
            availableActions,
            sectionTitle("Active Pin"),
            activeScroll,
            activeActions,
            inspectOverlayButton,
            statusLabel,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        for view in [subtitle, permissionsStack, permissionButtons, availableScroll, availableActions, activeScroll, activeActions, inspectOverlayButton, statusLabel] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -22),
        ])

        window?.center()
        updateActiveControls()
    }

    private func configureTable(_ table: NSTableView, kind: TableKind) {
        table.identifier = NSUserInterfaceItemIdentifier(kind.rawValue)
        table.headerView = nil
        table.rowHeight = 26
        table.usesAlternatingRowBackgroundColors = true
        table.allowsEmptySelection = true
        table.delegate = self
        table.dataSource = self
        table.setAccessibilityLabel(kind == .available ? "Available windows" : "Active pin")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
    }

    private func scrollView(for table: NSTableView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        return scroll
    }

    private func sectionTitle(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func refreshPermissionState() {
        screenPermissionLabel.stringValue = "Screen Recording: \(permissionsManager.hasScreenRecordingAccess ? "Granted" : "Not Granted")"
        accessibilityPermissionLabel.stringValue = "Accessibility: \(permissionsManager.hasAccessibilityAccess ? "Granted" : "Not Granted")"
        hotkeyStatusLabel.stringValue = "Global Hotkeys: \(hotkeyStatus())"
    }

    private func refreshWindows() {
        refreshPermissionState()
        statusLabel.stringValue = "Loading eligible windows…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                availableWindows = try await windowEnumerator.windows()
                availableTable.reloadData()
                if !availableWindows.isEmpty && availableTable.selectedRow < 0 {
                    availableTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                }
                statusLabel.stringValue = availableWindows.isEmpty
                    ? "No eligible windows found. Open a normal app window and refresh."
                    : "Found \(availableWindows.count) eligible window\(availableWindows.count == 1 ? "" : "s")."
            } catch {
                availableWindows = []
                availableTable.reloadData()
                statusLabel.stringValue = "Could not load windows: \(error.localizedDescription)"
            }
        }
    }

    private func reloadActivePins() {
        activeTable.reloadData()
        if sessions.isEmpty {
            activeTable.deselectAll(nil)
        } else if activeTable.selectedRow < 0 || activeTable.selectedRow >= sessions.count {
            activeTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updateActiveControls()
    }

    private func selectedSession() -> PinSession? {
        guard sessions.indices.contains(activeTable.selectedRow) else { return nil }
        return sessions[activeTable.selectedRow]
    }

    private func updateActiveControls() {
        guard let session = selectedSession() else {
            opacitySlider.isEnabled = false
            opacityLabel.stringValue = "-"
            clickThroughButton.isEnabled = false
            clickThroughButton.state = .off
            showButton.isEnabled = false
            unpinButton.isEnabled = false
            return
        }
        opacitySlider.isEnabled = true
        opacitySlider.doubleValue = Double(session.opacity)
        opacityLabel.stringValue = "\(Int((session.opacity * 100).rounded()))%"
        clickThroughButton.isEnabled = session.mode == .detached
        clickThroughButton.state = session.isClickThrough ? .on : .off
        showButton.isEnabled = true
        unpinButton.isEnabled = true
    }

    @objc private func requestScreenRecording() {
        _ = permissionsManager.requestScreenRecordingAccess()
        refreshPermissionState()
        refreshWindows()
    }

    @objc private func requestAccessibility() {
        _ = permissionsManager.requestAccessibilityAccess()
        refreshPermissionState()
    }

    @objc private func refreshPressed() {
        refreshWindows()
    }

    @objc private func pinSelected() {
        guard availableWindows.indices.contains(availableTable.selectedRow) else {
            statusLabel.stringValue = "Select a window to pin."
            return
        }
        let mode: PinMode = modeControl.selectedSegment == 1 ? .detached : .pinnedInPlace
        guard permissionsManager.ensureScreenRecordingAccess() else {
            refreshPermissionState()
            statusLabel.stringValue = "Screen Recording permission is required."
            return
        }
        if mode == .pinnedInPlace && !permissionsManager.ensureAccessibilityAccess() {
            refreshPermissionState()
            statusLabel.stringValue = "Accessibility permission is required for Pin in Place."
            return
        }

        let descriptor = availableWindows[availableTable.selectedRow]
        statusLabel.stringValue = "Starting \(mode.menuLabel.lowercased()) for \(descriptor.owningAppName)…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await pinManager.pin(descriptor, mode: mode)
                reloadActivePins()
                switch result {
                case .created:
                    statusLabel.stringValue = "\(mode.menuLabel) started for \(descriptor.owningAppName) - \(descriptor.displayTitle)."
                case .alreadyPinned:
                    statusLabel.stringValue = "That window is already pinned."
                }
            } catch {
                statusLabel.stringValue = "Could not pin window: \(error.localizedDescription)"
            }
        }
    }

    @objc private func opacityChanged() {
        guard let session = selectedSession() else { return }
        session.opacity = CGFloat(opacitySlider.doubleValue)
        opacityLabel.stringValue = "\(Int((session.opacity * 100).rounded()))%"
    }

    @objc private func clickThroughChanged() {
        guard let session = selectedSession(), session.mode == .detached else { return }
        session.setClickThrough(clickThroughButton.state == .on)
    }

    @objc private func showRealWindow() {
        selectedSession()?.showRealWindow()
    }

    @objc private func unpinSelected() {
        guard let session = selectedSession() else { return }
        pinManager.unpin(sessionID: session.id)
        statusLabel.stringValue = "Unpinned \(session.source.owningAppName) - \(session.source.displayTitle)."
    }

    @objc private func inspectActiveOverlay() {
        guard selectedSession() != nil else {
            statusLabel.stringValue = "Start and select a pin before inspecting its overlay."
            return
        }
        window?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self else { return }
            self.window?.makeKeyAndOrderFront(nil)
        }
    }
}
