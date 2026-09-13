import Foundation

/// A **recorded** acknowledgement — a pointer to where the content was absorbed.
///
/// TASK §12.10 settles the model and left the mechanics open: which forms of pointer
/// the tool accepts, and whether it verifies them. Settled here:
///
/// - Four forms — `comment:`, `commit:`, `pr-body`, `none:<reason>`. The last is the
///   *"no action needed, because …"* §12.10 names explicitly; it demands a reason, so
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
    /// item by itself — the hash is doing real work, not belt-and-braces (§13.4).
    public var bodySha256AtAck: String
    public var verified: Bool
    public var verificationNote: String

    public init(
        kind: Kind, pointer: String, at: Date = Date(),
        bodySha256AtAck: String, verified: Bool, verificationNote: String
    ) {
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

/// Parses and checks `--with <pointer>`.
public struct AcknowledgementParser: Sendable {
    /// Ids present in the fetch this run, for the free existence check on `comment:`.
    public let knownCommentIDs: Set<String>
    /// Resolves a git object, or `nil` when there is no repository to ask.
    public let resolveCommit: (@Sendable (String) async -> Bool)?

    public init(
        knownCommentIDs: Set<String>,
        resolveCommit: (@Sendable (String) async -> Bool)? = nil
    ) {
        self.knownCommentIDs = knownCommentIDs
        self.resolveCommit = resolveCommit
    }

    public func parse(_ raw: String, bodySha256: String) async throws -> Acknowledgement {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let separator = trimmed.firstIndex(of: ":") else {
            guard trimmed == "pr-body" else { throw AcknowledgementError.unparsable(raw) }
            return Acknowledgement(
                kind: .prBody, pointer: "pr-body", bodySha256AtAck: bodySha256,
                verified: false,
                verificationNote: "a PR description edit is not checkable from here")
        }
        let scheme = String(trimmed[..<separator])
        let value = String(trimmed[trimmed.index(after: separator)...])
            .trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { throw AcknowledgementError.emptyPointer(raw) }

        switch scheme {
        case "comment":
            // Accept a bare fragment or a full permalink; the id is the fragment.
            let id = value.split(separator: "#").last.map(String.init) ?? value
            let known = knownCommentIDs.contains(id)
            return Acknowledgement(
                kind: .comment, pointer: id, bodySha256AtAck: bodySha256,
                verified: known,
                verificationNote: known
                    ? "id present in this run's fetch"
                    : "id not in this run's fetch — recorded unverified")
        case "commit":
            let looksLikeSHA =
                value.count >= 7 && value.count <= 40
                && value.allSatisfy { $0.isHexDigit }
            guard looksLikeSHA else { throw AcknowledgementError.notASHA(value) }
            let resolved = await resolveCommit?(value)
            return Acknowledgement(
                kind: .commit, pointer: value, bodySha256AtAck: bodySha256,
                verified: resolved == true,
                verificationNote: resolved == nil
                    ? "no local repository to resolve it against — recorded unverified"
                    : (resolved! ? "resolves in the local repository" : "does not resolve locally"))
        case "none":
            return Acknowledgement(
                kind: .none, pointer: value, bodySha256AtAck: bodySha256,
                verified: true,
                verificationNote: "explicit no-action, reason recorded")
        default:
            throw AcknowledgementError.unknownKind(scheme)
        }
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
