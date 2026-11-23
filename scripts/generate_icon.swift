#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Usage:
//   generate_icon.swift <output_icns_path> [source_png_path]
guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate_icon.swift <output_icns_path> [source_png_path]\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let sourceImage: NSImage? = {
    guard CommandLine.arguments.count >= 3 else { return nil }
    let srcURL = URL(fileURLWithPath: CommandLine.arguments[2])
    return NSImage(contentsOf: srcURL)
}()

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

/// Creates a continuous-looking macOS app icon squircle path inside `rect`.
func macOSSquirclePath(in rect: NSRect) -> NSBezierPath {
    let radius = rect.width * 0.2237
    return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func renderPNG(pixels: Int) -> Data? {
    let s = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)
    ctx?.imageInterpolation = .high
    NSGraphicsContext.current = ctx

    // Standard macOS Big Sur+ icon grid: ~82.4% squircle centered with subtle bottom drop shadow
    let inset = s * 0.088
    let iconRect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = macOSSquirclePath(in: iconRect)

    // Subtle macOS drop shadow
    if pixels >= 32 {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.018)
        shadow.shadowBlurRadius = s * 0.032
        shadow.set()
        NSColor(calibratedRed: 0.10, green: 0.28, blue: 0.82, alpha: 1.0).setFill()
        squircle.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    // Clip to squircle and draw artwork
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()

    if let sourceImage {
        // Aspect-fill source artwork into the squircle
        let imgSize = sourceImage.size
        let scaleX = iconRect.width / max(1, imgSize.width)
        let scaleY = iconRect.height / max(1, imgSize.height)
        let scale = max(scaleX, scaleY)
        let drawW = imgSize.width * scale
        let drawH = imgSize.height * scale
        let drawRect = NSRect(
            x: iconRect.midX - drawW / 2,
            y: iconRect.midY - drawH / 2,
            width: drawW,
            height: drawH
        )
        sourceImage.draw(
            in: drawRect,
            from: NSRect(origin: .zero, size: imgSize),
            operation: .sourceOver,
            fraction: 1.0
        )
    } else {
        // Fallback vector icon if no source image provided
        let gradient = NSGradient(
            starting: NSColor(calibratedRed: 0.16, green: 0.45, blue: 0.98, alpha: 1.0),
            ending: NSColor(calibratedRed: 0.08, green: 0.24, blue: 0.78, alpha: 1.0)
        )
        gradient?.draw(in: squircle, angle: -90)
    }

    NSGraphicsContext.restoreGraphicsState()

    // Crisp subtle glass rim highlight around the squircle edge
    NSColor.white.withAlphaComponent(0.22).setStroke()
    squircle.lineWidth = max(0.8, s * 0.012)
    squircle.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

func appendUInt32BE(_ value: UInt32, to data: inout Data) {
    var be = value.bigEndian
    withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
}

let entries: [(String, Int)] = [
    ("icp4", 16),   // 16x16
    ("icp5", 32),   // 32x32
    ("icp6", 64),   // 64x64
    ("ic07", 128),  // 128x128
    ("ic08", 256),  // 256x256
    ("ic09", 512),  // 512x512
    ("ic10", 1024), // 512x512@2x
    ("ic11", 32),   // 16x16@2x
    ("ic12", 64),   // 32x32@2x
    ("ic13", 256),  // 128x128@2x
    ("ic14", 512)   // 256x256@2x
]

var pngCache: [Int: Data] = [:]
var body = Data()

for (chunkType, px) in entries {
    let png: Data
    if let cached = pngCache[px] {
        png = cached
    } else if let rendered = renderPNG(pixels: px) {
        pngCache[px] = rendered
        png = rendered
    } else {
        continue
    }

    body.append(contentsOf: chunkType.utf8)
    appendUInt32BE(UInt32(8 + png.count), to: &body)
    body.append(png)
}

var icns = Data()
icns.append(contentsOf: "icns".utf8)
appendUInt32BE(UInt32(8 + body.count), to: &icns)
icns.append(body)

try icns.write(to: outputURL)
