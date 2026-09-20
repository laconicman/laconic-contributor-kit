import Foundation
import Testing

@testable import ContributorKit

/// The parts that are contracts rather than behaviour: the `--json` shape, the
/// provenance gate, and the acknowledgement pointer rules.
@Suite("contracts")
struct ContractTests {

    /// <doc:Design>: per item `id`, `kind`, `permalink`, `state`, `question`, `changed`
    /// and the minimum text — **nothing else**. Both failure modes cost the same
    /// thing, so this is pinned as an exact key set rather than a superset.
    @Test("--json emits exactly the seven keys, and no more")
    func jsonContractIsExact() throws {
        let pr = try Fixtures.threads(pr: 5233, comments: "pr-5233.positive.comments.json")
        let result = try Fixtures.audit().run(pr, against: nil)
        var provenance = Provenance(command: "test")
        provenance.examined("items", result.items.count)

        let data = try InboundReporting.json(result, provenance: provenance)
        let document = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(document.keys) == ["provenance", "items"])

        let items = try #require(document["items"] as? [[String: Any]])
        #expect(!items.isEmpty)
        for item in items {
            #expect(
                Set(item.keys) == ["id", "kind", "permalink", "state", "question", "changed", "text"],
                "item \(item["id"] ?? "?")")
            let text = try #require(item["text"] as? [String: Any])
            #expect(Set(text.keys) == ["ask", "reply"])
        }
    }

    /// `changed` is present as `null` rather than absent, so a consumer reads a null
    /// instead of having to tell "key missing" from "nothing changed".
    @Test("changed and reply encode as null, never as an absent key")
    func nullsAreExplicit() throws {
        let item = InboundItem(
            id: "x", kind: .reviewBody, permalink: "u", state: .obligationOpen,
            question: "q", changed: nil, text: .init(ask: "a", reply: nil))
        let object = try #require(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(item))
                as? [String: Any])
        #expect(object["changed"] is NSNull)
        #expect((object["text"] as? [String: Any])?["reply"] is NSNull)
    }

    // MARK: - The provenance gate

    /// A command that recorded no examined counts cannot distinguish "ran and found
    /// nothing" from "did not run", so it raises rather than reporting a clean bill.
    /// The field report's rule 5, enforced rather than documented.
    @Test("a command that examined nothing is an anomaly, not a pass")
    func nothingExaminedIsAnomalous() {
        var empty = Provenance(command: "contrib in")
        empty.finish()
        #expect(empty.hasAnomaly)
        #expect(empty.anomalies.first?.kind == "nothingExamined")

        var examined = Provenance(command: "contrib in")
        examined.examined("inline threads", 0)
        examined.finish()
        #expect(!examined.hasAnomaly, "zero is a finding; no counter at all is not")
    }

    /// **Never trust a truncated fetch.** A connection that still had a next page when
    /// fetching stopped is an anomaly, not a footnote — the 09-04 miss was a truncation
    /// propagating silently into "the round is done".
    @Test("a truncated fetch raises an anomaly")
    func truncationIsAnomalous() throws {
        let pr = PullRequestThreads(
            repository: "o/r", number: 1, title: "", url: "", state: "OPEN", isMerged: false,
            threads: [], reviewBodies: [], issueComments: [], pagesFetched: 50,
            truncatedConnections: ["reviews"])
        let result = try Fixtures.audit().run(pr, against: nil)
        var provenance = Provenance(command: "contrib in")
        InboundReporting.record(result, pr, previous: nil, into: &provenance)
        provenance.finish()
        #expect(provenance.anomalies.contains { $0.kind == "truncatedFetch" })
    }

    /// The fixtures store 120-character excerpts and no full bodies, so boilerplate and
    /// supersession checks see a fragment. Said out loud rather than left to be
    /// discovered — a supersession phrase past character 160 would be invisible.
    @Test("excerpt-only bodies raise an anomaly")
    func excerptBodiesAreAnomalous() throws {
        let pr = try Fixtures.threads(pr: 5234)
        #expect(pr.bodiesAreExcerpts)
        let result = try Fixtures.audit().run(pr, against: nil)
        var provenance = Provenance(command: "contrib in")
        InboundReporting.record(result, pr, previous: nil, into: &provenance)
        #expect(provenance.anomalies.contains { $0.kind == "excerptBodies" })
    }

    // MARK: - Acknowledgements

    @Test("every accepted pointer form parses, and the rest are refused")
    func acknowledgementForms() async throws {
        let parser = AcknowledgementParser(knownCommentIDs: ["issuecomment-1"])
        let hash = SHA256.hex(of: "body")

        let byComment = try await parser.parse("comment:issuecomment-1", bodySha256: hash)
        #expect(byComment.kind == .comment)
        #expect(byComment.verified, "the id is in this run's fetch")

        let byPermalink = try await parser.parse(
            "comment:https://github.com/o/r/pull/1#issuecomment-1", bodySha256: hash)
        #expect(byPermalink.pointer == "issuecomment-1")

        let unknown = try await parser.parse("comment:issuecomment-999", bodySha256: hash)
        #expect(!unknown.verified, "an id we never saw is recorded unverified, not refused")

        let noAction = try await parser.parse("none:pre-existing, not this PR", bodySha256: hash)
        #expect(noAction.kind == .none)
        #expect(noAction.pointer == "pre-existing, not this PR")

        #expect(try await parser.parse("pr-body", bodySha256: hash).kind == .prBody)

        await #expect(throws: AcknowledgementError.self) {
            try await parser.parse("commit:nonsense", bodySha256: hash)
        }
        await #expect(throws: AcknowledgementError.self) {
            try await parser.parse("telepathy:obviously", bodySha256: hash)
        }
        await #expect(throws: AcknowledgementError.self) {
            try await parser.parse("none:", bodySha256: hash)
        }
    }

    /// A commit sha with no repository to resolve it against is recorded **unverified**
    /// rather than assumed good. `verified` must never mean "we did not look".
    @Test("a sha with nothing to resolve it is unverified, not assumed")
    func unresolvableShaIsUnverified() async throws {
        let parser = AcknowledgementParser(knownCommentIDs: [])
        let ack = try await parser.parse("commit:e02b93e1", bodySha256: "h")
        #expect(!ack.verified)
        #expect(ack.verificationNote.contains("no local repository"))
    }

    /// What may be acknowledged. An inline thread is answered by replying in it, so the
    /// only record worth taking there is a responsiveness check on a reply that exists
    /// and has not been confirmed. Anything else would write a record the audit never
    /// reads — which once reported success and changed nothing.
    @Test("acknowledgement eligibility follows the thread's state")
    func acknowledgementEligibility() {
        func entry(_ kind: Channel, _ state: ItemState?) -> Snapshot.Entry {
            Snapshot.Entry(
                kind: kind, url: "u", author: "reviewer", createdAt: Date(),
                updatedAt: nil, lastEditedAt: nil, bodySha256: "h", state: state,
                firstSeen: Date(), myReplyID: "discussion_r2", myReplyAt: Date(),
                acknowledged: nil)
        }
        let allow = { (e: Snapshot.Entry) in AcknowledgementEligibility.refusal(for: e, id: "x") == nil }

        #expect(allow(entry(.reviewBody, .obligationOpen)))
        #expect(allow(entry(.issueComment, .obligationOpen)))
        #expect(allow(entry(.inlineThread, .answeredClaimed)))
        #expect(allow(entry(.inlineThread, .answeredChecked)), "re-checking is allowed")

        #expect(!allow(entry(.inlineThread, .openAsk)), "reply first")
        #expect(!allow(entry(.inlineThread, .editedAfterMyAnswer)), "the check would be stale")
        #expect(!allow(entry(.inlineThread, .answeredConfirmed)), "nothing to record")
        #expect(!allow(entry(.inlineThread, nil)), "state unknown")
    }

    /// **Every state `contrib` can print is in the skill's decision table.** A state
    /// outside it has no defined response, and one — `informational` — sat outside the
    /// table and outside `owed` while it hid two real asks. This fails the build the
    /// next time a state is added without a row.
    @Test("every item state has a row in SKILL.md's decision table")
    func everyStateIsInTheSkillTable() throws {
        let skill = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "plugin/skills/contributions/SKILL.md")
        let text = try String(contentsOf: skill, encoding: .utf8)
        for state in ItemState.allCases {
            #expect(text.contains("| `\(state.rawValue)` |"), "no table row for `\(state.rawValue)`")
        }
    }

    /// **The live decoder must carry the round.** It set `reviewID` to `nil` on every
    /// inline comment while the REST-shaped fixtures populated it, so round grouping was
    /// green in tests and collapsed into one unknown round against the real API.
    ///
    /// `pullRequestReview.databaseId` is the same integer REST calls
    /// `pull_request_review_id` — verified against both APIs on a live pull request.
    @Test("the GraphQL decoder carries the review that held each inline comment")
    func liveDecoderKeepsTheRound() throws {
        let payload = """
            {"data":{"repository":{"issueOrPullRequest":{
              "__typename":"PullRequest","number":1,"title":"t","url":"u",
              "pullRequestState":"OPEN",
              "reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
                {"isResolved":false,"isOutdated":false,"path":"a.swift",
                 "comments":{"pageInfo":{"hasNextPage":false},"nodes":[
                   {"body":"ask","url":"https://github.com/o/r/pull/1#discussion_r1",
                    "createdAt":"2026-09-20T08:00:00Z","viewerDidAuthor":false,
                    "author":{"login":"devin"},
                    "pullRequestReview":{"databaseId":5260120440}}]}}]}}}}}
            """
        let response = try JSONDecoder().decode(
            ThreadDetailResponse.self, from: Data(payload.utf8))
        let node = try #require(
            response.data?.repository?.issueOrPullRequest?.reviewThreads?.nodes?.first?
                .comments?.nodes?.first)
        let comment = try #require(node.remoteComment(channel: .inlineThread))
        #expect(comment.reviewID == "5260120440")
        #expect(comment.id == "discussion_r1")
    }

    // MARK: - Snapshot

    @Test("a snapshot round-trips, and a future schema is refused rather than guessed at")
    func snapshotRoundTrip() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ck-snap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(directory: directory)

        #expect(try store.load(repository: "o/r") == nil, "no snapshot is nil, not empty")

        let pr = try Fixtures.threads(pr: 5234)
        let result = try Fixtures.audit().run(pr, against: nil)
        try store.save(result.updatedSnapshot)

        let reloaded = try #require(try store.load(repository: "pjsip/pjproject"))
        #expect(reloaded.entries.count == result.updatedSnapshot.entries.count)

        // **A path component per name, because `__` was not injective**: `a/b__c` and
        // `a__b/c` are both valid GitHub names and both mapped to `a__b__c.json`, so
        // auditing one could load and then overwrite the other's history.
        #expect(store.url(for: "a/b").pathComponents.suffix(2) == ["a", "b.json"])
        #expect(store.url(for: "a/b__c") != store.url(for: "a__b/c"))

        // And a file naming a different repository is an aliasing bug, not prior state.
        var alias = result.updatedSnapshot
        alias.repository = "someone/else"
        let aliasStore = SnapshotStore(directory: directory)
        try FileManager.default.createDirectory(
            at: aliasStore.url(for: "pjsip/pjproject").deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(alias).write(to: aliasStore.url(for: "pjsip/pjproject"))
        #expect(throws: SnapshotError.self) {
            _ = try aliasStore.load(repository: "pjsip/pjproject")
        }
        try store.save(result.updatedSnapshot)

        var future = result.updatedSnapshot
        future.schemaVersion = Snapshot.currentSchemaVersion + 1
        try store.save(future)
        #expect(throws: SnapshotError.self) {
            _ = try store.load(repository: "pjsip/pjproject")
        }
    }

    // MARK: - The subprocess seam

    /// stdout and stderr are read on separate pipes and never merged. A successful
    /// query returning a diagnostic as its result is the field report's rule 5, case 3.
    @Test("stderr never reaches stdout")
    func streamsAreNotMerged() async throws {
        let runner = SystemCommandRunner()
        let out = try await runner.run(
            ["sh", "-c", "echo out; echo err >&2"], cwd: nil)
        #expect(out.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines) == "out")
        #expect(out.stderrText.trimmingCharacters(in: .whitespacesAndNewlines) == "err")
    }

    /// `cloc` and `gh` both exit 0 on an empty result, and a decoder handed an empty
    /// document reports zeroes rather than an error.
    @Test("exit zero with no output is an error, and a non-zero exit is never silent")
    func executionEvidenceIsRequired() async throws {
        let runner = SystemCommandRunner()
        await #expect(throws: CommandError.self) {
            try await runner.runExpectingOutput(["sh", "-c", "exit 0"], cwd: nil)
        }
        await #expect(throws: CommandError.self) {
            try await runner.runExpectingOutput(["sh", "-c", "echo hi; exit 3"], cwd: nil)
        }
    }

    /// A recorded runner that silently answers "nothing" to a command nobody recorded
    /// is the unexecuted check in miniature.
    @Test("an unrecorded command throws rather than returning empty")
    func unrecordedCommandThrows() async throws {
        let runner = RecordedCommandRunner([
            .init(match: ["--version"], stdout: Data("2.06".utf8))
        ])
        _ = try await runner.run(["cloc", "--version"], cwd: nil)
        await #expect(throws: CommandError.self) {
            try await runner.run(["cloc", "--diff", "a", "b"], cwd: nil)
        }
        #expect(runner.unusedRecordings.isEmpty)
        #expect(runner.calls.count == 2)
    }

    @Test("the counting runner is the evidence that a command actually ran")
    func countingRunner() async throws {
        let counting = CountingCommandRunner(SystemCommandRunner())
        #expect(counting.count == 0)
        _ = try await counting.run(["sh", "-c", "echo hi"], cwd: nil)
        _ = try await counting.run(["sh", "-c", "exit 1"], cwd: nil)
        #expect(counting.count == 2)
        #expect(counting.failures == 1)
    }

    // MARK: - Globs

    @Test("the glob subset behaves at the edges that matter")
    func globEdges() throws {
        #expect(try Glob("**/CMakeLists.txt").matches("CMakeLists.txt"))
        #expect(try Glob("**/CMakeLists.txt").matches("a/b/CMakeLists.txt"))
        #expect(try !Glob("**/CMakeLists.txt").matches("a/CMakeLists.txt.bak"))
        #expect(try Glob("third_party/**").matches("third_party/x/y.c"))
        #expect(try !Glob("third_party/**").matches("a/third_party/x.c"))
        #expect(try Glob("**").matches("anything/at/all"))
        #expect(try Glob("**/*_test.*").matches("src/foo_test.c"))
        #expect(try !Glob("**/*_test.*").matches("src/foo_tests.c"))
        #expect(try Glob("README*").matches("README.md"))
        #expect(try !Glob("README*").matches("docs/README.md"))
        // `.` is a regex metacharacter and must be escaped, or `*.ac` matches `*.bc`.
        #expect(try !Glob("**/*.ac").matches("configure.bc"))
    }
}

