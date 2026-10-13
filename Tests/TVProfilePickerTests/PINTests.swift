import Foundation
import Testing
@testable import TVProfilePicker

@Suite("PINs")
struct PINTests {
    @Test("A PIN matches its own digits and nothing else")
    func matches() throws {
        let pin = try ProfilePIN("0427")
        #expect(pin.matches("0427"))
        #expect(!pin.matches("0428"))
        #expect(!pin.matches("427"))
        #expect(!pin.matches("04270"))
        #expect(!pin.matches(""))
        #expect(!pin.matches("04a7"))
        #expect(pin.length == 4)
    }

    @Test("The digits are not stored")
    func notStored() throws {
        let pin = try ProfilePIN("2580")
        let json = String(decoding: try JSONEncoder().encode(pin), as: UTF8.self)
        #expect(!json.contains("2580"))
        #expect(pin.hash.count == 64)
    }

    @Test("Each PIN gets its own salt")
    func salted() throws {
        let first = try ProfilePIN("1234")
        let second = try ProfilePIN("1234")
        #expect(first.salt != second.salt)
        #expect(first.hash != second.hash)
        #expect(first.matches("1234") && second.matches("1234"))
    }

    @Test("A fixed salt gives a fixed hash")
    func fixedSalt() throws {
        let salt = Data(repeating: 7, count: 16)
        let first = try ProfilePIN("1234", salt: salt)
        let second = try ProfilePIN("1234", salt: salt)
        #expect(first == second)
    }

    @Test("Malformed PINs are refused", arguments: ["", "123", "123456789", "12a4", "１２３４", " 1234", "12.4"])
    func invalid(code: String) {
        #expect(throws: ProfilePINError.invalidFormat) {
            try ProfilePIN(code)
        }
        #expect(!ProfilePIN.isValid(code))
    }

    @Test("PINs of 4 to 8 digits are accepted", arguments: ["0000", "12345", "12345678"])
    func lengths(code: String) throws {
        let pin = try ProfilePIN(code)
        #expect(pin.length == code.count)
        #expect(pin.matches(code))
    }

    @Test("PINs round-trip through JSON")
    func codable() throws {
        let pin = try ProfilePIN("9876")
        let decoded = try JSONDecoder().decode(ProfilePIN.self, from: JSONEncoder().encode(pin))
        #expect(decoded == pin)
        #expect(decoded.matches("9876"))
    }
}

@Suite("PIN entry")
struct PINEntryTests {
    @Test("Digits fill up to the length")
    func filling() {
        var entry = PINEntry()
        #expect(entry.isEmpty)
        let added = [1, 2, 3, 4, 5].map { entry.append($0) }
        #expect(added == [true, true, true, true, false])
        #expect(entry.isComplete)
        #expect(entry.code == "1234")
        #expect(entry.accessibilityValue == "4 of 4 digits entered")
    }

    @Test("Delete and clear")
    func editing() {
        var entry = PINEntry(length: 4, digits: [3, 1])
        entry.deleteLast()
        #expect(entry.digits == [3])
        entry.deleteLast()
        entry.deleteLast()
        #expect(entry.isEmpty)
        entry.append(9)
        entry.append(0)
        entry.clear()
        #expect(entry.code == "")
    }

    @Test("Only 0 to 9 are digits")
    func invalidDigits() {
        var entry = PINEntry()
        let added = [-1, 10, 7].map { entry.append($0) }
        #expect(added == [false, false, true])
        #expect(entry.digits == [7])
        #expect(PINEntry(digits: [1, 12, 2]).digits == [1, 2])
    }

    @Test("The length is clamped to 4...8")
    func clampedLength() {
        #expect(PINEntry(length: 2).length == 4)
        #expect(PINEntry(length: 6).length == 6)
        #expect(PINEntry(length: 12).length == 8)
        #expect(PINEntry(length: 4, digits: [1, 2, 3, 4, 5, 6]).code == "1234")
    }
}

@Suite("PIN attempts")
struct PINAttemptsTests {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let policy = PINAttemptPolicy(maxAttempts: 3, lockoutDuration: 30)

    @Test("Wrong PINs count down, then lock")
    func lockout() {
        var attempts = PINAttempts()
        let first = attempts.recordFailure(at: start, policy: policy)
        let second = attempts.recordFailure(at: start, policy: policy)
        let third = attempts.recordFailure(at: start, policy: policy)
        #expect(first == .rejected(remainingAttempts: 2))
        #expect(second == .rejected(remainingAttempts: 1))
        #expect(third == .lockedOut(until: start.addingTimeInterval(30)))
        #expect(attempts.isLockedOut(at: start.addingTimeInterval(29)))
        #expect(!attempts.isLockedOut(at: start.addingTimeInterval(30)))
    }

    @Test("A failure during the lockout keeps the same end")
    func duringLockout() {
        var attempts = PINAttempts()
        for _ in 0..<3 {
            _ = attempts.recordFailure(at: start, policy: policy)
        }
        let again = attempts.recordFailure(at: start.addingTimeInterval(10), policy: policy)
        #expect(again == .lockedOut(until: start.addingTimeInterval(30)))
    }

    @Test("After the lockout, the count starts over")
    func afterLockout() {
        var attempts = PINAttempts()
        for _ in 0..<3 {
            _ = attempts.recordFailure(at: start, policy: policy)
        }
        let later = attempts.recordFailure(at: start.addingTimeInterval(31), policy: policy)
        #expect(later == .rejected(remainingAttempts: 2))
    }

    @Test("The unlimited policy never locks")
    func unlimited() {
        var attempts = PINAttempts()
        var results: [PINVerification] = []
        for _ in 0..<20 {
            results.append(attempts.recordFailure(at: start, policy: .unlimited))
        }
        #expect(results.allSatisfy { $0 == .rejected(remainingAttempts: nil) })
    }

    @Test("Reset clears failures and the lockout")
    func reset() {
        var attempts = PINAttempts()
        for _ in 0..<3 {
            _ = attempts.recordFailure(at: start, policy: policy)
        }
        attempts.reset()
        #expect(!attempts.isLockedOut(at: start))
        #expect(attempts.failures == 0)
    }
}
