import SwiftUI
import AppKit

@main
struct LunarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                coordinator: appDelegate.coordinator,
                launchAtLogin: appDelegate.launchAtLogin,
                openPhasesFolder: appDelegate.openPhasesFolder,
                openLog: appDelegate.openLog)
        } label: {
            Image(systemName: "moon.fill")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let coordinator: AppCoordinator
    let imageProvider: ImageProvider
    let launchAtLogin = LaunchAtLogin()

    private var observers: [NSObjectProtocol] = []
    private var dailyTimer: Timer?
    private var appearanceObservation: NSKeyValueObservation?

    override init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory,
                                  in: .userDomainMask)[0]
            .appendingPathComponent("Lunar", isDirectory: true)
        try? fm.createDirectory(at: appSupport,
                                 withIntermediateDirectories: true)

        let images = ImageProvider(supportDirectory: appSupport,
                                    resourceBundle: .main)
        let fileStore = WallpaperFileStore(
            directory: appSupport.appendingPathComponent("current",
                                                          isDirectory: true))
        let setter = WallpaperSetter(store: fileStore)

        self.imageProvider = images
        self.coordinator = AppCoordinator(
            images: images,
            compositor: Compositor(),
            setter: setter,
            canvasSizeProvider: AppDelegate.largestCanvasSize,
            defaults: .standard,
            clock: { Date() })

        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? imageProvider.ensureOverrideDirectoryExists()
        coordinator.updateWallpaper()
        installObservers()
        scheduleDailyTimer()
    }

    private func installObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.coordinator.updateWallpaper()
                    // The timer's fire date can drift across sleep; re-anchor it.
                    self.scheduleDailyTimer()
                }
            })

        let anc = NotificationCenter.default
        observers.append(anc.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.coordinator.handleScreenChange() }
            })

        // setDesktopImageURL only writes the Space that is active on each
        // screen at the moment of the call, so other Spaces keep whatever the
        // system had stored for them. Re-pushing today's PNG whenever the
        // active Space changes lets stale Spaces self-heal on first visit.
        // Screens whose Space already shows the file are skipped.
        observers.append(nc.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.coordinator.reapplyToday(onlyStale: true) }
            })

        // This re-push stays unconditional. It keeps the light and dark
        // wallpaper slots in sync, and a URL match on one slot proves nothing
        // about the other.
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) {
            [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in self.coordinator.reapplyToday() }
        }
    }

    private func scheduleDailyTimer() {
        dailyTimer?.invalidate()
        guard let fire = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 6, minute: 0, second: 0),
            matchingPolicy: .nextTime) else { return }
        let timer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.coordinator.updateWallpaper()
                self.scheduleDailyTimer()
            }
        }
        // A few minutes of slack lets macOS batch this wake-up with others.
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
        dailyTimer = timer
    }

    static func largestCanvasSize() -> CGSize {
        canvasSize(forScreenPixelSizes: NSScreen.screens.map { s in
            CGSize(width: s.frame.width * s.backingScaleFactor,
                   height: s.frame.height * s.backingScaleFactor)
        })
    }

    /// Picks the screen with the most pixels, so no screen gets an upscaled
    /// image. Compares pixels, not points: a 1x 2560×1440 display has fewer
    /// pixels than a 2x 1512×982 laptop panel.
    static func canvasSize(forScreenPixelSizes sizes: [CGSize]) -> CGSize {
        sizes.max { $0.width * $0.height < $1.width * $1.height }
            ?? CGSize(width: 5120, height: 2880)
    }

    func openPhasesFolder() { imageProvider.openOverrideFolderInFinder() }

    func openLog() {
        NSWorkspace.shared.open(Log.file.currentURL)
    }

    func applicationWillTerminate(_ notification: Notification) {
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            NotificationCenter.default.removeObserver($0)
        }
        appearanceObservation?.invalidate()
        dailyTimer?.invalidate()
    }
}
