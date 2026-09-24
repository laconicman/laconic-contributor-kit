import Foundation

/// Strips a review body down to its prose, so "is this body empty?" can be answered
/// without reading meaning.
///
/// This exists because **empty review bodies are the common case, not an edge case**.
/// One field round produced six review bodies of which four were badge markup only —
/// zero characters after stripping HTML comments and the `<picture>` block. Listing
/// those as obligations lists four no-ops.
public struct BoilerplateStripper: Sendable {
    private let blocks: [(open: String, close: String)]
    private let linePatterns: [NSRegularExpression]
    /// Case-insensitive substrings of a `<summary>`'s text whose `<details>`
    /// block unwraps into prose rather than collapsing to a marker.
    private let keptDetailsSummaries: [String]

    /// The line prefix a collapsed `<details>` block leaves in `prose`. A marker
    /// flags retrievable content without being an ask itself — the emptiness
    /// check in `InboundAudit` filters lines starting with this.
    public static let collapsedMarkerPrefix = "[collapsed:"

    public init(settings: Configuration.InboundSettings) throws {
        self.blocks = settings.boilerplateBlocks.compactMap { spec in
            let parts = spec.components(separatedBy: "...")
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            return (parts[0], parts[1])
        }
        self.linePatterns = try settings.boilerplatePatterns.map {
            try NSRegularExpression(pattern: $0)
        }
        self.keptDetailsSummaries = settings.keptDetailsSummaries
    }

    public func prose(of body: String) -> String {
        strip(body).prose
    }

    /// Strip, and return the marker lines the details pass emitted AND that
    /// survive into the output. The set is provenance, not shape: a
    /// marker-shaped line the *author* wrote — quoting the format, filing a
    /// bug about it — matches `isCollapsedMarker` but collapsed nothing, and a
    /// marker a later boilerplate pass erased flags content nobody can
    /// retrieve anyway. Neither counts as unexamined.
    public func strip(_ body: String) -> (prose: String, collapsedMarkers: Set<String>) {
        // The details pass runs FIRST: an earlier `<!--…-->` pass could sever a
        // summary from its content — the same pairing lesson `boilerplateBlocks`'s
        // order already encodes — and a kept section's inner comments still strip
        // normally in the generic passes that follow.
        var (text, emitted) = collapseDetails(in: Substring(body))
        for block in blocks {
            text = Self.removeBlocks(from: text, open: block.open, close: block.close)
        }
        let kept = text.components(separatedBy: .newlines).filter { line in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            return !linePatterns.contains { $0.firstMatch(in: line, range: range) != nil }
        }
        let surviving = emitted.intersection(
            Set(kept.map { $0.trimmingCharacters(in: .whitespaces) }))
        return (kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                surviving)
    }

    /// The full emitted marker shape — `[collapsed: "Title" ·8hex]`. A bare
    /// prefix match would eat an author's own line that happens to open with
    /// `[collapsed:`; colliding with the generated form needs the quoted
    /// title, the separator, and the eight-char hash.
    public static func isCollapsedMarker(_ line: String) -> Bool {
        guard line.hasPrefix("\(collapsedMarkerPrefix) \""),
            let separator = line.range(of: "\" ·", options: .backwards),
            line.hasSuffix("]")
        else { return false }
        let hash = line[separator.upperBound...].dropLast()
        return hash.count == 8 && hash.allSatisfy(\.isHexDigit)
    }

