import Foundation

/// One edit of a subject's description, as `userContentEdits` reports it
/// (issue #17) — when it happened and who did it. `editor` is `nil` when the
/// account is gone, which reads as "not me" rather than as a guess.
public struct DescriptionEdit: Sendable, Equatable {
    public var editedAt: Date
    public var editor: String?

    public init(editedAt: Date, editor: String? = nil) {
        self.editedAt = editedAt
        self.editor = editor
    }
}
