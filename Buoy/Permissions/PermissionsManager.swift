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
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Let Buoy see your windows"
        alert.informativeText = "Buoy floats a live copy of any window you pick. To do that, macOS needs to grant Screen Recording. Buoy only mirrors the windows you choose, and nothing leaves your Mac."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if !requestScreenRecordingAccess() && !hasScreenRecordingAccess {
            presentScreenRecordingOffAlert()
        }
    }

    func ensureScreenRecordingAccess() -> Bool {
        guard !hasScreenRecordingAccess else { return true }
        presentScreenRecordingOffAlert()
        return hasScreenRecordingAccess
    }

    func ensureAccessibilityAccess() -> Bool {
        guard !hasAccessibilityAccess else { return true }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Buoy needs one more thing to pin in place"
        alert.informativeText = "Pinning in place lets Buoy raise and follow the real window as it moves. That needs Accessibility access. Floating windows do not - if you would rather not grant this, hold Option when picking a window to float it instead."
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
        let screenGranted = hasScreenRecordingAccess
        let accessibilityGranted = hasAccessibilityAccess
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Buoy Permissions"
        var body = "Screen Recording - \(status(screenGranted)). Required to mirror any window.\nAccessibility - \(status(accessibilityGranted)). Needed only for Pin in Place."
        if screenGranted && accessibilityGranted {
            body += "\n\nEverything Buoy needs is enabled."
        }
        alert.informativeText = body

        if !screenGranted {
            alert.addButton(withTitle: "Open Screen Recording")
            alert.addButton(withTitle: "Open Accessibility")
            alert.addButton(withTitle: "Done")
        } else if !accessibilityGranted {
            alert.addButton(withTitle: "Open Accessibility")
            alert.addButton(withTitle: "Open Screen Recording")
            alert.addButton(withTitle: "Done")
        } else {
            alert.addButton(withTitle: "Done")
        }

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if !screenGranted {
            if response == .alertFirstButtonReturn {
                openScreenRecordingSettings()
            } else if response == .alertSecondButtonReturn {
                openAccessibilitySettings()
            }
        } else if !accessibilityGranted {
            if response == .alertFirstButtonReturn {
                openAccessibilitySettings()
            } else if response == .alertSecondButtonReturn {
                openScreenRecordingSettings()
            }
        }
    }

    private func presentScreenRecordingOffAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Screen Recording is off"
        alert.informativeText = "Turn on Buoy under Privacy & Security, Screen Recording. macOS may ask you to quit and reopen Buoy once you do."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openScreenRecordingSettings()
        }
    }

    private func status(_ granted: Bool) -> String {
        granted ? "Granted" : "Not granted"
    }
}