    /// `prose` minus the lines the details pass emitted — the asker's own
    /// text, which is what supersession and informational phrases are meant to
    /// match. Provenance, not shape: a marker's embedded title is not the
    /// asker's words, so a collapsed section titled like a retraction must not
    /// retract the body it rides with; and a marker-shaped line the author
    /// *wrote* is not in `markers`, so a request written in marker form stays
    /// prose.
    public func substantiveProse(_ prose: String, markers: Set<String>) -> String {
        prose.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !markers.contains(trimmed)
        }.joined(separator: "\n")
    }

    /// Kept sections recurse; the cap keeps a deliberately deep body — nested
    /// kept summaries are constructible well inside GitHub's comment limit —
    /// from exhausting the stack. Past it a matching section collapses to a
    /// marker like any unmatched one.
    private static let maxDetailsNesting = 32

    /// Unwraps `<details>` blocks whose summary matches the keep list, collapses
    /// the rest to a marker. Nested blocks inside a kept section are classified
    /// on their own summaries; inside a collapsed one they disappear with it.
    private func collapseDetails(in text: Substring, level: Int = 0)
        -> (String, Set<String>)
    {
        var out = ""
        var markers = Set<String>()
        var rest = text
        while let open = Self.tagOutsideComments("<details", in: rest, boundaryCheck: true) {
            guard let openTagEnd = rest[open.upperBound...].range(of: ">") else { break }
            let innerStart = openTagEnd.upperBound

            // The close is the DEPTH-zero `</details>`: a nested block must not
            // end its parent early, so opens and closes are paired by counting.
            var depth = 1
            var cursor = innerStart
            var closeTag: Range<String.Index>?
            while closeTag == nil {
                guard let close = Self.tagOutsideComments(
                    "</details>", in: rest[cursor...], boundaryCheck: false)
                else {
                    // Unclosed opener swallows the rest — same rule as removeBlocks.
                    return (out + rest[..<open.lowerBound], markers)
                }
                if let nested = Self.tagOutsideComments(
                    "<details", in: rest[cursor..<close.lowerBound], boundaryCheck: true)
                {
                    depth += 1
                    cursor = nested.upperBound
                } else {
                    depth -= 1
                    if depth == 0 { closeTag = close }
                    cursor = close.upperBound
                }
            }
            let inner = rest[innerStart..<closeTag!.lowerBound]
            let (title, content) = Self.summary(in: inner)
            let kept = title.map { t in
                keptDetailsSummaries.contains {
                    t.range(of: $0, options: .caseInsensitive) != nil
                }
            } ?? false
            out += rest[..<open.lowerBound]
            if kept, let title, level < Self.maxDetailsNesting {
                let (inner, nested) = collapseDetails(in: content, level: level + 1)
                out += title + "\n" + inner
                markers.formUnion(nested)
            } else {
                let marker = Self.marker(title: title, content: inner)
                out += "\n" + marker + "\n"
                markers.insert(marker)
            }
            rest = rest[closeTag!.upperBound...]
        }
        return (out + rest, markers)
    }

    /// Tag search that skips `<!-- … -->` spans: a tag inside a comment is not
    /// markup the renderer sees, so the pairing walk must not see it either.
    /// An unclosed comment ends the search — the rest is commentary, the same
    /// rule `removeBlocks` already encodes. Ranges are into `text` itself —
    /// nothing is copied, so every slice downstream still indexes correctly.
    private static func tagOutsideComments(
        _ name: String, in text: Substring, boundaryCheck: Bool
    ) -> Range<String.Index>? {
        var cursor = text.startIndex
        while true {
            let slice = text[cursor...]
            let comment = slice.range(of: "<!--")
            let found = boundaryCheck ? tag(name, in: slice) : slice.range(of: name)
            guard let found else { return nil }
            if let comment, comment.lowerBound < found.lowerBound {
                // A comment opens before the tag — the tag is inside it. Skip the
                // comment body and rescan what follows.
                guard let end = text[comment.upperBound...].range(of: "-->") else {
                    return nil
                }
                cursor = end.upperBound
                continue
            }
            return found
        }
    }

    /// `<name` followed by `>` or whitespace — `<detailsfoo` is not a tag.
    private static func tag(_ name: String, in text: Substring) -> Range<String.Index>? {
        var cursor = text.startIndex
        while let found = text[cursor...].range(of: name) {
            if found.upperBound == text.endIndex || text[found.upperBound] == ">"
                || text[found.upperBound].isWhitespace
            {
                return found
            }
            cursor = found.upperBound
        }
        return nil
    }

    /// The first `<summary>…</summary>`'s text is the title; any later `<summary>`
    /// in the block is content (a pasted example, say), not another title.
    ///
    /// The search stops at the first nested `<details>`: a `<summary>` inside one
    /// is that block's legend, not this one's — an outer block with no summary of
    /// its own collapses untitled rather than unwrapping on a borrowed title. (A
    /// depth-zero summary AFTER a nested block is legal HTML but unseen in the
    /// field; it is missed, and the block collapses — flagged, not leaked.)
    private static func summary(in inner: Substring) -> (title: String?, content: Substring) {
        let scope =
            tagOutsideComments("<details", in: inner, boundaryCheck: true)
            .map { inner[..<$0.lowerBound] } ?? inner
        guard let open = tagOutsideComments("<summary", in: scope, boundaryCheck: true),
            let openEnd = scope[open.upperBound...].range(of: ">"),
            let close = tagOutsideComments(
                "</summary>", in: scope[openEnd.upperBound...], boundaryCheck: false)
        else { return (nil, inner) }
        let title = inner[openEnd.upperBound..<close.lowerBound]
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .components(separatedBy: .whitespacesAndNewlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let content = inner[..<open.lowerBound] + inner[close.upperBound...]
        return (title.isEmpty ? nil : title, content)
    }

    /// `[collapsed: "Title" ·hash]` — the hash covers the collapsed content, so an
    /// edit inside the section moves `prose` and can never pass for markup churn.
    private static func marker(title: String?, content: Substring) -> String {
        let hash = SHA256.hex(of: String(content)).prefix(8)
        return "\(collapsedMarkerPrefix) \"\(title ?? "untitled")\" ·\(hash)]"
    }

    /// Non-greedy, repeated, and tolerant of an unclosed opener: a body that opens
    /// `<!--` and never closes it is all boilerplate from there on.
    private static func removeBlocks(from text: String, open: String, close: String) -> String {
        var out = ""
        var rest = Substring(text)
        while let start = rest.range(of: open) {
            out += rest[..<start.lowerBound]
            guard let end = rest[start.upperBound...].range(of: close) else { return out }
            rest = rest[end.upperBound...]
        }
        return out + rest
    }
}
