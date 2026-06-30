#!/usr/bin/env swift
// Generates the Nimbus macOS app icon set from the design's brand mark:
// a purple gradient squircle (#9A7CFF → #6F4FE0) with a glowing white orb.
//
//   swift scripts/make-icon.swift [outputDir]
//
// Writes icon_<px>.png + Contents.json into the AppIcon.appiconset.
import AppKit

func color(_ hex: UInt, _ a: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a).cgColor
}

func renderIcon(px: Int) -> Data {
    let size = CGFloat(px)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

    // macOS icon grid: rounded square inset with a transparent margin.
    let margin = size * 0.094
    let rect = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
    let radius = rect.width * 0.2237
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                  blur: size * 0.045, color: color(0x000000, 0.45))
    ctx.addPath(path); ctx.setFillColor(color(0x6F4FE0)); ctx.fillPath()
    ctx.restoreGState()

    // Purple diagonal gradient.
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let grad = CGGradient(colorsSpace: cs, colors: [color(0x9A7CFF), color(0x6F4FE0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    // Soft top highlight.
    let hl = CGGradient(colorsSpace: cs, colors: [color(0xFFFFFF, 0.30), color(0xFFFFFF, 0)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(hl, start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.midY), options: [])
    ctx.restoreGState()

    // Glowing white orb.
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let dotR = rect.width * 0.155
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let glow = CGGradient(colorsSpace: cs, colors: [color(0xFFFFFF, 0.55), color(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: dotR * 2.7, options: [])
    ctx.restoreGState()
    ctx.setFillColor(color(0xFFFFFF, 0.95))
    ctx.fillEllipse(in: CGRect(x: center.x - dotR, y: center.y - dotR, width: dotR * 2, height: dotR * 2))

    let cg = ctx.makeImage()!
    return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
}

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "App/Nimbus/Resources/Assets.xcassets/AppIcon.appiconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let pixels = [16, 32, 64, 128, 256, 512, 1024]
for px in pixels {
    let url = URL(fileURLWithPath: "\(outDir)/icon_\(px).png")
    try! renderIcon(px: px).write(to: url)
    print("→ icon_\(px).png")
}

// Asset-catalog manifest.
struct Entry { let size: String; let scale: String; let px: Int }
let entries = [
    Entry(size: "16x16", scale: "1x", px: 16), Entry(size: "16x16", scale: "2x", px: 32),
    Entry(size: "32x32", scale: "1x", px: 32), Entry(size: "32x32", scale: "2x", px: 64),
    Entry(size: "128x128", scale: "1x", px: 128), Entry(size: "128x128", scale: "2x", px: 256),
    Entry(size: "256x256", scale: "1x", px: 256), Entry(size: "256x256", scale: "2x", px: 512),
    Entry(size: "512x512", scale: "1x", px: 512), Entry(size: "512x512", scale: "2x", px: 1024),
]
let images = entries.map {
    "    { \"idiom\" : \"mac\", \"size\" : \"\($0.size)\", \"scale\" : \"\($0.scale)\", \"filename\" : \"icon_\($0.px).png\" }"
}.joined(separator: ",\n")
let contents = "{\n  \"images\" : [\n\(images)\n  ],\n  \"info\" : { \"version\" : 1, \"author\" : \"nimbus\" }\n}\n"
try! contents.write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)
print("→ Contents.json")
