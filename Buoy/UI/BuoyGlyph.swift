import AppKit

enum BuoyGlyph {
    static func image(pointSize: CGFloat, active: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            let scale = min(rect.width, rect.height) / 32
            context.saveGState()
            context.translateBy(x: rect.midX - 16 * scale, y: rect.midY - 16 * scale)
            context.scaleBy(x: scale, y: scale)
            context.setFillColor(NSColor.black.cgColor)
            context.fillEllipse(in: CGRect(x: 2.4, y: 2.4, width: 27.2, height: 27.2))

            context.setBlendMode(.clear)
            context.setStrokeColor(NSColor.clear.cgColor)
            context.setLineWidth(4.0)
            let wave = CGMutablePath()
            wave.move(to: CGPoint(x: 0, y: 17.4))
            wave.addQuadCurve(to: CGPoint(x: 8, y: 17.4), control: CGPoint(x: 4, y: 12.9))
            wave.addQuadCurve(to: CGPoint(x: 16, y: 17.4), control: CGPoint(x: 12, y: 21.9))
            wave.addQuadCurve(to: CGPoint(x: 24, y: 17.4), control: CGPoint(x: 20, y: 12.9))
            wave.addQuadCurve(to: CGPoint(x: 32, y: 17.4), control: CGPoint(x: 28, y: 21.9))
            context.addPath(wave)
            context.strokePath()

            if active {
                context.setBlendMode(.normal)
                context.setFillColor(NSColor.black.cgColor)
                context.fillEllipse(in: CGRect(x: 13.9, y: 15.3, width: 4.2, height: 4.2))
            }

            context.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }
}
