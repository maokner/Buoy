import AppKit
import CoreMedia
import CoreVideo
import ScreenCaptureKit

protocol SampleBufferRendering: AnyObject {
    func display(_ sampleBuffer: CMSampleBuffer)
    func resetRenderer()
}

final class WindowCapture: NSObject {
    struct CaptureDimensions: Equatable {
        let width: Int
        let height: Int
    }

    private weak var renderer: SampleBufferRendering?
    private let streamQueue = DispatchQueue(label: "com.maokner.Buoy.capture", qos: .userInteractive)
    private var filter: SCContentFilter?
    private var stream: SCStream?
    private var configuredDimensions: CaptureDimensions?
    private var requestedDimensions: CaptureDimensions?
    private var requestedPointSize: CGSize?
    private var requestedSourceFrame: CGRect?
    private var configurationUpdateTask: Task<Void, Never>?
    private var lifecycleTask: Task<Void, Never>?
    private var wantsCaptureRunning = false
    private var isStopping = false

    var onError: ((Error) -> Void)?
    var onFrameDelivered: (() -> Void)?

    init(renderer: SampleBufferRendering) {
        self.renderer = renderer
        super.init()
    }

    @MainActor
    func start(window: SCWindow) async throws {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let sourceFrame = Self.cocoaFrame(fromQuartzFrame: window.frame)
        self.filter = filter
        requestedPointSize = window.frame.size
        requestedSourceFrame = sourceFrame
        requestedDimensions = captureDimensions(using: filter)
        wantsCaptureRunning = true
        isStopping = false

        do {
            try await startNewStream(using: filter)
        } catch {
            self.filter = nil
            requestedDimensions = nil
            requestedPointSize = nil
            requestedSourceFrame = nil
            wantsCaptureRunning = false
            throw error
        }
    }

    @MainActor
    func updateSize(to size: CGSize, sourceFrame: CGRect? = nil) {
        guard filter != nil, !isStopping else { return }
        requestedPointSize = size
        if let sourceFrame {
            requestedSourceFrame = sourceFrame
        }
        refreshRequestedDimensions()

        guard stream != nil, requestedDimensions != configuredDimensions else { return }
        scheduleConfigurationUpdate()
    }

    @MainActor
    func pause() {
        guard filter != nil, !isStopping else { return }
        wantsCaptureRunning = false
        scheduleLifecycleTransition()
    }

    @MainActor
    func resume() {
        guard filter != nil, !isStopping else { return }
        refreshRequestedDimensions()
        wantsCaptureRunning = true
        scheduleLifecycleTransition()
    }

    @MainActor
    func stop() async {
        guard filter != nil || stream != nil || lifecycleTask != nil else {
            renderer?.resetRenderer()
            return
        }

        isStopping = true
        wantsCaptureRunning = false
        scheduleLifecycleTransition()
        while let task = lifecycleTask {
            await task.value
        }

        configurationUpdateTask?.cancel()
        if let task = configurationUpdateTask {
            await task.value
        }
        configurationUpdateTask = nil
        filter = nil
        stream = nil
        configuredDimensions = nil
        requestedDimensions = nil
        requestedPointSize = nil
        requestedSourceFrame = nil
        isStopping = false
        renderer?.resetRenderer()
    }

    static func captureDimensions(for size: CGSize, scale: CGFloat) -> CaptureDimensions {
        CaptureDimensions(
            width: max(Int((size.width * scale).rounded()), 1),
            height: max(Int((size.height * scale).rounded()), 1)
        )
    }

