import XCTest
@testable import Lunar

final class LoggingTests: XCTestCase {
    var tempDir: URL!
    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lunar-log-\(UUID().uuidString)",
                                     isDirectory: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testAppendsToFile() throws {
        let log = FileLog(directory: tempDir, rotateAtBytes: 1_000_000)
        log.write("hello")
        log.write("world")
        let content = try String(contentsOf: tempDir.appendingPathComponent("lunar.log"))
        XCTAssertTrue(content.contains("hello"))
        XCTAssertTrue(content.contains("world"))
    }

    func testRotatesWhenThresholdExceeded() throws {
        let log = FileLog(directory: tempDir, rotateAtBytes: 200)
        for _ in 0..<50 { log.write("some long-ish line to push past the threshold") }
        let files = (try FileManager.default.contentsOfDirectory(atPath: tempDir.path))
            .sorted()
        XCTAssertTrue(files.contains("lunar.log"))
        XCTAssertTrue(files.contains("lunar.log.1"))
        XCTAssertFalse(files.contains("lunar.log.2"))
    }
}
