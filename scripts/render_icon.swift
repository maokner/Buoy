// Renders the Buoy app icon per DESIGN.md section 4.1 at all required sizes.
// Usage: swift render_icon.swift <output-dir>
import AppKit

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let skyTop = srgb(0x2E9BE6)
let waterDeep = srgb(0x0A5FB0)
let waterBand = srgb(0x0A4E92)
let buoyRed = srgb(0xFF5A47)
let buoyWhite = srgb(0xF2F2F2)
let keelNavy = srgb(0x0A3A6E)
let lampAmber = srgb(0xFFC24B)
let shadowNavy = srgb(0x062C55, 0.3)

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    let S = CGFloat(pixels)

    // Tile: squircle with ~5% margin each side, Apple-style corner radius.
    let margin = S * 0.05
    let tile = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
    let corner = tile.width * 0.225
    let squircle = CGPath(roundedRect: tile, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Soft drop shadow behind the tile (skip at tiny sizes; it just muddies).
    if pixels >= 64 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.008), blur: S * 0.02, color: srgb(0x000000, 0.25))
        ctx.addPath(squircle)
        ctx.setFillColor(srgb(0x0A5FB0))
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Sky gradient, top -> bottom.
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let skyGrad = CGGradient(colorsSpace: space, colors: [skyTop, waterDeep] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(
        skyGrad,
        start: CGPoint(x: tile.midX, y: tile.maxY),
        end: CGPoint(x: tile.midX, y: tile.minY),
        options: []
    )

    // Geometry: elongated vertical capsule, bottom submerged below the waterline.
    let waterTop = tile.minY + tile.height * 0.35
    let bodyW = tile.width * 0.32
    let bodyH = tile.height * 0.46
    let bodyX = tile.midX - bodyW / 2
    let bodyBottom = waterTop - bodyH * 0.22 // ~22% of the hull sits under water
    let body = CGRect(x: bodyX, y: bodyBottom, width: bodyW, height: bodyH)

    // Mast: dark navy, rising from the body top; lamp sits on it.
    let mastW = tile.width * 0.05
    let mastH = tile.height * 0.14
    let mast = CGRect(x: tile.midX - mastW / 2, y: body.maxY - mastW, width: mastW, height: mastH + mastW)
    ctx.setFillColor(keelNavy)
    ctx.fill(mast)

    // Lamp glow first (behind lamp): radial amber 0.5 -> 0.
    let lampR = tile.width * 0.06
    let lampC = CGPoint(x: tile.midX, y: mast.maxY + lampR * 0.7)
    let glow = CGGradient(
        colorsSpace: space,
        colors: [srgb(0xFFC24B, 0.55), srgb(0xFFC24B, 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        glow, startCenter: lampC, startRadius: 0,
        endCenter: lampC, endRadius: lampR * 4.0, options: []
    )

    // Lamp.
    ctx.setFillColor(lampAmber)
    ctx.fillEllipse(in: CGRect(x: lampC.x - lampR, y: lampC.y - lampR, width: lampR * 2, height: lampR * 2))

    // Buoy body: capsule, red upper band / white lower band.
    let capsule = CGPath(roundedRect: body, cornerWidth: bodyW / 2, cornerHeight: bodyW / 2, transform: nil)
    ctx.saveGState()
    ctx.addPath(capsule)
    ctx.clip()
    ctx.setFillColor(buoyWhite)
    ctx.fill(body)
    ctx.setFillColor(buoyRed)
    let split = body.minY + bodyH * 0.52
    ctx.fill(CGRect(x: body.minX, y: split, width: bodyW, height: body.maxY - split))
    // Specular highlight down the left edge.
    ctx.setFillColor(srgb(0xFFFFFF, 0.3))
    let hi = CGRect(
        x: body.minX + bodyW * 0.13, y: waterTop + bodyH * 0.06,
        width: max(1, S * 0.018), height: body.maxY - waterTop - bodyH * 0.18
    )
    ctx.addPath(CGPath(roundedRect: hi, cornerWidth: hi.width / 2, cornerHeight: hi.width / 2, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()

    // Water band drawn OVER the hull so the buoy visibly sits in the water.
    ctx.setFillColor(waterBand)
    ctx.fill(CGRect(x: tile.minX, y: tile.minY, width: tile.width, height: waterTop - tile.minY))

    // Keel line: thin dark waterline across the hull where it meets the water.
    ctx.setFillColor(keelNavy)
    ctx.fill(CGRect(x: body.minX, y: waterTop, width: bodyW, height: max(1, S * 0.012)))

    // Contact shadow on the water directly beneath the buoy.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: S * 0.015, color: shadowNavy)
    ctx.setFillColor(shadowNavy)
    ctx.fillEllipse(in: CGRect(
        x: tile.midX - bodyW * 0.58, y: waterTop - tile.height * 0.035,
        width: bodyW * 1.16, height: tile.height * 0.028
    ))
    ctx.restoreGState()

    // Ripples: two thin lighter ellipse arcs hugging the hull on the water surface.
    for (i, alpha) in [(0, 0.25), (1, 0.15)] {
        let spread = 1.0 + CGFloat(i) * 0.45
        let rw = bodyW * 1.35 * spread
        let rh = tile.height * 0.035 * spread
        let rr = CGRect(
            x: tile.midX - rw / 2,
            y: waterTop - rh * 0.85 - CGFloat(i) * tile.height * 0.02,
            width: rw, height: rh
        )
        ctx.setStrokeColor(srgb(0xFFFFFF, alpha))
        ctx.setLineWidth(max(1, S * 0.006))
        ctx.strokeEllipse(in: rr)
    }

    ctx.restoreGState() // squircle clip
    ctx.flush()
    return rep
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for px in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = renderIcon(pixels: px)
    let png = rep.representation(using: .png, properties: [:])!
    let path = "\(outDir)/icon_\(px).png"
    try! png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}
