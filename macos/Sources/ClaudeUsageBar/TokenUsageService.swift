import Foundation
import Combine
import AppKit

/// Pure file-reading helper: returns newly-appended, newline-complete bytes.
enum TokenUsageReader {
    static func readAppended(
        path: String,
        cursor: FileCursor?,
        fileManager: FileManager = .default
    ) -> (data: Data, cursor: FileCursor)? {
        guard
            let attrs = try? fileManager.attributesOfItem(atPath: path),
            let size = (attrs[.size] as? NSNumber)?.intValue,
            let mtime = attrs[.modificationDate] as? Date
        else { return nil }

        var start = cursor?.offset ?? 0
        if start > size { start = 0 }                 // truncated / rotated
        if start == size { return (Data(), FileCursor(offset: size, mtime: mtime)) }

        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        try? handle.seek(toOffset: UInt64(start))
        let chunk = (try? handle.readToEnd()) ?? Data()

        // Consume only up to the last newline; leave a partial trailing line for next time.
        guard let lastNL = chunk.lastIndex(of: UInt8(ascii: "\n")) else {
            return (Data(), cursor ?? FileCursor(offset: start, mtime: mtime))
        }
        let end = chunk.index(after: lastNL)
        let consumed = chunk[chunk.startIndex..<end]
        return (Data(consumed), FileCursor(offset: start + consumed.count, mtime: mtime))
    }
}

@MainActor
final class TokenUsageService: ObservableObject {
    @Published private(set) var hasData = false
    @Published private(set) var isScanning = false
    @Published private(set) var lastUpdated: Date?

    private var store = TokenUsageStore()
    private let projectsDir: URL
    private let storeFileURL: URL
    private let pricing: TokenPricing
    private let calendar: Calendar

    init(
        projectsDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true),
        storeFileURL: URL = TokenUsageService.defaultStoreURL,
        pricing: TokenPricing = TokenPricing(),
        calendar: Calendar = .current
    ) {
        self.projectsDir = projectsDir
        self.storeFileURL = storeFileURL
        self.pricing = pricing
        self.calendar = calendar
        loadStore()
    }

    // `nonisolated` so it can serve as a default-argument value for `init`
    // (default arguments are evaluated in a nonisolated context). It only reads
    // `FileManager.default`, so it touches no main-actor state.
    nonisolated static var defaultStoreURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-usage-bar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("token-usage.json")
    }

    /// Compute a summary for a range from the in-memory store.
    func summary(for range: UsageRange, now: Date = Date()) -> UsageSummary {
        UsageSummary.compute(from: store, range: range, now: now,
                             calendar: calendar, pricing: pricing)
    }

    /// Scan the projects dir, incrementally read new bytes, ingest, persist.
    func refresh() async {
        guard FileManager.default.fileExists(atPath: projectsDir.path) else {
            hasData = false
            return
        }
        isScanning = true
        defer { isScanning = false }

        let dir = projectsDir
        let base = store
        // Heavy work off the main actor. `scan` takes the store by value and
        // returns the mutated copy, so nothing crosses the actor boundary by
        // reference (see the plan's concurrency note on the `inout` capture).
        let updated = await Task.detached(priority: .utility) {
            Self.scan(dir: dir, base: base)
        }.value

        store = updated
        hasData = !store.buckets.isEmpty
        lastUpdated = Date()
        saveStore()
    }

    /// Walk *.jsonl files, read appended bytes, parse, and ingest into a copy of
    /// the store, returning the mutated copy.
    nonisolated private static func scan(dir: URL, base: TokenUsageStore) -> TokenUsageStore {
        var working = base
        let fm = FileManager.default
        guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return working }
        for case let url as URL in en where url.pathExtension == "jsonl" {
            let path = url.path
            guard let (data, cursor) = TokenUsageReader.readAppended(path: path, cursor: working.cursors[path]) else { continue }
            working.cursors[path] = cursor
            guard !data.isEmpty else { continue }
            for record in ClaudeLogParser.parseLines(data) {
                working.ingest(record)   // uses Calendar.current for day bucketing
            }
        }
        return working
    }

    private func loadStore() {
        guard let data = try? Data(contentsOf: storeFileURL) else { return }
        do {
            store = try JSONDecoder.tokenDecoder.decode(TokenUsageStore.self, from: data)
            hasData = !store.buckets.isEmpty
        } catch {
            let backup = storeFileURL.deletingPathExtension().appendingPathExtension("bak.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: storeFileURL, to: backup)
            store = TokenUsageStore()
        }
    }

    private func saveStore() {
        guard let data = try? JSONEncoder.tokenEncoder.encode(store) else { return }
        try? data.write(to: storeFileURL, options: .atomic)
    }
}

private extension JSONDecoder {
    static let tokenDecoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
}
private extension JSONEncoder {
    static let tokenEncoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
}
