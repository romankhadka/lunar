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

    // MARK: Synodic age

    func testSynodicAgeAtKnownNewMoon() {
        // 2024-01-11 11:57 UTC — documented new moon (NASA GSFC eclipse catalog)
        let d = utcDate(2024, 1, 11, 12)
        let age = PhaseCalculator.synodicAge(for: d)
        // At noon UTC on 2024-01-11, we're ~0.0 days past new moon (±0.05).
        XCTAssertLessThan(age, 0.2)
    }

    func testSynodicAgeAtKnownFullMoon() {
        // 2024-01-25 17:54 UTC — documented full moon
        let d = utcDate(2024, 1, 25, 18)
        let age = PhaseCalculator.synodicAge(for: d)
        // Full moon is age ≈ 14.77 days.
        XCTAssertEqual(age, 14.77, accuracy: 0.3)
    }

    func testSynodicAgeWrapsWithinRange() {
        let d = utcDate(2026, 6, 15, 12)
        let age = PhaseCalculator.synodicAge(for: d)
        XCTAssertGreaterThanOrEqual(age, 0)
        XCTAssertLessThan(age, 29.530588853)
    }

    // MARK: Illumination

    func testIlluminationNewMoon() {
        let d = utcDate(2024, 1, 11, 12)
        let illum = PhaseCalculator.illumination(for: d)
        XCTAssertLessThan(illum, 0.05)
    }

    func testIlluminationFullMoon() {
        let d = utcDate(2024, 1, 25, 18)
        let illum = PhaseCalculator.illumination(for: d)
        XCTAssertGreaterThan(illum, 0.95)
    }

    func testIlluminationFirstQuarter() {
        // 2024-01-18 03:52 UTC — documented first quarter
        let d = utcDate(2024, 1, 18, 4)
        let illum = PhaseCalculator.illumination(for: d)
        XCTAssertEqual(illum, 0.50, accuracy: 0.05)
    }

    func testIlluminationMonotonicAroundFull() {
        // Before full, illumination should be rising.
        let d1 = utcDate(2024, 1, 24, 18)
        let d2 = utcDate(2024, 1, 25, 18)
        XCTAssertLessThan(PhaseCalculator.illumination(for: d1),
                          PhaseCalculator.illumination(for: d2))
    }

    // MARK: Bucketing

    func testBucketNewMoon() {
        XCTAssertEqual(PhaseCalculator.phaseName(forAge: 0.00), .new)
        XCTAssertEqual(PhaseCalculator.phaseName(forAge: 1.84), .new)
        XCTAssertEqual(PhaseCalculator.phaseName(forAge: 28.00), .new)
        XCTAssertEqual(PhaseCalculator.phaseName(forAge: 29.50), .new)
    }

    func testBucketFirstQuarter() {
        XCTAssertEqual(PhaseCalculator.phaseName(forAge: 6.00), .firstQuarter)
        XCTAssertEqual(PhaseCalculator.phaseName(forAge: 7.38), .firstQuarter)
        XCTAssertEqual(PhaseCalculator.phaseName(forAge: 9.00), .firstQuarter)
    }

    func testBucketFullMoon() {
        XCTAssertEqual(PhaseCalculator.phaseName(forAge: 13.50), .full)
        XCTAssertEqual(PhaseCalculator.phaseName(forAge: 14.77), .full)
        XCTAssertEqual(PhaseCalculator.phaseName(forAge: 16.00), .full)
    }

    func testBucketLastQuarter() {
        XCTAssertEqual(PhaseCalculator.phaseName(forAge: 21.00), .lastQuarter)
        XCTAssertEqual(PhaseCalculator.phaseName(forAge: 22.15), .lastQuarter)
        XCTAssertEqual(PhaseCalculator.phaseName(forAge: 23.50), .lastQuarter)
    }

    func testBucketWaxingGibbous() {
        XCTAssertEqual(PhaseCalculator.phaseName(forAge: 10.00), .waxingGibbous)
        XCTAssertEqual(PhaseCalculator.phaseName(forAge: 12.50), .waxingGibbous)
    }

    func testBucketWaningCrescent() {
        XCTAssertEqual(PhaseCalculator.phaseName(forAge: 25.00), .waningCrescent)
        XCTAssertEqual(PhaseCalculator.phaseName(forAge: 27.00), .waningCrescent)
    }

    func testBucketBoundariesExhaustive() {
        // Walk the cycle at 0.5-day increments; every result must be a PhaseName.
        var d = 0.0
        while d < 29.53 {
            let p = PhaseCalculator.phaseName(forAge: d)
            XCTAssertTrue(PhaseName.allCases.contains(p),
                          "Age \(d) produced unknown phase")
            d += 0.5
        }
    }

    // MARK: Public API

    func testPhaseForKnownDates() {
        struct Case { let y, m, d: Int; let name: PhaseName; let minIllum, maxIllum: Double }
        let cases: [Case] = [
            // NASA GSFC canonical phase dates (UTC). Times chosen to sit well
            // inside the relevant bucket.
            .init(y: 2024, m: 1,  d: 11, name: .new,          minIllum: 0.00, maxIllum: 0.05),
            .init(y: 2024, m: 1,  d: 18, name: .firstQuarter, minIllum: 0.45, maxIllum: 0.55),
            .init(y: 2024, m: 1,  d: 25, name: .full,         minIllum: 0.95, maxIllum: 1.00),
            .init(y: 2024, m: 2,  d: 2,  name: .lastQuarter,  minIllum: 0.45, maxIllum: 0.55),
            .init(y: 2026, m: 4,  d: 17, name: .new,          minIllum: 0.00, maxIllum: 0.05),
            .init(y: 2026, m: 4,  d: 24, name: .firstQuarter, minIllum: 0.40, maxIllum: 0.60),
            .init(y: 2026, m: 5,  d: 1,  name: .full,         minIllum: 0.95, maxIllum: 1.00),
            .init(y: 2026, m: 5,  d: 9,  name: .lastQuarter,  minIllum: 0.40, maxIllum: 0.60),
        ]
        for c in cases {
            let d = utcDate(c.y, c.m, c.d, 12)
            let phase = PhaseCalculator.phase(for: d)
            XCTAssertEqual(phase.phaseName, c.name,
                           "Wrong phase for \(c.y)-\(c.m)-\(c.d): got \(phase.phaseName)")
            XCTAssertGreaterThanOrEqual(phase.illumination, c.minIllum,
                           "Illum too low for \(c.y)-\(c.m)-\(c.d)")
            XCTAssertLessThanOrEqual(phase.illumination, c.maxIllum,
                           "Illum too high for \(c.y)-\(c.m)-\(c.d)")
        }
    }

    func testMoonPhaseCarriesInputDate() {
        let d = utcDate(2026, 4, 21, 12)
        let p = PhaseCalculator.phase(for: d)
        XCTAssertEqual(p.date, d)
    }

    func testAgeIsInValidRange() {
        let p = PhaseCalculator.phase(for: Date())
        XCTAssertGreaterThanOrEqual(p.age, 0)
        XCTAssertLessThan(p.age, PhaseCalculator.synodicPeriod)
    }
}
