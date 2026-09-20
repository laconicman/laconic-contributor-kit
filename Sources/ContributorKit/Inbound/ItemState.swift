import Foundation

/// What the CLI settled about one item, deterministically.
///
/// The boundary rule (<doc:Design>), stated so it can be enforced in review:
///
/// > The CLI decides everything decidable **without reading meaning**. It never
/// > decides a meaning question. It emits the meaning question, pre-loaded with
/// > exactly the text needed to answer it, and marks everything it already settled so
/// > the model does not re-check it.
///
/// Every case below is a fact about ids, authorship, timestamps and hashes. Not one of
/// them required reading what a comment *says*.
public enum ItemState: String, Codable, Sendable, CaseIterable {
    /// Channel 1: a root ask from someone else with no reply from me.
    case openAsk = "open-ask"
    /// Channel 1: I replied. Whether the reply is *responsive* is the model's call.
    case answeredClaimed = "answered-claimed"
    /// Channel 1: I replied, then re-read the reply against the ask and **recorded** that
    /// it is responsive (`contrib ack <id> --with …`).
    ///
    /// The record is keyed to the ask's body hash and to the reply it judged, so a new
    /// reply or an edit to the ask makes it stale and the thread is listed again.
    case answeredChecked = "answered-checked"
    /// Channel 1: the asker themselves replied after my reply.
    ///
    /// Stronger evidence than anything else here, and the field report is right that
    /// <doc:Design> did not admit it: it is the asker confirming the answer, where my own reply
    /// only records a claim. Not an inference from proximity — <doc:Design>'s rule is about
    /// inferring acceptance from *timing*; this is the asker speaking.
    case answeredConfirmed = "answered-confirmed"
    /// The ask was edited after my answer was posted. <doc:Design>'s sharpest check, and free
    /// given the snapshot: my answer may no longer address it.
    case editedAfterMyAnswer = "edited-after-my-answer"
    /// Channels 2 and 3: listed, never auto-cleared, shown first (<doc:Design>).
    case obligationOpen = "obligation-open"
    /// An acknowledgement is recorded and the body has not moved since.
    case obligationAcknowledged = "obligation-acknowledged"
    /// An acknowledgement is recorded but the body hash changed under it, so the item
    /// re-opens by itself. For review bodies the hash is not an optimisation — it is
    /// the only mechanism REST leaves available (<doc:Design>).
    case reopenedByEdit = "reopened-by-edit"
    /// The reviewer retracted it — *"This report is out of date."*
    ///
    /// Without this, <doc:Design>'s never-auto-cleared rule holds open an ask the asker has
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
    /// total so the count stays honest, but not owed: <doc:Design>'s argument for
    /// noise over silence does not extend to noise that is *definitionally* empty.
    case noProse = "no-prose"

    /// Does this item belong on the worklist?
    public var isOwed: Bool {
        switch self {
        case .openAsk, .obligationOpen, .reopenedByEdit, .editedAfterMyAnswer: return true
        case .answeredClaimed, .answeredChecked, .answeredConfirmed, .obligationAcknowledged,
            .superseded, .noProse, .informational:
            return false
        }
    }

    /// Not owed, but carrying a question nobody has answered: *is my reply actually
    /// responsive?* Listed by default until the asker confirms or a check is recorded.
    ///
    /// It used to appear only on the run it changed and vanish on the next, so the one
    /// item carrying a live meaning question was the one hidden by default — whether or
    /// not anyone had looked. Reported twice by the same trial session.
    public var needsLook: Bool { self == .answeredClaimed }

    /// The meaning question this state hands to the model — the decision table
    /// `SKILL.md` carries, kept here so the two cannot drift.
    public var question: String {
        switch self {
        case .openAsk:
            return "Answer it, or say why it should be left out — but it needs an answer."
        case .answeredClaimed:
            return "Is my reply actually responsive to the ask, or only adjacent to it?"
        case .answeredChecked:
            return "None. You re-read your reply against the ask and recorded that it answers it."
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
