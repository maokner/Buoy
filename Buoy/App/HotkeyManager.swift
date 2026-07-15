import Carbon

@MainActor
final class HotkeyManager {
    var onPinHotkeyPressed: (() -> Void)?
    var onUnpinHotkeyPressed: (() -> Void)?

    private(set) var pinIsInstalled = false
    private(set) var unpinIsInstalled = false
    private(set) var pinBinding: HotkeyBinding?
    private(set) var unpinBinding: HotkeyBinding?

    private var pinHotkeyReference: EventHotKeyRef?
    private var unpinHotkeyReference: EventHotKeyRef?
    private var handlerReference: EventHandlerRef?
    private var isSuspended = false

    func install(pinBinding: HotkeyBinding?, unpinBinding: HotkeyBinding?) {
        removeRegistrations()
        self.pinBinding = pinBinding
        self.unpinBinding = unpinBinding
        guard !isSuspended else { return }
        registerStoredBindings()
    }

    func suspendAll() {
        guard !isSuspended else { return }
        isSuspended = true
        removeRegistrations()
    }

    func restoreAll() {
        guard isSuspended else { return }
        isSuspended = false
        registerStoredBindings()
    }

    func uninstall() {
        isSuspended = false
        removeRegistrations()
        pinBinding = nil
        unpinBinding = nil
    }

    private func registerStoredBindings() {
        let pinBinding = pinBinding
        let unpinBinding = unpinBinding
        guard pinBinding != nil || unpinBinding != nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            buoyHotkeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerReference
        )
        guard handlerStatus == noErr else { return }

        if let pinBinding {
            pinHotkeyReference = register(pinBinding, identifier: Self.pinIdentifier)
            pinIsInstalled = pinHotkeyReference != nil
        }
        if let unpinBinding {
            unpinHotkeyReference = register(unpinBinding, identifier: Self.unpinIdentifier)
            unpinIsInstalled = unpinHotkeyReference != nil
        }
    }

    private func removeRegistrations() {
        if let pinHotkeyReference {
            UnregisterEventHotKey(pinHotkeyReference)
            self.pinHotkeyReference = nil
        }
        if let unpinHotkeyReference {
            UnregisterEventHotKey(unpinHotkeyReference)
            self.unpinHotkeyReference = nil
        }
        if let handlerReference {
            RemoveEventHandler(handlerReference)
            self.handlerReference = nil
        }
        pinIsInstalled = false
        unpinIsInstalled = false
    }

    fileprivate func handlePress(identifier: UInt32) {
        switch identifier {
        case Self.pinIdentifier:
            onPinHotkeyPressed?()
        case Self.unpinIdentifier:
            onUnpinHotkeyPressed?()
        default:
            break
        }
    }

    private func register(_ binding: HotkeyBinding, identifier: UInt32) -> EventHotKeyRef? {
        var reference: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.carbonModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        return status == noErr ? reference : nil
    }

    private static let pinIdentifier: UInt32 = 1
    private static let unpinIdentifier: UInt32 = 2
    private static let signature: OSType = {
        Array("BUOY".utf8).reduce(0) { ($0 << 8) | OSType($1) }
    }()
}

private func buoyHotkeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID
    )
    guard status == noErr else { return status }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            manager.handlePress(identifier: hotkeyID.id)
        }
    }
    return noErr
}
