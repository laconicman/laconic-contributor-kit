import Foundation
import Testing

@testable import ContributorKit

/// <doc:Design>, day one: the regression test with a known answer.
///
/// Every figure asserted here comes from `manifest.json`, which `make_manifest.py`
/// derived from 13 `cloc` documents captured twice and compared byte-for-byte.
@Suite("contrib loc — against the measured fixtures")
struct LocTests {

    @Test("every fixture's four sections decode exactly as captured")
    func decodesEverySection() async throws {
        let manifest = try Fixtures.manifest()
        #expect(manifest.fixtures.count == 13, "the fixture set is 13 cloc documents")

        for fixture in manifest.fixtures {
            let byFile = fixture.kind.hasSuffix("by-file")
            let document = try ClocDocument(
                json: try Fixtures.data(fixture.file), keySpace: byFile ? .path : .language)
            let stats = document.stats

            #expect(stats.added == fixture.cloc.added, "\(fixture.file) added")
            #expect(stats.removed == fixture.cloc.removed, "\(fixture.file) removed")
            #expect(stats.modified == fixture.cloc.modified, "\(fixture.file) modified")
            #expect(stats.net == fixture.net, "\(fixture.file) net")
        }
    }

    /// The headline row: `tls-restart` branch total, added/removed/modified code
    /// 107 / 82 / 35 and comment 109 / 0 / 8, netting code +25, comment +109, blank +21.
    @Test("tls-restart branch total reproduces the Design article's net figures")
    func tlsRestartBranchTotal() async throws {
        let runner = try Fixtures.clocRunner("cloc/tls-restart.branch.json")
        let document = try await Fixtures.cloc(runner).diff(
            refA: "2ba80f1ed", refB: "fix/tls-restart-no-listener-reports-success",
            options: .init(languages: ["C", "C/C++ Header", "Objective-C"]),
            cwd: URL(fileURLWithPath: "."))

        #expect(document.stats.added == Counts(code: 107, comment: 109, blank: 21))
        #expect(document.stats.removed == Counts(code: 82, comment: 0, blank: 0))
        #expect(document.stats.modified == Counts(code: 35, comment: 8, blank: 0))
        #expect(document.stats.net == Counts(code: 25, comment: 109, blank: 21))
        // Proof the code actually reached the subprocess seam rather than reading a
        // file directly — the check must be able to fail for the right reason.
        #expect(runner.calls.count == 1)
        #expect(runner.unusedRecordings.isEmpty)
    }

