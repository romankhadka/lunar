import Foundation
import CoreGraphics
import Combine
import AppKit

@MainActor
final class AppCoordinator: ObservableObject {

    private let images: ImageProviding
    private let compositor: Compositing
    private let setter: WallpaperApplying
    private let canvasSizeProvider: () -> CGSize
    private let defaults: UserDefaults
    private let clock: () -> Date

    @Published private(set) var currentPhase: MoonPhase?
    @Published private(set) var lastError: String?
    @Published private(set) var nextPhase: (name: PhaseName, date: Date)?

    private let lastAppliedKeyDefault = "LastAppliedKey"

    init(images: ImageProviding,
         compositor: Compositing,
         setter: WallpaperApplying,
         canvasSizeProvider: @escaping () -> CGSize,
         defaults: UserDefaults,
         clock: @escaping () -> Date = { Date() }) {
        self.images = images
        self.compositor = compositor
        self.setter = setter
        self.canvasSizeProvider = canvasSizeProvider
        self.defaults = defaults
        self.clock = clock
    }

    func updateWallpaper(force: Bool = false) throws {
        let now = clock()
        let phase = PhaseCalculator.phase(for: now)
        let key = Self.key(for: now, phase: phase.phaseName)

        if !force,
           defaults.string(forKey: lastAppliedKeyDefault) == key,
           setter.fileExists(for: now) {
            currentPhase = phase
            nextPhase = Self.predictNext(from: now, currentAge: phase.age)
            return
        }

        do {
            let base = try images.baseImage(for: phase.phaseName)
            let canvas = canvasSizeProvider()
            let composed = compositor.composite(
                base: base, phase: phase, canvasSize: canvas)
            try setter.apply(image: composed, for: now)
            defaults.set(key, forKey: lastAppliedKeyDefault)
            currentPhase = phase
            nextPhase = Self.predictNext(from: now, currentAge: phase.age)
            lastError = nil
            Log.coordinator.log("Applied \(phase.phaseName.rawValue, privacy: .public) @ \(key, privacy: .public)")
            Log.file.write("Applied \(phase.phaseName.rawValue) (\(Int(phase.illumination*100))%)")
        } catch {
            lastError = error.localizedDescription
            Log.coordinator.error("Update failed: \(error.localizedDescription, privacy: .public)")
            Log.file.write("ERROR: \(error.localizedDescription)")
        }
    }

    func reapplyToday() throws {
        do { try setter.reapplyToday() }
        catch {
            lastError = error.localizedDescription
            Log.coordinator.error("reapply failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func key(for date: Date, phase: PhaseName) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "\(f.string(from: date))|\(phase.rawValue)"
    }

    private static func predictNext(from now: Date,
                                     currentAge: Double) -> (name: PhaseName, date: Date) {
        let currentName = PhaseCalculator.phaseName(forAge: currentAge)
        var probe = now
        let cal = Calendar.current
        for hours in stride(from: 6, through: 240, by: 6) {
            if let p = cal.date(byAdding: .hour, value: hours, to: now) {
                let name = PhaseCalculator.phase(for: p).phaseName
                if name != currentName { probe = p; return (name, probe) }
            }
        }
        return (currentName, now)
    }
}
