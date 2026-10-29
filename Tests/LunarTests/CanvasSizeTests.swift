import XCTest
@testable import Lunar

final class CanvasSizeTests: XCTestCase {
    @MainActor
    func testPicksScreenWithMostPixels() {
        // 1x 2560×1440 external display vs 2x 1512×982 laptop panel.
        let external = CGSize(width: 2560, height: 1440)   // 3.69 MP
        let laptop = CGSize(width: 3024, height: 1964)     // 5.94 MP
        XCTAssertEqual(AppDelegate.canvasSize(forScreenPixelSizes: [external, laptop]), laptop)
    }

    @MainActor
    func testFallsBackWithoutScreens() {
        XCTAssertEqual(AppDelegate.canvasSize(forScreenPixelSizes: []),
                       CGSize(width: 5120, height: 2880))
    }
}
