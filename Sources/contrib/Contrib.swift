import ArgumentParser
import ContributorKit
import Foundation

@main
struct Contrib: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "contrib",
        abstract: "What was asked of me, what do I still owe, and is what I ship getting more laconic?",
        discussion: """
            Three questions about being an outside contributor to someone else's repo.

              contrib in    What was asked of me that I have not demonstrably absorbed?
              contrib loc   Is what I ship getting more laconic?
              contrib ack   Record where an obligation was absorbed.

            Nothing leaves the workspace without an explicit flag — including LOC
            figures. Default is read, compare, report locally.
            """,
        version: "0.1.0",
        subcommands: [InCommand.self, LocCommand.self, AckCommand.self]
    )
}

/// Every command ends with a provenance block it cannot be run without, and exits
/// non-zero on an anomaly (TASK §13.2). A guard you have to remember to invoke is a
/// guard that does not run.
struct AnomalousExit: Error {}

extension ParsableCommand {
    static func emit(_ provenance: Provenance, quiet: Bool) throws {
        var provenance = provenance
        provenance.finish()
        FileHandle.standardError.write(Data((provenance.rendered() + "\n").utf8))
        if provenance.hasAnomaly { throw ExitCode(2) }
        _ = quiet
    }
}
