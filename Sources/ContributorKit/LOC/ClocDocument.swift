import Foundation

/// Decoding `cloc --git --diff --json`, and the four traps <doc:Design> records.
///
/// 1. **Two document shapes, one command.** Without `--by-file` the four sections are
///    keyed by *language*; with it, by *path*. One `Codable` type does not fit both,
///    so this decodes into `[String: Counts]` plus a `KeySpace` tag saying which.
/// 2. **`SUM` is a sibling key inside every section**, not a top-level object. It is
///    dropped while iterating, or every total doubles.
/// 3. **`nFiles` is unreliable** — populated only on `modified` by language, `0`
///    everywhere by file. It is not decoded at all; file counts come from counting keys.
/// 4. **Paths contain spaces.** Everything here reads JSON keys; nothing splits output.
public struct ClocDocument: Sendable {
    public enum KeySpace: String, Sendable {
        case language
        case path
    }

    public let keySpace: KeySpace
    /// Section name (`added`/`removed`/`modified`/`same`) → key → counts, `SUM` removed.
    public let sections: [String: [String: Counts]]

    private static let sectionNames = ["added", "removed", "modified", "same"]
    private static let sumKey = "SUM"

    public init(json data: Data, keySpace: KeySpace) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClocError.malformedDocument("top level is not an object")
        }
        guard root["header"] != nil else {
            // cloc exits 0 and emits nothing at all when a range touches no file it
            // recognises. An empty decode reporting zeroes is a check that passes
            // because it did not run — refuse it here instead.
            throw root.isEmpty
                ? ClocError.noDiffDocument
                : ClocError.malformedDocument("no `header` — cloc produced an unexpected document")
        }

        var sections: [String: [String: Counts]] = [:]
        for name in Self.sectionNames {
            guard let raw = root[name] as? [String: Any] else { continue }
            var bucket: [String: Counts] = [:]
            for (key, value) in raw where key != Self.sumKey {
                guard let fields = value as? [String: Any] else { continue }
                bucket[key] = Counts(
                    code: fields["code"] as? Int ?? 0,
                    comment: fields["comment"] as? Int ?? 0,
                    blank: fields["blank"] as? Int ?? 0)
            }
            sections[name] = bucket
        }
        guard sections.values.contains(where: { !$0.isEmpty }) else {
            throw ClocError.malformedDocument("every diff section is empty")
        }
        self.keySpace = keySpace
        self.sections = sections
    }

    /// The document rolled up across all keys.
    public var stats: DiffStats {
        DiffStats(
            added: total("added"), removed: total("removed"),
            modified: total("modified"), same: total("same"))
    }

    /// Per-key stats — by language, or by path when the document came from `--by-file`.
    public var byKey: [String: DiffStats] {
        var out: [String: DiffStats] = [:]
        for (section, bucket) in sections {
            for (key, counts) in bucket {
                var stats = out[key] ?? DiffStats()
                switch section {
                case "added": stats.added = counts
                case "removed": stats.removed = counts
                case "modified": stats.modified = counts
                case "same": stats.same = counts
                default: break
                }
                out[key] = stats
            }
        }
        return out
    }

    private func total(_ section: String) -> Counts {
        (sections[section] ?? [:]).values.reduce(Counts(), +)
    }
}

public enum ClocError: Error, CustomStringConvertible {
    case malformedDocument(String)
    case noDiffDocument
    /// `--include-lang` left nothing of what the range touched: `touched` is the
    /// languages cloc counts there without the filter.
    case filterExcludedEverything(languages: [String], range: String, touched: [String])
    case clocNotFound(String?)

    public var description: String {
        switch self {
        case .malformedDocument(let why):
            return "cloc output could not be read: \(why)"
        case .noDiffDocument:
            return "cloc output could not be read: no `header` — cloc produced no diff document"
        case .filterExcludedEverything(let languages, let range, let touched):
            return "cloc matched no files: --include-lang=\(languages.joined(separator: ",")) "
                + "excluded every path in \(range) (touched: \(touched.joined(separator: ", "))); "
                + "pass --lang"
        case .clocNotFound(let path):
            return path.map { "cloc not found at \($0)" }
                ?? "cloc not found on PATH — pass --cloc <path>, or `brew install cloc`"
        }
    }
}
