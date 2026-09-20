import Foundation

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
