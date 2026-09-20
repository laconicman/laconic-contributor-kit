import Foundation

/// A **recorded** acknowledgement — a pointer to where the content was absorbed.
///
/// <doc:Design> settles the model and left the mechanics open: which forms of pointer
/// the tool accepts, and whether it verifies them. Settled here:
///
/// - Four forms — `comment:`, `commit:`, `pr-body`, `none:<reason>`. The last is the
///   *"no action needed, because …"* <doc:Design> names explicitly; it demands a reason, so
///   dismissing something still costs a sentence.
/// - **Shape is always checked. Existence is checked only where it is free** — an id
///   already present in the fetch, a sha the local repo can resolve. Never a network
///   call: a verifier that needs the network is a verifier that gets skipped offline,
///   and then `verified` means "we did not look" while reading as "fine".
/// - `verified` is recorded per acknowledgement, and the provenance block prints how
///   many are unverified. That is the difference between a fact and an assumption.
public struct Acknowledgement: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case comment
        case commit
        case prBody = "pr-body"
        case none
    }

    public var kind: Kind
    public var pointer: String
    public var at: Date
    /// The body hash at the moment of acknowledgement. An edit after this re-opens the
    /// item by itself — the hash is doing real work, not belt-and-braces (<doc:Design>).
    public var bodySha256AtAck: String
    public var verified: Bool
    public var verificationNote: String
    /// For an inline thread: the reply of mine the check judged. A later reply makes the
    /// check stale. Optional, so snapshots written before it existed still decode.
    public var replyIDAtAck: String?

    public init(
        kind: Kind, pointer: String, at: Date = Date(),
        bodySha256AtAck: String, verified: Bool, verificationNote: String,
        replyIDAtAck: String? = nil
    ) {
        self.replyIDAtAck = replyIDAtAck
        self.kind = kind
        self.pointer = pointer
        self.at = at
        self.bodySha256AtAck = bodySha256AtAck
        self.verified = verified
        self.verificationNote = verificationNote
    }

    public var rendered: String {
        kind == .none ? "none: \(pointer)" : "\(kind.rawValue):\(pointer)"
    }
}

public enum AcknowledgementError: Error, CustomStringConvertible {
    case unparsable(String)
    case emptyPointer(String)
    case unknownKind(String)
    case notASHA(String)

    public var description: String {
        switch self {
        case .unparsable(let raw):
            return "`\(raw)` is not an acknowledgement — expected comment:<id>, commit:<sha>, pr-body, or none:<reason>"
        case .emptyPointer(let raw):
            return "`\(raw)` has no pointer after the colon"
        case .unknownKind(let scheme):
            return "`\(scheme):` is not a recognised acknowledgement — use comment, commit, pr-body or none"
        case .notASHA(let value):
            return "`\(value)` is not a commit sha (7–40 hex characters)"
        }
    }
}
