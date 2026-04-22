import Foundation

enum PhaseCalculator {

    /// Converts a `Date` to a Julian Day number.
    /// Uses Meeus AA (2nd ed.), p. 61, formula 7.1.
    static func julianDay(for date: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day,
                                    .hour, .minute, .second],
                                   from: date)
        var Y = Double(c.year!)
        var M = Double(c.month!)
        let D = Double(c.day!)
              + Double(c.hour!) / 24.0
              + Double(c.minute!) / 1440.0
              + Double(c.second!) / 86400.0

        if M <= 2 { Y -= 1; M += 12 }
        let A = floor(Y / 100)
        let B = 2 - A + floor(A / 4)
        return floor(365.25 * (Y + 4716))
             + floor(30.6001 * (M + 1))
             + D + B - 1524.5
    }

    /// Synodic period (mean interval between new moons), in days.
    static let synodicPeriod: Double = 29.530588853

    /// Reference Julian Day of a known new moon:
    /// 2000-01-06 18:14 UTC (first new moon after J2000 epoch).
    static let referenceNewMoonJD: Double = 2451550.09766

    /// Days since the last new moon at the given instant.
    /// Result is in the half-open range [0, 29.530588853).
    static func synodicAge(for date: Date) -> Double {
        let jd = julianDay(for: date)
        let raw = (jd - referenceNewMoonJD).truncatingRemainder(
            dividingBy: synodicPeriod)
        return raw < 0 ? raw + synodicPeriod : raw
    }
}
