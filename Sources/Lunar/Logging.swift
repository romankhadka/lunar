import Foundation
import os

enum Log {
    static let coordinator = Logger(subsystem: "com.lunar", category: "coordinator")
    static let wallpaper   = Logger(subsystem: "com.lunar", category: "wallpaper")
    static let image       = Logger(subsystem: "com.lunar", category: "image")
    static let ui          = Logger(subsystem: "com.lunar", category: "ui")

    static var file: FileLog = {
        let dir = FileManager.default.urls(for: .libraryDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Lunar", isDirectory: true)
        return FileLog(directory: dir)
    }()
}

/// Simple appending file logger with one rotation at `rotateAtBytes`.
final class FileLog {
    let directory: URL
    let rotateAtBytes: Int
    private let lock = NSLock()
    private static let ts: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    init(directory: URL, rotateAtBytes: Int = 1_000_000) {
        self.directory = directory
        self.rotateAtBytes = rotateAtBytes
    }

    var currentURL: URL { directory.appendingPathComponent("lunar.log") }

    func write(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let url = currentURL
            rotateIfNeeded()
            let line = "\(Self.ts.string(from: Date())) \(message)\n"
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: url.path) {
                let h = try FileHandle(forWritingTo: url)
                try h.seekToEnd(); try h.write(contentsOf: data); try h.close()
            } else {
                try data.write(to: url)
            }
        } catch {
            Log.coordinator.error("FileLog write failed: \(error.localizedDescription)")
        }
    }

    private func rotateIfNeeded() {
        let url = currentURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size > rotateAtBytes else { return }
        let rotated = directory.appendingPathComponent("lunar.log.1")
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: url, to: rotated)
    }
}
