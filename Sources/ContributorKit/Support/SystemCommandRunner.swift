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

        // Set before `run()`: a child that exits at once must still find a handler.
        let exited = Exited()
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed(
                argv: argv, underlying: "\(executable): \(error.localizedDescription)")
        }

        async let outData = Self.drain(outPipe)
        async let errData = Self.drain(errPipe)
        let (stdout, stderr) = await (outData, errData)
        await exited.wait()

        return CommandOutput(
            argv: argv, status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    /// Read a pipe to EOF off the calling thread. Reading both pipes concurrently is
    /// required, not tidiness: `cloc --by-file` on a large range fills the 64 KB pipe
    /// buffer and deadlocks against the wait for exit if either is read serially.
    private static func drain(_ pipe: Pipe) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
                continuation.resume(returning: data)
            }
        }
    }

    /// The child's exit, as `terminationHandler` reports it. The handler runs on a
    /// thread of Foundation's choosing and may fire before anyone waits, so whichever
    /// of `signal` and `wait` comes second resumes the waiter.
    ///
    /// `waitUntilExit()` is not used: it runs the calling thread's run loop, and a
    /// task that resumed on another cooperative thread after `run()` could stay parked
    /// there after the child had exited and been reaped. A full `swift test` hung over
    /// ten minutes that way.
    private final class Exited: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private var waiter: CheckedContinuation<Void, Never>?

        func signal() {
            let waiter = lock.withLock {
                done = true
                defer { self.waiter = nil }
                return self.waiter
            }
            waiter?.resume()
        }

        func wait() async {
            await withCheckedContinuation { continuation in
                let done = lock.withLock {
                    if !self.done { waiter = continuation }
                    return self.done
                }
                if done { continuation.resume() }
            }
        }
    }
}
