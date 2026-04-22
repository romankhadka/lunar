import SwiftUI
import AppKit
import ServiceManagement

@main
struct LunarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                coordinator: appDelegate.coordinator,
                openPhasesFolder: appDelegate.openPhasesFolder,
                openLog: appDelegate.openLog,
                toggleLaunchAtLogin: appDelegate.toggleLaunchAtLogin,
                isLaunchAtLoginEnabled: appDelegate.isLaunchAtLoginEnabled)
        } label: {
            Image(systemName: "moon.fill")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let coordinator: AppCoordinator
    let imageProvider: ImageProvider

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
                                    resourceBundle: .module)
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
        try? coordinator.updateWallpaper()
        installObservers()
        scheduleDailyTimer()
    }

    private func installObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                try? self?.coordinator.updateWallpaper()
            })

        let anc = NotificationCenter.default
        observers.append(anc.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                try? self?.coordinator.updateWallpaper(force: true)
            })

        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) {
            [weak self] _, _ in
            DispatchQueue.main.async { try? self?.coordinator.reapplyToday() }
        }
    }

    private func scheduleDailyTimer() {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = 6; comps.minute = 0; comps.second = 0
        var fire = cal.date(from: comps)!
        if fire <= now { fire = cal.date(byAdding: .day, value: 1, to: fire)! }
        dailyTimer?.invalidate()
        dailyTimer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            try? self?.coordinator.updateWallpaper()
            self?.scheduleDailyTimer()
        }
        RunLoop.main.add(dailyTimer!, forMode: .common)
    }

    static func largestCanvasSize() -> CGSize {
        guard let s = NSScreen.screens.max(by: {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }) else { return CGSize(width: 5120, height: 2880) }
        let scale = s.backingScaleFactor
        return CGSize(width: s.frame.width * scale,
                      height: s.frame.height * scale)
    }

    func openPhasesFolder() { imageProvider.openOverrideFolderInFinder() }

    func openLog() {
        NSWorkspace.shared.open(Log.file.currentURL)
    }

    var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.ui.error("Launch-at-login toggle failed: \(error.localizedDescription, privacy: .public)")
        }
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
