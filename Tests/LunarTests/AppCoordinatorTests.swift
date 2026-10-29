import XCTest
import CoreGraphics
@testable import Lunar

final class AppCoordinatorTests: XCTestCase {

    /// Per-test log folder, so tests never write to ~/Library/Logs/Lunar.
    private var logDir: URL!

    override func setUpWithError() throws {
        logDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lunar-coord-log-\(UUID().uuidString)",
                                    isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: logDir)
    }

    private func logContents() -> String {
        (try? String(contentsOf: logDir.appendingPathComponent("lunar.log"),
                     encoding: .utf8)) ?? ""
    }

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
        var reapplied: [Bool] = []   // onlyStale flag of each call
        var todayFileExists = false   // default: no file yet
        func apply(image: CGImage, for date: Date) throws {
            applied.append(date)
            todayFileExists = true   // apply "creates" the file
        }
        func reapplyToday(onlyStale: Bool) throws { reapplied.append(onlyStale) }
        func fileExists(for date: Date) -> Bool { todayFileExists }
    }

    @MainActor
    private func makeCoordinator(
        images: FakeImages = FakeImages(),
        compositor: FakeCompositor = FakeCompositor(),
        setter: FakeSetter = FakeSetter(),
        defaults: UserDefaults? = nil,
        canvas: @escaping () -> CGSize = { CGSize(width: 1920, height: 1080) }
    ) -> AppCoordinator {
        let defaults = defaults ?? UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return AppCoordinator(
            images: images, compositor: compositor, setter: setter,
            canvasSizeProvider: canvas,
            defaults: defaults,
            fileLog: FileLog(directory: logDir),
            clock: { Date(timeIntervalSince1970: 1_745_000_000) }
        )
    }

    @MainActor
    func testFirstCallTriggersFullPipeline() {
        let images = FakeImages()
        let comp = FakeCompositor()
        let setter = FakeSetter()
        let c = makeCoordinator(images: images, compositor: comp, setter: setter)
        c.updateWallpaper()
        XCTAssertEqual(images.calls, 1)
        XCTAssertEqual(comp.calls, 1)
        XCTAssertEqual(setter.applied.count, 1)
        XCTAssertTrue(logContents().contains("Applied"), "Success goes to the injected log")
    }

    @MainActor
    func testIdempotentSecondCallSkips() {
        let images = FakeImages()
        let comp = FakeCompositor()
        let setter = FakeSetter()
        let c = makeCoordinator(images: images, compositor: comp, setter: setter)
        c.updateWallpaper()
        c.updateWallpaper()
        XCTAssertEqual(images.calls, 1, "ImageProvider should not be hit twice")
        XCTAssertEqual(comp.calls, 1)
        XCTAssertEqual(setter.applied.count, 1)
    }

    @MainActor
    func testForceBypassesIdempotency() {
        let images = FakeImages()
        let comp = FakeCompositor()
        let setter = FakeSetter()
        let c = makeCoordinator(images: images, compositor: comp, setter: setter)
        c.updateWallpaper()
        c.updateWallpaper(force: true)
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
            fileLog: FileLog(directory: logDir),
            clock: { Date() })
        XCTAssertFalse(c.updateWallpaper())
        XCTAssertEqual(setter.applied.count, 0)
        XCTAssertTrue(logContents().contains("ERROR:"), "Error goes to the injected log")
    }

    @MainActor
    func testReapplyForwardsToSetter() {
        let setter = FakeSetter()
        let c = makeCoordinator(setter: setter)
        c.reapplyToday()
        c.reapplyToday(onlyStale: true)
        XCTAssertEqual(setter.reapplied, [false, true])
    }

    @MainActor
    func testUpdateReportsWhetherItApplied() {
        let c = makeCoordinator()
        XCTAssertTrue(c.updateWallpaper())
        XCTAssertFalse(c.updateWallpaper())
        XCTAssertTrue(c.updateWallpaper(force: true))
    }

    @MainActor
    func testScreenChangeWithSameCanvasReappliesWithoutRendering() {
        let images = FakeImages()
        let comp = FakeCompositor()
        let setter = FakeSetter()
        let c = makeCoordinator(images: images, compositor: comp, setter: setter)
        c.updateWallpaper()
        c.handleScreenChange()
        c.handleScreenChange()
        XCTAssertEqual(comp.calls, 1, "Same canvas must not render again")
        XCTAssertEqual(setter.applied.count, 1)
        XCTAssertEqual(setter.reapplied, [false, false],
                       "Existing file is pushed to every screen")
    }

    @MainActor
    func testScreenChangeWithNewCanvasRendersAgain() {
        var size = CGSize(width: 1920, height: 1080)
        let comp = FakeCompositor()
        let setter = FakeSetter()
        let c = makeCoordinator(compositor: comp, setter: setter, canvas: { size })
        c.updateWallpaper()
        size = CGSize(width: 5120, height: 2880)
        c.handleScreenChange()
        XCTAssertEqual(comp.calls, 2)
        XCTAssertEqual(setter.applied.count, 2)
        XCTAssertTrue(setter.reapplied.isEmpty, "A fresh apply already covers every screen")
    }

    @MainActor
    func testPublishesCurrentAndNextPhase() throws {
        let c = makeCoordinator()
        c.updateWallpaper()
        let current = try XCTUnwrap(c.currentPhase)
        let next = try XCTUnwrap(c.nextPhase)
        XCTAssertNotEqual(next.name, current.phaseName)
        XCTAssertGreaterThan(next.date, current.date)
    }
}
