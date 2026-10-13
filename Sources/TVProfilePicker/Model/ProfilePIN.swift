import CryptoKit
import Foundation

/// A profile's PIN, stored as a salted SHA-256 hash rather than the digits themselves.
///
/// A profile PIN is a household convenience (keeping kids out of a parent's profile), not
/// account security: four digits can be guessed, which is why `ProfileStore` also limits wrong
/// attempts. Keep real credentials in the Keychain.
public struct ProfilePIN: Codable, Hashable, Sendable {
    /// The number of digits.
    public let length: Int
    /// Base64 of the random salt.
    public let salt: String
    /// Hex SHA-256 of the salt followed by the digits.
    public let hash: String

    /// The lengths a PIN may have.
    public static let allowedLengths = 4...8

    /// Hashes a PIN made of 4 to 8 ASCII digits with a fresh random salt.
    public init(_ code: String) throws(ProfilePINError) {
        var generator = SystemRandomNumberGenerator()
        let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        try self.init(code, salt: salt)
    }

    /// Hashes a PIN with the given salt. Use the other initializer unless you need a fixed salt
    /// (in tests, for example).
    public init(_ code: String, salt: Data) throws(ProfilePINError) {
        guard Self.isValid(code) else {
            throw .invalidFormat
        }
        length = code.count
        self.salt = salt.base64EncodedString()
        hash = Self.digest(code, salt: salt)
    }

    /// Whether the code is a well-formed PIN: 4 to 8 ASCII digits.
    public static func isValid(_ code: String) -> Bool {
        allowedLengths.contains(code.count) && code.unicodeScalars.allSatisfy { (48...57).contains($0.value) }
    }

    /// Whether the code is this PIN. The comparison takes the same time wherever the hashes differ.
    public func matches(_ code: String) -> Bool {
        guard code.count == length, Self.isValid(code), let saltData = Data(base64Encoded: salt) else {
            return false
        }
        let candidate = Array(Self.digest(code, salt: saltData).utf8)
        let stored = Array(hash.utf8)
        guard candidate.count == stored.count else { return false }
        var difference: UInt8 = 0
        for index in candidate.indices {
            difference |= candidate[index] ^ stored[index]
        }
        return difference == 0
    }

    private static func digest(_ code: String, salt: Data) -> String {
        var input = salt
        input.append(contentsOf: Array(code.utf8))
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }
}

/// Why a PIN could not be created.
public enum ProfilePINError: Error, Hashable, Sendable {
    /// The PIN is not 4 to 8 ASCII digits.
    case invalidFormat
}

/// How many wrong PINs are allowed before the profile is locked for a while.
public struct PINAttemptPolicy: Hashable, Sendable {
    /// Wrong attempts allowed in a row; 0 or less never locks.
    public var maxAttempts: Int
    /// How long the profile stays locked after the last allowed wrong attempt, in seconds.
    public var lockoutDuration: TimeInterval

    public init(maxAttempts: Int, lockoutDuration: TimeInterval) {
        self.maxAttempts = maxAttempts
        self.lockoutDuration = lockoutDuration
    }

    /// Five attempts, then 30 seconds.
    public static let standard = PINAttemptPolicy(maxAttempts: 5, lockoutDuration: 30)
    /// Never locks.
    public static let unlimited = PINAttemptPolicy(maxAttempts: 0, lockoutDuration: 0)
}

/// The outcome of checking a PIN.
public enum PINVerification: Hashable, Sendable {
    /// The PIN is right, or the profile has none.
    case accepted
    /// The PIN is wrong. `remainingAttempts` is nil when the policy never locks or the profile
    /// does not exist.
    case rejected(remainingAttempts: Int?)
    /// Too many wrong PINs; no PIN is checked until the date.
    case lockedOut(until: Date)
}

/// Wrong-PIN bookkeeping for one profile.
public struct PINAttempts: Hashable, Sendable {
    public private(set) var failures = 0
    public private(set) var lockedUntil: Date?

    public init() {}

    /// Whether PINs are refused at the date.
    public func isLockedOut(at date: Date) -> Bool {
        guard let lockedUntil else { return false }
        return date < lockedUntil
    }

    /// Records a wrong PIN and says what happens next.
    public mutating func recordFailure(at date: Date, policy: PINAttemptPolicy) -> PINVerification {
        if let lockedUntil, date < lockedUntil {
            return .lockedOut(until: lockedUntil)
        }
        lockedUntil = nil
        guard policy.maxAttempts > 0 else {
            return .rejected(remainingAttempts: nil)
        }
        failures += 1
        if failures >= policy.maxAttempts {
            failures = 0
            let until = date.addingTimeInterval(policy.lockoutDuration)
            lockedUntil = until
            return .lockedOut(until: until)
        }
        return .rejected(remainingAttempts: policy.maxAttempts - failures)
    }

    /// Clears the count after a right PIN.
    public mutating func reset() {
        failures = 0
        lockedUntil = nil
    }
}
