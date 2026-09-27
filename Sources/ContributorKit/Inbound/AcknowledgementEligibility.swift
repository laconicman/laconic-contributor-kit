import Foundation

/// What may be acknowledged, and why not otherwise.
///
/// Review bodies and issue comments cannot be replied to, so a record is the only way to
/// discharge them. An inline thread is discharged by replying in it; the one thing worth
/// recording there is a *responsiveness check* on a reply that exists and that the asker
/// has not confirmed. Anything else would write a record the audit never reads — a silent
/// no-op that reports success, which this tool refuses everywhere.
public enum AcknowledgementEligibility {
    /// `nil` when `kind` is permitted by the repository's configuration.
    ///
    /// `acknowledgementKinds` used to be inert: it merged into the configuration and
    /// nothing read it, so a repository could disable a pointer form and still record
    /// one. A configured value that changes nothing is worse than no setting at all.
    public static func refusal(
        forKind kind: Acknowledgement.Kind, allowed: [String], id: String
    ) -> String? {
        guard !allowed.isEmpty, !allowed.contains(kind.rawValue) else { return nil }
        return """
            `\(kind.rawValue)` is not an accepted acknowledgement in this repository. \
            `.contributorkit.yml` allows: \(allowed.joined(separator: ", ")).
            """
    }

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
                confirm, record that you checked the reply answers the ask. \
                Already replied on GitHub? Refresh the snapshot first — `contrib in`, \
                or `ack --refresh`.
                """
        case .editedAfterMyAnswer:
            return """
                \(id) was edited after your reply, so a check of that reply would be stale \
                on arrival. Re-read the ask; reply again if it changed what is being asked. \
                Already replied again on GitHub? Refresh the snapshot first — `contrib in`, \
                or `ack --refresh`.
                """
        case .answeredConfirmed:
            return "\(id) is already confirmed by the asker. There is nothing to record."
        case .askerReplied:
            // A check here would judge my reply while the asker's later one went unread,
            // and the audit decides this state before it ever reads a check.
            return """
                \(id): the asker replied after you, and not with its verdict. Read that \
                reply — `contrib show \(id) <owner>/<repo>` — and answer it in the thread. \
                Your reply lists it as answered-claimed, which a verdict confirms or `ack` \
                checks. Already replied on GitHub? Refresh the snapshot first — \
                `contrib in`, or `ack --refresh`.
                """
        case nil:
            return "\(id) has no recorded state yet. Run `contrib in` for its PR first."
        default:
            return "\(id) is an inline thread in state `\(entry.state!.rawValue)`, which takes no acknowledgement."
        }
    }
}
