import Foundation

/// The small glob subset the role rules need: `*` within a path segment, `**` across
/// segments, everything else literal.
///
/// The one rule worth stating: **a leading `**​/` also matches nothing at all**, so
/// `**/CMakeLists.txt` matches a bare `CMakeLists.txt` at the repo root. Naïve glob
/// matching does not do that, and TASK §3.3 asks for the case to be tested explicitly.
///
/// `@unchecked Sendable`: the only stored reference is an `NSRegularExpression`, which
/// Foundation documents as immutable and safe to use from multiple threads.
public struct Glob: @unchecked Sendable {
    public let pattern: String
    private let regex: NSRegularExpression

    public init(_ pattern: String) throws {
        self.pattern = pattern
        self.regex = try NSRegularExpression(pattern: "^" + Self.regexSource(for: pattern) + "$")
    }

    public func matches(_ path: String) -> Bool {
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return regex.firstMatch(in: path, range: range) != nil
    }

    static func regexSource(for pattern: String) -> String {
        let segments = pattern.split(separator: "/", omittingEmptySubsequences: false)
        var source = ""
        for (index, segment) in segments.enumerated() {
            let isLast = index == segments.count - 1
            if segment == "**" {
                // Trailing `**` consumes the rest; a leading or interior one consumes
                // whole segments *or none*, which is the bare-name case above.
                source += isLast ? ".*" : "(?:.*/)?"
            } else {
                source +=
                    segment
                    .map {
                        $0 == "*"
                            ? "[^/]*" : NSRegularExpression.escapedPattern(for: String($0))
                    }
                    .joined()
                if !isLast { source += "/" }
            }
        }
        return source
    }
}
