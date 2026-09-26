import Foundation

/// An inline review thread: ordered comments, the first of which is the root ask.
///
/// `isResolved` and `resolvedBy` are **reported**, on every inline item, and no state is
/// ever decided on them. One listing rule reads `isResolved`: a closed subject does not
/// quiet a thread that is still unresolved (``InboundItem/awaitsLook``). **`isResolved` is not
/// "answered"** (<doc:Design>): a thread is resolved for more reasons than the asker's
/// consent — I can resolve my own, a maintainer can, a reviewer bot's fix session
/// resolves under the reviewer's own login — a thread can be resolved with no reply
/// from us, and an open thread can be fully answered. Never substitute one for the
/// other.
public struct RemoteThread: Codable, Sendable {
    public var comments: [RemoteComment]
    public var isResolved: Bool
    /// Who resolved it, `[bot]` suffix removed (``Login``) so it compares with a comment
    /// author's login. `nil` when unresolved, or when the source does not say.
    public var resolvedBy: String?
    public var isOutdated: Bool
    public var path: String?

    public init(
        comments: [RemoteComment], isResolved: Bool = false, resolvedBy: String? = nil,
        isOutdated: Bool = false, path: String? = nil
    ) {
        self.comments = comments
        self.isResolved = isResolved
        self.resolvedBy = resolvedBy.map(Login.normalised)
        self.isOutdated = isOutdated
        self.path = path
    }

    public var root: RemoteComment? { comments.first }
    public var replies: ArraySlice<RemoteComment> { comments.dropFirst() }
}
