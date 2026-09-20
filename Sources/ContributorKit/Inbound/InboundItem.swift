import Foundation

/// One line of `contrib in`'s worklist.
///
/// The `--json` shape is exactly <doc:Design>'s contract: `id`, `kind`, `permalink`,
/// `state`, `question`, `changed`, and the minimum text — the ask, and my reply if
/// there is one. **Nothing else.** Both failure modes cost the same thing: if the CLI
/// judges meaning it will be wrong and the model re-derives anyway; if it dumps raw
/// comments the model re-enumerates, which is the waste being eliminated.
public struct InboundItem: Codable, Sendable {
    public struct Text: Codable, Sendable {
        public var ask: String
        public var reply: String?

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(ask, forKey: .ask)
            try container.encode(reply, forKey: .reply)
        }
    }

    public var id: String
    public var kind: Channel
    public var permalink: String
    public var state: ItemState
    public var question: String
    /// What moved since the last run. `nil` means the snapshot had it and nothing
    /// changed — which is the majority, and why this is a differ and not a reporter.
    public var changed: String?
    public var text: Text

    /// Not part of the `--json` item contract — carried for terminal grouping only
    /// (<doc:Design>), and stripped before encoding.
    public var roundID: String?
    public var roundAt: Date?
    public var author: String?
    /// The state this item held last run, when it differs from the current one.
    public var previousState: ItemState?
    /// Raised before the configured review horizon — an era this repository declared
    /// out of audit.
    public var beyondHorizon: Bool = false
    /// True on the run that first records this item. "New since the last run" is a
    /// baseline artifact, not activity, and must not be read as one.
    public var isNewToSnapshot: Bool = false
    /// The PR or issue is closed or merged.
    public var subjectClosed: Bool = false

    /// Does this item belong in the output?
    ///
    /// Beyond the horizon an item stays hidden **unless something actually moved** — a
    /// body edit or a state transition. A reviewer editing a June comment today is
    /// today's activity, and a horizon that hid that would be a check quietly running
    /// against the wrong set.
    public var isVisible: Bool {
        guard beyondHorizon else { return true }
        return changed != nil && !isNewToSnapshot
    }

    /// Listed without `--all`?
    ///
    /// Owed items always, wherever the subject stands: reviewers post rounds after a
    /// merge, and a close can carry a condition addressed to me. A `needsLook` item
    /// only while the subject is open — once it is closed nobody is waiting on the
    /// responsiveness check — unless something about it actually moved.
    public var isListedByDefault: Bool {
        guard isVisible else { return false }
        if state.isOwed { return true }
        if state.needsLook && !subjectClosed { return true }
        // Real movement only. "New since the last run" is a baseline artifact, and
        // treating it as movement made the first run on a PR print every badge-only body
        // it had ever received — 49 of them on one real PR, none of them actionable.
        // A state that is never owed becomes visible when it *changes*, not when it is
        // first seen.
        return changed != nil && !isNewToSnapshot
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, permalink, state, question, changed, text
    }

    /// All seven keys, always — `changed` and `text.reply` encode as `null` rather
    /// than vanishing. The contract is *exactly* these keys, so a consumer reads a
    /// null instead of having to tell "absent" from "nothing changed".
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(permalink, forKey: .permalink)
        try container.encode(state, forKey: .state)
        try container.encode(question, forKey: .question)
        try container.encode(changed, forKey: .changed)
        try container.encode(text, forKey: .text)
    }
}
