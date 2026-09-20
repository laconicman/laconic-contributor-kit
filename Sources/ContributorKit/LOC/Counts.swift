import Foundation

/// Code, comment and blank — **never summed** (<doc:Design>). There is deliberately
/// no `total` property on this type; a quality score built from one number is the
/// thing the whole LOC half exists to not produce.
public struct Counts: Codable, Sendable, Equatable, CustomStringConvertible {
    public var description: String { "code \(code) / comment \(comment) / blank \(blank)" }

    public var code: Int
    public var comment: Int
    public var blank: Int

    public init(code: Int = 0, comment: Int = 0, blank: Int = 0) {
        self.code = code
        self.comment = comment
        self.blank = blank
    }

    public static func + (a: Counts, b: Counts) -> Counts {
        Counts(code: a.code + b.code, comment: a.comment + b.comment, blank: a.blank + b.blank)
    }

    public static func - (a: Counts, b: Counts) -> Counts {
        Counts(code: a.code - b.code, comment: a.comment - b.comment, blank: a.blank - b.blank)
    }
}
