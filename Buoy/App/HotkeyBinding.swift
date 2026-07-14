import AppKit
import Carbon

struct HotkeyBinding: Equatable {
    let keyCode: UInt32
    let modifiers: NSEvent.ModifierFlags
    let keyEquivalent: String

    static let defaultBinding = HotkeyBinding(
        keyCode: UInt32(kVK_ANSI_P),
        modifiers: [.option, .shift],
        keyEquivalent: "p"
    )

    var menuModifierMask: NSEvent.ModifierFlags {
        normalizedModifiers
    }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if normalizedModifiers.contains(.command) { value |= UInt32(cmdKey) }
        if normalizedModifiers.contains(.option) { value |= UInt32(optionKey) }
        if normalizedModifiers.contains(.control) { value |= UInt32(controlKey) }
        if normalizedModifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    var displayString: String {
        var result = ""
        if normalizedModifiers.contains(.control) { result += "⌃" }
        if normalizedModifiers.contains(.option) { result += "⌥" }
        if normalizedModifiers.contains(.shift) { result += "⇧" }
        if normalizedModifiers.contains(.command) { result += "⌘" }
        result += displayKey
        return result
    }

    private var normalizedModifiers: NSEvent.ModifierFlags {
        modifiers.intersection([.command, .option, .control, .shift])
    }

    private var displayKey: String {
        if let functionKey = functionKeyNames[Int(keyCode)] {
            return functionKey
        }
        switch Int(keyCode) {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        default:
            return keyEquivalent.uppercased()
        }
    }

    private var functionKeyNames: [Int: String] {
        [
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
            kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        ]
    }
}
