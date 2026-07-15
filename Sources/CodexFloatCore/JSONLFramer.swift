import Foundation

/// Incremental JSONL splitter for app-server stdio streams.
public struct JSONLFramer: Sendable {
    private var buffer = Data()

    public init() {}

    /// Append raw bytes and return complete UTF-8 lines (without trailing newlines).
    public mutating func push(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        buffer.append(data)
        return drainCompleteLines()
    }

    /// Flush any remaining buffered content as a final line if non-empty.
    public mutating func finish() -> [String] {
        guard !buffer.isEmpty else { return [] }
        defer { buffer.removeAll(keepingCapacity: false) }
        if let line = String(data: buffer, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
            .nilIfEmpty
        {
            return [line]
        }
        return []
    }

    private mutating func drainCompleteLines() -> [String] {
        var lines: [String] = []
        while let range = buffer.range(of: Data([0x0A])) {
            let slice = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)
            if slice.last == 0x0D {
                // strip CR from CRLF
                let trimmed = slice.dropLast()
                if let line = String(data: trimmed, encoding: .utf8)?.nilIfEmpty {
                    lines.append(line)
                }
            } else if let line = String(data: slice, encoding: .utf8)?.nilIfEmpty {
                lines.append(line)
            }
        }
        return lines
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
