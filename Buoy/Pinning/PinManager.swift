import AppKit

@MainActor
final class PinManager {
    static let shared = PinManager()

    private(set) var sessions: [PinSession] = []
    var onSessionsChanged: (() -> Void)?

    private init() {}

    func pin(_ window: WindowDescriptor) async throws {
        guard !sessions.contains(where: { $0.source.windowID == window.windowID }) else { return }

        let session = PinSession(source: window)
        session.panel.onClose = { [weak self, weak session] in
            guard let session else { return }
            self?.unpin(sessionID: session.id)
        }
        session.capture.onError = { [weak self, weak session] error in
            guard let self, let session else { return }
            self.presentCaptureError(error, for: session)
            self.unpin(sessionID: session.id)
        }

        do {
            try await session.start()
            sessions.append(session)
            onSessionsChanged?()
        } catch {
            await session.stop()
            throw error
        }
    }

    func unpin(sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let session = sessions.remove(at: index)
        onSessionsChanged?()
        Task { @MainActor in
            await session.stop()
        }
    }

    func stopAll() {
        let activeSessions = sessions
        sessions.removeAll()
        onSessionsChanged?()
        for session in activeSessions {
            Task { @MainActor in
                await session.stop()
            }
        }
    }

    private func presentCaptureError(_ error: Error, for session: PinSession) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Capture Stopped"
        alert.informativeText = "Buoy stopped mirroring \(session.source.displayTitle): \(error.localizedDescription)"
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

