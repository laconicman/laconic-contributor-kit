import Foundation

/// What may be acknowledged, and why not otherwise.
///
/// Review bodies and issue comments cannot be replied to, so a record is the only way to
/// discharge them. An inline thread is discharged by replying in it; the one thing worth
/// recording there is a *responsiveness check* on a reply that exists and that the asker
/// has not confirmed. Anything else would write a record the audit never reads — a silent
/// no-op that reports success, which this tool refuses everywhere.
public enum AcknowledgementEligibility {
    /// `nil` when `entry` may be acknowledged; otherwise the reason it may not.
    public static func refusal(for entry: Snapshot.Entry, id: String) -> String? {
        guard entry.kind == .inlineThread else { return nil }
        switch entry.state {
        case .answeredClaimed, .answeredChecked:
            return nil
        case .openAsk:
            return """
                \(id) has no reply from you yet. An inline thread is answered by replying in \
                it — the audit reads the reply. Reply first; then, if the asker does not \
                confirm, record that you checked the reply answers the ask.
                """
        case .editedAfterMyAnswer:
            return """
                \(id) was edited after your reply, so a check of that reply would be stale \
                on arrival. Re-read the ask; reply again if it changed what is being asked.
                """
        case .answeredConfirmed:
            return "\(id) is already confirmed by the asker. There is nothing to record."
        case nil:
            return "\(id) has no recorded state yet. Run `contrib in` for its PR first."
        default:
            return "\(id) is an inline thread in state `\(entry.state!.rawValue)`, which takes no acknowledgement."
        }
    }
}
