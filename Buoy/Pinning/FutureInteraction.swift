import Foundation

protocol WindowTracking: AnyObject {
    func startTracking()
    func stopTracking()
}

protocol InteractionRouting: AnyObject {
    func startRouting()
    func stopRouting()
}

// TODO: Implement Accessibility-based source window tracking in the next phase.
final class WindowTracker: WindowTracking {
    func startTracking() {}
    func stopTracking() {}
}

// TODO: Implement click pass-through and event routing in the next phase.
final class InteractionRouter: InteractionRouting {
    func startRouting() {}
    func stopRouting() {}
}