/// **Every snapshot a released build has written must still decode.**
///
/// The snapshot is the capability — a state dir holds the round history the differ
/// exists to keep, and the only workaround for a snapshot that will not load is a new
/// state dir, which throws that history away. Adding `authored` as a non-optional
/// property with a default broke every existing state dir on upgrade: synthesized
/// `Decodable` ignores property defaults, so the decode threw `keyNotFound` before the
/// schema-version guard was ever reached, and the error read like a corrupt file.
///
/// One fixture per historical shape, with no real PR data in either. Adding a field to
/// `Snapshot` means adding a fixture here, not only a property.
@Suite("snapshot compatibility")
struct SnapshotCompatibilityTests {

    private func decode(_ name: String) throws -> Snapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            Snapshot.self, from: try Fixtures.data("snapshots/\(name).json"))
    }

    /// Written by builds up to `2709164`: no per-entry `state`, no `authored`.
    @Test("a schema-1 snapshot from before per-entry state decodes")
    func beforeState() throws {
        let snapshot = try decode("schema1-before-state")
        #expect(snapshot.entries.count == 2)
        #expect(snapshot.entries.values.allSatisfy { $0.state == nil })
        #expect(snapshot.authored.isEmpty)
        #expect(snapshot.entries["pullrequestreview-3"]?.acknowledged?.pointer == "1da04eb")
    }

    /// Written by `66576ab` and `273ea8b`: per-entry `state`, no `authored`. This is the
    /// exact shape that crashed on upgrade to `3eaf469`.
    @Test("a schema-1 snapshot from before authored ids decodes")
    func beforeAuthored() throws {
        let snapshot = try decode("schema1-before-authored")
        #expect(snapshot.entries["discussion_r1"]?.state == .answeredClaimed)
        #expect(snapshot.authored.isEmpty)
    }

    /// Decoding an old snapshot must not lose what it held: the next run compares
    /// against it as a real previous round, not as a baseline.
    @Test("an upgraded snapshot is a previous round, not a baseline")
    func upgradedSnapshotIsUsable() throws {
        let previous = try decode("schema1-before-authored")
        let root = RemoteComment(
            id: "discussion_r1", channel: .inlineThread, author: "devin-ai-integration",
            viewerDidAuthor: false, createdAt: GitHubTime.parse("2026-09-10T08:00:00Z")!,
            body: "body", permalink: "https://github.com/o/r/pull/1#discussion_r1")
        let pr = PullRequestThreads(
            repository: "o/r", number: 1, title: "", url: "", state: "OPEN", isMerged: false,
            threads: [RemoteThread(comments: [root])], reviewBodies: [], issueComments: [],
            pagesFetched: 1)

        let result = try Fixtures.audit().run(pr, against: previous)
        let item = try #require(result.items.first)
        #expect(item.isNewToSnapshot == false)
        #expect(item.previousState == .answeredClaimed)
    }
}

