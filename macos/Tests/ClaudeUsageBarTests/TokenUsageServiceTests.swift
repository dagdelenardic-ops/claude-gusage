import XCTest
@testable import ClaudeUsageBar

@MainActor
final class TokenUsageServiceTests: XCTestCase {
    private func makeDirs() -> (projects: URL, storeFile: URL) {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tus-\(UUID().uuidString)")
        let projects = base.appendingPathComponent("projects")
        try? FileManager.default.createDirectory(at: projects.appendingPathComponent("Proj"),
                                                 withIntermediateDirectories: true)
        return (projects, base.appendingPathComponent("token-usage.json"))
    }

    func testRefreshParsesAndSummarizes() async throws {
        let (projects, storeFile) = makeDirs()
        let jsonl = projects.appendingPathComponent("Proj/session.jsonl")
        let line = #"{"type":"assistant","timestamp":"2026-07-12T08:00:00Z","cwd":"/Users/x/Proj","requestId":"r","message":{"id":"m","model":"claude-opus-4-8","usage":{"input_tokens":1000000,"output_tokens":1000000}}}"#
        try (line + "\n").write(to: jsonl, atomically: true, encoding: .utf8)

        let svc = TokenUsageService(projectsDir: projects, storeFileURL: storeFile)
        await svc.refresh()

        XCTAssertNotNil(svc.hasData)
        let sum = svc.summary(for: .all)
        XCTAssertEqual(sum.counts.total, 2_000_000)
        XCTAssertEqual(sum.cost, 90.0, accuracy: 0.001)
    }

    func testRefreshIsIncrementalAndPersists() async throws {
        let (projects, storeFile) = makeDirs()
        let jsonl = projects.appendingPathComponent("Proj/session.jsonl")
        let l1 = #"{"type":"assistant","timestamp":"2026-07-12T08:00:00Z","cwd":"/P","requestId":"r1","message":{"id":"m1","model":"claude-sonnet-5","usage":{"input_tokens":10}}}"#
        try (l1 + "\n").write(to: jsonl, atomically: true, encoding: .utf8)

        let svc = TokenUsageService(projectsDir: projects, storeFileURL: storeFile)
        await svc.refresh()

        // Reload from disk in a fresh service; the cursor should prevent re-counting.
        let svc2 = TokenUsageService(projectsDir: projects, storeFileURL: storeFile)
        await svc2.refresh()
        XCTAssertEqual(svc2.summary(for: .all).counts.total, 10)
    }
}
