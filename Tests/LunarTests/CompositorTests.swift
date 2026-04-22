import XCTest
import CoreGraphics
@testable import Lunar

final class CompositorTests: XCTestCase {

    private func solidBaseImage(_ size: Int, gray: CGFloat = 0.5) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: size, height: size,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: gray, green: gray, blue: gray, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()!
    }

    private func samplePixel(_ img: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        var data = [UInt8](repeating: 0, count: 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: &data, width: 1, height: 1,
                            bitsPerComponent: 8, bytesPerRow: 4,
                            space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: -x, y: -(img.height - 1 - y),
                                  width: img.width, height: img.height))
        return (data[0], data[1], data[2])
    }

    private let phase = MoonPhase(
        date: Date(timeIntervalSince1970: 1_745_000_000),
        age: 14.77, illumination: 1.0, phaseName: .full)

    func testOutputDimensionsMatchCanvas() {
        let out = Compositor().composite(
            base: solidBaseImage(256),
            phase: phase,
            canvasSize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(out.width, 1920)
        XCTAssertEqual(out.height, 1080)
    }

    func testPillarboxColumnsAreBlackOnLandscape() {
        let out = Compositor().composite(
            base: solidBaseImage(256, gray: 0.5),
            phase: phase,
            canvasSize: CGSize(width: 1920, height: 1080))
        let left = samplePixel(out, x: 10, y: 540)
        let right = samplePixel(out, x: 1910, y: 540)
        XCTAssertEqual(left.0, 0);  XCTAssertEqual(left.1, 0);  XCTAssertEqual(left.2, 0)
        XCTAssertEqual(right.0, 0); XCTAssertEqual(right.1, 0); XCTAssertEqual(right.2, 0)
    }

    func testCenterPixelIsFromBase() {
        let out = Compositor().composite(
            base: solidBaseImage(256, gray: 0.5),
            phase: phase,
            canvasSize: CGSize(width: 1920, height: 1080))
        let cx = 1920 / 2
        let cy = 1080 / 2
        let p = samplePixel(out, x: cx, y: cy)
        XCTAssertGreaterThan(p.0, 96)
        XCTAssertLessThan(p.0, 160)
    }

    func testOverlayAreaIsNotBlackWhenRendering() {
        // Bottom-right corner should contain some non-black pixels (the text).
        let out = Compositor().composite(
            base: solidBaseImage(256, gray: 0.0),
            phase: phase,
            canvasSize: CGSize(width: 1920, height: 1080))
        // Compositor draws the overlay text at CG-y ≈ margin..margin+fontAscent
        // (margin = 1.25% of width = 24; font = 1.5% of height ≈ 16pt).
        // In top-down coordinates that's roughly rows 1020..1070.
        // Sample a 300×60 region in the bottom-right that covers the text.
        var sawNonBlack = false
        for y in 1015..<1075 {
            for x in (1920 - 320)..<(1920 - 10) {
                let p = samplePixel(out, x: x, y: y)
                if p.0 > 20 { sawNonBlack = true; break }
            }
            if sawNonBlack { break }
        }
        XCTAssertTrue(sawNonBlack, "Expected overlay text in bottom-right region (CG-y ≈ 5..65)")
    }

    func testSquareCanvasStillRenders() {
        let out = Compositor().composite(
            base: solidBaseImage(256),
            phase: phase,
            canvasSize: CGSize(width: 2880, height: 2880))
        XCTAssertEqual(out.width, 2880)
        XCTAssertEqual(out.height, 2880)
    }
}
