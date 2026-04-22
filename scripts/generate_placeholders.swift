#!/usr/bin/env swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outDir = URL(fileURLWithPath: "Sources/Lunar/Resources/phases", isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

struct PhaseDesc { let name: String; let illum: Double; let waxing: Bool }
let phases: [PhaseDesc] = [
    .init(name: "new",              illum: 0.00, waxing: true),
    .init(name: "waxing_crescent",  illum: 0.25, waxing: true),
    .init(name: "first_quarter",    illum: 0.50, waxing: true),
    .init(name: "waxing_gibbous",   illum: 0.75, waxing: true),
    .init(name: "full",             illum: 1.00, waxing: true),
    .init(name: "waning_gibbous",   illum: 0.75, waxing: false),
    .init(name: "last_quarter",     illum: 0.50, waxing: false),
    .init(name: "waning_crescent",  illum: 0.25, waxing: false),
]

let size = 4096
for p in phases {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: size, height: size,
                        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

    let radius = CGFloat(size) * 0.36
    let center = CGPoint(x: CGFloat(size)/2, y: CGFloat(size)/2)
    let disc = CGRect(x: center.x - radius, y: center.y - radius,
                      width: radius * 2, height: radius * 2)

    // Full bright moon
    ctx.setFillColor(red: 0.92, green: 0.92, blue: 0.88, alpha: 1)
    ctx.fillEllipse(in: disc)

    // Shadow by drawing a dark disc offset horizontally.
    // illum 1.0 → no shadow. illum 0.5 → shadow covers half.
    if p.illum < 1.0 {
        let offsetFrac = 1.0 - 2.0 * p.illum    // -1 .. +1
        let offset = (p.waxing ? -1 : 1) * offsetFrac * radius
        ctx.setFillColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)
        ctx.addEllipse(in: CGRect(x: center.x + CGFloat(offset) - radius,
                                   y: center.y - radius,
                                   width: radius * 2, height: radius * 2))
        ctx.fillPath()
    }

    let img = ctx.makeImage()!
    let url = outDir.appendingPathComponent("\(p.name).png")
    let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    _ = CGImageDestinationFinalize(dest)
    print("wrote \(url.path)")
}
