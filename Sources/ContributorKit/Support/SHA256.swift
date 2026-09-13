import CryptoKit
import Foundation

/// Body hashing for the snapshot. Keyed by comment id *and* body hash, so an edit
/// after an acknowledgement re-opens the item by itself (TASK §12.10).
public enum SHA256 {
    public static func hex(of text: String) -> String {
        CryptoKit.SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

public enum GitHubTime {
    public static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        return try? Date(text, strategy: .iso8601)
    }

    public static func string(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}
