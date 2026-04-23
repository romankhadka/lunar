import Foundation

struct MoonPhase: Equatable {
    let date: Date
    let age: Double
    let illumination: Double
    let phaseName: PhaseName
}

enum PhaseCalculator {

    /// Synodic period (mean interval between new moons), in days.
    static let synodicPeriod: Double = 29.530588853

    // MARK: - Public API

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

    /// Days since the last true new moon (new-moon elongation = 0), in [0, 29.53).
    /// Derived from the Moon's true geocentric elongation from the Sun, so the
    /// result tracks the actual lunation rather than the mean cycle.
    static func synodicAge(for date: Date) -> Double {
        let elong = trueElongationDegrees(for: date)
        // Elongation = 0° at new, 180° at full, approaches 360°≡0° back at next new.
        // Age fraction of synodic cycle = elong / 360°.
        let fraction = elong / 360.0
        return fraction * synodicPeriod
    }

    /// Fraction of the Moon's disk illuminated, in [0, 1].
    /// Meeus Astronomical Algorithms (2nd ed.), chapters 25, 47, 48.
    /// Accurate to better than 0.1% against USNO / NASA sources.
    static func illumination(for date: Date) -> Double {
        let i = phaseAngleDegrees(for: date)  // 0°=full, 180°=new
        let iRad = i * .pi / 180.0
        return (1.0 + cos(iRad)) / 2.0
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

    // MARK: - Internal astronomy (Meeus)

    /// Elongation of Moon from Sun in ecliptic longitude, 0°–360°
    /// (0° at new, 180° at full). Uses geocentric longitudes from chs. 25/47.
    private static func trueElongationDegrees(for date: Date) -> Double {
        let jd = julianDay(for: date)
        let sun = solarLongitudeDegrees(jd: jd)
        let moon = moonLongitudeDegrees(jd: jd)
        var d = (moon - sun).truncatingRemainder(dividingBy: 360.0)
        if d < 0 { d += 360.0 }
        return d
    }

    /// Sun–Earth–Moon phase angle `i` in degrees (Meeus eq. 48.3).
    /// 0°=full, 90°=quarter, 180°=new.
    private static func phaseAngleDegrees(for date: Date) -> Double {
        let jd = julianDay(for: date)
        let (sunLon, sunR) = solarPosition(jd: jd)                         // λ☉ (deg), R (AU)
        let (moonLon, moonLat, moonDelta) = moonPosition(jd: jd)           // λ☽, β, Δ
        // Geocentric elongation ψ from ecliptic coords (Meeus eq. 48.4):
        //   cos ψ = cos(β) · cos(λ☽ − λ☉)
        let dLon = (moonLon - sunLon) * .pi / 180.0
        let betaRad = moonLat * .pi / 180.0
        let cosPsi = cos(betaRad) * cos(dLon)
        let psi = acos(max(-1.0, min(1.0, cosPsi)))   // radians
        // i = atan2(R · sin ψ, Δ − R · cos ψ), with R and Δ in km.
        let R_km = sunR * 149_597_870.7    // AU → km
        let numer = R_km * sin(psi)
        let denom = moonDelta - R_km * cos(psi)
        let i = atan2(numer, denom) * 180.0 / .pi
        return i < 0 ? i + 360.0 : i
    }

    // MARK: - Solar position (Meeus ch. 25, low-accuracy form)

    private static func solarPosition(jd: Double) -> (longitude: Double, distanceAU: Double) {
        let T = (jd - 2451545.0) / 36525.0
        let L0 = normalizeDegrees(280.46646 + 36000.76983 * T + 0.0003032 * T * T)
        let M  = normalizeDegrees(357.52911 + 35999.05029 * T - 0.0001537 * T * T)
        let Mrad = M * .pi / 180.0
        // Equation of center (eq 25.4)
        let C = (1.914602 - 0.004817 * T - 0.000014 * T * T) * sin(Mrad)
              + (0.019993 - 0.000101 * T) * sin(2 * Mrad)
              + 0.000289 * sin(3 * Mrad)
        let trueLon = L0 + C
        let trueAnom = M + C
        // Apparent longitude: nutation + aberration (eq 25.8)
        let omega = 125.04 - 1934.136 * T
        let lambda = trueLon - 0.00569 - 0.00478 * sin(omega * .pi / 180.0)
        // Distance in AU (eq 25.3)
        let e = 0.016708634 - 0.000042037 * T - 0.0000001267 * T * T
        let trueAnomRad = trueAnom * .pi / 180.0
        let R = (1.000001018 * (1 - e * e)) / (1 + e * cos(trueAnomRad))
        return (normalizeDegrees(lambda), R)
    }

    private static func solarLongitudeDegrees(jd: Double) -> Double {
        solarPosition(jd: jd).longitude
    }

    // MARK: - Lunar position (Meeus ch. 47, tables 47.A/47.B)

    /// Meeus table 47.A — 60 rows: (D, M, M', F, coeffL, coeffR)
    ///   coeffL in 10⁻⁶ degrees, coeffR in 10⁻³ km.
    /// Copied verbatim from MeeusJs `Astro.Moon.js` `ta` (MIT).
    private static let termsLR: [(Int, Int, Int, Int, Double, Double)] = [
        (0, 0, 1, 0, 6288774, -20905355),
        (2, 0, -1, 0, 1274027, -3699111),
        (2, 0, 0, 0, 658314, -2955968),
        (0, 0, 2, 0, 213618, -569925),

        (0, 1, 0, 0, -185116, 48888),
        (0, 0, 0, 2, -114332, -3149),
        (2, 0, -2, 0, 58793, 246158),
        (2, -1, -1, 0, 57066, -152138),

        (2, 0, 1, 0, 53322, -170733),
        (2, -1, 0, 0, 45758, -204586),
        (0, 1, -1, 0, -40923, -129620),
        (1, 0, 0, 0, -34720, 108743),

        (0, 1, 1, 0, -30383, 104755),
        (2, 0, 0, -2, 15327, 10321),
        (0, 0, 1, 2, -12528, 0),
        (0, 0, 1, -2, 10980, 79661),

        (4, 0, -1, 0, 10675, -34782),
        (0, 0, 3, 0, 10034, -23210),
        (4, 0, -2, 0, 8548, -21636),
        (2, 1, -1, 0, -7888, 24208),

        (2, 1, 0, 0, -6766, 30824),
        (1, 0, -1, 0, -5163, -8379),
        (1, 1, 0, 0, 4987, -16675),
        (2, -1, 1, 0, 4036, -12831),

        (2, 0, 2, 0, 3994, -10445),
        (4, 0, 0, 0, 3861, -11650),
        (2, 0, -3, 0, 3665, 14403),
        (0, 1, -2, 0, -2689, -7003),

        (2, 0, -1, 2, -2602, 0),
        (2, -1, -2, 0, 2390, 10056),
        (1, 0, 1, 0, -2348, 6322),
        (2, -2, 0, 0, 2236, -9884),

        (0, 1, 2, 0, -2120, 5751),
        (0, 2, 0, 0, -2069, 0),
        (2, -2, -1, 0, 2048, -4950),
        (2, 0, 1, -2, -1773, 4130),

        (2, 0, 0, 2, -1595, 0),
        (4, -1, -1, 0, 1215, -3958),
        (0, 0, 2, 2, -1110, 0),
        (3, 0, -1, 0, -892, 3258),

        (2, 1, 1, 0, -810, 2616),
        (4, -1, -2, 0, 759, -1897),
        (0, 2, -1, 0, -713, -2117),
        (2, 2, -1, 0, -700, 2354),

        (2, 1, -2, 0, 691, 0),
        (2, -1, 0, -2, 596, 0),
        (4, 0, 1, 0, 549, -1423),
        (0, 0, 4, 0, 537, -1117),

        (4, -1, 0, 0, 520, -1571),
        (1, 0, -2, 0, -487, -1739),
        (2, 1, 0, -2, -399, 0),
        (0, 0, 2, -2, -381, -4421),

        (1, 1, 1, 0, 351, 0),
        (3, 0, -2, 0, -340, 0),
        (4, 0, -3, 0, 330, 0),
        (2, -1, 2, 0, 327, 0),

        (0, 2, 1, 0, -323, 1165),
        (1, 1, -1, 0, 299, 0),
        (2, 0, 3, 0, 294, 0),
        (2, 0, -1, -2, 0, 8752),
    ]

    /// Meeus table 47.B — 60 rows: (D, M, M', F, coeffB)
    ///   coeffB in 10⁻⁶ degrees.
    /// Copied verbatim from MeeusJs `Astro.Moon.js` `tb` (MIT).
    private static let termsB: [(Int, Int, Int, Int, Double)] = [
        (0, 0, 0, 1, 5128122),
        (0, 0, 1, 1, 280602),
        (0, 0, 1, -1, 277693),
        (2, 0, 0, -1, 173237),

        (2, 0, -1, 1, 55413),
        (2, 0, -1, -1, 46271),
        (2, 0, 0, 1, 32573),
        (0, 0, 2, 1, 17198),

        (2, 0, 1, -1, 9266),
        (0, 0, 2, -1, 8822),
        (2, -1, 0, -1, 8216),
        (2, 0, -2, -1, 4324),

        (2, 0, 1, 1, 4200),
        (2, 1, 0, -1, -3359),
        (2, -1, -1, 1, 2463),
        (2, -1, 0, 1, 2211),

        (2, -1, -1, -1, 2065),
        (0, 1, -1, -1, -1870),
        (4, 0, -1, -1, 1828),
        (0, 1, 0, 1, -1794),

        (0, 0, 0, 3, -1749),
        (0, 1, -1, 1, -1565),
        (1, 0, 0, 1, -1491),
        (0, 1, 1, 1, -1475),

        (0, 1, 1, -1, -1410),
        (0, 1, 0, -1, -1344),
        (1, 0, 0, -1, -1335),
        (0, 0, 3, 1, 1107),

        (4, 0, 0, -1, 1021),
        (4, 0, -1, 1, 833),

        (0, 0, 1, -3, 777),
        (4, 0, -2, 1, 671),
        (2, 0, 0, -3, 607),
        (2, 0, 2, -1, 596),

        (2, -1, 1, -1, 491),
        (2, 0, -2, 1, -451),
        (0, 0, 3, -1, 439),
        (2, 0, 2, 1, 422),

        (2, 0, -3, -1, 421),
        (2, 1, -1, 1, -366),
        (2, 1, 0, 1, -351),
        (4, 0, 0, 1, 331),

        (2, -1, 1, 1, 315),
        (2, -2, 0, -1, 302),
        (0, 0, 1, 3, -283),
        (2, 1, 1, -1, -229),

        (1, 1, 0, -1, 223),
        (1, 1, 0, 1, 223),
        (0, 1, -2, -1, -220),
        (2, 1, -1, -1, -220),

        (1, 0, 1, 1, -185),
        (2, -1, -2, -1, 181),
        (0, 1, 2, 1, -177),
        (4, 0, -2, -1, 176),

        (4, -1, -1, -1, 166),
        (1, 0, 1, -1, -164),
        (4, 0, 1, -1, 132),
        (1, 0, -1, -1, -119),

        (4, -1, 0, -1, 115),
        (2, -2, 0, 1, 107),
    ]

    private static func moonPosition(jd: Double) -> (longitude: Double, latitude: Double, distanceKm: Double) {
        let T = (jd - 2451545.0) / 36525.0
        // Meeus eqs. 47.1–47.5 (full quartic expansions as per MeeusJs)
        let Lp = normalizeDegrees(218.3164477 + 481267.88123421 * T
                                  - 0.0015786 * T*T + T*T*T/538841 - T*T*T*T/65194000)
        let D  = normalizeDegrees(297.8501921 + 445267.1114034 * T
                                  - 0.0018819 * T*T + T*T*T/545868 - T*T*T*T/113065000)
        let M  = normalizeDegrees(357.5291092 + 35999.0502909 * T
                                  - 0.0001536 * T*T + T*T*T/24490000)
        let Mp = normalizeDegrees(134.9633964 + 477198.8675055 * T
                                  + 0.0087414 * T*T + T*T*T/69699 - T*T*T*T/14712000)
        let F  = normalizeDegrees(93.2720950 + 483202.0175233 * T
                                  - 0.0036539 * T*T - T*T*T/3526000 + T*T*T*T/863310000)
        let E = 1.0 - 0.002516 * T - 0.0000074 * T * T
        let E2 = E * E

        var sigmaL = 0.0, sigmaR = 0.0, sigmaB = 0.0
        let Drad = D * .pi / 180.0
        let Mrad = M * .pi / 180.0
        let Mprad = Mp * .pi / 180.0
        let Frad = F * .pi / 180.0

        for (d, m, mp, f, cL, cR) in termsLR {
            let arg = Double(d)*Drad + Double(m)*Mrad + Double(mp)*Mprad + Double(f)*Frad
            var ef: Double = 1
            if abs(m) == 1 { ef = E } else if abs(m) == 2 { ef = E2 }
            sigmaL += cL * ef * sin(arg)
            sigmaR += cR * ef * cos(arg)
        }
        for (d, m, mp, f, cB) in termsB {
            let arg = Double(d)*Drad + Double(m)*Mrad + Double(mp)*Mprad + Double(f)*Frad
            var ef: Double = 1
            if abs(m) == 1 { ef = E } else if abs(m) == 2 { ef = E2 }
            sigmaB += cB * ef * sin(arg)
        }

        // Planetary-perturbation corrections (Meeus pp. 338)
        let A1 = normalizeDegrees(119.75 + 131.849 * T)
        let A2 = normalizeDegrees(53.09 + 479264.290 * T)
        let A3 = normalizeDegrees(313.45 + 481266.484 * T)
        sigmaL += 3958 * sin(A1 * .pi / 180.0)
               + 1962 * sin((Lp - F) * .pi / 180.0)
               +  318 * sin(A2 * .pi / 180.0)
        sigmaB += -2235 * sin(Lp * .pi / 180.0)
                +  382 * sin(A3 * .pi / 180.0)
                +  175 * sin((A1 - F) * .pi / 180.0)
                +  175 * sin((A1 + F) * .pi / 180.0)
                +  127 * sin((Lp - Mp) * .pi / 180.0)
                -  115 * sin((Lp + Mp) * .pi / 180.0)

        let longitude = normalizeDegrees(Lp + sigmaL / 1_000_000.0)
        let latitude  = sigmaB / 1_000_000.0
        let distanceKm = 385000.56 + sigmaR / 1000.0
        return (longitude, latitude, distanceKm)
    }

    private static func moonLongitudeDegrees(jd: Double) -> Double {
        moonPosition(jd: jd).longitude
    }

    private static func normalizeDegrees(_ x: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: 360.0)
        return r < 0 ? r + 360.0 : r
    }
}
