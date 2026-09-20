import Foundation

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
