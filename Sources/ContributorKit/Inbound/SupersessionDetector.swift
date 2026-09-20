import Foundation

/// Does the stripped prose retract the item? Matched case-insensitively.
public struct SupersessionDetector: Sendable {
    public let phrases: [String]

    public init(phrases: [String]) {
        self.phrases = phrases.map { $0.lowercased() }
    }

    /// A retraction **leads** the body; a mention of one can appear anywhere.
    ///
    /// Matching anywhere meant ordinary prose retracted itself: *"This API was
    /// superseded by `fetchV2`; please update this caller"* classified the whole body as
    /// withdrawn and removed a live request from `owed`. Only the opening lines are
    /// considered, which is where a reviewer that retracts a report puts the notice.
    public func supersedes(_ prose: String) -> String? {
        let opening =
            prose
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .joined(separator: " ")
            .lowercased()
        guard !opening.isEmpty else { return nil }
        return phrases.first { opening.contains($0) }
    }
}