/// Round 2 of this repository's own review. Each test fails against the old behaviour.
@Suite("second review round")
struct SecondRoundTests {

    /// **A retraction leads a body; a mention of one can appear anywhere.** Matching
    /// `superseded by` as a substring meant ordinary prose retracted itself and a live
    /// request left `owed`.
    @Test("prose mentioning a supersession is not a retraction")
    func retractionMustLeadTheBody() throws {
        let detector = SupersessionDetector(
            phrases: try Configuration.builtInDefaults().inbound.supersessionPhrases)

        let realRetraction = """
            > [!NOTE]
            > **This report is out of date.** Scroll down for the latest report.

            **Devin Review** found 7 potential issues.
            """
        #expect(detector.supersedes(realRetraction) != nil)

        let liveRequest =
            "This API was superseded by `fetchV2`; please update this caller before merging."
        #expect(detector.supersedes(liveRequest) == nil, "that request is still owed")

        // A retraction phrase buried far down a long body is not a retraction either.
        let buried = "Please add a regression test.\n\n" + String(repeating: "detail\n", count: 20)
            + "\nThis report is out of date."
        #expect(detector.supersedes(buried) == nil)
    }

    /// `a/b__c` and `a__b/c` are both valid GitHub names, and both used to address
    /// `a__b__c.json` — so auditing one could load and overwrite the other's history.
    @Test("snapshot paths cannot alias one another")
    func snapshotPathsAreInjective() {
        let store = SnapshotStore(directory: URL(fileURLWithPath: "/tmp/ck"))
        #expect(store.url(for: "a/b__c") != store.url(for: "a__b/c"))
        #expect(store.url(for: "o/r").pathComponents.suffix(2) == ["o", "r.json"])
    }

