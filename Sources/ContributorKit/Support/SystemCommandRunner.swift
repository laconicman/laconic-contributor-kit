import Foundation

/// `Foundation.Process` behind `CommandRunner`.
///
/// <doc:Design> prefers `swift-subprocess`; it is not used here because `Process` needs no
/// dependency and this protocol is the only thing any caller sees, so swapping it is
/// one file. `stdout` and `stderr` are read on separate pipes and never merged: the
/// feedback's rule 5 case 3 was a successful query returning a diagnostic as its
/// hit count, which is exactly what merging produces.
public struct SystemCommandRunner: CommandRunner {
    public init() {}

    public func run(_ argv: [String], cwd: URL?) async throws -> CommandOutput {
        guard let executable = argv.first else {
            throw CommandError.launchFailed(argv: argv, underlying: "empty argv")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = argv
        if let cwd { process.currentDirectoryURL = cwd }

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed(
                argv: argv, underlying: "\(executable): \(error.localizedDescription)")
        }

        async let outData = Self.drain(outPipe)
        async let errData = Self.drain(errPipe)
        let (stdout, stderr) = await (outData, errData)
        process.waitUntilExit()

        return CommandOutput(
            argv: argv, status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    /// Read a pipe to EOF off the calling thread. Reading both pipes concurrently is
    /// required, not tidiness: `cloc --by-file` on a large range fills the 64 KB pipe
    /// buffer and deadlocks against `waitUntilExit` if either is read serially.
    private static func drain(_ pipe: Pipe) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
                continuation.resume(returning: data)
            }
        }
    }
}
