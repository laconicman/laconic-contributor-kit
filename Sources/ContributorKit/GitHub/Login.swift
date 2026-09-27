import Foundation

/// A GitHub login, as the audit compares it.
///
/// A GitHub App is one actor with two spellings: its comments are authored by
/// `devin-ai-integration`, and the same app resolving a thread is reported as
/// `devin-ai-integration[bot]`. Comparing one against the other needs the suffix gone,
/// and GitHub logins are case-insensitive.
public enum Login {
    /// `login` without a GitHub App's `[bot]` suffix. Case is kept for display.
    public static func normalised(_ login: String) -> String {
        login.lowercased().hasSuffix("[bot]") ? String(login.dropLast("[bot]".count)) : login
    }

    public static func same(_ a: String, _ b: String) -> Bool {
        normalised(a).caseInsensitiveCompare(normalised(b)) == .orderedSame
    }
}
