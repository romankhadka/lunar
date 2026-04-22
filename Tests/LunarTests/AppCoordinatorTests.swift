import XCTest
import CoreGraphics
@testable import Lunar

final class AppCoordinatorTests: XCTestCase {

    final class FakeImages: ImageProviding {
        var calls = 0
        func baseImage(for phase: PhaseName) throws -> CGImage {
            calls += 1
            let cs = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(data: nil, width: 8, height: 8,
                                bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            return ctx.makeImage()!
        }
    }

    final class FakeCompositor: Compositing {
        var calls = 0
        func composite(base: CGImage, phase: MoonPhase, canvasSize: CGSize) -> CGImage {
            calls += 1
            return base
        }
    }

    final class FakeSetter: WallpaperApplying {
        var applied: [Date] = []
        var reapplied = 0
        func apply(image: CGImage, for date: Date) throws { applied.append(date) }
        func reapplyToday() throws { reapplied += 1 }
    }

    @MainActor
    private func makeCoordinator(
        images: FakeImages = FakeImages(),
        compositor: FakeCompositor = FakeCompositor(),
        setter: FakeSetter = FakeSetter(),
        defaults: UserDefaults? = nil
    ) -> AppCoordinator {
        let defaults = defaults ?? UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return AppCoordinator(
            images: images, compositor: compositor, setter: setter,
            canvasSizeProvider: { CGSize(width: 1920, height: 1080) },
            defaults: defaults,
            clock: { Date(timeIntervalSince1970: 1_745_000_000) }
        )
    }

    @MainActor
    func testFirstCallTriggersFullPipeline() throws {
        let images = FakeImages()
        let comp = FakeCompositor()
        let setter = FakeSetter()
        let c = makeCoordinator(images: images, compositor: comp, setter: setter)
        try c.updateWallpaper()
        XCTAssertEqual(images.calls, 1)
        XCTAssertEqual(comp.calls, 1)
        XCTAssertEqual(setter.applied.count, 1)
    }

    @MainActor
    func testIdempotentSecondCallSkips() throws {
        let images = FakeImages()
        let comp = FakeCompositor()
        let setter = FakeSetter()
        let c = makeCoordinator(images: images, compositor: comp, setter: setter)
        try c.updateWallpaper()
        try c.updateWallpaper()
        XCTAssertEqual(images.calls, 1, "ImageProvider should not be hit twice")
        XCTAssertEqual(comp.calls, 1)
        XCTAssertEqual(setter.applied.count, 1)
    }

    @MainActor
    func testForceBypassesIdempotency() throws {
        let images = FakeImages()
        let comp = FakeCompositor()
        let setter = FakeSetter()
        let c = makeCoordinator(images: images, compositor: comp, setter: setter)
        try c.updateWallpaper()
        try c.updateWallpaper(force: true)
        XCTAssertEqual(images.calls, 2)
        XCTAssertEqual(setter.applied.count, 2)
    }

    @MainActor
    func testImageProviderErrorIsSwallowedAndLogged() {
        final class Throwing: ImageProviding {
            func baseImage(for phase: PhaseName) throws -> CGImage {
                throw ImageProvider.Error.bundledImageMissing(phase)
            }
        }
        let setter = FakeSetter()
        let c = AppCoordinator(
            images: Throwing(), compositor: FakeCompositor(), setter: setter,
            canvasSizeProvider: { CGSize(width: 100, height: 100) },
            defaults: UserDefaults(suiteName: "t-\(UUID().uuidString)")!,
            clock: { Date() })
        XCTAssertNoThrow(try c.updateWallpaper())
        XCTAssertEqual(setter.applied.count, 0)
    }

    @MainActor
    func testReapplyForwardsToSetter() throws {
        let setter = FakeSetter()
        let c = makeCoordinator(setter: setter)
        try c.reapplyToday()
        XCTAssertEqual(setter.reapplied, 1)
    }
}
