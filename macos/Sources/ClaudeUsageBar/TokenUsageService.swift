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
