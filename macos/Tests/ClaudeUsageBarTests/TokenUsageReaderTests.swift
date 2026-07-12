import XCTest
@testable import ClaudeUsageBar

final class TokenUsageReaderTests: XCTestCase {
    private func tempFile() -> String {
        let dir = NSTemporaryDirectory()
        return (dir as NSString).appendingPathComponent("tur-\(UUID().uuidString).jsonl")
    }

    func testReadsOnlyCompleteAppendedLines() throws {
        let path = tempFile()
        defer { try? FileManager.default.removeItem(atPath: path) }

        try "line1\nline2\n".write(toFile: path, atomically: true, encoding: .utf8)
        let first = TokenUsageReader.readAppended(path: path, cursor: nil)
        XCTAssertEqual(String(decoding: first!.data, as: UTF8.self), "line1\nline2\n")

        // Append a complete line plus a partial one; only the complete part is consumed.
        let handle = FileHandle(forWritingAtPath: path)!
        handle.seekToEndOfFile()
        handle.write(Data("line3\npartial".utf8))
        try handle.close()

        let second = TokenUsageReader.readAppended(path: path, cursor: first!.cursor)
        XCTAssertEqual(String(decoding: second!.data, as: UTF8.self), "line3\n")
    }

    func testTruncationResetsToZero() throws {
        let path = tempFile()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try "aaaa\nbbbb\n".write(toFile: path, atomically: true, encoding: .utf8)
        let first = TokenUsageReader.readAppended(path: path, cursor: nil)!
        try "x\n".write(toFile: path, atomically: true, encoding: .utf8) // smaller than cursor.offset
        let second = TokenUsageReader.readAppended(path: path, cursor: first.cursor)!
        XCTAssertEqual(String(decoding: second.data, as: UTF8.self), "x\n")
    }
}
