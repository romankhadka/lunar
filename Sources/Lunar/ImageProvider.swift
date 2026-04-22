import Foundation
import CoreGraphics
import ImageIO
import AppKit

protocol ImageProviding {
    func baseImage(for phase: PhaseName) throws -> CGImage
}

struct ImageProvider: ImageProviding {
    enum Error: Swift.Error {
        case bundledImageMissing(PhaseName)
    }

    let supportDirectory: URL
    let resourceBundle: Bundle

    var overrideDirectory: URL {
        supportDirectory.appendingPathComponent("phases", isDirectory: true)
    }

    func ensureOverrideDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: overrideDirectory, withIntermediateDirectories: true)
    }

    func baseImage(for phase: PhaseName) throws -> CGImage {
        if let fromOverride = loadImage(at:
            overrideDirectory.appendingPathComponent("\(phase.rawValue).png")) {
            return fromOverride
        }
        guard let url = resourceBundle.url(forResource: phase.rawValue,
                                           withExtension: "png",
                                           subdirectory: "phases"),
              let img = loadImage(at: url) else {
            throw Error.bundledImageMissing(phase)
        }
        return img
    }

    func openOverrideFolderInFinder() {
        try? ensureOverrideDirectoryExists()
        NSWorkspace.shared.open(overrideDirectory)
    }

    private func loadImage(at url: URL) -> CGImage? {
        guard FileManager.default.fileExists(atPath: url.path),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return nil
        }
        return img
    }
}
