import Foundation

public enum GitHubTime {
    public static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        return try? Date(text, strategy: .iso8601)
    }

    public static func string(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}
