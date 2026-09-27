import Foundation

/// One line of `contrib in`'s worklist.
///
/// The `--json` shape is exactly <doc:Design>'s contract: `id`, `kind`, `permalink`,
/// `state`, `question`, `changed`, the minimum text — the ask, and my reply if there is
/// one — and an inline thread's `resolution`. **Nothing else.** Both failure modes cost
/// the same thing: if the CLI judges meaning it will be wrong and the model re-derives
/// anyway; if it dumps raw comments the model re-enumerates, which is the waste being
/// eliminated.
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

    /// GitHub's resolution of an inline thread, and whose login set it.
    ///
    /// **Reported, never decided on** (``RemoteThread``): resolution happens for more
    /// reasons than the asker's consent, so the reader is given who did it rather than
    /// a conclusion. `byAsker` is the one derived field — the kit compares `resolvedBy`
    /// with the root's author, since the item carries no author — and it cannot tell a
    /// reviewer bot from its own fix session, which share a login.
    public struct Resolution: Codable, Sendable, Equatable {
        public var isResolved: Bool
        public var resolvedBy: String?
        public var byAsker: Bool

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(isResolved, forKey: .isResolved)
            try container.encode(resolvedBy, forKey: .resolvedBy)
            try container.encode(byAsker, forKey: .byAsker)
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
    /// Inline threads only; `nil` on the channels that have no resolution, and on a
    /// thread whose source did not say.
    public var resolution: Resolution? = nil

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

    /// A `needsLook` question someone may still be waiting on.
    ///
    /// Closure quiets it — once the subject is closed nobody is waiting on the
    /// responsiveness check — **unless the thread is still unresolved**. That is the
    /// asker's side of the thread disagreeing with closure, and it only keeps the item
    /// listed: nothing is cleared or owed on it. Issue #7's case 4 was the one open
    /// thread across seven pull requests, and closure hid it among twelve quiet ones.
    public var awaitsLook: Bool {
        state.needsLook && (!subjectClosed || resolution?.isResolved == false)
    }

    /// Listed without `--all`?
    ///
    /// Owed items always, wherever the subject stands: reviewers post rounds after a
    /// merge, and a close can carry a condition addressed to me. A `needsLook` item
    /// while it ``awaitsLook``, or once something about it actually moved.
    public var isListedByDefault: Bool {
        guard isVisible else { return false }
        if state.isOwed { return true }
        if awaitsLook { return true }
        // Unexamined is not empty: the flag lists until someone acknowledges it —
        // the whole point is that a collapsed section cannot be told from a hidden
        // ask without looking, so looking (or declining to) must be a recorded act.
        if state == .collapsedUnexamined { return true }
        // Real movement only. "New since the last run" is a baseline artifact, and
        // treating it as movement made the first run on a PR print every badge-only body
        // it had ever received — 49 of them on one real PR, none of them actionable.
        // A state that is never owed becomes visible when it *changes*, not when it is
        // first seen.
        return changed != nil && !isNewToSnapshot
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, permalink, state, question, changed, text, resolution
    }

    /// All eight keys, always — `changed`, `text.reply` and `resolution` encode as
    /// `null` rather than vanishing. The contract is *exactly* these keys, so a consumer
    /// reads a null instead of having to tell "absent" from "nothing changed".
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(permalink, forKey: .permalink)
        try container.encode(state, forKey: .state)
        try container.encode(question, forKey: .question)
        try container.encode(changed, forKey: .changed)
        try container.encode(text, forKey: .text)
        try container.encode(resolution, forKey: .resolution)
    }
}
