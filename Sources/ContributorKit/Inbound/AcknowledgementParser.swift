import Foundation

/// Parses and checks `--with <pointer>`.
public struct AcknowledgementParser: Sendable {
    /// Ids present in the fetch this run, for the free existence check on `comment:`.
    public let knownCommentIDs: Set<String>
    /// The `owner/repo` being audited — `authored` is repository-scoped, so a
    /// subject URL only resolves to a body id when it names this repository.
    public let repository: String?
    /// Resolves a git object, or `nil` when there is no repository to ask.
    public let resolveCommit: (@Sendable (String) async -> Bool)?

    public init(
        knownCommentIDs: Set<String>,
        repository: String? = nil,
        resolveCommit: (@Sendable (String) async -> Bool)? = nil
    ) {
        self.knownCommentIDs = knownCommentIDs
        self.repository = repository
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
            var id = value.split(separator: "#").last.map(String.init) ?? value
            // A fragmentless URL to the subject itself — `…/issues/3`, `…/pull/7` —
            // names the body item, whose synthesized id is what `authored` holds when
            // the subject is mine. The URL must name THIS repository: `authored` is
            // repo-scoped, so a foreign `…/issues/3` resolving to `issue-3` would
            // verify a pointer at a different repository entirely.
            if !value.contains("#"), let repository {
                let tail = Array(value.split(separator: "/").suffix(4))
                if tail.count == 4,
                    "\(tail[0])/\(tail[1])".caseInsensitiveCompare(repository) == .orderedSame,
                    let number = Int(tail[3])
                {
                    if tail[2] == "issues" { id = "issue-\(number)" }
                    if tail[2] == "pull" || tail[2] == "pulls" { id = "pullrequest-\(number)" }
                }
            }
            let known = knownCommentIDs.contains(id)
            return Acknowledgement(
                kind: .comment, pointer: id, bodySha256AtAck: bodySha256,
                verified: known,
                verificationNote: known
                    ? "id is in the snapshot"
                    : "id is not in the snapshot for this repository")
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
