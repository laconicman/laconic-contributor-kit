import Foundation

/// A `-`/`+` line diff for `contrib show`'s "what moved" view.
///
/// Deliberately not a minimal diff: the common prefix and suffix lines are trimmed,
/// then everything between is shown as removed and added. For the edits this exists
/// to display — an appended badge, a re-opened finding rewritten wholesale — the
/// middle *is* the change, and a Myers implementation would buy smaller output for
/// cases nobody has hit at the cost of an algorithm nobody needs to read.
public enum LineDiff {
    /// `-`-prefixed removed lines then `+`-prefixed added lines; empty when identical.
    public static func lines(from old: String, to new: String) -> [String] {
        let oldLines = old.components(separatedBy: .newlines)
        let newLines = new.components(separatedBy: .newlines)

        var prefix = 0
        while prefix < min(oldLines.count, newLines.count),
            oldLines[prefix] == newLines[prefix]
        { prefix += 1 }

        var suffix = 0
        while suffix < min(oldLines.count - prefix, newLines.count - prefix),
            oldLines[oldLines.count - 1 - suffix] == newLines[newLines.count - 1 - suffix]
        { suffix += 1 }

        return oldLines[prefix ..< oldLines.count - suffix].map { "- " + $0 }
            + newLines[prefix ..< newLines.count - suffix].map { "+ " + $0 }
    }
}
