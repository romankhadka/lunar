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

    /// Renders and applies today's wallpaper unless the same day, phase and
    /// canvas size were already applied. Returns `true` when it applied a
    /// new image.
    @discardableResult
    func updateWallpaper(force: Bool = false) -> Bool {
        let now = clock()
        let phase = PhaseCalculator.phase(for: now)
        let canvas = canvasSizeProvider()
        let key = Self.key(for: now, phase: phase.phaseName, canvas: canvas)

        if !force,
           defaults.string(forKey: lastAppliedKeyDefault) == key,
           setter.fileExists(for: now) {
            publish(phase, at: now)
            return false
        }

        do {
            let base = try images.baseImage(for: phase.phaseName)
            let composed = compositor.composite(
                base: base, phase: phase, canvasSize: canvas)
            try setter.apply(image: composed, for: now)
            defaults.set(key, forKey: lastAppliedKeyDefault)
            publish(phase, at: now)
            lastError = nil
            Log.coordinator.log("Applied \(phase.phaseName.rawValue, privacy: .public) @ \(key, privacy: .public)")
            Log.file.write("Applied \(phase.phaseName.rawValue) (\(Int(phase.illumination*100))%)")
            return true
        } catch {
            lastError = error.localizedDescription
            Log.coordinator.error("Update failed: \(error.localizedDescription, privacy: .public)")
            Log.file.write("ERROR: \(error.localizedDescription)")
            return false
        }
    }

    /// The display layout changed. Screen-change notifications arrive in
    /// bursts, so render again only when the canvas size changed. Otherwise
    /// push the existing file, which also covers a newly attached screen.
    func handleScreenChange() {
        if !updateWallpaper() {
            reapplyToday()
        }
    }

    func reapplyToday(onlyStale: Bool = false) {
        do { try setter.reapplyToday(onlyStale: onlyStale) }
        catch {
            lastError = error.localizedDescription
            Log.coordinator.error("reapply failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func publish(_ phase: MoonPhase, at now: Date) {
        currentPhase = phase
        nextPhase = PhaseCalculator.nextPhaseChange(after: now)
    }

    private static func key(for date: Date, phase: PhaseName, canvas: CGSize) -> String {
        let day = WallpaperFileStore.dayStamp(for: date)
        return "\(day)|\(phase.rawValue)|\(Int(canvas.width))x\(Int(canvas.height))"
    }
}