    /// Two audits of different pull requests in one repository must not lose each
    /// other's entries: the snapshot is a read-modify-write over the whole file.
    @Test("a locked merge keeps another subject's entries")
    func lockedMergeKeepsOtherSubjects() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ck-lock-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(directory: directory)

        func entry(_ subject: String) -> Snapshot.Entry {
            Snapshot.Entry(
                kind: .inlineThread, url: "u", author: "reviewer", createdAt: Date(),
                updatedAt: nil, lastEditedAt: nil, bodySha256: "h", subject: subject,
                prose: nil, state: .openAsk, firstSeen: Date(),
                myReplyID: nil, myReplyAt: nil, acknowledged: nil)
        }

        // Audit of #1 lands.
        var first = Snapshot(repository: "o/r")
        first.entries["discussion_r1"] = entry("o/r#1")
        try store.withLock(repository: "o/r") { try store.save(first) }

        // Audit of #2 merges rather than replacing.
        try store.withLock(repository: "o/r") {
            var merged = try store.load(repository: "o/r") ?? Snapshot(repository: "o/r")
            merged.entries["discussion_r2"] = entry("o/r#2")
            try store.save(merged)
        }

        let final = try #require(try store.load(repository: "o/r"))
        #expect(final.entries.keys.sorted() == ["discussion_r1", "discussion_r2"])
    }

    /// **Changing the snapshot path must not abandon existing history.** The collision
    /// fix moved snapshots from `<dir>/<owner>__<repo>.json` to a path component per
    /// name, which silently turned every existing state directory into a fresh baseline
    /// — the same class as the upgrade crash the first round found, one layer up.
    @Test("a snapshot written at the legacy path is read and then migrated")
    func legacySnapshotPathMigrates() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ck-migrate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(directory: directory)

        var old = Snapshot(repository: "o/r")
        old.entries["discussion_r1"] = Snapshot.Entry(
            kind: .inlineThread, url: "u", author: "reviewer", createdAt: Date(),
            updatedAt: nil, lastEditedAt: nil, bodySha256: "h", subject: "o/r#1",
            prose: nil, state: .openAsk, firstSeen: Date(), myReplyID: nil,
            myReplyAt: nil, acknowledged: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(old).write(to: store.legacyURL(for: "o/r"))

        // Read from the legacy path rather than reported as a first run.
        let loaded = try #require(try store.load(repository: "o/r"))
        #expect(loaded.entries.keys.contains("discussion_r1"))

        // When BOTH files exist they are merged, never chosen between: they can hold
        // different subjects, and preferring one would make the other's pull requests
        // invisible and delete them on the next save.
        var newer = Snapshot(repository: "o/r")
        newer.entries["discussion_r2"] = old.entries["discussion_r1"]
        try FileManager.default.createDirectory(
            at: store.url(for: "o/r").deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try encoder.encode(newer).write(to: store.url(for: "o/r"))
        let both = try #require(try store.load(repository: "o/r"))
        #expect(both.entries.keys.sorted() == ["discussion_r1", "discussion_r2"])

        // And migrated on the next save, without leaving the old file behind.
        try store.save(both)
        #expect(FileManager.default.fileExists(atPath: store.url(for: "o/r").path))
        #expect(!FileManager.default.fileExists(atPath: store.legacyURL(for: "o/r").path))
    }

    /// The old layout could alias, so the legacy path this repository *would* have used
    /// may belong to a different one. That must not make a perfectly good current
    /// snapshot unreadable — the collision is the thing being migrated away from.
    @Test("a legacy file owned by another repository does not block this one")
    func legacyCollisionDoesNotBlockLoad() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ck-collide-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(directory: directory)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // A legacy file at the path `a/b__c` would use, but owned by `a__b/c`.
        try encoder.encode(Snapshot(repository: "a__b/c"))
            .write(to: store.legacyURL(for: "a/b__c"))

        // A perfectly good current snapshot for `a/b__c`.
        var mine = Snapshot(repository: "a/b__c")
        mine.authored = ["discussion_r1"]
        try FileManager.default.createDirectory(
            at: store.url(for: "a/b__c").deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try encoder.encode(mine).write(to: store.url(for: "a/b__c"))

        let loaded = try #require(try store.load(repository: "a/b__c"))
        #expect(loaded.authored == ["discussion_r1"])

        // And saving must not delete the other repository's file.
        try store.save(loaded)
        #expect(FileManager.default.fileExists(atPath: store.legacyURL(for: "a/b__c").path))
    }

    /// **A legacy file that is ours and unreadable must not be silently dropped.** The
    /// previous fix used `try?`, which swallowed malformed JSON, I/O failures and schema
    /// mismatches alike — so an audit would re-baseline over stored history without a
    /// word. Only an established *repository mismatch* is safe to ignore.
    @Test("an unreadable legacy snapshot is an error, not an empty history")
    func unreadableLegacyIsNotSilent() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ck-legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(directory: directory)

        // Ours, but written by a future schema. There is no current-path file.
        var future = Snapshot(repository: "o/r")
        future.schemaVersion = Snapshot.currentSchemaVersion + 1
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(future).write(to: store.legacyURL(for: "o/r"))

        #expect(throws: SnapshotError.self) {
            _ = try store.load(repository: "o/r")
        }

        // Malformed JSON is likewise not an empty history.
        try Data("{ not json".utf8).write(to: store.legacyURL(for: "o/r"))
        #expect(throws: (any Error).self) {
            _ = try store.load(repository: "o/r")
        }

        // A file naming a *different* repository stays ignorable — that is the aliasing
        // the new layout exists to retire.
        try encoder.encode(Snapshot(repository: "someone/else"))
            .write(to: store.legacyURL(for: "o/r"))
        #expect(try store.load(repository: "o/r") == nil)
    }

    /// A commit subject is arbitrary text and `|` ends a Markdown cell.
    @Test("a pipe in a commit subject does not break the table")
    func markdownCellsAreEscaped() {
        #expect(LocReporting.escapedCell("pjsip: fix a|b") == "pjsip: fix a\\|b")
        #expect(LocReporting.escapedCell("no pipes here") == "no pipes here")
        #expect(!LocReporting.escapedCell("multi\nline").contains("\n"))
    }

    /// A subprocess that never launched is the most complete failure there is; counting
    /// only non-zero exits left it out of the tally.
    @Test("a launch failure counts as a failure")
    func launchFailuresAreCounted() async throws {
        let counting = CountingCommandRunner(RecordedCommandRunner([]))
        await #expect(throws: CommandError.self) {
            try await counting.run(["nothing-recorded"], cwd: nil)
        }
        #expect(counting.count == 1)
        #expect(counting.failures == 1, "a throw is a failure, not an absence")
    }

    /// An anomalous run must not become the next run's baseline: a truncated fetch that
    /// saved its partial pages would have the retry treat them as established history.
    @Test("an anomalous run is recognisable before the snapshot is written")
    func anomalyIsKnownBeforeSaving() throws {
        let pr = PullRequestThreads(
            repository: "o/r", number: 1, title: "", url: "", state: "OPEN", isMerged: false,
            threads: [], reviewBodies: [], issueComments: [], pagesFetched: 50,
            truncatedConnections: ["reviews"])
        let result = try Fixtures.audit().run(pr, against: nil)

        var provenance = Provenance(command: "contrib in")
        InboundReporting.record(result, pr, previous: nil, into: &provenance)
        provenance.finish()
        #expect(provenance.hasAnomaly, "and the command skips the save on exactly this")

        // finish() is idempotent, because the command finishes early to make that
        // decision and the emitter finishes again on the way out.
        let anomalies = provenance.anomalies.count
        provenance.finish()
        #expect(provenance.anomalies.count == anomalies)
    }

    /// The baseline is a property of the subject, not the repository: sweeping five
    /// issues in one repo, only the first used to announce a baseline.
    @Test("a first run on a new PR in a known repository says it is a baseline")
    func baselineIsPerSubject() throws {
        let one = PullRequestThreads(
            repository: "o/r", number: 1, title: "", url: "", state: "OPEN", isMerged: false,
            threads: [], reviewBodies: [], issueComments: [], pagesFetched: 1)
        var two = one
        two.number = 2

        let first = try Fixtures.audit().run(one, against: nil)
        var provenance = Provenance(command: "contrib in")
        let second = try Fixtures.audit().run(two, against: first.updatedSnapshot)
        InboundReporting.record(second, two, previous: first.updatedSnapshot, into: &provenance)
        #expect(provenance.notes.contains { $0.contains("o/r#2") && $0.contains("baseline") })
    }
}
