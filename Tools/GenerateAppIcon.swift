#!/usr/bin/swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct IconRenderer {
    private let canvasSize = 1_024

    func render(to destination: URL) throws {
        let fileManager = FileManager.default
        let iconsetURL = fileManager.temporaryDirectory
            .appendingPathComponent("MenuMonitorAppIcon-\(UUID().uuidString).iconset", isDirectory: true)
        try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: iconsetURL) }

        let sizes: [(String, Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1_024)
        ]

        for (name, size) in sizes {
            guard let image = image(size: size) else {
                throw IconError.imageCreationFailed
            }
            try writePNG(image, to: iconsetURL.appendingPathComponent(name))
        }

        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", "-o", destination.path, iconsetURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw IconError.iconutilFailed
        }
    }

    private func image(size: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let scale = CGFloat(size) / CGFloat(canvasSize)
        context.scaleBy(x: scale, y: scale)
        draw(in: context)
        return context.makeImage()
    }

    private func draw(in context: CGContext) {
        let canvas = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
        // Keep the corners transparent. macOS supplies the final icon mask while
        // the neutral glass tile remains crisp on both light and dark desktops.
        context.clear(canvas)

        let outer = CGRect(x: 56, y: 56, width: 912, height: 912)
        let outerPath = CGPath(
            roundedRect: outer,
            cornerWidth: 224,
            cornerHeight: 224,
            transform: nil
        )
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -14),
            blur: 30,
            color: color(0.06, 0.09, 0.13, 0.24)
        )
        drawGradient(
            in: context,
            path: outerPath,
            colors: [
                color(0.97, 0.98, 0.99, 1),
                color(0.82, 0.87, 0.93, 1)
            ],
            start: CGPoint(x: 512, y: 990),
            end: CGPoint(x: 512, y: 44)
        )
        context.restoreGState()

        // A single dark monitor surface gives the mark a strong silhouette at 16px.
        let screen = CGRect(x: 176, y: 216, width: 672, height: 592)
        let screenPath = CGPath(
            roundedRect: screen,
            cornerWidth: 156,
            cornerHeight: 156,
            transform: nil
        )
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -8),
            blur: 18,
            color: color(0.04, 0.06, 0.09, 0.30)
        )
        drawGradient(
            in: context,
            path: screenPath,
            colors: [
                color(0.19, 0.23, 0.29, 1),
                color(0.08, 0.11, 0.15, 1)
            ],
            start: CGPoint(x: 512, y: 820),
            end: CGPoint(x: 512, y: 210)
        )
        context.restoreGState()

        context.saveGState()
        context.setShadow(
            offset: .zero,
            blur: 12,
            color: color(0.04, 0.52, 1.0, 0.28)
        )
        context.setStrokeColor(color(0.04, 0.52, 1.0, 1))
        context.setLineWidth(54)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.move(to: CGPoint(x: 254, y: 510))
        context.addLine(to: CGPoint(x: 352, y: 510))
        context.addLine(to: CGPoint(x: 414, y: 404))
        context.addLine(to: CGPoint(x: 502, y: 638))
        context.addLine(to: CGPoint(x: 590, y: 432))
        context.addLine(to: CGPoint(x: 654, y: 510))
        context.addLine(to: CGPoint(x: 770, y: 510))
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor(color(1, 1, 1, 0.13))
        context.setLineWidth(4)
        context.addPath(screenPath)
        context.strokePath()
        context.restoreGState()
    }

    private func drawGradient(
        in context: CGContext,
        path: CGPath,
        colors: [CGColor],
        start: CGPoint,
        end: CGPoint
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: [0, 1]
        ) else {
            return
        }
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
        context.restoreGState()
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw IconError.pngDestinationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw IconError.pngWriteFailed
        }
    }

    private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat) -> CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

enum IconError: Error {
    case imageCreationFailed
    case pngDestinationFailed
    case pngWriteFailed
    case iconutilFailed
}

let arguments = CommandLine.arguments.dropFirst()
let outputPath = arguments.first ?? "Resources/AppIcon.icns"
try IconRenderer().render(to: URL(fileURLWithPath: outputPath))
