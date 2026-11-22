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
    /// What the refresh fetch carried about the subject description's edit
    /// history — the only evidence `pr-body` may verify against (issue #17).
    /// `nil` means no fetch supplied it; the parser itself never goes anywhere.
    public let descriptionEvidence: DescriptionEvidence?

    public init(
        knownCommentIDs: Set<String>,
        repository: String? = nil,
        resolveCommit: (@Sendable (String) async -> Bool)? = nil,
        descriptionEvidence: DescriptionEvidence? = nil
    ) {
        self.knownCommentIDs = knownCommentIDs
        self.repository = repository
        self.resolveCommit = resolveCommit
        self.descriptionEvidence = descriptionEvidence
    }

    /// The description-edit evidence `pr-body` verification is allowed to see:
    /// the subject's `userContentEdits` from the refresh fetch, whether the
    /// list was cut at 100, and who "me" is — `--me` when given, else the
    /// fetch's own `viewer.login`. `edits` is `nil` when the fetch never
    /// carried the connection — absent history is "not checked", not "no
    /// edits".
    public struct DescriptionEvidence: Sendable {
        public var edits: [DescriptionEdit]?
        public var truncated: Bool
        public var me: String?

        public init(edits: [DescriptionEdit]?, truncated: Bool, me: String?) {
            self.edits = edits
            self.truncated = truncated
            self.me = me
        }
    }

    public func parse(
        _ raw: String, bodySha256: String, askLastMoved: Date? = nil
    ) async throws -> Acknowledgement {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let separator = trimmed.firstIndex(of: ":") else {
            guard trimmed == "pr-body" else { throw AcknowledgementError.unparsable(raw) }
            return prBody(bodySha256: bodySha256, askLastMoved: askLastMoved)
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
            if !value.contains("#"), let repository,
                let subjectID = Self.subjectBodyID(of: value, in: repository)
            {
                id = subjectID
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
            // The hint `contrib in` prints is runnable as printed, placeholder
            // included — and a `none` with no reason would clear an ask nobody read.
            // A reason has at least one letter or digit; `…`, `...`, `???` and
            // every other run of punctuation is the placeholder's shape, not a reason.
            // Listing the placeholder's own characters was tried first and left `?`
            // through (review of #14).
            guard value.contains(where: { $0.isLetter || $0.isNumber })
            else { throw AcknowledgementError.placeholderReason(raw) }
            return Acknowledgement(
                kind: .none, pointer: value, bodySha256AtAck: bodySha256,
                verified: true,
                verificationNote: "explicit no-action, reason recorded")
        default:
            throw AcknowledgementError.unknownKind(scheme)
        }
    }

    /// `pr-body` is verified only by evidence the refresh fetch already carried
    /// (issue #17): an edit of the subject's description **by me**, strictly
    /// later than the acknowledged item last moved — the same threshold an asker
    /// reply is held to (68e1e55). `lastEditedAt` + `editor` describe only the
    /// LAST edit, and a bot re-appending its badge would mask mine, so the
    /// latest of *my* edits decides, wherever it sits in the list. Verified
    /// means "an edit by me exists after the ask last moved" — never "the edit
    /// says what was asked", the same level `commit:` = "resolves locally"
    /// claims. Every shortfall records unverified with the reason, because
    /// `verified` must never mean "we did not look".
    private func prBody(bodySha256: String, askLastMoved: Date?) -> Acknowledgement {
        func record(_ verified: Bool, _ note: String) -> Acknowledgement {
            Acknowledgement(
                kind: .prBody, pointer: "pr-body", bodySha256AtAck: bodySha256,
                verified: verified, verificationNote: note)
        }
        guard let evidence = descriptionEvidence else {
            return record(
                false,
                "not checked — re-run with --refresh to check the description's edit history")
        }
        guard let edits = evidence.edits else {
            return record(
                false, "not checked — the fetch carried no description edit history")
        }
        guard let me = evidence.me else {
            return record(
                false, "not checked — the fetch did not name the viewer; pass --me")
        }
        guard let askLastMoved, askLastMoved != .distantPast else {
            return record(false, "not checked — this item's own time is unknown")
        }
        let mine = edits.filter { edit in
            edit.editor.map { Login.same($0, me) } ?? false
        }
        let latest = mine.map(\.editedAt).max()
        if let latest, latest > askLastMoved {
            return record(
                true,
                "the description has an edit by \(me) at \(GitHubTime.string(latest)), "
                    + "later than this item — that it was edited, not what the edit says")
        }
        let truncated =
            evidence.truncated ? " — only 100 edits were read, and there are more" : ""
        guard let latest else {
            return record(false, "the description has no edit by \(me)\(truncated)")
        }
        return record(
            false,
            "the latest description edit by \(me) (\(GitHubTime.string(latest))) "
                + "is not later than this item (\(GitHubTime.string(askLastMoved)))\(truncated)")
    }

    /// The synthesized body id a subject URL names, or `nil` when the value is not
    /// exactly `<scheme>://<host>/<owner>/<repo>/(issues|pull|pulls)/<number>` for
    /// `repository`. The whole path is matched, not a suffix of it: a longer path
    /// that merely ends in `o/r/issues/3` — a `blob` URL elsewhere, say — names a
    /// different resource. The host is not checked because `owner/repo` says
    /// nothing about it (github.com or an enterprise host).
    static func subjectBodyID(of value: String, in repository: String) -> String? {
        guard let url = URL(string: value),
            let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
            url.host != nil
        else { return nil }
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard segments.count == 4,
            "\(segments[0])/\(segments[1])".caseInsensitiveCompare(repository) == .orderedSame,
            segments[3].allSatisfy(\.isNumber), let number = Int(segments[3])
        else { return nil }
        switch segments[2] {
        case "issues": return "issue-\(number)"
        case "pull", "pulls": return "pullrequest-\(number)"
        default: return nil
        }
    }
}
