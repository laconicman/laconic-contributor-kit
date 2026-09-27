import Foundation

/// Does a reply from the asker's login open with the asker's own resolution verdict?
///
/// Devin Review answers a finding it considers fixed with a reply opening
/// `✅ **Resolved**: <what fixed it>`, carrying no marker. On one repository that held
/// for 92 of 92 verdicts, and for none of the 19 fix-session replies posted under the
/// same login — so the phrase, and only the phrase, tells the two apart. Like a
/// supersession notice, it is a fixed phrase the asker emits about its own comment:
/// declared structure, not a reading of what the reply means. Matched
/// case-insensitively against the stripped prose.
public struct VerdictDetector: Sendable {
    public let phrases: [String]

    public init(phrases: [String]) {
        // An empty phrase would be a prefix of every reply, confirming them all.
        self.phrases = phrases.map { $0.lowercased() }.filter { !$0.isEmpty }
    }

    /// A verdict **opens** the reply; a mention of one can appear anywhere.
    ///
    /// `SupersessionDetector` learned this first: matching anywhere let ordinary prose
    /// that mentioned a retraction phrase retract a live ask. A reply quoting or
    /// discussing the verdict phrase must not confirm anything either.
    public func isVerdict(_ prose: String) -> Bool {
        let opening = prose.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return phrases.contains { opening.hasPrefix($0) }
    }
}