    private static func makeConfiguration(for dimensions: CaptureDimensions) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = dimensions.width
        configuration.height = dimensions.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 5
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true
        configuration.showsCursor = false
        return configuration
    }

    @MainActor
    private func captureDimensions(using filter: SCContentFilter) -> CaptureDimensions? {
        guard let requestedPointSize else { return nil }
        let filterScale = CGFloat(filter.pointPixelScale)
        let scale = filterScale.isFinite && filterScale > 0
            ? filterScale
            : Self.fallbackScale(for: requestedSourceFrame)
        return Self.captureDimensions(for: requestedPointSize, scale: scale)
    }

    @MainActor
    private func refreshRequestedDimensions() {
        guard let filter else { return }
        requestedDimensions = captureDimensions(using: filter)
    }

    @MainActor
    private func startNewStream(using filter: SCContentFilter) async throws {
        refreshRequestedDimensions()
        guard let dimensions = requestedDimensions else { return }

        let stream = SCStream(
            filter: filter,
            configuration: Self.makeConfiguration(for: dimensions),
            delegate: self
        )
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: streamQueue)
        self.stream = stream
        configuredDimensions = dimensions
        do {
            try await stream.startCapture()
        } catch {
            if self.stream === stream {
                self.stream = nil
                configuredDimensions = nil
            }
            throw error
        }
    }

    @MainActor
    private func scheduleLifecycleTransition() {
        guard lifecycleTask == nil else { return }
        lifecycleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await reconcileLifecycle()
            lifecycleTask = nil
            if needsLifecycleTransition {
                scheduleLifecycleTransition()
            }
        }
    }

    @MainActor
    private var needsLifecycleTransition: Bool {
        wantsCaptureRunning ? stream == nil && filter != nil : stream != nil
    }

    @MainActor
    private func reconcileLifecycle() async {
        while needsLifecycleTransition {
            if wantsCaptureRunning {
                guard let filter else { return }
                do {
                    try await startNewStream(using: filter)
                } catch {
                    wantsCaptureRunning = false
                    if !isStopping {
                        onError?(error)
                    }
                    return
                }
            } else {
                await stopActiveStreamPreservingFrame()
            }
        }
    }

    @MainActor
    private func stopActiveStreamPreservingFrame() async {
        configurationUpdateTask?.cancel()
        if let task = configurationUpdateTask {
            await task.value
        }
        configurationUpdateTask = nil

        guard let activeStream = stream else { return }
        stream = nil
        configuredDimensions = nil
        do {
            try await activeStream.stopCapture()
        } catch {
            // This stop is intentional. A delegate error from this stream is also ignored
            // because it is no longer the active stream.
        }
    }

    @MainActor
    private func scheduleConfigurationUpdate() {
        guard configurationUpdateTask == nil else { return }
        configurationUpdateTask = Task { @MainActor [weak self] in
            await self?.applyRequestedConfigurationUpdates()
        }
    }

    @MainActor
    private func applyRequestedConfigurationUpdates() async {
        guard let activeStream = stream else {
            configurationUpdateTask = nil
            return
        }

        while !Task.isCancelled,
              stream === activeStream,
              wantsCaptureRunning,
              let dimensions = requestedDimensions,
              dimensions != configuredDimensions {
            do {
                try await activeStream.updateConfiguration(Self.makeConfiguration(for: dimensions))
            } catch {
                configurationUpdateTask = nil
                if !Task.isCancelled, stream === activeStream, wantsCaptureRunning, !isStopping {
                    onError?(error)
                }
                return
            }

            guard !Task.isCancelled, stream === activeStream, wantsCaptureRunning else {
                configurationUpdateTask = nil
                return
            }
            configuredDimensions = dimensions
        }

        configurationUpdateTask = nil
    }

    private static func fallbackScale(for sourceFrame: CGRect?) -> CGFloat {
        let screen: NSScreen?
        if let sourceFrame {
            screen = NSScreen.screens.max { first, second in
                intersectionArea(first.frame, sourceFrame) < intersectionArea(second.frame, sourceFrame)
            }
        } else {
            screen = nil
        }
        return max(screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1, 1)
    }

    private static func intersectionArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private static func cocoaFrame(fromQuartzFrame frame: CGRect) -> CGRect {
        let primaryScreenTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(
            x: frame.minX,
            y: primaryScreenTop - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    @MainActor
    private func handleUnexpectedStop(stream: SCStream, error: Error) {
        guard self.stream === stream, wantsCaptureRunning, !isStopping else { return }
        self.stream = nil
        configuredDimensions = nil
        wantsCaptureRunning = false
        configurationUpdateTask?.cancel()
        configurationUpdateTask = nil
        onError?(error)
    }

    @MainActor
    private func deliver(_ sampleBuffer: CMSampleBuffer, from stream: SCStream) {
        guard self.stream === stream, wantsCaptureRunning, !isStopping else { return }
        renderer?.display(sampleBuffer)
        onFrameDelivered?()
    }
}

extension WindowCapture: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.deliver(sampleBuffer, from: stream)
        }
    }
}

extension WindowCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.handleUnexpectedStop(stream: stream, error: error)
        }
    }
}
