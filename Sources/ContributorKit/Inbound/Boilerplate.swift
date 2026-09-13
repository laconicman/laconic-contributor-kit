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

/// Does the stripped prose retract the item? Matched case-insensitively.
public struct SupersessionDetector: Sendable {
    public let phrases: [String]

    public init(phrases: [String]) {
        self.phrases = phrases.map { $0.lowercased() }
    }

    public func supersedes(_ prose: String) -> String? {
        let haystack = prose.lowercased()
        return phrases.first { haystack.contains($0) }
    }
}

/// Did the *asker* declare this comment a note rather than a request?
///
/// Patterns are matched against the **raw body**, not the stripped prose, because the
/// most reliable signal is a machine-readable marker the reviewer emits inside an HTML
/// comment — which stripping removes. A second pass over the stripped prose catches the
/// fixed-phrase cases (a bot's "Starting …" announcement).
public struct InformationalDetector: Sendable {
    private let patterns: [NSRegularExpression]
    public let sources: [String]

    public init(patterns: [String]) throws {
        self.sources = patterns
        self.patterns = try patterns.map {
            try NSRegularExpression(pattern: $0, options: [.anchorsMatchLines])
        }
    }

    public func isInformational(raw: String, prose: String) -> String? {
        for (index, regex) in patterns.enumerated() {
            for text in [raw, prose] {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                if regex.firstMatch(in: text, range: range) != nil { return sources[index] }
            }
        }
        return nil
    }
}
