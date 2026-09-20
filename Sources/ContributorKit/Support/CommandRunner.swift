import Foundation

/// The single seam through which any code in this package reaches a subprocess.
///
/// Everything else — `cloc`, `git`, `gh` — goes through here, which is what makes
/// the whole suite runnable offline against recorded output.
public protocol CommandRunner: Sendable {
    func run(_ argv: [String], cwd: URL?) async throws -> CommandOutput
}

public struct CommandOutput: Sendable {
    public let argv: [String]
    public let status: Int32
    public let stdout: Data
    public let stderr: Data

    public init(argv: [String], status: Int32, stdout: Data, stderr: Data) {
        self.argv = argv
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

public enum CommandError: Error, CustomStringConvertible {
    case launchFailed(argv: [String], underlying: String)
    case nonZeroExit(argv: [String], status: Int32, stderr: String)
    case emptyOutput(argv: [String])
    case noRecording(argv: [String])

    public var description: String {
        switch self {
        case .launchFailed(let argv, let underlying):
            return "could not launch `\(argv.joined(separator: " "))`: \(underlying)"
        case .nonZeroExit(let argv, let status, let stderr):
            let tail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`\(argv.joined(separator: " "))` exited \(status)"
                + (tail.isEmpty ? "" : ": \(tail)")
        case .emptyOutput(let argv):
            return "`\(argv.joined(separator: " "))` exited 0 but produced no output"
        case .noRecording(let argv):
            return "no recorded output for `\(argv.joined(separator: " "))`"
        }
    }
}

extension CommandRunner {
    /// Run and insist on evidence that the command actually did something.
    ///
    /// `cloc` and `gh` both exit 0 on an empty result, and a decoder handed an empty
    /// document reports zeroes rather than an error — a check that passes because it
    /// did not run. Callers that need output call this rather than `run` directly.
    public func runExpectingOutput(_ argv: [String], cwd: URL? = nil) async throws -> CommandOutput {
        let out = try await run(argv, cwd: cwd)
        guard out.status == 0 else {
            throw CommandError.nonZeroExit(argv: argv, status: out.status, stderr: out.stderrText)
        }
        guard !out.stdout.isEmpty else {
            throw CommandError.emptyOutput(argv: argv)
        }
        return out
    }
}
