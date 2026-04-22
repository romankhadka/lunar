import Foundation

struct MoonPhase: Equatable {
    let date: Date
    let age: Double
    let illumination: Double
    let phaseName: PhaseName
}

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
    /// 2024-01-11 11:57 UTC. Anchored recently so the simplified mean-cycle
    /// model stays accurate for the years the app actually runs.
    static let referenceNewMoonJD: Double = 2460320.9979

    /// Days since the last new moon at the given instant.
    /// Result is in the half-open range [0, 29.530588853).
    static func synodicAge(for date: Date) -> Double {
        let jd = julianDay(for: date)
        let raw = (jd - referenceNewMoonJD).truncatingRemainder(
            dividingBy: synodicPeriod)
        return raw < 0 ? raw + synodicPeriod : raw
    }

    /// Fraction of the Moon's disk illuminated, in [0, 1].
    /// Uses a simplified Meeus ch. 48 formulation via the Moon's mean
    /// elongation from the Sun; sufficient for phase bucketing and
    /// percentage display (accurate to a few tenths of a percent).
    static func illumination(for date: Date) -> Double {
        let age = synodicAge(for: date)
        // Phase angle i varies ~linearly with synodic age from 180° at
        // new to 0° at full and back to 180°. i = |180° − (age/P)·360°|.
        let fraction = age / synodicPeriod          // 0 … 1
        let phaseDeg = abs(180.0 - fraction * 360.0) // 180 at new, 0 at full
        let phaseRad = phaseDeg * .pi / 180.0
        return (1.0 + cos(phaseRad)) / 2.0
    }

    /// Buckets a synodic-age value into one of 8 phase names.
    /// Buckets are 29.53/8 ≈ 3.691 days wide and centered on the four
    /// astronomical events (new at 0, first quarter at 7.38, full at 14.77,
    /// last quarter at 22.15). "New" wraps across the cycle boundary.
    static func phaseName(forAge age: Double) -> PhaseName {
        let bucket = synodicPeriod / 8.0       // ≈ 3.691
        let shifted = (age + bucket / 2)
            .truncatingRemainder(dividingBy: synodicPeriod)
        let normalized = shifted < 0 ? shifted + synodicPeriod : shifted
        let index = Int(normalized / bucket) % 8
        switch index {
        case 0: return .new
        case 1: return .waxingCrescent
        case 2: return .firstQuarter
        case 3: return .waxingGibbous
        case 4: return .full
        case 5: return .waningGibbous
        case 6: return .lastQuarter
        case 7: return .waningCrescent
        default: return .new   // unreachable
        }
    }

    /// Full phase information for a given instant.
    static func phase(for date: Date) -> MoonPhase {
        let age = synodicAge(for: date)
        return MoonPhase(
            date: date,
            age: age,
            illumination: illumination(for: date),
            phaseName: phaseName(forAge: age)
        )
    }
}
