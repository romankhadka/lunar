import XCTest
@testable import Lunar

final class PhaseCalculatorTests: XCTestCase {

    // MARK: Julian Day conversion

    private func utcDate(_ year: Int, _ month: Int, _ day: Int,
                         _ hour: Int = 12) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = 0; c.second = 0
        c.timeZone = TimeZone(identifier: "UTC")!
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func testJulianDayKnownValues() {
        // Meeus, Astronomical Algorithms 2nd ed., p.62:
        // 1957 Oct 4.81 UTC → JD 2436116.31
        let d1 = Date(timeIntervalSince1970: -386845200 + 7 * 3600 / 10 * 10)
        _ = d1 // unused; use explicit UTC construction instead
        let d = utcDate(1957, 10, 4, 12)  // noon UTC; adjust below
        let jdNoon = PhaseCalculator.julianDay(for: d)
        // Noon UTC on 1957-10-04 → JD 2436116.00
        XCTAssertEqual(jdNoon, 2436116.00, accuracy: 0.01)

        // 2000-01-01 12:00 UTC → JD 2451545.0 (J2000.0 epoch)
        let j2000 = utcDate(2000, 1, 1, 12)
        XCTAssertEqual(PhaseCalculator.julianDay(for: j2000),
                       2451545.0, accuracy: 0.001)
    }
}
