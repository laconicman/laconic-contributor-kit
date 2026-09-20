import Foundation

/// Strips a review body down to its prose, so "is this body empty?" can be answered
/// without reading meaning.
///
/// This exists because **empty review bodies are the common case, not an edge case**.
/// One field round produced six review bodies of which four were badge markup only —
/// zero characters after stripping HTML comments and the `<picture>` block. Listing
/// those as obligations lists four no-ops.
public struct BoilerplateStripper: Sendable {
    private let blocks: [(open: String, close: String)]
    private let linePatterns: [NSRegularExpression]

    public init(settings: Configuration.InboundSettings) throws {
        self.blocks = settings.boilerplateBlocks.compactMap { spec in
            let parts = spec.components(separatedBy: "...")
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            return (parts[0], parts[1])
        }
        self.linePatterns = try settings.boilerplatePatterns.map {
            try NSRegularExpression(pattern: $0)
        }
    }

    public func prose(of body: String) -> String {
        var text = body
        for block in blocks {
            text = Self.removeBlocks(from: text, open: block.open, close: block.close)
        }
        let kept = text.components(separatedBy: .newlines).filter { line in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            return !linePatterns.contains { $0.firstMatch(in: line, range: range) != nil }
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Non-greedy, repeated, and tolerant of an unclosed opener: a body that opens
    /// `<!--` and never closes it is all boilerplate from there on.
    private static func removeBlocks(from text: String, open: String, close: String) -> String {
        var out = ""
        var rest = Substring(text)
        while let start = rest.range(of: open) {
            out += rest[..<start.lowerBound]
            guard let end = rest[start.upperBound...].range(of: close) else { return out }
            rest = rest[end.upperBound...]
        }
        return out + rest
    }
}
