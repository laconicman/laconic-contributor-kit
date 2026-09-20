import Foundation
import Testing

@testable import ContributorKit

/// File roles: ordered, first match wins, and the order is part of the contract
/// (<doc:Design>). These assertions are against `manifest.json`'s own `paths` and
/// `byRole` blocks, which `make_manifest.py` produced with the same ordered list the
/// 39/33/18/7/1 distribution was measured with.
struct ConsequenceTableMissing: Error {}

@Suite("file roles — ordered, first match wins")
struct RoleTests {

    private func classifier() throws -> FileRoleClassifier {
        try Configuration.builtInDefaults().roleClassifier()
    }

    /// `**/x` must also match a bare `x` at the repo root, which naïve glob matching
    /// does not do. <doc:Design> asks for this case explicitly.
    @Test("a bare CMakeLists.txt at the repo root is `build`")
    func bareNameGlobAtRoot() throws {
        #expect(try classifier().role(of: "CMakeLists.txt") == "build")
        #expect(try classifier().role(of: "Makefile") == "build")
        #expect(try classifier().role(of: "pjlib/build/Makefile") == "build")
    }

    /// `vendor` is the role the original plan missed, and it is a third of pjproject.
    /// Growth in `third_party/` is not our code at all.
    @Test("third_party is vendor, including its own tests")
    func vendorWinsOverTest() throws {
        let c = try classifier()
        #expect(c.role(of: "third_party/webrtc_aec3/src/x.cc") == "vendor")
        #expect(c.role(of: "third_party/webrtc_aec3/test/x.cc") == "vendor")
        #expect(c.role(of: "pjlib/src/pjlib-test/ssl_sock.c") == "test")
        #expect(c.role(of: "pjlib/src/pj/ssl_sock_darwin.c") == "source")
    }

    /// **Location beats type**, which is what the ordering encodes: `vendor` and `test`
    /// say where a file lives, `build` and `docs` say what it is, and location wins.
    /// The question the tool answers is *what part of the tree did this change touch*,
    /// so a Makefile inside `tests/` is test-harness growth.
    @Test("test precedes build, so a Makefile in the test tree is `test`")
    func locationBeatsType() throws {
        let c = try classifier()
        #expect(c.role(of: "tests/automated/Makefile") == "test")
        #expect(c.role(of: "Makefile") == "build")
    }

    /// The skill's reference page documents the consequences of the ordering as a
    /// table. **This test reads that table out of the file and asserts every row**, so
    /// the prose cannot drift from the rules the way it did once already — the
    /// documented example said `build` where the shipped rules said `test`, and nothing
    /// could catch it because the example was hand-written.
    ///
    /// The doc is the fixture. Add a row there and it is checked from the next run.
    @Test("every consequence documented in references/file-roles.md still holds")
    func documentedConsequencesHold() throws {
        let markdown = String(decoding: try Fixtures.data("file-roles.md"), as: UTF8.self)
        let rows = try Self.consequenceRows(in: markdown)
        // The table is located by its header and read whole. An earlier version of this
        // test guessed which rows were paths, and silently examined 12 of 13 — the same
        // shape of bug it exists to catch.
        #expect(rows.count == 13, "the consequences table has 13 rows")

        let c = try classifier()
        for (path, role) in rows {
            #expect(c.role(of: path) == role, "\(path) is documented as `\(role)`")
        }
    }

    /// Every row of the table introduced by `| Path | Role | Why |`, in order.
    /// Throws rather than returning empty when the header is not found: a doc-driven
    /// test that quietly finds no rows passes for the wrong reason.
    static func consequenceRows(in markdown: String) throws -> [(String, String)] {
        let lines = markdown.components(separatedBy: .newlines)
        guard
            let header = lines.firstIndex(where: {
                $0.hasPrefix("| Path ") && $0.contains("| Role ")
            })
        else {
            throw ConsequenceTableMissing()
        }
        var rows: [(String, String)] = []
        for line in lines.dropFirst(header + 2) {
            guard line.hasPrefix("|") else { break }
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 4 else { break }
            let unquote = { (s: String) in
                s.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            }
            rows.append((unquote(cells[1]), unquote(cells[2])))
        }
        return rows
    }

    @Test("paths containing spaces survive — nothing splits on whitespace")
    func pathsWithSpaces() throws {
        let c = try classifier()
        #expect(
            c.role(of: "pjsip-apps/src/swift/Preview Content/Assets.swift") == "source")
        #expect(c.role(of: "docs/Preview Content/notes.md") == "docs")
    }
}

@Suite("configuration")
struct ConfigurationTests {

    /// The shipped default must be a byte-identical copy of the fixtures' file, which
    /// is itself generated from the script that measured the role distribution. If
    /// these ever differ, the shipped defaults and the measured numbers have drifted —
    /// which is the exact failure the fixtures README set this rule up to prevent.
    /// The consequences test reads a *copy* of `references/file-roles.md` under
    /// `Fixtures/`, because SwiftPM test resources must live in the test target. That
    /// copy is itself a drift hazard, so it is compared with the real file here —
    /// otherwise the doc-driven test could keep passing against a stale duplicate while
    /// the page the reader actually sees says something else.
    @Test("the fixture copy of file-roles.md matches the page the skill ships")
    func fileRolesCopyMatchesTheSkill() throws {
        let shipped = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ContributorKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appending(path: "plugin/skills/contributions/references/file-roles.md")
        guard FileManager.default.fileExists(atPath: shipped.path) else {
            // Running from somewhere the source tree is not laid out as expected — say
            // so rather than passing silently.
            Issue.record("could not find the shipped page at \(shipped.path)")
            return
        }
        #expect(
            try Data(contentsOf: shipped) == (try Fixtures.data("file-roles.md")),
            "cp plugin/skills/contributions/references/file-roles.md Tests/ContributorKitTests/Fixtures/")
    }

    @Test("the shipped default config is byte-identical to the fixtures' copy")
    func shippedDefaultMatchesFixture() throws {
        let fromFixtures = String(
            decoding: try Fixtures.data("contributorkit.default.yml"), as: UTF8.self)
        #expect(try Configuration.defaultYAMLText() == fromFixtures)
        #expect(
            try Configuration.builtInDefaults().roles.map(\.role)
                == ["vendor", "test", "build", "docs", "source"])
    }

    @Test("the defaults carry both provenances — measured roles and reasoned inbound rules")
    func defaultsCoverBothFiles() throws {
        let config = try Configuration.builtInDefaults()
        #expect(config.offerPhrases.contains("separate PR"))
        #expect(config.cloc.forceLang[".m"] == "Objective-C")
        #expect(config.inbound.supersessionPhrases.contains("this report is out of date"))
        #expect(config.inbound.boilerplateBlocks.contains("<picture>...</picture>"))
    }

    @Test("a .contributorkit.yml replaces a whole key, never a merged order")
    func fileOverridesWholeKey() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ck-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try """
            roles:
              - role: everything
                globs: ["**"]
            """.write(
                to: directory.appending(path: ".contributorkit.yml"),
                atomically: true, encoding: .utf8)

        let config = try Configuration.load(directory: directory)
        #expect(config.roles.map(\.role) == ["everything"])
        // Untouched keys keep the shipped defaults.
        #expect(config.offerPhrases.contains("separate PR"))
    }
}
