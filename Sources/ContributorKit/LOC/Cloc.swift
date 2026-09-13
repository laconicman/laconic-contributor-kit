import Foundation

/// Invokes `cloc --git --diff` and decodes it. **`cloc` is the classifier; this
/// package does not contain a line counter** (TASK §3.1) — writing one means
/// re-deriving a 300-language comment table to arrive at the same numbers, with the
/// `*p = x;` bug waiting at the end of it.
public struct Cloc: Sendable {
    public let executable: String
    public let runner: any CommandRunner

    public init(executable: String, runner: any CommandRunner) {
        self.executable = executable
        self.runner = runner
    }

    /// `--cloc <path>` if given, else the first of the well-known locations that
    /// exists, else `cloc` on `PATH`. Neither is hardcoded (TASK §2).
    public static func locate(explicit: String?, repository: URL) -> String {
        if let explicit { return explicit }
        let vendored = repository.appending(path: "node_modules/cloc/lib/cloc")
        if FileManager.default.isExecutableFile(atPath: vendored.path) { return vendored.path }
        return "cloc"
    }

    public func version(cwd: URL) async throws -> String {
        let out = try await runner.runExpectingOutput([executable, "--version"], cwd: cwd)
        return out.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public struct Options: Sendable {
        public var languages: [String]
        public var forceLang: [String: String]
        public var byFile: Bool
        public var ignoreWhitespace: Bool

        public init(
            languages: [String], forceLang: [String: String] = [:],
            byFile: Bool = false, ignoreWhitespace: Bool = false
        ) {
            self.languages = languages
            self.forceLang = forceLang
            self.byFile = byFile
            self.ignoreWhitespace = ignoreWhitespace
        }
    }

    public func argv(refA: String, refB: String, options: Options) -> [String] {
        var argv = [executable, "--git", "--diff", refA, refB]
        if !options.languages.isEmpty {
            // ONE argument whose value contains a comma, a slash and a space. Through
            // `Process` it must be a single element of the array, never split on
            // spaces (TASK §3.2).
            argv.append("--include-lang=" + options.languages.joined(separator: ","))
        }
        for (ext, language) in options.forceLang.sorted(by: { $0.key < $1.key }) {
            // cloc must otherwise resolve `.m` against MATLAB, Mercury and MUMPS, and
            // it does not always guess right.
            argv.append("--force-lang=\(language),\(ext.hasPrefix(".") ? String(ext.dropFirst()) : ext)")
        }
        if options.byFile { argv.append("--by-file") }
        if options.ignoreWhitespace { argv.append("--ignore-whitespace") }
        argv.append(contentsOf: ["--json", "--quiet"])
        return argv
    }

    public func diff(
        refA: String, refB: String, options: Options, cwd: URL
    ) async throws -> ClocDocument {
        let out = try await runner.runExpectingOutput(
            argv(refA: refA, refB: refB, options: options), cwd: cwd)
        return try ClocDocument(json: out.stdout, keySpace: options.byFile ? .path : .language)
    }
}