    /// **Gross churn deliberately does not agree with <doc:Design> and must not be asserted
    /// against it.** <doc:Design>'s heuristic gave `+148 −123`; cloc splits the same edits into
    /// 107 added, 82 removed and 35 modified in place. Same net, truer churn.
    @Test("net agrees with the the Design article heuristic; gross is asserted only against cloc")
    func netAgreesGrossDoesNot() throws {
        let manifest = try Fixtures.manifest()
        for fixture in manifest.fixtures {
            guard let heuristic = fixture.heuristic else { continue }
            let agrees =
                fixture.net.code == heuristic.code && fixture.net.comment == heuristic.comment
            #expect(
                agrees == (fixture.agrees ?? false),
                "\(fixture.file): manifest records agrees=\(fixture.agrees ?? false)")
        }
    }

    /// The one fixture that disagrees, and that is the point: <doc:Design>'s awk heuristic files
    /// two `*p_min = …;` dereferences as comments. The manifest carries both figures.
    @Test("darwin-tls is code +32 / comment +30 — deliberately not the Design article's +30/+32")
    func darwinTlsDisagreesWithTheHeuristic() throws {
        let manifest = try Fixtures.manifest()
        let fixture = try #require(
            manifest.fixtures.first { $0.file == "cloc/darwin-tls.branch.json" })
        #expect(fixture.net == Counts(code: 32, comment: 30, blank: 8))
        #expect(fixture.heuristic?.code == 30)
        #expect(fixture.heuristic?.comment == 32)
        #expect(fixture.agrees == false)
    }

    @Test("--ignore-whitespace moves modified code 35 → 20 with net unchanged at +25")
    func ignoreWhitespaceCorrection() throws {
        let manifest = try Fixtures.manifest()
        let plain = try #require(
            manifest.fixtures.first { $0.file == "cloc/tls-restart.branch.json" })
        let corrected = try #require(
            manifest.fixtures.first { $0.file == "cloc/tls-restart.branch.ignore-ws.json" })
        #expect(plain.cloc.modified.code == 35)
        #expect(corrected.cloc.modified.code == 20)
        #expect(plain.net.code == corrected.net.code)
        #expect(plain.net.code == 25)
    }

    /// Commit `56e706f7d` is `code −33 / comment +21`. A ratio field there prints
    /// `−0.64`, which is worse than printing nothing (<doc:Design>).
    @Test("the comment-to-code ratio is suppressed when net code ≤ 0")
    func ratioSuppressedOnNegativeNetCode() throws {
        let document = try ClocDocument(
            json: try Fixtures.data("cloc/tls-restart.commit-03-56e706f7d.json"),
            keySpace: .language)
        #expect(document.stats.net.code == -33)
        #expect(document.stats.net.comment == 21)
        #expect(document.stats.commentToCodeRatio == nil)

        let positive = try ClocDocument(
            json: try Fixtures.data("cloc/tls-restart.commit-01-5ba09a23f.json"),
            keySpace: .language)
        #expect(positive.stats.commentToCodeRatio == 1.2)
    }

    /// Per-commit figures do not sum to the branch total and must never be presented as
    /// a check on it: commits re-touch the same lines, so the per-commit added comments
    /// sum to 121 against a branch total of 109 (added code 172 against 107).
    @Test("per-commit figures deliberately do not sum to the branch total")
    func perCommitDoesNotSumToBranch() throws {
        let manifest = try Fixtures.manifest()
        let commits = manifest.fixtures.filter { $0.kind == "commit" }
        #expect(commits.count == 7)
        let addedCode = commits.reduce(0) { $0 + $1.cloc.added.code }
        let addedComment = commits.reduce(0) { $0 + $1.cloc.added.comment }
        let branch = try #require(
            manifest.fixtures.first { $0.file == "cloc/tls-restart.branch.json" })
        #expect(addedCode == 172)
        #expect(addedComment == 121)
        #expect(branch.cloc.added.code == 107)
        #expect(branch.cloc.added.comment == 109)
    }

    /// `SUM` is a sibling key inside every section, not a separate top-level object.
    /// Reading it while iterating doubles every total.
    @Test("SUM is skipped, so totals do not double")
    func sumKeyIsSkipped() throws {
        let document = try ClocDocument(
            json: try Fixtures.data("cloc/darwin-tls.branch.json"), keySpace: .language)
        #expect(document.sections["added"]?.keys.contains("SUM") == false)
        #expect(document.stats.added.code == 58)
    }

    /// cloc exits 0 and emits an empty document when a range touches nothing it
    /// recognises. A decoder that reports zeroes there is a check that passes because
    /// it did not run — the field report's rule 5.
    @Test("an empty cloc document is an error, not a row of zeroes")
    func emptyDocumentRefused() {
        #expect(throws: ClocError.self) {
            _ = try ClocDocument(json: Data("{}".utf8), keySpace: .language)
        }
        #expect(throws: ClocError.self) {
            _ = try ClocDocument(
                json: Data(#"{"header":{"cloc_version":"2.06"}}"#.utf8), keySpace: .language)
        }
    }

    /// A three-dot comparison measures from the two refs' **merge base**. Treating it
    /// as two-dot reports everything the base branch gained since the divergence as
    /// branch churn, in reverse.
    @Test("a three-dot range resolves through git merge-base")
    func threeDotRangeUsesMergeBase() async throws {
        let two = try RangeWalker.parseRange("main..feature")
        #expect(two.base == "main" && two.head == "feature")
        #expect(!two.usesMergeBase)

        let three = try RangeWalker.parseRange("main...feature")
        #expect(three.usesMergeBase, "and it is resolved before any cloc call")

        let runner = RecordedCommandRunner([
            .init(match: ["merge-base", "main", "feature"], stdout: Data("abc1234\n".utf8))
        ])
        let walker = RangeWalker(
            repository: URL(fileURLWithPath: "."), runner: runner,
            cloc: Cloc(executable: "cloc", runner: runner))
        let resolved = try await walker.resolved(three)
        #expect(resolved.base == "abc1234")
        #expect(resolved.head == "feature")
        #expect(!resolved.usesMergeBase)
        #expect(runner.unusedRecordings.isEmpty, "merge-base was actually consulted")
    }

    /// A root commit has no `<sha>^`, so `--per-commit` aborted on any range including
    /// one. It is compared against git's empty tree instead — which is what it added.
    ///
    /// The empty-parent field is why this test exists twice over: Swift's `split` drops
    /// empty subsequences by default, so the first version of the fix parsed the root
    /// commit's line into two fields and skipped the commit entirely.
    @Test("a root commit is walked against the empty tree, not an unresolvable parent")
    func rootCommitUsesTheEmptyTree() async throws {
        let log = "aaa1111\u{1f}\u{1f}root commit\nbbb2222\u{1f}aaa1111\u{1f}second\n"
        let runner = RecordedCommandRunner([
            .init(match: ["git", "log", "--reverse"], stdout: Data(log.utf8))
        ])
        let walker = RangeWalker(
            repository: URL(fileURLWithPath: "."), runner: runner,
            cloc: Cloc(executable: "cloc", runner: runner))

        let commits = try await walker.commits(in: .init(base: "x", head: "y"))
        #expect(commits.count == 2, "the root commit is not dropped")
        #expect(commits[0].isRoot)
        #expect(!commits[1].isRoot)
        #expect(RangeWalker.emptyTree == "4b825dc642cb6eb9a060e54bf8d69288fbee4904")
    }

    /// **A rollback must not delete a row this process never wrote.** `O_APPEND` places
    /// a write at the then-current end but reserves nothing, so another process could
    /// append a complete row after `start` was read — and truncating to `start` would
    /// take that row with it. The whole seek/write/rollback is one locked transaction
    /// now, with `start` captured only under the lock.
    @Test("appends are serialised, and a good row survives a neighbour's failure")
    func ledgerAppendsAreSerialised() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ck-ledger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "loc.jsonl")
        let ledger = Ledger(url: url)

        func report(_ ref: String) -> LocReport {
            LocReport(
                repository: "r", refA: "base", refB: ref, capturedAt: Date(),
                languages: ["C"], total: DiffStats(), modifiedCodeIgnoringWhitespace: nil,
                byRole: nil, byPath: nil, commits: nil)
        }

        // Concurrent appends: every row must survive, and every line must be valid JSON.
        DispatchQueue.concurrentPerform(iterations: 8) { i in
            try? ledger.append(report("head-\(i)"))
        }

        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        #expect(lines.count == 8)
        for line in lines {
            #expect(
                (try? JSONSerialization.jsonObject(with: Data(line.utf8))) != nil,
                "every row is whole")
        }
    }

    /// `--include-lang` is ONE argument whose value contains a comma, a slash and a
    /// space. Through `Process` it must be a single element of the argv array.
    @Test("--include-lang is one argv element, never split on spaces")
    func includeLangIsOneArgument() {
        let cloc = Cloc(executable: "cloc", runner: RecordedCommandRunner([]))
        let argv = cloc.argv(
            refA: "a", refB: "b",
            options: .init(
                languages: ["C", "C/C++ Header", "Objective-C"],
                forceLang: [".m": "Objective-C"]))
        #expect(argv.contains("--include-lang=C,C/C++ Header,Objective-C"))
        #expect(argv.contains("--force-lang=Objective-C,m"))
        #expect(argv.filter { $0.hasPrefix("--include-lang") }.count == 1)
    }
}
