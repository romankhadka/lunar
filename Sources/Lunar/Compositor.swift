import Foundation
import CoreGraphics
import CoreText
import AppKit

protocol Compositing {
    func composite(base: CGImage, phase: MoonPhase, canvasSize: CGSize) -> CGImage
}

struct Compositor: Compositing {

    func composite(base: CGImage,
                   phase: MoonPhase,
                   canvasSize: CGSize) -> CGImage {
        let w = Int(canvasSize.width)
        let h = Int(canvasSize.height)
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        let bw = CGFloat(base.width)
        let bh = CGFloat(base.height)
        let scale = min(CGFloat(w) / bw, CGFloat(h) / bh)
        let drawW = bw * scale
        let drawH = bh * scale
        let drawX = (CGFloat(w) - drawW) / 2
        let drawY = (CGFloat(h) - drawH) / 2
        ctx.draw(base, in: CGRect(x: drawX, y: drawY,
                                   width: drawW, height: drawH))

        drawOverlay(in: ctx, canvasSize: canvasSize, phase: phase)

        return ctx.makeImage()!
    }

    private func drawOverlay(in ctx: CGContext,
                              canvasSize: CGSize,
                              phase: MoonPhase) {
        let pct = Int((phase.illumination * 100).rounded())
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "MMM d"
        let text = "\(phase.phaseName.displayName) · \(pct)% · \(df.string(from: phase.date))"

        let fontSize = canvasSize.height * 0.015
        let font = NSFont.systemFont(ofSize: fontSize, weight: .light)
        let textColor = NSColor(calibratedWhite: 232.0/255.0, alpha: 0.7).cgColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .kern: 0.5
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attr)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        let margin = canvasSize.width * 0.0125
        let x = canvasSize.width - bounds.width - margin
        let y = margin

        ctx.saveGState()
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
