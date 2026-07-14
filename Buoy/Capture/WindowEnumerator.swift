import AppKit
import ScreenCaptureKit

struct WindowDescriptor {
    let displayTitle: String
    let owningAppName: String
    let window: SCWindow
    let windowID: CGWindowID
    let processID: pid_t
    let owningAppBundleIdentifier: String?
    let frame: CGRect

    var persistenceAppIdentifier: String {
        owningAppBundleIdentifier ?? owningAppName
    }
}

enum WindowEnumerationError: LocalizedError {
    case unavailable(Error)

    var errorDescription: String? {
        switch self {
        case .unavailable(let error):
            return "Windows could not be loaded: \(error.localizedDescription)"
        }
    }
}

struct WindowEnumerator {
    func window(withID windowID: CGWindowID) async throws -> WindowDescriptor? {
        try await windows().first(where: { $0.windowID == windowID })
    }

    func windows() async throws -> [WindowDescriptor] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            throw WindowEnumerationError.unavailable(error)
        }

        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        return content.windows.compactMap { window in
            guard window.isOnScreen else { return nil }
            guard window.windowLayer == 0 else { return nil }
            guard window.frame.width > 1, window.frame.height > 1 else { return nil }
            guard let application = window.owningApplication else { return nil }
            guard application.processID != ownProcessID else { return nil }

            let appName = application.applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !appName.isEmpty else { return nil }
            let rawBundleIdentifier = application.bundleIdentifier
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let bundleIdentifier = rawBundleIdentifier.isEmpty ? nil : rawBundleIdentifier

            let rawTitle = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let displayTitle = rawTitle.isEmpty ? "Untitled Window" : rawTitle
            return WindowDescriptor(
                displayTitle: displayTitle,
                owningAppName: appName,
                window: window,
                windowID: window.windowID,
                processID: application.processID,
                owningAppBundleIdentifier: bundleIdentifier,
                frame: window.frame
            )
        }
        .sorted {
            let appOrder = $0.owningAppName.localizedCaseInsensitiveCompare($1.owningAppName)
            if appOrder == .orderedSame {
                return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
            return appOrder == .orderedAscending
        }
    }
}
