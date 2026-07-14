import Carbon

@MainActor
final class HotkeyManager {
    var onHotkeyPressed: (() -> Void)?
    private(set) var isInstalled = false

    private var hotkeyReference: EventHotKeyRef?
    private var handlerReference: EventHandlerRef?

    func install() {
        guard !isInstalled else { return }

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

        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            UInt32(optionKey | cmdKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotkeyReference
        )
        guard registrationStatus == noErr else {
            if let handlerReference {
                RemoveEventHandler(handlerReference)
                self.handlerReference = nil
            }
            return
        }

        isInstalled = true
    }

    func uninstall() {
        if let hotkeyReference {
            UnregisterEventHotKey(hotkeyReference)
            self.hotkeyReference = nil
        }
        if let handlerReference {
            RemoveEventHandler(handlerReference)
            self.handlerReference = nil
        }
        isInstalled = false
    }

    fileprivate func handlePress() {
        onHotkeyPressed?()
    }

    private static let signature: OSType = {
        Array("BUOY".utf8).reduce(0) { ($0 << 8) | OSType($1) }
    }()
}

private func buoyHotkeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            manager.handlePress()
        }
    }
    return noErr
}
