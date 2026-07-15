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
        static let unpinHotkeyEnabled = "unpinHotkey.enabled"
        static let unpinHotkeyKeyCode = "unpinHotkey.keyCode"
        static let unpinHotkeyModifiers = "unpinHotkey.modifiers"
        static let unpinHotkeyEquivalent = "unpinHotkey.keyEquivalent"
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

    var pinHotkeyBinding: HotkeyBinding? {
        binding(
            enabledKey: Key.hotkeyEnabled,
            keyCodeKey: Key.hotkeyKeyCode,
            modifiersKey: Key.hotkeyModifiers,
            equivalentKey: Key.hotkeyEquivalent,
            defaultBinding: .defaultPinBinding
        )
    }

    var unpinHotkeyBinding: HotkeyBinding? {
        let candidate = binding(
            enabledKey: Key.unpinHotkeyEnabled,
            keyCodeKey: Key.unpinHotkeyKeyCode,
            modifiersKey: Key.unpinHotkeyModifiers,
            equivalentKey: Key.unpinHotkeyEquivalent,
            defaultBinding: .defaultUnpinBinding
        )
        // Preserve a pre-Phase 8 custom pin shortcut if it already used the
        // new unpin default. The user can choose a distinct unpin binding.
        if defaults.object(forKey: Key.unpinHotkeyEnabled) == nil,
           let candidate,
           let pinHotkeyBinding,
           candidate.conflicts(with: pinHotkeyBinding) {
            return nil
        }
        return candidate
    }

    @discardableResult
    func setPinHotkeyBinding(_ binding: HotkeyBinding?) -> Bool {
        if let binding, let other = unpinHotkeyBinding, binding.conflicts(with: other) {
            return false
        }
        store(
            binding,
            enabledKey: Key.hotkeyEnabled,
            keyCodeKey: Key.hotkeyKeyCode,
            modifiersKey: Key.hotkeyModifiers,
            equivalentKey: Key.hotkeyEquivalent
        )
        return true
    }

    @discardableResult
    func setUnpinHotkeyBinding(_ binding: HotkeyBinding?) -> Bool {
        if let binding, let other = pinHotkeyBinding, binding.conflicts(with: other) {
            return false
        }
        store(
            binding,
            enabledKey: Key.unpinHotkeyEnabled,
            keyCodeKey: Key.unpinHotkeyKeyCode,
            modifiersKey: Key.unpinHotkeyModifiers,
            equivalentKey: Key.unpinHotkeyEquivalent
        )
        return true
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

    private func binding(
        enabledKey: String,
        keyCodeKey: String,
        modifiersKey: String,
        equivalentKey: String,
        defaultBinding: HotkeyBinding
    ) -> HotkeyBinding? {
        guard defaults.object(forKey: enabledKey) != nil else { return defaultBinding }
        guard defaults.bool(forKey: enabledKey) else { return nil }
        let keyCode = UInt32(defaults.integer(forKey: keyCodeKey))
        let modifierRawValue = UInt(defaults.object(forKey: modifiersKey) as? NSNumber != nil
            ? defaults.integer(forKey: modifiersKey)
            : Int(defaultBinding.modifiers.rawValue))
        let equivalent = defaults.string(forKey: equivalentKey) ?? defaultBinding.keyEquivalent
        return HotkeyBinding(
            keyCode: keyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: modifierRawValue),
            keyEquivalent: equivalent
        )
    }

    private func store(
        _ binding: HotkeyBinding?,
        enabledKey: String,
        keyCodeKey: String,
        modifiersKey: String,
        equivalentKey: String
    ) {
        defaults.set(binding != nil, forKey: enabledKey)
        if let binding {
            defaults.set(Int(binding.keyCode), forKey: keyCodeKey)
            defaults.set(Int(binding.modifiers.rawValue), forKey: modifiersKey)
            defaults.set(binding.keyEquivalent, forKey: equivalentKey)
        }
        NotificationCenter.default.post(name: .buoyHotkeyChanged, object: self)
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
