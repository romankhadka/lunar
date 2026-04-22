import XCTest
@testable import Lunar

final class PhaseNameTests: XCTestCase {
    func testRawValuesMatchSnakeCaseFilenames() {
        XCTAssertEqual(PhaseName.new.rawValue,             "new")
        XCTAssertEqual(PhaseName.waxingCrescent.rawValue,  "waxing_crescent")
        XCTAssertEqual(PhaseName.firstQuarter.rawValue,    "first_quarter")
        XCTAssertEqual(PhaseName.waxingGibbous.rawValue,   "waxing_gibbous")
        XCTAssertEqual(PhaseName.full.rawValue,            "full")
        XCTAssertEqual(PhaseName.waningGibbous.rawValue,   "waning_gibbous")
        XCTAssertEqual(PhaseName.lastQuarter.rawValue,     "last_quarter")
        XCTAssertEqual(PhaseName.waningCrescent.rawValue,  "waning_crescent")
    }

    func testCaseIterableCount() {
        XCTAssertEqual(PhaseName.allCases.count, 8)
    }

    func testDisplayNameIsHumanReadable() {
        XCTAssertEqual(PhaseName.waxingCrescent.displayName, "Waxing Crescent")
        XCTAssertEqual(PhaseName.full.displayName, "Full Moon")
        XCTAssertEqual(PhaseName.new.displayName, "New Moon")
        XCTAssertEqual(PhaseName.lastQuarter.displayName, "Last Quarter")
    }
}
