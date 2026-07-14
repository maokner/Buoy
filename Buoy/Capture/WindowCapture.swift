import CoreMedia
import CoreVideo
import ScreenCaptureKit

protocol SampleBufferRendering: AnyObject {
    func display(_ sampleBuffer: CMSampleBuffer)
    func resetRenderer()
}

final class WindowCapture: NSObject {
    private weak var renderer: SampleBufferRendering?
    private let streamQueue = DispatchQueue(label: "com.maokner.Buoy.capture", qos: .userInteractive)
    private var stream: SCStream?

    var onError: ((Error) -> Void)?

    init(renderer: SampleBufferRendering) {
        self.renderer = renderer
        super.init()
    }

    @MainActor
    func start(window: SCWindow) async throws {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(window.frame.width), 1)
        configuration.height = max(Int(window.frame.height), 1)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 5
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true
        configuration.showsCursor = false

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: streamQueue)
        self.stream = stream
        try await stream.startCapture()
    }

    @MainActor
    func stop() async {
        guard let stream else { return }
        do {
            try await stream.stopCapture()
        } catch {
            onError?(error)
        }
        self.stream = nil
        renderer?.resetRenderer()
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
            self?.renderer?.display(sampleBuffer)
        }
    }
}

extension WindowCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(error)
        }
    }
}
