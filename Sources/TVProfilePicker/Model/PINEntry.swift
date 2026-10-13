import Foundation

/// The digits typed so far on a PIN pad.
public struct PINEntry: Hashable, Sendable {
    /// How many digits make a complete PIN.
    public let length: Int
    /// The digits typed so far, each 0 to 9.
    public private(set) var digits: [Int]

    /// An empty entry for a PIN of `length` digits (clamped to 4...8).
    public init(length: Int = 4, digits: [Int] = []) {
        let clamped = min(max(length, ProfilePIN.allowedLengths.lowerBound), ProfilePIN.allowedLengths.upperBound)
        self.length = clamped
        self.digits = Array(digits.filter { (0...9).contains($0) }.prefix(clamped))
    }

    /// Whether every digit has been typed.
    public var isComplete: Bool { digits.count == length }

    /// Whether no digit has been typed.
    public var isEmpty: Bool { digits.isEmpty }

    /// The digits as a string, such as `"0427"`.
    public var code: String { digits.map(String.init).joined() }

    /// Adds a digit. Returns false, changing nothing, when the entry is complete or the digit is
    /// not 0 to 9.
    @discardableResult
    public mutating func append(_ digit: Int) -> Bool {
        guard !isComplete, (0...9).contains(digit) else { return false }
        digits.append(digit)
        return true
    }

    /// Removes the last digit, if any.
    public mutating func deleteLast() {
        if !digits.isEmpty { digits.removeLast() }
    }

    /// Removes every digit.
    public mutating func clear() {
        digits.removeAll()
    }

    /// What VoiceOver reads for the dots: "2 of 4 digits entered".
    public var accessibilityValue: String {
        "\(digits.count) of \(length) digits entered"
    }
}
