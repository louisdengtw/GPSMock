#!/usr/bin/env swift

// Renders a 1024×1024 PNG for the GPSMock app icon.
// Design: macOS-style rounded square (squircle) with a green→teal gradient,
// a white map pin centered, and a small iPhone silhouette below the pin head.

import AppKit
import CoreGraphics
import Foundation

let size: CGFloat = 1024
let bitsPerComponent = 8
let bytesPerRow = Int(size) * 4

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
    fputs("colorspace failed\n", stderr); exit(1)
}
guard let ctx = CGContext(
    data: nil,
    width: Int(size), height: Int(size),
    bitsPerComponent: bitsPerComponent,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("context failed\n", stderr); exit(1)
}

ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

// ── 1. Squircle background with vertical gradient (teal → green)
let inset: CGFloat = 0
let bgRect = CGRect(x: inset, y: inset, width: size - 2*inset, height: size - 2*inset)
// macOS uses ~22% corner radius for app icons (≈ 225 / 1024).
let radius: CGFloat = size * 0.2237

let bgPath = CGPath(roundedRect: bgRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(bgPath)
ctx.clip()

let topColor = CGColor(red: 0.21, green: 0.78, blue: 0.62, alpha: 1.0)   // teal-green
let botColor = CGColor(red: 0.08, green: 0.49, blue: 0.43, alpha: 1.0)   // deeper teal
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [topColor, botColor] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: size/2, y: size),
    end: CGPoint(x: size/2, y: 0),
    options: []
)

// Subtle inner highlight on top
ctx.saveGState()
let highlightColors = [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
] as CFArray
let highlight = CGGradient(colorsSpace: colorSpace, colors: highlightColors, locations: [0.0, 0.55])!
ctx.drawLinearGradient(
    highlight,
    start: CGPoint(x: size/2, y: size),
    end: CGPoint(x: size/2, y: size * 0.4),
    options: []
)
ctx.restoreGState()

// ── 2. Map pin (teardrop) — drawn in white with a soft drop shadow
ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -size * 0.012),
    blur: size * 0.04,
    color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.30)
)

// Pin geometry: head circle + tail triangle merged smoothly.
let pinHeadRadius: CGFloat = size * 0.20
let pinHeadCenter = CGPoint(x: size / 2, y: size * 0.585)
let pinTipY: CGFloat = size * 0.18

let pinPath = CGMutablePath()
// Start at the tip, sweep up the right side to the head.
pinPath.move(to: CGPoint(x: size / 2, y: pinTipY))
// Tangent angle for a smooth teardrop: line from tip to point on circle.
let theta: CGFloat = .pi / 6 // 30°
let rightTangent = CGPoint(
    x: pinHeadCenter.x + pinHeadRadius * sin(theta),
    y: pinHeadCenter.y - pinHeadRadius * cos(theta)
)
let leftTangent = CGPoint(
    x: pinHeadCenter.x - pinHeadRadius * sin(theta),
    y: pinHeadCenter.y - pinHeadRadius * cos(theta)
)
pinPath.addLine(to: rightTangent)
// Sweep around the top of the head.
pinPath.addArc(
    center: pinHeadCenter,
    radius: pinHeadRadius,
    startAngle: -(.pi/2 - theta),
    endAngle: .pi + (.pi/2 - theta),
    clockwise: false
)
pinPath.addLine(to: CGPoint(x: size / 2, y: pinTipY))
pinPath.closeSubpath()

ctx.addPath(pinPath)
ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
ctx.fillPath()
ctx.restoreGState()

// ── 3. Inner hole on the pin head (the classic donut)
let holeRadius: CGFloat = size * 0.075
ctx.addEllipse(in: CGRect(
    x: pinHeadCenter.x - holeRadius,
    y: pinHeadCenter.y - holeRadius,
    width: holeRadius * 2,
    height: holeRadius * 2
))
// Use the gradient color (transparent hole would show shadow; we want the bg color through).
ctx.setBlendMode(.destinationOut)
ctx.fillPath()
ctx.setBlendMode(.normal)

// Re-paint the gradient through the hole so the background shows.
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
ctx.addEllipse(in: CGRect(
    x: pinHeadCenter.x - holeRadius,
    y: pinHeadCenter.y - holeRadius,
    width: holeRadius * 2,
    height: holeRadius * 2
))
ctx.clip()
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: size/2, y: size),
    end: CGPoint(x: size/2, y: 0),
    options: []
)
ctx.restoreGState()

// ── 4. Bottom shadow ellipse beneath pin tip (fake ground)
ctx.saveGState()
let shadowRect = CGRect(
    x: size * 0.34,
    y: size * 0.115,
    width: size * 0.32,
    height: size * 0.04
)
ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 0.18)
ctx.fillEllipse(in: shadowRect)
ctx.restoreGState()

// ── Output PNG
guard let cgImage = ctx.makeImage() else {
    fputs("makeImage failed\n", stderr); exit(1)
}
let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
guard let tiff = nsImage.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("PNG encode failed\n", stderr); exit(1)
}

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon_1024.png"
let url = URL(fileURLWithPath: outPath)
do {
    try png.write(to: url)
    print("wrote \(outPath) (\(png.count) bytes)")
} catch {
    fputs("write failed: \(error)\n", stderr); exit(1)
}
