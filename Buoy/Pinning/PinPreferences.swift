import AppKit

@MainActor
final class PinPreferences {
    static let shared = PinPreferences()

    private let defaults = UserDefaults.standard

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

