import Foundation

/// An inline review thread: ordered comments, the first of which is the root ask.
///
/// `isResolved` is carried because the API supplies it and the snapshot should not have
/// to re-fetch it — but the audit never consults it. **`isResolved` is not "answered"**
/// (TASK §12.3 rule 3): the maintainer sets resolution, a thread can be resolved with no
/// reply from us, and an open thread can be fully answered. Never substitute one for the
/// other.
public struct RemoteThread: Codable, Sendable {
    public var comments: [RemoteComment]
    public var isResolved: Bool
    public var isOutdated: Bool
    public var path: String?

    public init(
        comments: [RemoteComment], isResolved: Bool = false,
        isOutdated: Bool = false, path: String? = nil
    ) {
        self.comments = comments
        self.isResolved = isResolved
        self.isOutdated = isOutdated
        self.path = path
    }

    public var root: RemoteComment? { comments.first }
    public var replies: ArraySlice<RemoteComment> { comments.dropFirst() }
}
