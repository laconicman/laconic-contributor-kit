import Foundation
import Testing

@testable import ContributorKit

/// `contrib in` against the thread fixtures — <doc:Design>, and the four gaps two live
/// review rounds exposed in the field report.
@Suite("contrib in — three channels, obligations, and the differ")
struct InboundTests {

    // MARK: - The positive and negative cases the definition of done names

    /// #5233 is the positive case. Its two open inline threads — `3948887913` and
    /// `3948887920` — are a use-after-free on OpenSSL below 3.0 that was taking down
    /// two Windows CI jobs, and a doc gap on ownership. Neither was known beforehand;
    /// nothing about the diff would have surfaced either.
    @Test("#5233 positive: two open inline asks, by id")
    func positiveCaseInline() throws {
        let pr = try Fixtures.threads(pr: 5233, comments: "pr-5233.positive.comments.json")
        let result = try Fixtures.audit().run(pr, against: nil)

        let open = result.items.filter { $0.kind == .inlineThread && $0.state == .openAsk }
        #expect(
            open.map(\.id).sorted() == ["discussion_r3948887913", "discussion_r3948887920"])
        #expect(result.examined[.inlineThread] == 24)
        #expect(result.count(of: .answeredClaimed, in: .inlineThread) == 22)
    }

    /// **All three channels, on one PR.** The inline channel is 2 open; the review-body
    /// channel is 8 open obligations, because a review body cannot be replied to and
    /// none of them carries a recorded acknowledgement yet (<doc:Design>). That is the
    /// capability working, not a false positive: the two historical #5233 misses were
    /// both review bodies, and an inline-only run reports this PR as two items rather
    /// than ten.
    @Test("#5233 positive: three channels give ten owed items, not two")
    func positiveCaseAllChannels() throws {
        let pr = try Fixtures.threads(pr: 5233, comments: "pr-5233.positive.comments.json")
        let result = try Fixtures.audit().run(pr, against: nil)

        #expect(result.examined[.inlineThread] == 24)
        #expect(result.examined[.reviewBody] == 8)
        #expect(result.examined[.issueComment] == 5)

        #expect(result.count(of: .openAsk, in: .inlineThread) == 2)
        #expect(result.count(of: .obligationOpen, in: .reviewBody) == 8)
        // Every issue comment on #5233 is ours, so none is an obligation against us.
        #expect(result.ownAuthored[.issueComment] == 5)
        #expect(result.count(of: .obligationOpen, in: .issueComment) == 0)

        #expect(result.owed.count == 10)
    }

    /// #5234 is the negative case in the two channels <doc:Design> measured — and a real one:
    /// every review there carried inline comments with an empty body, so
    /// `pr-5234.reviews.json` is `[]`. A tool that only read review bodies would report
    /// nothing at all for this PR.
    @Test("#5234 negative: no open inline asks, and no review bodies at all")
    func negativeCase() throws {
        let pr = try Fixtures.threads(pr: 5234)
        let result = try Fixtures.audit().run(pr, against: nil)

        #expect(result.examined[.inlineThread] == 10)
        #expect(result.count(of: .openAsk, in: .inlineThread) == 0)
        #expect(result.examined[.reviewBody] == 0)
        #expect(result.count(of: .obligationOpen, in: .reviewBody) == 0)
    }

    /// The third channel is not empty on #5234, and saying so is the point. One of its
    /// two issue comments is the maintainer's; under <doc:Design> that is an obligation until
    /// something is recorded against it, and the CLI does not get to decide whether it
    /// is "really" an ask — that is the meaning question it hands to the model.
    @Test("#5234: the issue-comment channel carries one obligation, ours excluded")
    func negativeCaseIssueComments() throws {
        let pr = try Fixtures.threads(pr: 5234)
        let result = try Fixtures.audit().run(pr, against: nil)

        #expect(result.examined[.issueComment] == 2)
        #expect(result.ownAuthored[.issueComment] == 1)
        let open = result.items.filter {
            $0.kind == .issueComment && $0.state == .obligationOpen
        }
        #expect(open.count == 1)
        #expect(open.first?.author == "sauwming")
        #expect(result.owed.count == 1)
    }

    // MARK: - Gap 2.1: authorship filtering

    /// GitHub records a reply submitted through the review API as a review, so on any
    /// PR where the contributor replies, an unfiltered obligation list is immediately
    /// polluted with their own words. `pr-5233.selfreply.reviews.json` is the captured
    /// eight plus one derived record authored by us.
    @Test("a review body I wrote is never an obligation against me")
    func ownReviewBodyIsNotAnObligation() throws {
        let pr = try Fixtures.threads(
            pr: 5233, comments: "pr-5233.positive.comments.json",
            reviews: "pr-5233.selfreply.reviews.json")
        let result = try Fixtures.audit().run(pr, against: nil)

        #expect(result.examined[.reviewBody] == 9, "all nine are examined and counted")
        #expect(result.ownAuthored[.reviewBody] == 1, "one of them is mine")
        #expect(
            result.count(of: .obligationOpen, in: .reviewBody) == 8,
            "and only the other eight are owed")
        #expect(!result.items.contains { $0.id == "pullrequestreview-5130977999" })
    }

    /// The same filter, with no `--me` and no `viewerDidAuthor`: nothing is mine, so
    /// everything is owed. This is what the unfiltered list looks like, pinned so the
    /// filter cannot quietly stop working.
    @Test("without an author filter the same fixture yields nine obligations")
    func withoutAuthorFilterEverythingIsOwed() throws {
        let pr = try Fixtures.threads(
            pr: 5233, comments: "pr-5233.positive.comments.json",
            reviews: "pr-5233.selfreply.reviews.json", me: "nobody")
        let result = try Fixtures.audit(me: nil).run(pr, against: nil)
        #expect(result.count(of: .obligationOpen, in: .reviewBody) == 9)
    }

    // MARK: - Gap 2.2: empty review bodies are the common case

    /// Four of six bodies in the field round were badge markup only. Counted in the
    /// examined total so the count stays honest; excluded from the worklist, because
    /// <doc:Design>'s argument for noise over silence does not extend to noise that is
    /// definitionally empty.
    @Test("a badge-only review body is counted but not owed")
    func boilerplateOnlyBodyIsNotOwed() throws {
        let config = try Configuration.builtInDefaults()
        let stripper = try BoilerplateStripper(settings: config.inbound)

        let badgeOnly = """
            <!-- devin-review-badge -->
            <picture>
              <source media="(prefers-color-scheme: dark)" srcset="https://example.invalid/d.svg">
              <img src="https://example.invalid/l.svg">
            </picture>

            ---
            """
        #expect(stripper.prose(of: badgeOnly).isEmpty)
        #expect(!stripper.prose(of: badgeOnly + "\nOne real sentence.").isEmpty)
    }

    @Test("an unclosed boilerplate opener swallows the rest rather than leaking it")
    func unclosedBoilerplateBlock() throws {
        let stripper = try BoilerplateStripper(
            settings: try Configuration.builtInDefaults().inbound)
        #expect(stripper.prose(of: "Real prose.\n<!-- never closed").trimmed == "Real prose.")
    }

    // MARK: - The reviewer's own kind marker

    /// **Regression: a declared `kind` must never suppress an inline ask.**
    ///
    /// This kit briefly read Devin Review's `"kind": "analysis"` marker as "a receipt,
    /// not an ask", on a sample of 13 across two repositories that were all 📝 Info
    /// verification notes. On a third repository the same kind carries 🔍 findings —
    /// *"Redirect refusal loses its reason"*, *"Dismissal leaves other work running"* —
    /// and both were hidden from `owed` across roughly ten runs, then found by a human
    /// in the GitHub UI. Devin uses one kind for two purposes.
    ///
    /// The bodies below are the real ones, from `laconicman/YDelivery#28`.
    @Test("an analysis-kind inline finding is owed, marker or no marker")
    func declaredKindNeverSuppressesAnInlineAsk() throws {
        func devinComment(_ id: String, kind: String, title: String) -> RemoteComment {
            RemoteComment(
                id: id, channel: .inlineThread, author: "devin-ai-integration",
                viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
                body: """
                    <!-- devin-review-comment {"id": "X", "kind": "\(kind)"} -->

                    \(title)

                    The body of the finding.
                    """,
                permalink: "https://github.com/o/r/pull/28#\(id)")
        }

        let hidden = [
            devinComment(
                "discussion_r3999579354", kind: "analysis",
                title: "🔍 **Redirect refusal loses its reason**"),
            devinComment(
                "discussion_r3999579379", kind: "analysis",
                title: "🔍 **Dismissal leaves other work running**"),
        ]
        let alwaysOwed = devinComment(
            "discussion_r3999579314", kind: "bug",
            title: "🟡 **Saved-place failures look empty**")

        let result = try Fixtures.audit().run(
            pullRequest(
                threads: (hidden + [alwaysOwed]).map { RemoteThread(comments: [$0]) }),
            against: nil)

        #expect(result.owed.count == 3, "every one of them is an ask")
        #expect(result.items.allSatisfy { $0.state == .openAsk })
        #expect(!result.items.contains { $0.state == .informational })
    }

    /// `informational` applies only where there is no reply relation. An inline thread's
    /// lifecycle is decidable from ids alone, so suppressing one on a marker can only
    /// ever hide a real ask — and it also made the state sticky, surviving replies that
    /// should have moved it to `answered-claimed`.
    @Test("informational never applies to an inline thread")
    func informationalIsChannelTwoAndThreeOnly() throws {
        let announcement = RemoteComment(
            id: "discussion_r1", channel: .inlineThread, author: "devin-ai-integration",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: "Starting Devin Review.",
            permalink: "https://github.com/o/r/pull/1#discussion_r1")
        let inline = try Fixtures.audit().run(
            pullRequest(threads: [RemoteThread(comments: [announcement])]), against: nil)
        #expect(inline.items.first?.state == .openAsk)

        var asIssueComment = announcement
        asIssueComment.channel = .issueComment
        let issue = try Fixtures.audit().run(
            pullRequest(issueComments: [asIssueComment]), against: nil)
        #expect(issue.items.first?.state == .informational)
    }

    /// A bot's run announcement is a fixed phrase, and the only prose left once the
    /// badge is stripped. Matched against the stripped prose rather than the raw body.
    @Test("a bot run announcement is informational, not an obligation")
    func botAnnouncementIsInformational() throws {
        let config = try Configuration.builtInDefaults()
        let detector = try InformationalDetector(
            patterns: config.inbound.informationalPatterns)
        let stripper = try BoilerplateStripper(settings: config.inbound)

        let announcement = """
            Starting Devin Review.

            <!-- devin-review-badge-begin -->
            <a href="https://app.devin.ai/review/o/r/pull/3" target="_blank">
              <picture>
                <img src="https://static.devin.ai/assets/gh-devin-review-light.svg?v=3">
              </picture>
            </a>
            <!-- devin-review-badge-end -->
            """
        let prose = stripper.prose(of: announcement)
        #expect(prose == "Starting Devin Review.")
        #expect(detector.isInformational(raw: announcement, prose: prose) != nil)
    }

    /// **Paired markers must be stripped before generic HTML comments.** Removing
    /// `<!--…-->` first destroys the begin/end pairing and leaves the wrapped block
    /// behind — a bare `<a href=…>` / `</a>` trailing every excerpt, which is what sent
    /// a trial session through `--json` for every single triage.
    @Test("the badge block is removed whole, leaving no anchor residue")
    func badgeBlockLeavesNoResidue() throws {
        let stripper = try BoilerplateStripper(
            settings: try Configuration.builtInDefaults().inbound)
        let body = """
            **Devin Review** found 1 new potential issue.

            <!-- devin-review-badge-begin -->
            <a href="https://app.devin.ai/review/o/r/pull/3" target="_blank">
              <picture>
                <source media="(prefers-color-scheme: dark)" srcset="https://x/d.svg">
                <img src="https://x/l.svg" alt="Devin Review">
              </picture>
            </a>
            <!-- devin-review-badge-end -->
            """
        #expect(stripper.prose(of: body) == "**Devin Review** found 1 new potential issue.")
    }

    // MARK: - Collapsed <details> sections

    /// Devin Review puts its reasoning — call-site links, the example, the
    /// recommended fix — under `<details><summary>Learn more</summary>`, and
    /// stripping the block wholesale threw the fix away with the boilerplate
    /// (measured on laconic-contributor-kit#5, 2026-09-24). Kept summaries
    /// unwrap; anything else collapses to a marker so "there is more here"
    /// survives without the content.
    @Test("a kept summary unwraps; any other collapses to a flagged marker")
    func keptSummaryUnwraps() throws {
        let stripper = try BoilerplateStripper(
            settings: try Configuration.builtInDefaults().inbound)
        let body = """
            🔴 **Empty body blocks future audit snapshots**

            When an audited subject body becomes empty, `bodyComment()` drops it.

            <details>
            <summary>Learn more</summary>

            The audit stores each observed item. **Recommended fix:** retain one.
            </details>

            <details>
            <summary>Environment</summary>

            macOS 14, swift 6.2
            </details>
            """
        let prose = stripper.prose(of: body)
        #expect(prose.contains("The audit stores each observed item"))
        #expect(prose.contains("**Recommended fix:**"))
        #expect(!prose.contains("macOS 14"), "the unmatched block's content is not prose")
        #expect(prose.contains(#"[collapsed: "Environment""#), "the marker still names it")
    }

    /// The marker carries a short hash of the collapsed content, so an edit
    /// INSIDE a collapsed section moves `prose` and reports as a real change —
    /// not the mislabel "markup only, prose unchanged".
    @Test("an edit inside a collapsed section is prose movement, not markup churn")
    func collapsedEditMovesProse() throws {
        let stripper = try BoilerplateStripper(
            settings: try Configuration.builtInDefaults().inbound)
        func body(_ detail: String) -> String {
            """
            Please look at this.

            <details>
            <summary>Diagnostics</summary>

            \(detail)
            </details>
            """
        }
        let before = stripper.prose(of: body("first stack"))
        let after = stripper.prose(of: body("second stack"))
        #expect(before.contains("[collapsed:"))
        #expect(before != after, "the marker's hash tracks the collapsed content")
    }

    /// A body that is ONLY a collapsed section carries no readable ask —
    /// markers flag retrievable content but are not themselves prose. It is
    /// `collapsed-unexamined`: listed so the flag reaches the worklist, never
    /// owed.
    @Test("a details-only body is flagged unexamined, not an obligation")
    func detailsOnlyBodyIsNoProse() throws {
        let comment = RemoteComment(
            id: "issuecomment-1", channel: .issueComment, author: "bot",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: "<details>\n<summary>Diagnostics</summary>\n\nstack trace\n</details>",
            permalink: "https://github.com/o/r/issues/1#issuecomment-1")
        let result = try Fixtures.audit().run(
            pullRequest(issueComments: [comment]), against: nil)
        #expect(result.items.first?.state == .collapsedUnexamined)
        #expect(result.owed.isEmpty)
        #expect(result.items.first?.text.ask.contains("[collapsed:") == true,
            "the flag survives — the raw body does not leak in its place")
    }

    /// Nesting is real in hand-edited bodies: a matching outer block keeps its
    /// content, and a nested `<details>` inside it is classified on its own
    /// summary — depth counting, not first-close matching.
    @Test("a nested details block is classified inside an unwrapped parent")
    func nestedDetailsClassifySeparately() throws {
        let stripper = try BoilerplateStripper(
            settings: try Configuration.builtInDefaults().inbound)
        let body = """
            The ask.

            <details>
            <summary>Learn more</summary>

            Outer reasoning.
            <details>
            <summary>Logs</summary>

            inner noise
            </details>
            Tail of the outer section.
            </details>
            """
        let prose = stripper.prose(of: body)
        #expect(prose.contains("Outer reasoning."))
        #expect(prose.contains("Tail of the outer section."),
            "the outer close is the DEPTH-zero close, not the inner one")
        #expect(!prose.contains("inner noise"))
        #expect(prose.contains(#"[collapsed: "Logs""#))
    }

    /// A `<summary>` titles only its own `<details>` — one inside a nested
    /// block is that block's legend, so an outer block with no summary of its
    /// own collapses untitled rather than borrowing the inner one's title and
    /// unwrapping on a match that was never its own.
    @Test("a nested block's summary does not title its parent")
    func nestedSummaryIsNotTheParents() throws {
        let stripper = try BoilerplateStripper(
            settings: try Configuration.builtInDefaults().inbound)
        let body = """
            <details>
            <details>
            <summary>Learn more</summary>

            inner reasoning
            </details>
            outer hidden
            </details>
            """
        let prose = stripper.prose(of: body)
        #expect(prose.contains(#"[collapsed: "untitled""#),
            "the outer block has no summary of its own")
        #expect(!prose.contains("inner reasoning"),
            "nothing unwraps on a borrowed title")
        #expect(!prose.contains("outer hidden"))
    }

    /// A marker line is generated metadata, not the asker's prose — a
    /// collapsed section whose TITLE happens to read like a retraction must
    /// not retract the body it rides with.
    @Test("a collapsed section's title cannot supersede the body")
    func markerTitleDoesNotSupersede() throws {
        let comment = RemoteComment(
            id: "issuecomment-1", channel: .issueComment, author: "reviewer",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: """
                <details>
                <summary>This report has been superseded</summary>

                diagnostics
                </details>

                Please update the caller.
                """,
            permalink: "https://github.com/o/r/issues/1#issuecomment-1")
        let result = try Fixtures.audit().run(
            pullRequest(issueComments: [comment]), against: nil)
        #expect(result.items.first?.state == .obligationOpen)
    }

    /// Kept sections recurse, and the recursion is capped: nested kept
    /// summaries are constructible well inside GitHub's comment limit, and an
    /// uncapped walk would exhaust the stack. Past the cap a matching section
    /// collapses to a marker like any unmatched one.
    @Test("deeply nested kept sections bottom out in a marker")
    func nestedKeptSectionsAreCapped() throws {
        let stripper = try BoilerplateStripper(
            settings: try Configuration.builtInDefaults().inbound)
        let depth = 40
        let body =
            (0..<depth).map { _ in "<details>\n<summary>Learn more</summary>\n" }
            .joined() + "the core." + String(repeating: "\n</details>", count: depth)
        let prose = stripper.prose(of: body)
        #expect(prose.contains("[collapsed:"), "the cap emits a marker")
        #expect(!prose.contains("the core."), "the capped section keeps its content")
    }

    /// A `<details>` tag inside an HTML comment is not markup — the renderer
    /// never sees it, so the pairing walk must not either: an opener inside a
    /// comment would otherwise swallow every line of real prose after it.
    @Test("a details tag inside an HTML comment is not a live opener")
    func commentedDetailsTagIsNotLive() throws {
        let stripper = try BoilerplateStripper(
            settings: try Configuration.builtInDefaults().inbound)
        #expect(
            stripper.prose(of: "<!-- example: <details> -->\nPlease update the API.")
                == "Please update the API.")
    }

    /// The mirror case: a `</details>` inside a comment inside a real block
    /// must not pair with the real opener and leak the comment tail into prose.
    @Test("a commented close tag does not pair with a real opener")
    func commentedCloseTagDoesNotPair() throws {
        let stripper = try BoilerplateStripper(
            settings: try Configuration.builtInDefaults().inbound)
        let prose = stripper.prose(
            of: "<details>\n<summary>Diagnostics</summary>\nkeep<!-- </details> -->more\n</details>")
        #expect(!prose.contains("more"), "the whole block collapsed; no comment tail leaked")
        #expect(prose.contains(#"[collapsed: "Diagnostics""#))
    }

    /// The marker check matches the emitted shape — `[collapsed: "T" ·8hex]` —
    /// not the bare prefix: an author discussing collapsed UI keeps their line.
    @Test("author text that opens with the marker prefix is still prose")
    func markerPrefixInAuthorTextIsNotMetadata() throws {
        let stripper = try BoilerplateStripper(
            settings: try Configuration.builtInDefaults().inbound)
        let body = "[collapsed: legacy UI] must display the full label."
        #expect(stripper.substantiveProse(stripper.prose(of: body)) == body)
    }

    /// A marker-only body is not `no-prose` — `no-prose` means *definitionally
    /// empty*, and collapsed content is not empty, it is unexamined. It gets
    /// its own state: listed by default so the flag reaches the worklist, but
    /// never owed — the agent decides from the marker's title whether
    /// `--full` is worth it, and acknowledges it otherwise.
    @Test("a marker-only body is listed as collapsed-unexamined, not owed")
    func markerOnlyBodyIsCollapsedUnexamined() throws {
        let comment = RemoteComment(
            id: "issuecomment-1", channel: .issueComment, author: "bot",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: "<details>\n<summary>Diagnostics</summary>\n\nstack trace\n</details>",
            permalink: "https://github.com/o/r/issues/1#issuecomment-1")
        let pr = pullRequest(issueComments: [comment])
        let result = try Fixtures.audit().run(pr, against: nil)
        let item = try #require(result.items.first)
        #expect(item.state == .collapsedUnexamined)
        #expect(!item.state.isOwed)
        #expect(item.isListedByDefault,
            "the flag must reach the worklist even on first sight — that is its point")
    }

    /// The flag must be dismissible, or it is undismissable noise: an
    /// acknowledged marker-only body leaves the worklist, and a body edit
    /// after the ack re-flags it.
    @Test("an acknowledged collapsed body leaves the worklist until the body moves")
    func acknowledgedCollapsedBodyDismisses() throws {
        let body = "<details>\n<summary>Diagnostics</summary>\n\nstack trace\n</details>"
        let comment = RemoteComment(
            id: "issuecomment-1", channel: .issueComment, author: "bot",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: body,
            permalink: "https://github.com/o/r/issues/1#issuecomment-1")
        var snapshot = try Fixtures.audit().run(
            pullRequest(issueComments: [comment]), against: nil
        ).updatedSnapshot
        snapshot.entries["issuecomment-1"]?.acknowledged = Acknowledgement(
            kind: .none, pointer: "diagnostics", bodySha256AtAck: comment.bodySHA256,
            verified: true, verificationNote: "test")

        let after = try Fixtures.audit().run(
            pullRequest(issueComments: [comment]), against: snapshot)
        #expect(after.items.first?.state == .obligationAcknowledged,
            "an acknowledged flag is quiet while the body is unmoved")

        let edited = RemoteComment(
            id: "issuecomment-1", channel: .issueComment, author: "bot",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: "<details>\n<summary>Diagnostics</summary>\n\nstack trace line 2\n</details>",
            permalink: "https://github.com/o/r/issues/1#issuecomment-1")
        let next = try Fixtures.audit().run(
            pullRequest(issueComments: [edited]), against: snapshot)
        #expect(next.items.first?.state == .collapsedUnexamined,
            "a body change after acknowledgement re-flags it")
    }

    /// An announcement followed by a collapsed section is NOT informational:
    /// stripping the marker leaves "Starting Devin Review." as a fragment that
    /// whole-matches the fixed phrase — the same suppression the detector's
    /// own comment warns about, recreated through the marker pass. Unexamined
    /// content cannot be ruled a note.
    @Test("an announcement before a collapsed section is not informational")
    func announcementBeforeCollapsedSectionIsNotInformational() throws {
        let comment = RemoteComment(
            id: "issuecomment-1", channel: .issueComment, author: "bot",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: "Starting Devin Review.\n\n<details>\n<summary>Next steps</summary>\nPlease add a regression test.\n</details>",
            permalink: "https://github.com/o/r/issues/1#issuecomment-1")
        let result = try Fixtures.audit().run(
            pullRequest(issueComments: [comment]), against: nil)
        #expect(result.items.first?.state == .obligationOpen,
            "the collapsed request is unexamined — the announcement cannot suppress it")
    }

    /// Same class through the other suppression state: a retraction in the
    /// opening lines followed by a collapsed section cannot be verified to
    /// cover the unread content.
    @Test("a retraction before a collapsed section does not supersede the unread content")
    func retractionBeforeCollapsedSectionDoesNotSupersede() throws {
        let comment = RemoteComment(
            id: "issuecomment-1", channel: .issueComment, author: "bot",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: "This report has been superseded\n\n<details>\n<summary>Findings</summary>\nPlease add a regression test.\n</details>",
            permalink: "https://github.com/o/r/issues/1#issuecomment-1")
        let result = try Fixtures.audit().run(
            pullRequest(issueComments: [comment]), against: nil)
        #expect(result.items.first?.state == .obligationOpen,
            "a retraction cannot be verified against content nobody has read")
    }

    /// The worklist excerpt truncates at 150 characters; a marker inserted
    /// past that cut leaves no visible flag at all. The terminal render must
    /// name hidden collapsed sections explicitly.
    @Test("a marker past the excerpt cut still prints a flag")
    func markerBeyondExcerptCutPrintsFlag() throws {
        let comment = RemoteComment(
            id: "issuecomment-1", channel: .issueComment, author: "bot",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: String(repeating: "x", count: 170)
                + "\n\n<details>\n<summary>Example</summary>\nAdditional request\n</details>",
            permalink: "https://github.com/o/r/issues/1#issuecomment-1")
        let pr = pullRequest(issueComments: [comment])
        let result = try Fixtures.audit().run(pr, against: nil)
        let output = InboundReporting.terminal(pr, result)
        #expect(output.contains("collapsed"),
            "the worklist must say collapsed content exists even when the excerpt hides the marker")
    }

    /// The raw-body fallback in `text.ask` must not leak into the marker-only
    /// check: an HTML-only body whose comment happens to contain the literal
    /// text `[collapsed:` has no collapsed section to retrieve.
    @Test("an empty-prose body containing the marker text is not flagged")
    func rawBodyFallbackDoesNotFlagCollapsed() throws {
        let comment = RemoteComment(
            id: "issuecomment-1", channel: .issueComment, author: "bot",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: "<!-- [collapsed: legacy UI] -->",
            permalink: "https://github.com/o/r/issues/1#issuecomment-1")
        let pr = pullRequest(issueComments: [comment])
        let result = try Fixtures.audit().run(pr, against: nil)
        #expect(result.items.first?.state == .noProse)
        #expect(result.items.first?.isListedByDefault == false,
            "no collapsed section was processed — nothing to flag")
    }

    /// Same rule as every unclosed boilerplate opener: the rest is boilerplate
    /// from there on, not leaked.
    @Test("an unclosed details opener swallows the rest rather than leaking it")
    func unclosedDetailsBlock() throws {
        let stripper = try BoilerplateStripper(
            settings: try Configuration.builtInDefaults().inbound)
        #expect(
            stripper.prose(of: "Real prose.\n<details>\n<summary>x</summary>").trimmed
                == "Real prose.")
    }

    /// Summary text arrives decorated — `**Learn more**`, emoji prefixes — so the
    /// match is a case-insensitive substring, never exact equality.
    @Test("decorated summary text still matches the keep list")
    func decoratedSummaryMatches() throws {
        let stripper = try BoilerplateStripper(
            settings: try Configuration.builtInDefaults().inbound)
        let body = """
            <details>
            <summary>🔍 **Learn more** about this finding</summary>

            Kept content.
            </details>
            """
        #expect(stripper.prose(of: body).contains("Kept content."))
    }

    /// The marker's hash is what keeps the annotation honest: an edit inside a
    /// collapsed section changes the marker, `prose` moves, and the change is
    /// not mislabeled "markup only".
    @Test("a collapsed-section edit is not reported as markup-only")
    func collapsedEditAnnotatesHonestly() throws {
        func comment(_ detail: String) -> RemoteComment {
            RemoteComment(
                id: "issuecomment-1", channel: .issueComment, author: "reviewer",
                viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
                body: """
                    Please look at this.

                    <details>
                    <summary>Diagnostics</summary>

                    \(detail)
                    </details>
                    """,
                permalink: "https://github.com/o/r/issues/1#issuecomment-1")
        }
        let first = try Fixtures.audit().run(
            pullRequest(issueComments: [comment("first stack")]), against: nil)
        let second = try Fixtures.audit().run(
            pullRequest(issueComments: [comment("second stack")]),
            against: first.updatedSnapshot)
        #expect(second.items.first?.changed?.contains("body changed") == true)
        #expect(
            second.items.first?.changed?.contains("prose unchanged") == false,
            "the collapsed edit moved the marker hash — it is not markup churn")
    }

    /// The finding title must lead the excerpt. An inline Devin body opens with its
    /// marker, so the raw slice showed an invisible HTML comment and pushed the title
    /// out of view.
    @Test("an inline ask's text leads with the finding, not the marker")
    func inlineAskLeadsWithTheFinding() throws {
        let raw = """
            <!-- devin-review-comment {"id": "BUG_pr-review-job-295bbd", "kind": "bug"} -->

            🔴 **Interrupted sync skips new pages**

            After one incremental page, `commitPage` clears `backfillComplete`.
            """
        let root = RemoteComment(
            id: "discussion_r1", channel: .inlineThread, author: "devin-ai-integration",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: raw, permalink: "https://github.com/o/r/pull/1#discussion_r1")

        let result = try Fixtures.audit().run(
            pullRequest(threads: [RemoteThread(comments: [root])]), against: nil)
        let ask = try #require(result.items.first?.text.ask)
        #expect(ask.hasPrefix("🔴 **Interrupted sync skips new pages**"))
        #expect(!ask.contains("devin-review-comment"))
        #expect(result.items.first?.state == .openAsk, "a declared bug is still owed")
    }

    // MARK: - Gap 2.3: supersession

    /// A reviewer can retract an obligation. Without this, <doc:Design>'s never-auto-cleared
    /// rule holds open an ask the asker has themselves withdrawn — forever.
    @Test("a retracted review body is superseded, not owed")
    func supersededBodyIsNotOwed() throws {
        let config = try Configuration.builtInDefaults()
        let detector = SupersessionDetector(phrases: config.inbound.supersessionPhrases)
        let retraction =
            "**This report is out of date.** Scroll down for the latest report on this PR."
        #expect(detector.supersedes(retraction) == "this report is out of date")
        #expect(detector.supersedes("Please apply this to sip_transport_tcp.c too.") == nil)
        #expect(ItemState.superseded.isOwed == false)
    }

    // MARK: - Gap 2.4: acknowledgement by the asker

    /// The asker replying in the thread, describing the fix in their own words, is
    /// better evidence than our own claim to have fixed something — it is the asker
    /// confirming the answer. Not an inference from proximity: <doc:Design>'s rule is about
    /// inferring acceptance from *timing*, and this is the asker speaking.
    ///
    /// No current fixture contains one, so this is constructed. Said plainly rather
    /// than left to be discovered.
    @Test("the asker's own reply after mine clears the thread; mine alone only claims")
    func askerConfirmationBeatsMyClaim() throws {
        func thread(withAskerReply: Bool) -> RemoteThread {
            var comments = [
                comment("discussion_r1", "sauwming", at: 0),
                comment("discussion_r2", "laconicman", at: 10),
            ]
            if withAskerReply {
                comments.append(comment("discussion_r3", "sauwming", at: 20))
            }
            return RemoteThread(comments: comments)
        }

        let claimed = try Fixtures.audit().run(
            pullRequest(threads: [thread(withAskerReply: false)]), against: nil)
        #expect(claimed.items.first?.state == .answeredClaimed)
        #expect(claimed.items.first?.state.isOwed == false)

        let confirmed = try Fixtures.audit().run(
            pullRequest(threads: [thread(withAskerReply: true)]), against: nil)
        #expect(confirmed.items.first?.state == .answeredConfirmed)
    }

    /// <doc:Design>'s sharpest check, and free given the snapshot:
    /// `lastEditedAt > myReplyAt` means the ask was edited after I answered it.
    @Test("an ask edited after my answer re-opens as its own state")
    func editedAfterMyAnswer() throws {
        var root = comment("discussion_r1", "sauwming", at: 0)
        root.lastEditedAt = Date(timeIntervalSince1970: 30)
        let thread = RemoteThread(comments: [root, comment("discussion_r2", "laconicman", at: 10)])

        let result = try Fixtures.audit().run(pullRequest(threads: [thread]), against: nil)
        #expect(result.items.first?.state == .editedAfterMyAnswer)
        #expect(result.items.first?.state.isOwed == true)
    }

    // MARK: - The differ

    /// <doc:Design>'s "since the last iteration" is the load-bearing piece. Without
    /// round-over-round state, a second round re-lists everything already answered.
    @Test("a second run reports only what moved")
    func secondRunReportsOnlyTheDelta() throws {
        let pr = try Fixtures.threads(pr: 5233, comments: "pr-5233.positive.comments.json")
        let first = try Fixtures.audit().run(pr, against: nil)
        #expect(first.items.allSatisfy { $0.changed == "new since the last run" })

        let second = try Fixtures.audit().run(pr, against: first.updatedSnapshot)
        #expect(second.items.allSatisfy { $0.changed == nil })
        // The worklist is unchanged — a differ reports the delta, it does not forget
        // what is still owed.
        #expect(second.owed.count == first.owed.count)
    }

    /// **A state transition is movement.** Comparing bodies alone means the run straight
    /// after a round of replies reports "nothing moved" — true of what the snapshot
    /// tracks, false of what a contributor tracks. Reported from a live trial: six
    /// threads answered and one obligation acknowledged, and the next run said nothing
    /// had changed.
    @Test("answering a thread shows up as a transition on the next run")
    func stateTransitionsAreMovement() throws {
        let root = comment("discussion_r1", "sauwming", at: 0)
        let unanswered = RemoteThread(comments: [root])
        let answered = RemoteThread(
            comments: [root, comment("discussion_r2", "laconicman", at: 10)])

        let first = try Fixtures.audit().run(
            pullRequest(threads: [unanswered]), against: nil)
        #expect(first.items.first?.state == .openAsk)

        // Nothing changed at all: no transition, no movement.
        let stable = try Fixtures.audit().run(
            pullRequest(threads: [unanswered]), against: first.updatedSnapshot)
        #expect(stable.items.first?.changed == nil)
        #expect(stable.items.first?.previousState == nil)

        // Now I reply. The body did not change; the state did.
        let moved = try Fixtures.audit().run(
            pullRequest(threads: [answered]), against: first.updatedSnapshot)
        #expect(moved.items.first?.state == .answeredClaimed)
        #expect(moved.items.first?.previousState == .openAsk)
        #expect(moved.items.first?.changed == "open-ask → answered-claimed")
        // And it is visible, even though it is no longer owed — which is the run in
        // which "is my reply actually responsive?" is worth asking.
        #expect(moved.items.first?.state.isOwed == false)
        #expect(moved.items.contains { $0.changed != nil })
    }

    /// An acknowledgement is a transition too, and it was the other half of the same
    /// silent run.
    @Test("acknowledging an obligation shows up as a transition")
    func acknowledgementIsATransition() throws {
        let body = RemoteComment(
            id: "pullrequestreview-1", channel: .reviewBody, author: "devin",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: "Please add a regression test.",
            permalink: "https://github.com/o/r/pull/1#pullrequestreview-1")

        var snapshot = try Fixtures.audit().run(
            pullRequest(reviewBodies: [body]), against: nil
        ).updatedSnapshot
        snapshot.entries["pullrequestreview-1"]?.acknowledged = Acknowledgement(
            kind: .commit, pointer: "1da04eb", bodySha256AtAck: body.bodySHA256,
            verified: true, verificationNote: "test")

        let after = try Fixtures.audit().run(
            pullRequest(reviewBodies: [body]), against: snapshot)
        #expect(after.items.first?.state == .obligationAcknowledged)
        #expect(after.items.first?.changed == "obligation-open → obligation-acknowledged")
    }

    /// **The `--json` ask must be answerable from the JSON.** It was truncated at 400
    /// characters, so every round-3 ask in the live trial ended mid-sentence and the
    /// session had to re-fetch bodies with `gh api` — which is the re-enumeration the
    /// machine contract exists to eliminate. Terminal display still truncates; the
    /// contract does not.
    @Test("the ask is carried whole, not sliced")
    func askIsNotTruncated() throws {
        let long = String(repeating: "A resumed backfill loses the newest watermark. ", count: 40)
        #expect(long.count > 400)
        let body = RemoteComment(
            id: "pullrequestreview-1", channel: .reviewBody, author: "devin",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: long, permalink: "https://github.com/o/r/pull/1#pullrequestreview-1")

        let result = try Fixtures.audit().run(
            pullRequest(reviewBodies: [body]), against: nil)
        // A review body's ask is the *stripped* prose — badge markup should not pad the
        // contract — so it is trimmed, but never sliced.
        #expect(result.items.first?.text.ask == long.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(result.items.first?.text.ask.hasSuffix("…") == false)
        #expect((result.items.first?.text.ask.count ?? 0) > 400)
    }

    /// The record is keyed by comment id **and** body hash, so an edit after
    /// acknowledgement re-opens the item by itself. For review bodies the hash is not
    /// an optimisation — it is the only mechanism REST leaves available.
    @Test("an acknowledged review body re-opens when its body is edited")
    func acknowledgementIsKeyedByHash() throws {
        let original = RemoteComment(
            id: "pullrequestreview-1", channel: .reviewBody, author: "sauwming",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: "Please add a regression test.",
            permalink: "https://github.com/o/r/pull/1#pullrequestreview-1")

        var snapshot = try Fixtures.audit().run(
            pullRequest(reviewBodies: [original]), against: nil
        ).updatedSnapshot
        snapshot.entries["pullrequestreview-1"]?.acknowledged = Acknowledgement(
            kind: .commit, pointer: "e02b93e1", bodySha256AtAck: original.bodySHA256,
            verified: true, verificationNote: "test")

        let unchanged = try Fixtures.audit().run(
            pullRequest(reviewBodies: [original]), against: snapshot)
        #expect(unchanged.items.first?.state == .obligationAcknowledged)
        #expect(unchanged.owed.isEmpty)

        var edited = original
        edited.body = "Please add a regression test — and one for the TCP path too."
        let reopened = try Fixtures.audit().run(
            pullRequest(reviewBodies: [edited]), against: snapshot)
        #expect(reopened.items.first?.state == .reopenedByEdit)
        #expect(reopened.owed.count == 1)
    }

    // MARK: - The subject body, issue #3 follow-up

    /// For an issue the body IS the ask — and `contrib in` never fetched it, so an
    /// issue carrying four asks reported "nothing owed". Synthesized as an
    /// issue-comments item, it flows through the obligation machinery unchanged.
    @Test("a subject body from someone else is an obligation like any other")
    func subjectBodyIsAnObligation() throws {
        let body = RemoteComment(
            id: "issue-3", channel: .issueComment, author: "maintainer",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: "Please add a regression test.",
            permalink: "https://github.com/o/r/issues/3")
        let result = try Fixtures.audit().run(
            pullRequest(issueComments: [body]), against: nil)
        let item = try #require(result.items.first)
        #expect(item.id == "issue-3")
        #expect(item.state == .obligationOpen)
        #expect(item.state.isOwed)
    }

    /// On my own issue or pull request the body is mine — `viewerDidAuthor` filters
    /// it exactly like my own comments, so the dogfooding mainline stays silent.
    @Test("my own subject body is authored, never an obligation")
    func mySubjectBodyIsAuthored() throws {
        let body = RemoteComment(
            id: "issue-3", channel: .issueComment, author: "laconicman",
            viewerDidAuthor: true, createdAt: Date(timeIntervalSince1970: 0),
            body: "Tracking the work.", permalink: "https://github.com/o/r/issues/3")
        let result = try Fixtures.audit().run(
            pullRequest(issueComments: [body]), against: nil)
        #expect(result.items.isEmpty)
        #expect(result.ownAuthored[.issueComment] == 1)
        #expect(result.updatedSnapshot.authored.contains("issue-3"))
    }

    /// The record is keyed by body hash — an edited issue body re-opens the
    /// acknowledgement by itself, which is precisely why the body had to be an item.
    @Test("an acknowledged subject body re-opens when it is edited")
    func subjectBodyReopensOnEdit() throws {
        let original = RemoteComment(
            id: "issue-3", channel: .issueComment, author: "maintainer",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: "Please add a regression test.",
            permalink: "https://github.com/o/r/issues/3")

        var snapshot = try Fixtures.audit().run(
            pullRequest(issueComments: [original]), against: nil
        ).updatedSnapshot
        snapshot.entries["issue-3"]?.acknowledged = Acknowledgement(
            kind: .commit, pointer: "e02b93e1", bodySha256AtAck: original.bodySHA256,
            verified: true, verificationNote: "test")

        var edited = original
        edited.body = "Please add a regression test — for the TCP path too."
        let reopened = try Fixtures.audit().run(
            pullRequest(issueComments: [edited]), against: snapshot)
        #expect(reopened.items.first?.state == .reopenedByEdit)
    }

    /// The wedge the review round on #5 caught: a body that empties after being
    /// recorded used to make the item VANISH, and the vanished-item anomaly blocked
    /// every later snapshot write — the guard that protects the baseline bricked it
    /// permanently, because an emptied body stays empty. Now it transitions to
    /// `no-prose` instead: a recorded change, not a disappearance.
    @Test("a subject body that empties transitions to no-prose, never vanishes")
    func emptiedSubjectBodyIsNoProseNotVanished() throws {
        let original = RemoteComment(
            id: "issue-3", channel: .issueComment, author: "maintainer",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: "Please add a regression test.",
            permalink: "https://github.com/o/r/issues/3")
        let first = try Fixtures.audit().run(
            pullRequest(issueComments: [original]), against: nil)

        var emptied = original
        emptied.body = ""
        let second = try Fixtures.audit().run(
            pullRequest(issueComments: [emptied]), against: first.updatedSnapshot)

        #expect(second.items.first?.state == .noProse)
        #expect(second.vanished.isEmpty, "an emptied body is a transition, not a disappearance")
        #expect(second.items.first?.changed?.contains("no-prose") == true)
    }

    /// Root comments only — a reply inside a thread is not a new ask (<doc:Design>).
    @Test("replies inside a thread are never counted as roots")
    func repliesAreNotRoots() throws {
        let pr = try Fixtures.threads(pr: 5233, comments: "pr-5233.positive.comments.json")
        #expect(pr.threads.count == 24)
        #expect(pr.threads.reduce(0) { $0 + $1.comments.count } == 46)
        #expect(pr.threads.allSatisfy { $0.root?.author == "sauwming" })
    }

    /// Rounds are unevenly sized — #5233's carry 2, 4, 5, 5, 3, 2, 2 and 1 threads.
    /// Grouping by review is therefore not cosmetic; a flat list of 24 loses which
    /// round is open (<doc:Design>).
    @Test("threads group into the rounds that carried them")
    func roundGrouping() throws {
        let pr = try Fixtures.threads(pr: 5233, comments: "pr-5233.positive.comments.json")
        let result = try Fixtures.audit().run(pr, against: nil)
        let rounds = Dictionary(grouping: result.items.filter { $0.kind == .inlineThread }) {
            $0.roundID ?? "—"
        }
        let expected = try Fixtures.threadsManifest().prs["5233"]?.rounds
        #expect(rounds.count == expected?.count)
        for (review, size) in expected ?? [:] {
            #expect(rounds[review]?.count == size, "round \(review)")
        }
    }

    // MARK: - Answered but unchecked

    /// **An `answered-claimed` thread stays listed until the asker confirms or a check is
    /// recorded.** It used to appear on the run it changed and vanish on the next, so the
    /// one item carrying a live meaning question was hidden by default whether or not
    /// anyone had looked. A trial session reported it on two separate rounds.
    @Test("answered-claimed stays listed on an open PR, run after run")
    func answeredClaimedStaysListed() throws {
        let thread = RemoteThread(comments: [
            comment("discussion_r1", "reviewer", at: 0),
            comment("discussion_r2", "laconicman", at: 10),
        ])
        let first = try Fixtures.audit().run(pullRequest(threads: [thread]), against: nil)
        let second = try Fixtures.audit().run(
            pullRequest(threads: [thread]), against: first.updatedSnapshot)

        let item = try #require(second.items.first)
        #expect(item.state == .answeredClaimed)
        #expect(item.changed == nil, "nothing moved")
        #expect(item.isListedByDefault, "and it is listed anyway")
        #expect(second.owed.isEmpty, "not owed — a separate count")
        #expect(second.toReRead.count == 1)
    }

    /// Closure quiets the responsiveness question and **nothing else**. Reviewers post
    /// rounds after a merge — a trial handled six findings posted on an already-merged PR
    /// — and a close can carry a condition addressed to the contributor.
    @Test("a closed PR quiets answered-claimed but never an ask")
    func closureQuietsOnlyTheReReadList() throws {
        let answered = RemoteThread(comments: [
            comment("discussion_r1", "reviewer", at: 0),
            comment("discussion_r2", "laconicman", at: 10),
        ])
        let postMergeAsk = RemoteThread(comments: [comment("discussion_r3", "reviewer", at: 50)])
        var pr = pullRequest(threads: [answered, postMergeAsk])
        pr.state = "MERGED"
        pr.isMerged = true

        let first = try Fixtures.audit().run(pr, against: nil)
        let second = try Fixtures.audit().run(pr, against: first.updatedSnapshot)

        let claimed = try #require(second.items.first { $0.id == "discussion_r1" })
        let ask = try #require(second.items.first { $0.id == "discussion_r3" })
        #expect(!claimed.isListedByDefault, "nobody is waiting on the check any more")
        #expect(ask.isListedByDefault, "a post-merge ask is still owed")
        #expect(second.owed.map(\.id) == ["discussion_r3"])
        #expect(second.toReRead.isEmpty)
    }

    /// A recorded check is keyed to the ask and to the reply it judged. A new reply or an
    /// edited ask must list the thread again rather than inherit a check it never had.
    @Test("a responsiveness check holds until the reply or the ask changes")
    func responsivenessCheckIsKeyed() throws {
        let root = comment("discussion_r1", "reviewer", at: 0)
        let reply = comment("discussion_r2", "laconicman", at: 10)
        let pr = pullRequest(threads: [RemoteThread(comments: [root, reply])])

        var snapshot = try Fixtures.audit().run(pr, against: nil).updatedSnapshot
        snapshot.entries["discussion_r1"]?.acknowledged = Acknowledgement(
            kind: .none, pointer: "covers both parts; tested",
            bodySha256AtAck: root.bodySHA256, verified: true,
            verificationNote: "explicit", replyIDAtAck: "discussion_r2")

        let checked = try Fixtures.audit().run(pr, against: snapshot)
        #expect(checked.items.first?.state == .answeredChecked)
        #expect(checked.items.first?.changed == "answered-claimed → answered-checked")
        #expect(checked.toReRead.isEmpty)

        // I reply again: the check judged the old reply.
        let secondReply = comment("discussion_r4", "laconicman", at: 20)
        let replied = try Fixtures.audit().run(
            pullRequest(threads: [RemoteThread(comments: [root, reply, secondReply])]),
            against: checked.updatedSnapshot)
        #expect(replied.items.first?.state == .answeredClaimed)
        #expect(replied.toReRead.count == 1)

        // The reviewer edits the ask: stale again, and the stronger state wins.
        var edited = root
        edited.body = "the ask, widened"
        edited.lastEditedAt = Date(timeIntervalSince1970: 30)
        let reopened = try Fixtures.audit().run(
            pullRequest(threads: [RemoteThread(comments: [edited, reply])]),
            against: checked.updatedSnapshot)
        #expect(reopened.items.first?.state == .editedAfterMyAnswer)
    }

    /// A reviewer that appends its badge to a superseded body re-opens every
    /// acknowledged item in that round for no semantic reason — observed twice in one
    /// morning on one thread. The item still re-opens and a stale check is still
    /// refused; what changes is that the contributor is told which kind of edit it was.
    @Test("a markup-only edit says so, and still re-opens the item")
    func markupOnlyEditIsNamed() throws {
        let ask = "🔴 **Same-channel syncs remain concurrent**\n\nTwo syncs can overlap."
        let badge = "\n\n<!-- devin-review-badge-begin -->\n<a href=\"https://x\">\n"
            + "  <picture><img src=\"https://x/l.svg\"></picture>\n</a>\n"
            + "<!-- devin-review-badge-end -->"

        var body = RemoteComment(
            id: "pullrequestreview-1", channel: .reviewBody, author: "devin-ai-integration",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: ask, permalink: "https://github.com/o/r/pull/1#pullrequestreview-1")
        let first = try Fixtures.audit().run(
            pullRequest(reviewBodies: [body]), against: nil)

        body.body = ask + badge
        let markupOnly = try Fixtures.audit().run(
            pullRequest(reviewBodies: [body]), against: first.updatedSnapshot)
        let changed = try #require(markupOnly.items.first?.changed)
        #expect(changed.contains("markup only, prose unchanged"))

        body.body = ask + "\n\nAlso: the retry path." + badge
        let proseMoved = try Fixtures.audit().run(
            pullRequest(reviewBodies: [body]), against: first.updatedSnapshot)
        let changed2 = try #require(proseMoved.items.first?.changed)
        #expect(!changed2.contains("markup only"))

        // The same annotation must reach the acknowledged branch: an acknowledged item
        // re-opened by a re-appended badge is the commonest case of all.
        var acknowledged = first.updatedSnapshot
        acknowledged.entries["pullrequestreview-1"]?.acknowledged = Acknowledgement(
            kind: .none, pointer: "absorbed", bodySha256AtAck: SHA256.hex(of: ask),
            verified: true, verificationNote: "test")
        body.body = ask + badge
        let reopened = try Fixtures.audit().run(
            pullRequest(reviewBodies: [body]), against: acknowledged)
        #expect(reopened.items.first?.changed?.contains("markup only") == true)
    }

    /// The "prose changed vs markup only" distinction reaches inline threads too — an
    /// `edited-after-my-answer` whose whole prose moved and one whose markup moved are
    /// different urgencies, and the issue-3 report asked for the note review bodies
    /// already carried. The item still re-opens (TD-4's cheap direction); the
    /// contributor is told which kind of edit it was.
    @Test("a markup-only edit on an inline thread says so, and still re-opens it")
    func markupOnlyInlineEditIsNamed() throws {
        var root = comment("discussion_r1", "reviewer", at: 0)
        let reply = comment("discussion_r2", "laconicman", at: 10)
        let first = try Fixtures.audit().run(
            pullRequest(threads: [RemoteThread(comments: [root, reply])]), against: nil)

        root.body += "\n\n<!-- devin-review-badge-begin -->\n<a href=\"https://x\"></a>\n"
            + "<!-- devin-review-badge-end -->"
        root.lastEditedAt = Date(timeIntervalSince1970: 20)
        let second = try Fixtures.audit().run(
            pullRequest(threads: [RemoteThread(comments: [root, reply])]),
            against: first.updatedSnapshot)

        let item = try #require(second.items.first)
        #expect(item.state == .editedAfterMyAnswer)
        #expect(item.state.isOwed)
        #expect(item.changed?.contains("markup only, prose unchanged") == true)
    }

    /// A `lastEditedAt` bump with a byte-identical body is the strongest form of the
    /// same signal: nothing moved at all. It carried no annotation — the `changed`
    /// line read as a plain `answered-claimed → edited-after-my-answer` transition,
    /// which is the urgent-looking version of a no-op.
    @Test("an edit that moved only the timestamp says the body is unchanged")
    func timestampOnlyEditIsNamed() throws {
        var root = comment("discussion_r1", "reviewer", at: 0)
        let reply = comment("discussion_r2", "laconicman", at: 10)
        let first = try Fixtures.audit().run(
            pullRequest(threads: [RemoteThread(comments: [root, reply])]), against: nil)

        root.lastEditedAt = Date(timeIntervalSince1970: 20) // body identical
        let second = try Fixtures.audit().run(
            pullRequest(threads: [RemoteThread(comments: [root, reply])]),
            against: first.updatedSnapshot)

        let item = try #require(second.items.first)
        #expect(item.state == .editedAfterMyAnswer)
        #expect(item.changed?.contains("body unchanged") == true)
    }

    /// **The baseline run lists what is actionable, not everything it has ever seen.**
    /// Treating "new since the last run" as movement made the first run on a real PR print
    /// 49 badge-only review bodies, none of them actionable. They stay counted.
    @Test("a first run lists owed and re-read items, not definitionally empty ones")
    func baselineRunListsOnlyActionableItems() throws {
        func body(_ id: String, _ text: String) -> RemoteComment {
            RemoteComment(
                id: id, channel: .reviewBody, author: "devin-ai-integration",
                viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
                body: text, permalink: "https://github.com/o/r/pull/1#\(id)")
        }
        let badge = "<!-- devin-review-badge-begin -->\n<a href=\"https://x\"></a>\n"
            + "<!-- devin-review-badge-end -->"

        let pr = pullRequest(
            threads: [
                RemoteThread(comments: [comment("discussion_r1", "reviewer", at: 0)]),
                RemoteThread(comments: [
                    comment("discussion_r2", "reviewer", at: 0),
                    comment("discussion_r3", "laconicman", at: 10),
                ]),
            ],
            reviewBodies: [
                body("pullrequestreview-1", badge),
                body("pullrequestreview-2", badge),
                body("pullrequestreview-3", "**Devin Review** found 2 potential issues."),
            ])

        let first = try Fixtures.audit().run(pr, against: nil)
        let listed = first.items.filter(\.isListedByDefault).map(\.id).sorted()
        #expect(
            listed == ["discussion_r1", "discussion_r2", "pullrequestreview-3"],
            "one open ask, one to re-read, one obligation — and neither badge")
        // Counted, all the same.
        #expect(first.items.count == 5)
        #expect(first.count(of: .noProse, in: .reviewBody) == 2)
    }

    // MARK: - From Devin's review of this kit

    /// **An item that leaves the fetch must not leave silently.** The guard for this
    /// compared snapshot entry counts — and the snapshot only ever grows, so it could
    /// never fire. The comparison is now over ids actually fetched, scoped to this
    /// subject because the snapshot is per repository and a run is per pull request.
    @Test("an item this subject had last run and no longer has is an anomaly")
    func vanishedItemsAreDetected() throws {
        let a = comment("discussion_r1", "reviewer", at: 0)
        let b = comment("discussion_r2", "reviewer", at: 10)
        let both = pullRequest(
            threads: [RemoteThread(comments: [a]), RemoteThread(comments: [b])])

        let first = try Fixtures.audit().run(both, against: nil)
        #expect(first.vanished.isEmpty)

        // `b` disappears from the fetch.
        let fewer = pullRequest(threads: [RemoteThread(comments: [a])])
        let second = try Fixtures.audit().run(fewer, against: first.updatedSnapshot)
        #expect(second.vanished == ["discussion_r2"])
        // The snapshot still holds it, which is exactly why counting entries could not
        // have noticed.
        #expect(second.updatedSnapshot.entries.count == 2)

        var provenance = Provenance(command: "test")
        InboundReporting.record(second, fewer, previous: first.updatedSnapshot, into: &provenance)
        #expect(provenance.anomalies.contains { $0.kind == "itemsVanished" })
    }

    /// Another subject's items are not this subject's business. The snapshot is shared
    /// per repository, so an unscoped comparison would report every other PR's items as
    /// vanished on every run.
    @Test("items belonging to another pull request are never reported as vanished")
    func vanishedIsScopedToTheSubject() throws {
        let one = pullRequest(threads: [RemoteThread(comments: [comment("discussion_r1", "reviewer", at: 0)])])
        var two = pullRequest(threads: [RemoteThread(comments: [comment("discussion_r9", "reviewer", at: 0)])])
        two.number = 2

        let first = try Fixtures.audit().run(one, against: nil)
        let second = try Fixtures.audit().run(two, against: first.updatedSnapshot)
        #expect(second.vanished.isEmpty, "PR #1's item is not missing from PR #2")
    }

    /// **A whole-body phrase must not match one line of a longer body.** Line anchoring
    /// let a bot's announcement suppress an ask that shared the comment — the same
    /// false-negative class that already cost this kit two real asks once.
    @Test("an announcement line does not suppress an ask in the same body")
    func announcementDoesNotSuppressAnAsk() throws {
        let detector = try InformationalDetector(
            patterns: try Configuration.builtInDefaults().inbound.informationalPatterns)

        let announcementOnly = "Starting Devin Review."
        #expect(detector.isInformational(raw: announcementOnly, prose: announcementOnly) != nil)

        let announcementPlusAsk = "Starting Devin Review.\n\nPlease add a regression test."
        #expect(
            detector.isInformational(raw: announcementPlusAsk, prose: announcementPlusAsk) == nil,
            "the regression-test request is still owed")
    }

    /// A configured value that changes nothing is worse than no setting: a repository
    /// could disable a pointer form and still record one.
    @Test("acknowledgementKinds actually restricts the pointer forms")
    func acknowledgementKindsIsEnforced() {
        let onlyNone = ["none"]
        #expect(
            AcknowledgementEligibility.refusal(forKind: .none, allowed: onlyNone, id: "x") == nil)
        let refused = AcknowledgementEligibility.refusal(
            forKind: .commit, allowed: onlyNone, id: "x")
        #expect(refused?.contains("not an accepted acknowledgement") == true)
        // An empty list means "unconfigured", not "forbid everything".
        #expect(
            AcknowledgementEligibility.refusal(forKind: .commit, allowed: [], id: "x") == nil)
    }

    // MARK: - The review horizon

    /// A repository can declare an era out of audit. **Nothing is cleared** — the items
    /// stay in the snapshot, stay counted, and the provenance block says how many would
    /// otherwise be owed. That is the difference between scoping a question and writing
    /// dozens of acknowledgements asserting an absorption that did not happen.
    @Test("items before the horizon are counted and not listed")
    func horizonScopesRatherThanClears() throws {
        let old = comment("discussion_r1", "reviewer", at: 0)
        let recent = comment("discussion_r2", "reviewer", at: 10_000)
        let pr = pullRequest(
            threads: [RemoteThread(comments: [old]), RemoteThread(comments: [recent])])

        let unscoped = try Fixtures.audit().run(pr, against: nil)
        #expect(unscoped.owed.count == 2)

        let scoped = try Fixtures.audit(horizon: Date(timeIntervalSince1970: 5_000))
            .run(pr, against: nil)
        #expect(scoped.owed.count == 1, "only the recent one is in scope")
        #expect(scoped.owed.first?.id == "discussion_r2")
        #expect(scoped.beyondHorizon.count == 1)
        // Still examined, still in the snapshot, still an open ask — just not asked about.
        #expect(scoped.items.count == 2)
        #expect(scoped.updatedSnapshot.entries.count == 2)
        #expect(scoped.items.first { $0.id == "discussion_r1" }?.state == .openAsk)
    }

    /// A horizon must scope the backlog, never hide activity. A reviewer editing a June
    /// comment today is today's activity, and a horizon that swallowed it would be a
    /// check quietly running against the wrong set.
    @Test("an old item that moves surfaces despite the horizon")
    func horizonDoesNotHideMovement() throws {
        var old = comment("discussion_r1", "reviewer", at: 0)
        let pr = pullRequest(threads: [RemoteThread(comments: [old])])
        let horizon = Date(timeIntervalSince1970: 5_000)

        let first = try Fixtures.audit(horizon: horizon).run(pr, against: nil)
        #expect(first.owed.isEmpty, "the baseline run does not surface it")

        // The reviewer edits it. Same creation date, different body.
        old.body = "the ask, restated and widened"
        old.lastEditedAt = Date(timeIntervalSince1970: 20_000)
        let moved = try Fixtures.audit(horizon: horizon).run(
            pullRequest(threads: [RemoteThread(comments: [old])]),
            against: first.updatedSnapshot)
        #expect(moved.owed.count == 1, "movement beats the horizon")
        #expect(moved.owed.first?.changed?.contains("body changed") == true)
    }

    /// An unparseable horizon throws. One that quietly did nothing would hide exactly
    /// what it was set to scope.
    @Test("a malformed horizon is an error, not a no-op")
    func malformedHorizonThrows() throws {
        var inbound = try Configuration.builtInDefaults().inbound
        inbound.horizon = "last summer"
        #expect(throws: ConfigurationError.self) { _ = try inbound.horizonDate() }

        inbound.horizon = "2026-07-01"
        #expect(try inbound.horizonDate() != nil)
        inbound.horizon = nil
        #expect(try inbound.horizonDate() == nil)
    }

    /// `inbound:` merges per sub-key. Setting a horizon must not require restating every
    /// pattern list — the first attempt failed with a decoding error naming an unrelated
    /// key, which is a poor way to learn a config rule.
    @Test("a partial inbound block keeps the shipped defaults")
    func partialInboundMerges() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ck-inbound-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "inbound:\n  horizon: \"2026-07-01\"\n".write(
            to: directory.appending(path: ".contributorkit.yml"),
            atomically: true, encoding: .utf8)

        let config = try Configuration.load(directory: directory)
        #expect(config.inbound.horizon == "2026-07-01")
        #expect(config.inbound.supersessionPhrases.contains("this report is out of date"))
        #expect(!config.inbound.boilerplateBlocks.isEmpty)
    }

    // MARK: - Helpers

    private func comment(_ id: String, _ author: String, at seconds: TimeInterval)
        -> RemoteComment
    {
        RemoteComment(
            id: id, channel: .inlineThread, author: author, viewerDidAuthor: false,
            createdAt: Date(timeIntervalSince1970: seconds),
            body: "body of \(id)", permalink: "https://github.com/o/r/pull/1#\(id)")
    }

    private func pullRequest(
        threads: [RemoteThread] = [], reviewBodies: [RemoteComment] = [],
        issueComments: [RemoteComment] = []
    ) -> PullRequestThreads {
        PullRequestThreads(
            repository: "o/r", number: 1, title: "t", url: "u", state: "OPEN",
            isMerged: false, threads: threads, reviewBodies: reviewBodies,
            issueComments: issueComments, pagesFetched: 1)
    }
}

extension String {
    fileprivate var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
