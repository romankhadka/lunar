import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit

protocol WallpaperApplying {
    func apply(image: CGImage, for date: Date) throws
    func reapplyToday() throws
    func fileExists(for date: Date) -> Bool
}

/// Pure file-layer: writes dated PNGs, prunes old ones.
struct WallpaperFileStore {
    let directory: URL
    var retentionDays: Int = 7

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func url(for date: Date) -> URL {
        directory.appendingPathComponent("\(Self.formatter.string(from: date)).png")
    }

    @discardableResult
    func write(image: CGImage, for date: Date) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let fileURL = url(for: date)
        guard let dest = CGImageDestinationCreateWithURL(
                fileURL as CFURL,
                UTType.png.identifier as CFString,
                1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try pruneToRetention()
        return fileURL
    }

    private func pruneToRetention() throws {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        let pngs = entries.filter { $0.hasSuffix(".png") }.sorted()
        guard pngs.count > retentionDays else { return }
        for name in pngs.prefix(pngs.count - retentionDays) {
            try? fm.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}

/// Side-effecting wrapper: writes the file and applies it to every screen.
struct WallpaperSetter: WallpaperApplying {
    let store: WallpaperFileStore

    func apply(image: CGImage, for date: Date) throws {
        let url = try store.write(image: image, for: date)
        try applyURLToAllScreens(url)
        kickWallpaperAgent()
    }

    func reapplyToday() throws {
        let url = store.url(for: Date())
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try applyURLToAllScreens(url)
    }

    func fileExists(for date: Date) -> Bool {
        FileManager.default.fileExists(atPath: store.url(for: date).path)
    }

    /// Nudges macOS's wallpaper daemon to drop its cache and redraw.
    /// Workaround for a Sonoma+ bug where `setDesktopImageURL` updates the
    /// preference but the visible desktop keeps showing the previously-rendered
    /// wallpaper, even with a fresh file URL per day. Observed when override
    /// PNGs are dropped mid-day and a force-refresh is triggered.
    private func kickWallpaperAgent() {
        let proc = Process()
        proc.launchPath = "/usr/bin/killall"
        proc.arguments = ["WallpaperAgent"]
        proc.standardError = Pipe()
        proc.standardOutput = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            Log.wallpaper.error("killall WallpaperAgent failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applyURLToAllScreens(_ url: URL) throws {
        var firstError: Error?
        for screen in NSScreen.screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(
                    url,
                    for: screen,
                    options: [
                        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                        .allowClipping: true
                    ])
            } catch {
                Log.wallpaper.error("setDesktopImageURL failed for screen \(screen.localizedName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }
}
