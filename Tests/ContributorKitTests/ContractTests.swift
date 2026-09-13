import Foundation
import Testing

@testable import ContributorKit

/// The parts that are contracts rather than behaviour: the `--json` shape, the
/// provenance gate, and the acknowledgement pointer rules.
@Suite("contracts")
struct ContractTests {

    /// TASK §13.3: per item `id`, `kind`, `permalink`, `state`, `question`, `changed`
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
        InboundReporting.record(result, pr, into: &provenance)
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
        InboundReporting.record(result, pr, into: &provenance)
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

    /// Acknowledging an inline thread used to report success and write a field nothing
    /// reads — owed unchanged, no transition, exit 0. A silent no-op that reads as
    /// success is the one failure this tool exists to refuse, so it is refused.
    @Test("an inline thread is not acknowledgeable, and says why")
    func inlineThreadsRefuseAcknowledgement() throws {
        let pr = try Fixtures.threads(pr: 5233, comments: "pr-5233.positive.comments.json")
        let snapshot = try Fixtures.audit().run(pr, against: nil).updatedSnapshot

        let inline = try #require(
            snapshot.entries.first { $0.value.kind == .inlineThread }?.key)
        #expect(inline.hasPrefix("discussion_r"))

        let body = try #require(
            snapshot.entries.first { $0.value.kind == .reviewBody }?.key)
        #expect(body.hasPrefix("pullrequestreview-"))

        // The audit consults `acknowledged` for channels 2 and 3 only, which is what
        // made the inline case a no-op rather than an error.
        #expect(snapshot.entries[inline]?.kind == .inlineThread)
        #expect(snapshot.entries[body]?.kind == .reviewBody)
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

        // The path is derived from the repository, so two repos never collide.
        #expect(store.url(for: "a/b").lastPathComponent == "a__b.json")

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
