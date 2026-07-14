import AppKit

@MainActor
final class PinManager {
    enum PinResult {
        case created
        case alreadyPinned
    }

    static let shared = PinManager()

    private(set) var sessions: [PinSession] = []
    var onSessionsChanged: (() -> Void)?
    var onUnexpectedCaptureFailure: (() -> Void)?

    // Windows with a pin() currently suspended at an await; guards against
    // reentrant double-pinning (e.g. two fast hotkey presses) before append.
    private var inFlightWindowIDs: Set<CGWindowID> = []

    private init() {}

    @discardableResult
    func pin(
        _ window: WindowDescriptor,
        mode: PinMode = .pinnedInPlace
    ) async throws -> PinResult {
        guard !sessions.contains(where: { $0.source.windowID == window.windowID }),
              !inFlightWindowIDs.contains(window.windowID) else {
            return .alreadyPinned
        }
        inFlightWindowIDs.insert(window.windowID)
        defer { inFlightWindowIDs.remove(window.windowID) }

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
            PinPreferences.shared.recordRecent(window)
            notifySessionsChanged()
            return .created
        } catch {
            await session.stop()
            throw error
        }
    }

    func unpin(sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let session = sessions.remove(at: index)
        session.savePersistentState()
        notifySessionsChanged()
        Task { @MainActor in
            await session.stop()
        }
    }

    func stopAll() {
        let activeSessions = sessions
        sessions.removeAll()
        notifySessionsChanged()
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

    private func notifySessionsChanged() {
        onSessionsChanged?()
        NotificationCenter.default.post(name: .buoySessionsChanged, object: self)
    }
}

extension Notification.Name {
    static let buoySessionsChanged = Notification.Name("Buoy.sessionsChanged")
}
