import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let size = 1024
private let cropInset: CGFloat = 106
private let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let sourceURL = workspace
    .appendingPathComponent("docs/assets/app-icon/live-transcriber-liquid-glass-master.png")
private let outputDirectory = workspace
    .appendingPathComponent("LiveTranscriber/Assets.xcassets/AppIcon.appiconset")
private let outputFilenames = [
    "LiveTranscriberIcon-Light.png",
    "LiveTranscriberIcon-Dark.png",
    "LiveTranscriberIcon-Tinted.png"
]

private func loadSourceImage() throws -> CGImage {
    guard
        let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw NSError(
            domain: "LiveTranscriberIcon",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to read \(sourceURL.path)"]
        )
    }
    return image
}

private func resizedOpaquePNG(from sourceImage: CGImage) throws -> CGImage {
    let cropRect = CGRect(
        x: cropInset,
        y: cropInset,
        width: CGFloat(sourceImage.width) - cropInset * 2,
        height: CGFloat(sourceImage.height) - cropInset * 2
    )
    guard let croppedImage = sourceImage.cropping(to: cropRect) else {
        throw NSError(domain: "LiveTranscriberIcon", code: 2)
    }

    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw NSError(domain: "LiveTranscriberIcon", code: 3)
    }

    context.interpolationQuality = .high
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: size, height: size))

    guard let image = context.makeImage() else {
        throw NSError(domain: "LiveTranscriberIcon", code: 4)
    }
    return image
}

private func write(_ image: CGImage, filename: String) throws {
    let destinationURL = outputDirectory.appendingPathComponent(filename)
    guard let destination = CGImageDestinationCreateWithURL(
        destinationURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw NSError(domain: "LiveTranscriberIcon", code: 5)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "LiveTranscriberIcon", code: 6)
    }
    print("Wrote \(destinationURL.path)")
}

let sourceImage = try loadSourceImage()
let iconImage = try resizedOpaquePNG(from: sourceImage)
try outputFilenames.forEach { try write(iconImage, filename: $0) }
