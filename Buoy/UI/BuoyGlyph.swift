import AppKit

enum BuoyGlyph {
    static func image(pointSize: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            context.saveGState()
            let scale = min(rect.width, rect.height) / 16
            context.translateBy(x: rect.midX - 8 * scale, y: rect.midY - 8 * scale)
            context.scaleBy(x: scale, y: scale)
            context.setFillColor(NSColor.black.cgColor)
            context.setStrokeColor(NSColor.black.cgColor)

            let body = CGMutablePath()
            body.move(to: CGPoint(x: 5.2, y: 1.1))
            body.addCurve(
                to: CGPoint(x: 3.9, y: 3.6),
                control1: CGPoint(x: 4.4, y: 1.5),
                control2: CGPoint(x: 3.9, y: 2.4)
            )
            body.addLine(to: CGPoint(x: 3.9, y: 5.5))
            body.addLine(to: CGPoint(x: 4.8, y: 6.0))
            body.addLine(to: CGPoint(x: 3.9, y: 6.5))
            body.addLine(to: CGPoint(x: 3.9, y: 8.2))
            body.addCurve(
                to: CGPoint(x: 6.1, y: 10.2),
                control1: CGPoint(x: 3.9, y: 9.4),
                control2: CGPoint(x: 4.9, y: 10.2)
            )
            body.addLine(to: CGPoint(x: 9.9, y: 10.2))
            body.addCurve(
                to: CGPoint(x: 12.1, y: 8.2),
                control1: CGPoint(x: 11.1, y: 10.2),
                control2: CGPoint(x: 12.1, y: 9.4)
            )
            body.addLine(to: CGPoint(x: 12.1, y: 6.5))
            body.addLine(to: CGPoint(x: 11.2, y: 6.0))
            body.addLine(to: CGPoint(x: 12.1, y: 5.5))
            body.addLine(to: CGPoint(x: 12.1, y: 3.6))
            body.addCurve(
                to: CGPoint(x: 10.8, y: 1.1),
                control1: CGPoint(x: 12.1, y: 2.4),
                control2: CGPoint(x: 11.6, y: 1.5)
            )
            body.closeSubpath()
            context.addPath(body)
            context.fillPath()

            context.fill(CGRect(x: 7.35, y: 9.8, width: 1.3, height: 2.05))
            context.fillEllipse(in: CGRect(x: 6.6, y: 11.25, width: 2.8, height: 2.8))

            context.setLineWidth(1.05)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: 5.7, y: 13.2))
            context.addLine(to: CGPoint(x: 4.7, y: 14.1))
            context.move(to: CGPoint(x: 8, y: 14.45))
            context.addLine(to: CGPoint(x: 8, y: 15.55))
            context.move(to: CGPoint(x: 10.3, y: 13.2))
            context.addLine(to: CGPoint(x: 11.3, y: 14.1))
            context.strokePath()
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }
}
