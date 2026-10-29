import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit

protocol WallpaperApplying {
    func apply(image: CGImage, for date: Date) throws
    /// Re-pushes today's file to every screen. With `onlyStale`, screens
    /// whose active Space already shows that file are skipped.
    func reapplyToday(onlyStale: Bool) throws
    func fileExists(for date: Date) -> Bool
}

/// Pure file-layer: writes dated PNGs, prunes old ones.
struct WallpaperFileStore {
    let directory: URL
    var retentionDays: Int = 7

    /// `yyyy-MM-dd` for `date` in the current time zone. File names and the
    /// coordinator's idempotency key both use this, so they always agree.
    static func dayStamp(for date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func url(for date: Date) -> URL {
        directory.appendingPathComponent("\(Self.dayStamp(for: date)).png")
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
        try applyURLToAllScreens(url, onlyStale: false)
    }

    func reapplyToday(onlyStale: Bool) throws {
        let url = store.url(for: Date())
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try applyURLToAllScreens(url, onlyStale: onlyStale)
    }

    func fileExists(for date: Date) -> Bool {
        FileManager.default.fileExists(atPath: store.url(for: date).path)
    }

    private func applyURLToAllScreens(_ url: URL, onlyStale: Bool) throws {
        let workspace = NSWorkspace.shared
        let target = url.standardizedFileURL.path
        var firstError: Error?
        for screen in NSScreen.screens {
            // Each set makes the system reload the multi-MB PNG, so skip
            // screens that already show it.
            if onlyStale,
               workspace.desktopImageURL(for: screen)?.standardizedFileURL.path == target {
                continue
            }
            do {
                try workspace.setDesktopImageURL(
                    url,
                    for: screen,
                    options: [
                        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                        .allowClipping: false,
                        .fillColor: NSColor.black
                    ])
            } catch {
                Log.wallpaper.error("setDesktopImageURL failed for screen \(screen.localizedName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }
}
