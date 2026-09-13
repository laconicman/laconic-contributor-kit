import Foundation
import Testing

@testable import ContributorKit

/// File roles: ordered, first match wins, and the order is part of the contract
/// (TASK §3.3). These assertions are against `manifest.json`'s own `paths` and
/// `byRole` blocks, which `make_manifest.py` produced with the same ordered list the
/// 39/33/18/7/1 distribution was measured with.
@Suite("file roles — ordered, first match wins")
struct RoleTests {

    private func classifier() throws -> FileRoleClassifier {
        try Configuration.builtInDefaults().roleClassifier()
    }

    /// `**/x` must also match a bare `x` at the repo root, which naïve glob matching
    /// does not do. TASK §3.3 asks for this case explicitly.
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

    /// **TASK §3.3's prose is wrong about this one case and the shipped rules are
    /// right.** The prose says `tests/automated/Makefile` lands in `build`; the ordered
    /// list ships `test` ahead of `build`, so it lands in `test` — and the measured
    /// 18%/7% split was produced by that same ordering, so the rules are authoritative
    /// and the sentence is the error. Pinned here so the next reader finds the answer
    /// rather than the claim.
    @Test("test precedes build, so tests/automated/Makefile is `test`")
    func testPrecedesBuild() throws {
        #expect(try classifier().role(of: "tests/automated/Makefile") == "test")
    }

    /// Every path the by-file fixtures touch, against the roles `make_manifest.py`
    /// assigned. This is the check that the Swift glob matcher and the Python one
    /// agree, rather than each being separately plausible.
    @Test("every fixture path classifies exactly as the manifest recorded")
    func matchesManifestPaths() throws {
        let c = try classifier()
        var checked = 0
        for fixture in try Fixtures.manifest().fixtures {
            for (path, expected) in fixture.paths ?? [:] {
                #expect(c.role(of: path) == expected, "\(path)")
                checked += 1
            }
        }
        #expect(checked == 6, "both by-file fixtures contribute their paths")
    }

    /// `darwin-tls` by role: `source: code +28, comment +23` and
    /// `test: code +4, comment +7`. One source file and one test file, so the split is
    /// assertable rather than synthetic.
    @Test("by-role aggregation reproduces the manifest's darwin-tls split")
    func byRoleAggregation() throws {
        let c = try classifier()
        let fixture = try #require(
            try Fixtures.manifest().fixtures.first {
                $0.file == "cloc/darwin-tls.branch.by-file.json"
            })
        let document = try ClocDocument(
            json: try Fixtures.data(fixture.file), keySpace: .path)

        var byRole: [String: DiffStats] = [:]
        for (path, stats) in document.byKey {
            let role = c.role(of: path) ?? "unclassified"
            byRole[role] = (byRole[role] ?? DiffStats()) + stats
        }

        #expect(byRole["source"]?.net == Counts(code: 28, comment: 23, blank: 8))
        #expect(byRole["test"]?.net == Counts(code: 4, comment: 7, blank: 0))
        for (role, expected) in fixture.byRole ?? [:] {
            #expect(byRole[role]?.net == expected.net, "role \(role)")
            #expect(byRole[role]?.added == expected.added, "role \(role) added")
        }
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
