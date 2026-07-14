import AppKit

@MainActor
final class PinPreferences {
    struct RecentWindowIdentity: Codable, Equatable {
        let appIdentifier: String
        let appName: String
        let windowTitle: String
    }

    static let shared = PinPreferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let hotkeyEnabled = "hotkey.enabled"
        static let hotkeyKeyCode = "hotkey.keyCode"
        static let hotkeyModifiers = "hotkey.modifiers"
        static let hotkeyEquivalent = "hotkey.keyEquivalent"
        static let recentWindows = "pin.recentWindows"
    }

    private init() {}

    func opacity(for source: WindowDescriptor) -> CGFloat {
        let key = opacityKey(for: source)
        guard defaults.object(forKey: key) != nil else { return 1 }
        return min(max(defaults.double(forKey: key), 0.15), 1)
    }

    func setOpacity(_ opacity: CGFloat, for source: WindowDescriptor) {
        defaults.set(Double(opacity), forKey: opacityKey(for: source))
    }

    func detachedFrame(for source: WindowDescriptor) -> CGRect? {
        guard let value = defaults.string(forKey: geometryKey(for: source)) else { return nil }
        let frame = NSRectFromString(value)
        guard frame.width > 1, frame.height > 1, isVisibleOnConnectedScreen(frame) else {
            return nil
        }
        return frame
    }

    func setDetachedFrame(_ frame: CGRect, for source: WindowDescriptor) {
        guard frame.width > 1, frame.height > 1 else { return }
        defaults.set(NSStringFromRect(frame), forKey: geometryKey(for: source))
    }

    var hotkeyBinding: HotkeyBinding? {
        guard defaults.object(forKey: Key.hotkeyEnabled) != nil else {
            return .defaultBinding
        }
        guard defaults.bool(forKey: Key.hotkeyEnabled) else { return nil }
        let keyCode = UInt32(defaults.integer(forKey: Key.hotkeyKeyCode))
        let modifierRawValue = UInt(defaults.object(forKey: Key.hotkeyModifiers) as? NSNumber != nil
            ? defaults.integer(forKey: Key.hotkeyModifiers)
            : Int(HotkeyBinding.defaultBinding.modifiers.rawValue))
        let equivalent = defaults.string(forKey: Key.hotkeyEquivalent) ?? "p"
        return HotkeyBinding(
            keyCode: keyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: modifierRawValue),
            keyEquivalent: equivalent
        )
    }

    func setHotkeyBinding(_ binding: HotkeyBinding?) {
        defaults.set(binding != nil, forKey: Key.hotkeyEnabled)
        if let binding {
            defaults.set(Int(binding.keyCode), forKey: Key.hotkeyKeyCode)
            defaults.set(Int(binding.modifiers.rawValue), forKey: Key.hotkeyModifiers)
            defaults.set(binding.keyEquivalent, forKey: Key.hotkeyEquivalent)
        }
        NotificationCenter.default.post(name: .buoyHotkeyChanged, object: self)
    }

    var recentWindows: [RecentWindowIdentity] {
        guard let data = defaults.data(forKey: Key.recentWindows) else { return [] }
        return (try? JSONDecoder().decode([RecentWindowIdentity].self, from: data)) ?? []
    }

    func recordRecent(_ source: WindowDescriptor) {
        let identity = RecentWindowIdentity(
            appIdentifier: source.persistenceAppIdentifier,
            appName: source.owningAppName,
            windowTitle: source.displayTitle
        )
        var values = recentWindows.filter { $0 != identity }
        values.insert(identity, at: 0)
        values = Array(values.prefix(12))
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: Key.recentWindows)
        }
    }

    private func opacityKey(for source: WindowDescriptor) -> String {
        "pin.opacity.\(source.persistenceAppIdentifier)"
    }

    private func geometryKey(for source: WindowDescriptor) -> String {
        "pin.detachedFrame.\(source.persistenceAppIdentifier).\(stableHash(source.displayTitle))"
    }

    private func stableHash(_ string: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func isVisibleOnConnectedScreen(_ frame: CGRect) -> Bool {
        NSScreen.screens.contains { screen in
            let intersection = screen.visibleFrame.intersection(frame)
            let minimumWidth = min(100, frame.width * 0.25)
            let minimumHeight = min(100, frame.height * 0.25)
            return intersection.width >= minimumWidth && intersection.height >= minimumHeight
        }
    }
}

extension Notification.Name {
    static let buoyHotkeyChanged = Notification.Name("Buoy.hotkeyChanged")
}
