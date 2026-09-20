import Foundation

/// The three channels <doc:Design> requires. A run that skips review bodies
/// reproduces the original bug: the two historical #5233 misses were both review
/// bodies carrying no inline comment of their own.
public enum Channel: String, Codable, Sendable, CaseIterable {
    case inlineThread = "inline-thread"
    case reviewBody = "review-body"
    case issueComment = "issue-comment"

    public var label: String {
        switch self {
        case .inlineThread: return "inline thread"
        case .reviewBody: return "review body"
        case .issueComment: return "issue comment"
        }
    }

    public var plural: String {
        switch self {
        case .inlineThread: return "inline threads"
        case .reviewBody: return "review bodies"
        case .issueComment: return "issue comments"
        }
    }
}
