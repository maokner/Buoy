import AppKit
import ApplicationServices

@MainActor
final class PermissionsManager {
    static let shared = PermissionsManager()

    private enum SettingsURL {
        static let screenRecording = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )!
        static let accessibility = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
    }

    private let firstLaunchPromptKey = "didOfferScreenRecordingSetup"

    private init() {}

    var hasScreenRecordingAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    var hasAccessibilityAccess: Bool {
        AXIsProcessTrusted()
    }

    func requestScreenRecordingAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func requestAccessibilityAccess() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    func openScreenRecordingSettings() {
        NSWorkspace.shared.open(SettingsURL.screenRecording)
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(SettingsURL.accessibility)
    }

    func offerFirstLaunchScreenRecordingSetup() {
        guard !hasScreenRecordingAccess else { return }
        guard !UserDefaults.standard.bool(forKey: firstLaunchPromptKey) else { return }

        UserDefaults.standard.set(true, forKey: firstLaunchPromptKey)
        presentScreenRecordingPrompt(
            message: "To make a window float, Buoy needs Screen Recording access. Buoy only captures windows you choose."
        )
    }

    func ensureScreenRecordingAccess() -> Bool {
        guard !hasScreenRecordingAccess else { return true }

        presentScreenRecordingPrompt(
            message: "Buoy needs Screen Recording access before it can create a live window mirror."
        )
        return hasScreenRecordingAccess
    }

    func ensureAccessibilityAccess() -> Bool {
        guard !hasAccessibilityAccess else { return true }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Allow Accessibility"
        alert.informativeText = "Pin in Place needs Accessibility access to track and raise the window you choose. Detached floats do not need this permission."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        _ = requestAccessibilityAccess()
        if !hasAccessibilityAccess {
            openAccessibilitySettings()
        }
        return hasAccessibilityAccess
    }

    func presentPermissions() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Buoy Permissions"
        alert.informativeText = "Screen Recording: \(status(hasScreenRecordingAccess))\nAccessibility: \(status(hasAccessibilityAccess))\n\nAccessibility is not needed yet, but will support window tracking in a later phase."
        alert.addButton(withTitle: "Screen Recording")
        alert.addButton(withTitle: "Accessibility")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if hasScreenRecordingAccess {
                openScreenRecordingSettings()
            } else {
                _ = requestScreenRecordingAccess()
                if !hasScreenRecordingAccess {
                    openScreenRecordingSettings()
                }
            }
        case .alertSecondButtonReturn:
            openAccessibilitySettings()
        default:
            break
        }
    }

    private func presentScreenRecordingPrompt(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Allow Screen Recording"
        alert.informativeText = message
        alert.addButton(withTitle: "Grant Access")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if !requestScreenRecordingAccess() && !hasScreenRecordingAccess {
            let settingsAlert = NSAlert()
            settingsAlert.alertStyle = .informational
            settingsAlert.messageText = "Open System Settings"
            settingsAlert.informativeText = "Enable Buoy in Privacy & Security > Screen Recording, then reopen Buoy if macOS asks you to."
            settingsAlert.addButton(withTitle: "Open Settings")
            settingsAlert.addButton(withTitle: "Later")
            if settingsAlert.runModal() == .alertFirstButtonReturn {
                openScreenRecordingSettings()
            }
        }
    }

    private func status(_ granted: Bool) -> String {
        granted ? "Granted" : "Not granted"
    }
}
