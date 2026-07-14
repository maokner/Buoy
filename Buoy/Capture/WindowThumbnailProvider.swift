import AppKit
import ScreenCaptureKit

@MainActor
final class WindowThumbnailProvider {
    private struct Entry {
        let image: NSImage
        let date: Date
    }

    private var cache: [CGWindowID: Entry] = [:]
    private var inFlight: [CGWindowID: Task<NSImage?, Never>] = [:]
    private let cacheLifetime: TimeInterval = 15

    func thumbnail(for descriptor: WindowDescriptor) async -> NSImage? {
        if let entry = cache[descriptor.windowID], Date().timeIntervalSince(entry.date) < cacheLifetime {
            return entry.image
        }
        if let task = inFlight[descriptor.windowID] {
            return await task.value
        }

        let task = Task<NSImage?, Never> {
            let filter = SCContentFilter(desktopIndependentWindow: descriptor.window)
            let configuration = SCStreamConfiguration()
            let aspectRatio = max(descriptor.frame.width, 1) / max(descriptor.frame.height, 1)
            configuration.height = 88
            configuration.width = min(max(Int((88 * aspectRatio).rounded()), 44), 264)
            configuration.scalesToFit = true
            configuration.showsCursor = false
            do {
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
                return Self.framedThumbnail(from: image, aspectRatio: aspectRatio)
            } catch {
                return nil
            }
        }
        inFlight[descriptor.windowID] = task
        let image = await task.value
        inFlight[descriptor.windowID] = nil
        if let image {
            cache[descriptor.windowID] = Entry(image: image, date: Date())
        }
        return image
    }

    private static func framedThumbnail(from image: CGImage, aspectRatio: CGFloat) -> NSImage {
        let contentSize = NSSize(
            width: min(max(40 * aspectRatio, 22), 120),
            height: 40
        )
        let canvasSize = NSSize(width: contentSize.width + 4, height: 44)
        let sourceImage = NSImage(cgImage: image, size: contentSize)
        let thumbnail = NSImage(size: canvasSize, flipped: false) { rect in
            let backdrop = NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                xRadius: 4,
                yRadius: 4
            )
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            (isDark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.04)).setFill()
            backdrop.fill()

            NSGraphicsContext.saveGraphicsState()
            let contentRect = NSRect(origin: NSPoint(x: 2, y: 2), size: contentSize)
            NSBezierPath(roundedRect: contentRect, xRadius: 3, yRadius: 3).addClip()
            sourceImage.draw(
                in: contentRect,
                from: NSRect(origin: .zero, size: sourceImage.size),
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            NSGraphicsContext.restoreGraphicsState()

            NSColor.separatorColor.withAlphaComponent(0.8).setStroke()
            backdrop.lineWidth = 1
            backdrop.stroke()
            return true
        }
        thumbnail.isTemplate = false
        return thumbnail
    }
}
