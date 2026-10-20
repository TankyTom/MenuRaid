#!/usr/bin/env swift
// Regenerates MenuRaid's app icon set. Run from the repository root:
//
//   swiftc -O scripts/make-icon.swift -o /tmp/make-icon && /tmp/make-icon
//
// With no argument it writes into MenuRaid/Assets.xcassets/AppIcon.appiconset. Pass a folder to write elsewhere.
// The artwork is drawn from scratch with Core Graphics. It deliberately uses no SF Symbols: Apple's licence
// doesn't allow them in app icons.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Original MenuRaid icon: a stack of three server slabs with status LEDs on a blue squircle.
// Drawn from scratch with Core Graphics (no SF Symbols). Everything is specified on a 1024 grid and scaled.

func render(pixels: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let k = CGFloat(pixels) / 1024
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }

    // Icon body: 824 x 824 inset 100, as macOS app icons are laid out.
    let body = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185 * k, cornerHeight: 185 * k, transform: nil)

    // Soft drop shadow under the whole icon.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * k), blur: 26 * k, color: rgb(0, 0, 0, 0.28))
    ctx.addPath(bodyPath); ctx.setFillColor(rgb(0.15, 0.45, 0.92)); ctx.fillPath()
    ctx.restoreGState()

    // Blue gradient, light at the top.
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    let gradient = CGGradient(colorsSpace: space,
                              colors: [rgb(0.37, 0.66, 1.0), rgb(0.10, 0.37, 0.86)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512 * k, y: 924 * k), end: CGPoint(x: 512 * k, y: 100 * k), options: [])
    ctx.restoreGState()

    // Thin light edge along the top, like the system icons.
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    let edge = CGGradient(colorsSpace: space, colors: [rgb(1, 1, 1, 0.45), rgb(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
    ctx.setLineWidth(5 * k)
    ctx.addPath(bodyPath); ctx.replacePathWithStrokedPath(); ctx.clip()
    ctx.drawLinearGradient(edge, start: CGPoint(x: 512 * k, y: 924 * k), end: CGPoint(x: 512 * k, y: 760 * k), options: [])
    ctx.restoreGState()

    // Three server slabs.
    let slabW: CGFloat = 470, slabH: CGFloat = 122, gap: CGFloat = 34
    let total = 3 * slabH + 2 * gap
    let top = 512 + total / 2
    let leds: [CGColor] = [rgb(0.20, 0.78, 0.35), rgb(0.20, 0.78, 0.35), rgb(1.0, 0.69, 0.13)]   // green, green, amber
    for i in 0..<3 {
        let y = top - CGFloat(i + 1) * slabH - CGFloat(i) * gap
        let slab = CGRect(x: (512 - slabW / 2) * k, y: y * k, width: slabW * k, height: slabH * k)
        let path = CGPath(roundedRect: slab, cornerWidth: 38 * k, cornerHeight: 38 * k, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -7 * k), blur: 14 * k, color: rgb(0, 0.1, 0.4, 0.30))
        ctx.addPath(path); ctx.setFillColor(rgb(1, 1, 1)); ctx.fillPath()
        ctx.restoreGState()

        // Two short vent slits on the left.
        ctx.setFillColor(rgb(0.80, 0.86, 0.96))
        for n in 0..<2 {
            let slit = CGRect(x: (512 - slabW / 2 + 52) * k, y: (y + slabH / 2 + (n == 0 ? 12 : -22)) * k, width: 120 * k, height: 10 * k)
            ctx.addPath(CGPath(roundedRect: slit, cornerWidth: 5 * k, cornerHeight: 5 * k, transform: nil)); ctx.fillPath()
        }

        // Status LED on the right.
        let ledR: CGFloat = 21
        let cx = 512 + slabW / 2 - 62, cy = y + slabH / 2
        ctx.setFillColor(leds[i])
        ctx.fillEllipse(in: CGRect(x: (cx - ledR) * k, y: (cy - ledR) * k, width: 2 * ledR * k, height: 2 * ledR * k))
    }
    return ctx.makeImage()!
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("couldn't write \(path)") }
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "MenuRaid/Assets.xcassets/AppIcon.appiconset"
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32), ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256), ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in sizes { write(render(pixels: px), to: "\(out)/\(name)") }
print("wrote \(sizes.count) icons to \(out)")
