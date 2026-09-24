import Foundation

/// The `owner/repo#number` string every snapshot entry records as `subject`.
///
/// The snapshot is per repository and a run is per pull request or issue, so the
/// subject string is the only thing that tells a command which subject an entry came
/// from — `contrib show` and `ack --refresh` both re-fetch through it.
public enum Subject {
    /// `o/r#33` — the only shape this kit writes or reads.
    public static func format(repository: String, number: Int) -> String {
        "\(repository)#\(number)"
    }

    /// The number, when `subject` names a subject of `repository`; `nil` otherwise —
    /// a malformed subject and another repository's are equally not ours to fetch.
    public static func number(in subject: String, repository: String) -> Int? {
        let prefix = repository + "#"
        guard subject.hasPrefix(prefix) else { return nil }
        return Int(subject.dropFirst(prefix.count))
    }
}

extension Snapshot.Entry {
    /// True when `pr` names the subject this entry was fetched from.
    ///
    /// `contrib ack` accepts `--pr` for symmetry with `contrib in`, and a number that
    /// disagrees with the recorded subject almost always means the id was typed for
    /// one pull request and `--pr` for another. An entry with no recorded subject
    /// cannot disagree — snapshots written before `subject` existed simply have none.
    public func isFromSubject(repository: String, pr: Int) -> Bool {
        subject == Subject.format(repository: repository, number: pr)
    }
}
