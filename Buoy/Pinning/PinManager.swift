import AppKit

@MainActor
final class PinManager {
    static let shared = PinManager()

    private(set) var sessions: [PinSession] = []
    var onSessionsChanged: (() -> Void)?
    var onUnexpectedCaptureFailure: (() -> Void)?

    private init() {}

    func pin(_ window: WindowDescriptor, mode: PinMode = .pinnedInPlace) async throws {
        guard !sessions.contains(where: { $0.source.windowID == window.windowID }) else { return }

        let opacity = PinPreferences.shared.opacity(for: window)
        let session = PinSession(source: window, opacity: opacity, mode: mode)
        session.panel.onClose = { [weak self, weak session] in
            guard let session else { return }
            self?.unpin(sessionID: session.id)
        }
        session.onSourceClosed = { [weak self, weak session] in
            guard let session else { return }
            self?.unpin(sessionID: session.id)
        }
        session.onCaptureFailed = { [weak self, weak session] error in
            guard let self, let session,
                  self.sessions.contains(where: { $0.id == session.id }) else {
                return
            }
            NSLog("Buoy lost capture for window %u: %@", session.source.windowID, error.localizedDescription)
            self.unpin(sessionID: session.id)
            self.onUnexpectedCaptureFailure?()
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
        session.savePersistentState()
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
            session.savePersistentState()
            Task { @MainActor in
                await session.stop()
            }
        }
    }

    func session(withID id: UUID) -> PinSession? {
        sessions.first(where: { $0.id == id })
    }

    func session(forWindowID windowID: CGWindowID) -> PinSession? {
        sessions.first(where: { $0.source.windowID == windowID })
    }

}
