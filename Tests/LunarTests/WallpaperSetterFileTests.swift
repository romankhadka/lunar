import XCTest
import CoreGraphics
@testable import Lunar

final class WallpaperSetterFileTests: XCTestCase {
    var tempDir: URL!
    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lunar-ws-\(UUID().uuidString)",
                                     isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir,
                                                withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func solid(_ w: Int, _ h: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h,
                            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    func testWritesDatedPNG() throws {
        let store = WallpaperFileStore(directory: tempDir)
        let date = DateComponents(calendar: Calendar(identifier: .gregorian),
                                   year: 2026, month: 4, day: 21).date!
        let url = try store.write(image: solid(64, 64), for: date)
        XCTAssertEqual(url.lastPathComponent, "2026-04-21.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testRetainsOnlyLastSevenDays() throws {
        let store = WallpaperFileStore(directory: tempDir)
        let cal = Calendar(identifier: .gregorian)
        for dayOffset in 0..<10 {
            let d = cal.date(byAdding: .day, value: dayOffset,
                             to: cal.date(from:
                                DateComponents(year: 2026, month: 1, day: 1))!)!
            _ = try store.write(image: solid(8, 8), for: d)
        }
        let remaining = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
            .filter { $0.hasSuffix(".png") }
        XCTAssertEqual(remaining.count, 7)
        XCTAssertTrue(remaining.contains("2026-01-10.png"))
        XCTAssertTrue(remaining.contains("2026-01-04.png"))
        XCTAssertFalse(remaining.contains("2026-01-03.png"))
    }

    func testURLForDateRoundTrips() {
        let store = WallpaperFileStore(directory: tempDir)
        let d = DateComponents(calendar: .init(identifier: .gregorian),
                                year: 2026, month: 4, day: 21).date!
        XCTAssertEqual(store.url(for: d).lastPathComponent, "2026-04-21.png")
    }
}
