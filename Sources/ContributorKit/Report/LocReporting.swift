import Foundation

/// `contrib loc` output. Three columns, always, and never a sum (<doc:Design>).
public enum LocReporting {

    public static func terminal(_ report: LocReport) -> String {
        var lines: [String] = []
        lines.append("\(report.repository)  \(report.refA)..\(report.refB)")
        lines.append("")
        lines.append(row("", "code", "comment", "blank"))
        lines.append(row("added", report.total.added))
        lines.append(row("removed", report.total.removed))

        var modified = row("modified", report.total.modified)
        if let corrected = report.modifiedCodeIgnoringWhitespace {
            // Reported twice in one row: hiding the reindentation share overstates the
            // work. On the ground-truth branch ~43% of modified-code churn was
            // reindentation.
            modified += "   (code \(corrected) excluding whitespace)"
        }
        lines.append(modified)
        lines.append(row("net", report.total.net, signed: true))

        if let ratio = report.total.commentToCodeRatio {
            lines.append("")
            lines.append("comment/code   \(String(format: "%.2f", ratio))")
        }

        if let byRole = report.byRole, !byRole.isEmpty {
            lines.append("")
            lines.append("by role — net")
            for role in byRole.keys.sorted() {
                lines.append(row("  " + role, byRole[role]!.net, signed: true))
            }
        }

        if let commits = report.commits, !commits.isEmpty {
            lines.append("")
            lines.append("per commit — net (these do NOT sum to the branch total; commits re-touch lines)")
            for commit in commits {
                let net = commit.stats.net
                lines.append(
                    "  \(commit.sha.prefix(9))  "
                        + "code \(Self.signed(net.code).padded(to: 6))"
                        + "comment \(Self.signed(net.comment).padded(to: 6))"
                        + commit.subject)
            }
        }

        lines.append("")
        lines.append(
            "LOC is a trend, never a quality score: tests add lines legitimately and "
                + "comments are politeness. The three columns are never summed.")
        return lines.joined(separator: "\n")
    }

    public static func markdown(_ report: LocReport) -> String {
        var lines = [
            "# LOC — \(report.repository) `\(report.refA)..\(report.refB)`",
            "",
            "| | code | comment | blank |",
            "|---|---:|---:|---:|",
            mdRow("added", report.total.added),
            mdRow("removed", report.total.removed),
            mdRow("modified", report.total.modified),
            mdRow("**net**", report.total.net, signed: true),
        ]
        if let corrected = report.modifiedCodeIgnoringWhitespace {
            lines.append("")
            lines.append(
                "Modified code excluding whitespace: **\(corrected)** "
                    + "(raw \(report.total.modified.code)).")
        }
        if let ratio = report.total.commentToCodeRatio {
            lines.append("")
            lines.append("Comment-to-code ratio: **\(String(format: "%.2f", ratio))**.")
        }
        if let byRole = report.byRole, !byRole.isEmpty {
            lines.append("")
            lines.append("## By role — net")
            lines.append("")
            lines.append("| role | code | comment | blank |")
            lines.append("|---|---:|---:|---:|")
            for role in byRole.keys.sorted() {
                lines.append(mdRow(role, byRole[role]!.net, signed: true))
            }
        }
        if let commits = report.commits, !commits.isEmpty {
            lines.append("")
            lines.append("## Per commit — net")
            lines.append("")
            lines.append(
                "These **do not sum to the branch total** and are not a check on it: "
                    + "commits re-touch the same lines. Both views are correct.")
            lines.append("")
            lines.append("| commit | code | comment | subject |")
            lines.append("|---|---:|---:|---|")
            for commit in commits {
                lines.append(
                    "| `\(commit.sha.prefix(9))` | \(Self.signed(commit.stats.net.code)) "
                        + "| \(Self.signed(commit.stats.net.comment)) | \(commit.subject) |")
            }
        }
        lines.append("")
        lines.append(
            "> LOC is a trend, never a quality score. The three columns are never summed.")
        return lines.joined(separator: "\n")
    }

    private static func row(_ label: String, _ counts: Counts, signed isSigned: Bool = false)
        -> String
    {
        row(
            label,
            isSigned ? Self.signed(counts.code) : "\(counts.code)",
            isSigned ? Self.signed(counts.comment) : "\(counts.comment)",
            isSigned ? Self.signed(counts.blank) : "\(counts.blank)")
    }

    private static func row(_ label: String, _ a: String, _ b: String, _ c: String) -> String {
        label.padded(to: 15) + a.leftPadded(to: 6) + b.leftPadded(to: 10) + c.leftPadded(to: 8)
    }

    private static func mdRow(_ label: String, _ counts: Counts, signed isSigned: Bool = false)
        -> String
    {
        func format(_ value: Int) -> String { isSigned ? Self.signed(value) : "\(value)" }
        return "| \(label) | \(format(counts.code)) | \(format(counts.comment)) "
            + "| \(format(counts.blank)) |"
    }

    private static func signed(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }
}

extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self + " " : String(repeating: " ", count: width - count) + self
    }
}
