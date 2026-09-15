import Foundation

/// What the CLI settled about one item, deterministically.
///
/// The boundary rule (TASK §13.3), stated so it can be enforced in review:
///
/// > The CLI decides everything decidable **without reading meaning**. It never
/// > decides a meaning question. It emits the meaning question, pre-loaded with
/// > exactly the text needed to answer it, and marks everything it already settled so
/// > the model does not re-check it.
///
/// Every case below is a fact about ids, authorship, timestamps and hashes. Not one of
/// them required reading what a comment *says*.
public enum ItemState: String, Codable, Sendable {
    /// Channel 1: a root ask from someone else with no reply from me.
    case openAsk = "open-ask"
    /// Channel 1: I replied. Whether the reply is *responsive* is the model's call.
    case answeredClaimed = "answered-claimed"
    /// Channel 1: the asker themselves replied after my reply.
    ///
    /// Stronger evidence than anything else here, and the field report is right that
    /// §12 did not admit it: it is the asker confirming the answer, where my own reply
    /// only records a claim. Not an inference from proximity — §4.6's rule is about
    /// inferring acceptance from *timing*; this is the asker speaking.
    case answeredConfirmed = "answered-confirmed"
    /// The ask was edited after my answer was posted. §13.4's sharpest check, and free
    /// given the snapshot: my answer may no longer address it.
    case editedAfterMyAnswer = "edited-after-my-answer"
    /// Channels 2 and 3: listed, never auto-cleared, shown first (TASK §12.10).
    case obligationOpen = "obligation-open"
    /// An acknowledgement is recorded and the body has not moved since.
    case obligationAcknowledged = "obligation-acknowledged"
    /// An acknowledgement is recorded but the body hash changed under it, so the item
    /// re-opens by itself. For review bodies the hash is not an optimisation — it is
    /// the only mechanism REST leaves available (§12.10, §13.4).
    case reopenedByEdit = "reopened-by-edit"
    /// The reviewer retracted it — *"This report is out of date."*
    ///
    /// Without this, §12.10's never-auto-cleared rule holds open an ask the asker has
    /// themselves withdrawn, forever, requiring a human acknowledgement of something
    /// nobody is asking for any more.
    case superseded = "superseded"
    /// The reviewer declared this one a note rather than an ask.
    ///
    /// Not the CLI deciding a meaning question — it is reading metadata the *asker*
    /// emitted about their own comment. Devin Review opens every inline body with
    /// `<!-- devin-review-comment {… "kind": "analysis"} -->`, and those are receipts
    /// ("Bridge init field/order match verified"), not requests. Taking the asker at
    /// their word is the same move supersession makes.
    ///
    /// The dangerous direction is a false positive hiding a real ask, so the patterns
    /// are explicit, configurable, and counted in the provenance block.
    case informational = "informational"
    /// Nothing but badge markup once boilerplate is stripped. Counted in the examined
    /// total so the count stays honest, but not owed: §12.3 rule 4's argument for
    /// noise over silence does not extend to noise that is *definitionally* empty.
    case noProse = "no-prose"

    /// Does this item belong on the worklist?
    public var isOwed: Bool {
        switch self {
        case .openAsk, .obligationOpen, .reopenedByEdit, .editedAfterMyAnswer: return true
        case .answeredClaimed, .answeredConfirmed, .obligationAcknowledged,
            .superseded, .noProse, .informational:
            return false
        }
    }

    /// The meaning question this state hands to the model — the decision table
    /// `SKILL.md` carries, kept here so the two cannot drift.
    public var question: String {
        switch self {
        case .openAsk:
            return "Answer it, or say why it should be left out — but it needs an answer."
        case .answeredClaimed:
            return "Is my reply actually responsive to the ask, or only adjacent to it?"
        case .answeredConfirmed:
            return "None. The asker confirmed it themselves; read only if you doubt the match."
        case .editedAfterMyAnswer:
            return "Does the edit change what is being asked? Is my answer now wrong, or merely older?"
        case .obligationOpen:
            return "Does this need a response, or is it already absorbed? Either way, record which."
        case .obligationAcknowledged:
            return "None. Acknowledged, and the body has not moved since."
        case .reopenedByEdit:
            return "It was edited after I acknowledged it. Does the new text ask for something else?"
        case .superseded:
            return "None. The reviewer withdrew it. Confirm the replacement is in the list."
        case .informational:
            return "None. The reviewer marked this one a note, not an ask."
        case .noProse:
            return "None. No prose after stripping boilerplate."
        }
    }
}

/// One line of `contrib in`'s worklist.
///
/// The `--json` shape is exactly TASK §13.3's contract: `id`, `kind`, `permalink`,
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
    /// (TASK §12.4), and stripped before encoding.
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
