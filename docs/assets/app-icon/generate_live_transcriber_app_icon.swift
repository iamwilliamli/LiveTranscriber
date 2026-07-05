import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

private let size = 1024
private let scale = CGFloat(size) / 1024
private let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("LiveTranscriber/Assets.xcassets/AppIcon.appiconset")

private struct IconVariant {
    let filename: String
    let canvasTop: CGColor
    let canvasBottom: CGColor
    let symbolTop: CGColor
    let symbolBottom: CGColor
    let symbolShadow: CGColor
    let lineMidTop: CGColor
    let lineMidBottom: CGColor
    let lineLightTop: CGColor
    let lineLightBottom: CGColor
    let highlight: CGColor
}

private func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    let red = CGFloat((hex >> 16) & 0xff) / 255
    let green = CGFloat((hex >> 8) & 0xff) / 255
    let blue = CGFloat(hex & 0xff) / 255
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha).cgColor
}

private let variants: [IconVariant] = [
    IconVariant(
        filename: "LiveTranscriberIcon-Light.png",
        canvasTop: color(0xffffff),
        canvasBottom: color(0xeff1f3),
        symbolTop: color(0x4a4d4e),
        symbolBottom: color(0x17191a),
        symbolShadow: color(0x050607, 0.34),
        lineMidTop: color(0x8c8f90),
        lineMidBottom: color(0x4a4d4e),
        lineLightTop: color(0xdbddde),
        lineLightBottom: color(0xa7aaab),
        highlight: color(0xffffff, 0.22)
    ),
    IconVariant(
        filename: "LiveTranscriberIcon-Dark.png",
        canvasTop: color(0x1e2226),
        canvasBottom: color(0x090b0d),
        symbolTop: color(0xf5f6f7),
        symbolBottom: color(0xaeb4bb),
        symbolShadow: color(0x000000, 0.46),
        lineMidTop: color(0xd5d9dd),
        lineMidBottom: color(0x8d949b),
        lineLightTop: color(0x8d949b),
        lineLightBottom: color(0x5f666d),
        highlight: color(0xffffff, 0.36)
    ),
    IconVariant(
        filename: "LiveTranscriberIcon-Tinted.png",
        canvasTop: color(0xf9fafb),
        canvasBottom: color(0xe9ecef),
        symbolTop: color(0x292c2f),
        symbolBottom: color(0x111315),
        symbolShadow: color(0x050607, 0.30),
        lineMidTop: color(0x6b7075),
        lineMidBottom: color(0x3f4449),
        lineLightTop: color(0xb9bdc1),
        lineLightBottom: color(0x8d9297),
        highlight: color(0xffffff, 0.20)
    )
]

private func scaled(_ rect: CGRect) -> CGRect {
    CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
}

private func scaled(_ point: CGPoint) -> CGPoint {
    CGPoint(x: point.x * scale, y: point.y * scale)
}

private func drawLinearGradient(
    _ context: CGContext,
    in path: CGPath,
    colors: [CGColor],
    start: CGPoint,
    end: CGPoint
) {
    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil) else {
        return
    }
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(gradient, start: scaled(start), end: scaled(end), options: [])
    context.restoreGState()
}

private func drawShadowedFill(_ context: CGContext, path: CGPath, color: CGColor, shadow: CGColor, blur: CGFloat, y: CGFloat) {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: y * scale), blur: blur * scale, color: shadow)
    context.addPath(path)
    context.setFillColor(color)
    context.fillPath()
    context.restoreGState()
}

private func drawRoundedGradient(
    _ context: CGContext,
    rect: CGRect,
    radius: CGFloat,
    colors: [CGColor],
    start: CGPoint,
    end: CGPoint,
    shadow: CGColor? = nil,
    shadowBlur: CGFloat = 0,
    shadowY: CGFloat = 0
) {
    let path = CGPath(roundedRect: scaled(rect), cornerWidth: radius * scale, cornerHeight: radius * scale, transform: nil)
    if let shadow {
        drawShadowedFill(context, path: path, color: colors.last ?? color(0x000000), shadow: shadow, blur: shadowBlur, y: shadowY)
    }
    drawLinearGradient(context, in: path, colors: colors, start: start, end: end)
}

private func strokePath(
    _ context: CGContext,
    _ path: CGPath,
    color: CGColor,
    width: CGFloat,
    shadow: CGColor,
    blur: CGFloat,
    y: CGFloat,
    lineCap: CGLineCap = .round
) {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: y * scale), blur: blur * scale, color: shadow)
    context.addPath(path)
    context.setStrokeColor(color)
    context.setLineWidth(width * scale)
    context.setLineCap(lineCap)
    context.setLineJoin(.round)
    context.strokePath()
    context.restoreGState()
}

