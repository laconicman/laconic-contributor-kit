import Foundation

/// The block every command ends with, and cannot be run without (<doc:Design>).
///
/// A guard you have to remember to invoke is a guard that does not run: the 09-04
/// miss happened inside a step nobody thought needed guarding. So this is not a
/// `contrib check` subcommand — it is attached to every command's output, and an
/// anomaly makes the process exit non-zero.
///
/// Rule 5 of the field report lives here too. *Never trust an unexecuted check:* a
/// verification that cannot distinguish "ran and passed" from "did not run" reports
/// success in both cases. So every command records **what it examined**, and a
/// command that recorded no counters at all raises `.nothingExamined` — because when
/// a check's passing condition is an absence, every failure mode produces that
/// absence too.
public struct Provenance: Codable, Sendable {
    public struct Counter: Codable, Sendable {
        public var label: String
        public var value: Int
    }

    public struct Anomaly: Codable, Sendable {
        public var kind: String
        public var detail: String
    }

    public var command: String
    public var startedAt: Date
    public var finishedAt: Date?
    public var counters: [Counter] = []
    public var notes: [String] = []
    public var anomalies: [Anomaly] = []
    public var subprocessCalls: Int = 0

    public init(command: String, startedAt: Date = Date()) {
        self.command = command
        self.startedAt = startedAt
    }

    /// Print the count examined. <doc:Design>, and the field report calls it the
    /// best rule in the document: it is the difference between "0 issue comments" as a
    /// *fact* and as an *assumption*.
    public mutating func examined(_ label: String, _ value: Int) {
        counters.append(Counter(label: label, value: value))
    }

    public mutating func note(_ text: String) {
        notes.append(text)
    }

    public mutating func anomaly(_ kind: String, _ detail: String) {
        anomalies.append(Anomaly(kind: kind, detail: detail))
    }

    /// Idempotent: callers finish early to decide whether a run may be trusted, and
    /// the emitter finishes again on the way out.
    public mutating func finish() {
        guard finishedAt == nil else { return }
        finishedAt = Date()
        if counters.isEmpty {
            anomaly(
                "nothingExamined",
                "the command recorded no examined counts — it cannot distinguish "
                    + "\"ran and found nothing\" from \"did not run\"")
        }
    }

    public var hasAnomaly: Bool { !anomalies.isEmpty }

    public func rendered() -> String {
        var lines = ["", "— provenance —"]
        lines.append("command        \(command)")
        for counter in counters {
            lines.append("\(counter.label.padded(to: 15))\(counter.value)")
        }
        for note in notes {
            lines.append("note           \(note)")
        }
        lines.append("subprocesses   \(subprocessCalls)")
        if anomalies.isEmpty {
            lines.append("anomalies      none")
        } else {
            for anomaly in anomalies {
                lines.append("ANOMALY        \(anomaly.kind): \(anomaly.detail)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

extension String {
    func padded(to width: Int) -> String {
        count >= width ? self + " " : self + String(repeating: " ", count: width - count)
    }
}
