import ArgumentParser
import ContributorKit
import Foundation

struct LocCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "loc",
        abstract: "Is what I ship getting more laconic?",
        discussion: """
            LOC is a trend, never a quality score. Tests legitimately add lines and
            comments are programmer's politeness, so code, comment and blank are
            reported separately and never summed.

            The figures are INTERNAL BY DEFAULT: an input to your judgement about how
            large a patch really is and whether it wants splitting — not an output to
            anyone else. Nothing reaches a PR, a register row or an upstream thread
            without an explicit flag.

            --range never touches the network.
            """
    )

    @Option(name: .long, help: "Commit range, <base>..<head>.")
    var range: String

    @Option(name: .long, help: "Repository path (default: the working directory).")
    var repo: String = "."

    @Option(name: .long, help: "Path to cloc. Falls back to <repo>/node_modules/cloc/lib/cloc, then PATH.")
    var cloc: String?

    @Flag(name: .long, help: "Walk each commit in the range as well as the range total.")
    var perCommit = false

    @Flag(name: .long, help: "Break the totals down by file role.")
    var byRole = false

    @Flag(name: .long, help: "Also measure modified code with whitespace ignored.")
    var ignoreWhitespace = false

    @Option(name: .long, help: "Languages to include, comma separated.")
    var lang: String?

    @Option(name: .long, help: "table | markdown | json")
    var format: String = "table"

    @Option(name: .long, help: "Append the result to a JSONL ledger.")
    var record: String?

    func run() async throws {
        var provenance = Provenance(command: "contrib loc --range \(range)")
        let repository = URL(fileURLWithPath: repo).standardizedFileURL
        let configuration = try Configuration.load(directory: repository)
        let runner = CountingCommandRunner(SystemCommandRunner())

        let clocPath = Cloc.locate(explicit: cloc, repository: repository)
        let clocTool = Cloc(executable: clocPath, runner: runner)
        provenance.note("cloc \(clocPath)")
        provenance.note("cloc version \(try await clocTool.version(cwd: repository))")

        let parsed = try RangeWalker.parseRange(range)
        let walker = RangeWalker(repository: repository, runner: runner, cloc: clocTool)
        // Resolve both ends so the provenance block names commits, not branch tips that
        // will have moved by the time anyone reads it.
        provenance.note("base \(try await walker.resolve(parsed.base))")
        provenance.note("head \(try await walker.resolve(parsed.head))")

        let languages =
            lang.map { $0.split(separator: ",").map(String.init) }
            ?? configuration.cloc.defaultLanguages

        let report = try await walker.report(
            range: parsed, languages: languages, forceLang: configuration.cloc.forceLang,
            perCommit: perCommit, byRole: byRole, ignoreWhitespace: ignoreWhitespace,
            classifier: try configuration.roleClassifier())

        provenance.subprocessCalls = runner.count
        provenance.examined("languages", languages.count)
        provenance.examined("commits", report.commits?.count ?? 0)
        provenance.examined("paths", report.byPath?.count ?? 0)
        if let unclassified = report.byPath?.filter({ $0.value == "unclassified" }), !unclassified.isEmpty {
            provenance.anomaly(
                "unclassifiedPaths",
                "\(unclassified.count) path(s) matched no role rule — the catch-all is missing")
        }

        switch format {
        case "markdown": print(LocReporting.markdown(report))
        case "json":
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(report), as: UTF8.self))
        default: print(LocReporting.terminal(report))
        }

        if let record {
            try Ledger(url: URL(fileURLWithPath: record)).append(report)
            provenance.note("appended to \(record)")
        }

        try Self.emit(provenance, quiet: false)
    }
}