private func makeMicrophonePath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: scaled(CGPoint(x: 284, y: 484)))
    path.addLine(to: scaled(CGPoint(x: 284, y: 535)))
    path.addCurve(
        to: scaled(CGPoint(x: 426, y: 724)),
        control1: scaled(CGPoint(x: 284, y: 652)),
        control2: scaled(CGPoint(x: 346, y: 724))
    )
    path.addCurve(
        to: scaled(CGPoint(x: 568, y: 535)),
        control1: scaled(CGPoint(x: 506, y: 724)),
        control2: scaled(CGPoint(x: 568, y: 652))
    )
    path.addLine(to: scaled(CGPoint(x: 568, y: 484)))
    return path
}

private func makeLinePath(from start: CGPoint, to end: CGPoint) -> CGPath {
    let path = CGMutablePath()
    path.move(to: scaled(start))
    path.addLine(to: scaled(end))
    return path
}

private func drawIcon(_ variant: IconVariant) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw NSError(domain: "LiveTranscriberIcon", code: 1)
    }
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: 1, y: -1)

    let canvasPath = CGPath(rect: CGRect(x: 0, y: 0, width: size, height: size), transform: nil)
    drawLinearGradient(
        context,
        in: canvasPath,
        colors: [variant.canvasTop, variant.canvasBottom],
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 1024, y: 1024)
    )

    let micStroke = makeMicrophonePath()
    strokePath(context, micStroke, color: variant.symbolBottom, width: 39, shadow: variant.symbolShadow, blur: 9, y: 8)

    strokePath(
        context,
        makeLinePath(from: CGPoint(x: 426, y: 722), to: CGPoint(x: 426, y: 776)),
        color: variant.symbolBottom,
        width: 35,
        shadow: variant.symbolShadow,
        blur: 8,
        y: 7
    )
    strokePath(
        context,
        makeLinePath(from: CGPoint(x: 356, y: 776), to: CGPoint(x: 496, y: 776)),
        color: variant.symbolBottom,
        width: 35,
        shadow: variant.symbolShadow,
        blur: 8,
        y: 7
    )

    let bodyRect = CGRect(x: 342, y: 292, width: 168, height: 292)
    drawRoundedGradient(
        context,
        rect: bodyRect,
        radius: 84,
        colors: [variant.symbolTop, variant.symbolBottom],
        start: CGPoint(x: 342, y: 292),
        end: CGPoint(x: 510, y: 584),
        shadow: variant.symbolShadow,
        shadowBlur: 10,
        shadowY: 8
    )

    context.saveGState()
    let bodyPath = CGPath(roundedRect: scaled(bodyRect), cornerWidth: 84 * scale, cornerHeight: 84 * scale, transform: nil)
    context.addPath(bodyPath)
    context.clip()
    for index in 0..<48 {
        let x = CGFloat((index * 37) % 154) + 348
        let y = CGFloat((index * 61) % 270) + 304
        context.setFillColor(color(0xffffff, index.isMultiple(of: 2) ? 0.030 : 0.014))
        context.fillEllipse(in: scaled(CGRect(x: x, y: y, width: 2.2, height: 2.2)))
    }
    context.restoreGState()

    strokePath(
        context,
        makeLinePath(from: CGPoint(x: 374, y: 318), to: CGPoint(x: 488, y: 330)),
        color: variant.highlight,
        width: 4,
        shadow: color(0x000000, 0),
        blur: 0,
        y: 0
    )

    drawRoundedGradient(
        context,
        rect: CGRect(x: 622, y: 383, width: 220, height: 27),
        radius: 13.5,
        colors: [variant.symbolTop, variant.symbolBottom],
        start: CGPoint(x: 622, y: 383),
        end: CGPoint(x: 842, y: 410),
        shadow: variant.symbolShadow,
        shadowBlur: 8,
        shadowY: 7
    )
    drawRoundedGradient(
        context,
        rect: CGRect(x: 622, y: 459, width: 174, height: 27),
        radius: 13.5,
        colors: [variant.lineMidTop, variant.lineMidBottom],
        start: CGPoint(x: 622, y: 459),
        end: CGPoint(x: 796, y: 486),
        shadow: variant.symbolShadow,
        shadowBlur: 7,
        shadowY: 6
    )
    drawRoundedGradient(
        context,
        rect: CGRect(x: 622, y: 535, width: 119, height: 27),
        radius: 13.5,
        colors: [variant.lineLightTop, variant.lineLightBottom],
        start: CGPoint(x: 622, y: 535),
        end: CGPoint(x: 741, y: 562),
        shadow: variant.symbolShadow,
        shadowBlur: 6,
        shadowY: 5
    )

    guard let image = context.makeImage() else {
        throw NSError(domain: "LiveTranscriberIcon", code: 2)
    }

    let destinationURL = outputDirectory.appendingPathComponent(variant.filename)
    guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "LiveTranscriberIcon", code: 3)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "LiveTranscriberIcon", code: 4)
    }
    print("Wrote \(destinationURL.path)")
}

try variants.forEach(drawIcon)
