import Foundation
import Observation

/// Why a profile change was refused.
public enum ProfileStoreError: Error, Hashable, Sendable, LocalizedError {
    /// The name is empty or only spaces.
    case emptyName
    /// The name is longer than `ProfileStore.maxNameLength` characters.
    case nameTooLong(maxLength: Int)
    /// Another profile already has this name (ignoring case and accents).
    case duplicateName
    /// There are already `ProfileStore.maxProfiles` profiles.
    case limitReached(maxProfiles: Int)
    /// No profile has this id.
    case profileNotFound

    public var errorDescription: String? {
        switch self {
        case .emptyName: "Enter a name."
        case let .nameTooLong(maxLength): "Use \(maxLength) characters or fewer."
        case .duplicateName: "Another profile already has this name."
        case let .limitReached(maxProfiles): "This Apple TV already has \(maxProfiles) profiles."
        case .profileNotFound: "This profile no longer exists."
        }
    }
}

/// The profiles on this Apple TV, saved to a `ProfileStorage` after every change.
///
/// ```swift
/// @State private var store = ProfileStore(storage: UserDefaultsProfileStorage())
/// ```
@MainActor
@Observable
public final class ProfileStore {
    /// The profiles, in the order the picker shows them.
    public private(set) var profiles: [Profile] = []
    /// The profile chosen last; the picker focuses it first.
    public private(set) var lastSelectedID: Profile.ID? = nil
    /// The error from the last failed save or load, cleared by the next successful one.
    public private(set) var persistenceError: String? = nil

    /// The most profiles the store accepts.
    public let maxProfiles: Int
    /// The longest name accepted, in characters.
    public let maxNameLength: Int
    /// How many wrong PINs are allowed before a profile is locked for a while.
    public let pinPolicy: PINAttemptPolicy

    @ObservationIgnored private let storage: any ProfileStorage
    @ObservationIgnored private var attempts: [Profile.ID: PINAttempts] = [:]

    /// Loads the saved profiles from `storage`. When nothing has been saved yet, the store starts
    /// with `initialProfiles` (and saves them).
    public init(
        storage: any ProfileStorage = UserDefaultsProfileStorage(),
        initialProfiles: [Profile] = [],
        maxProfiles: Int = 6,
        maxNameLength: Int = 20,
        pinPolicy: PINAttemptPolicy = .standard
    ) {
        self.storage = storage
        self.maxProfiles = max(1, maxProfiles)
        self.maxNameLength = max(1, maxNameLength)
        self.pinPolicy = pinPolicy
        do {
            if let archive = try storage.load() {
                profiles = archive.profiles
                lastSelectedID = archive.lastSelectedID
            } else if !initialProfiles.isEmpty {
                profiles = initialProfiles
                persist()
            }
        } catch {
            persistenceError = error.localizedDescription
            profiles = initialProfiles
        }
    }

    /// Whether another profile can be added.
    public var canAddProfile: Bool { profiles.count < maxProfiles }

    /// The profile with this id.
    public func profile(id: Profile.ID?) -> Profile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }

    /// The profile chosen last, if it still exists.
    public var lastSelectedProfile: Profile? { profile(id: lastSelectedID) }

    // MARK: Names

    /// The trimmed name, or the reason it can't be used. Pass `excluding` when renaming, so the
    /// profile's own name doesn't count as a duplicate.
    public func validateName(_ name: String, excluding id: Profile.ID? = nil) throws(ProfileStoreError) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyName }
        guard trimmed.count <= maxNameLength else { throw .nameTooLong(maxLength: maxNameLength) }
        let duplicate = profiles.contains { profile in
            profile.id != id
                && profile.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard !duplicate else { throw .duplicateName }
        return trimmed
    }

    // MARK: Changes

    /// Adds a profile at the end. Without an avatar, it gets initials in a palette picked from
    /// the name.
    @discardableResult
    public func add(
        name: String,
        avatar: Avatar? = nil,
        isKids: Bool = false,
        pin: ProfilePIN? = nil
    ) throws(ProfileStoreError) -> Profile {
        guard canAddProfile else { throw .limitReached(maxProfiles: maxProfiles) }
        let validName = try validateName(name)
        let profile = Profile(name: validName, avatar: avatar, isKids: isKids, pin: pin)
        profiles.append(profile)
        persist()
        return profile
    }

    /// Saves a draft: as a new profile when `id` is nil, otherwise over that profile.
    @discardableResult
    public func save(_ draft: ProfileDraft, for id: Profile.ID?) throws(ProfileStoreError) -> Profile {
        guard let id else {
            return try add(name: draft.name, avatar: draft.avatar, isKids: draft.isKids, pin: draft.pin)
        }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw .profileNotFound }
        let name = try validateName(draft.name, excluding: id)
        if profiles[index].pin != draft.pin {
            attempts[id] = nil
        }
        profiles[index].name = name
        profiles[index].avatar = draft.avatar
        profiles[index].isKids = draft.isKids
        profiles[index].pin = draft.pin
        persist()
        return profiles[index]
    }

    /// Renames a profile.
    public func rename(_ id: Profile.ID, to name: String) throws(ProfileStoreError) {
        let index = try position(of: id)
        profiles[index].name = try validateName(name, excluding: id)
        persist()
    }

    /// Changes a profile's avatar.
    public func setAvatar(_ avatar: Avatar, for id: Profile.ID) throws(ProfileStoreError) {
        let index = try position(of: id)
        profiles[index].avatar = avatar
        persist()
    }

    /// Marks a profile as a kids profile, or not.
    public func setKids(_ isKids: Bool, for id: Profile.ID) throws(ProfileStoreError) {
        let index = try position(of: id)
        profiles[index].isKids = isKids
        persist()
    }

    /// Sets or removes (nil) a profile's PIN. Resets its wrong-PIN count.
    public func setPIN(_ pin: ProfilePIN?, for id: Profile.ID) throws(ProfileStoreError) {
        let index = try position(of: id)
        profiles[index].pin = pin
        attempts[id] = nil
        persist()
    }

    /// Deletes a profile.
    public func delete(_ id: Profile.ID) throws(ProfileStoreError) {
        let index = try position(of: id)
        profiles.remove(at: index)
        attempts[id] = nil
        if lastSelectedID == id {
            lastSelectedID = nil
        }
        persist()
    }

    /// Moves a profile to a new position (clamped to the list).
    public func move(_ id: Profile.ID, to newIndex: Int) throws(ProfileStoreError) {
        let index = try position(of: id)
        let profile = profiles.remove(at: index)
        profiles.insert(profile, at: min(max(newIndex, 0), profiles.count))
        persist()
    }

    /// Remembers the profile someone chose, so the picker focuses it next time.
    public func select(_ id: Profile.ID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        lastSelectedID = id
        persist()
    }

    /// Replaces every profile, for example after a sync.
    public func replaceAll(with profiles: [Profile], lastSelectedID: Profile.ID? = nil) {
        self.profiles = profiles
        self.lastSelectedID = lastSelectedID.flatMap { id in profiles.contains { $0.id == id } ? id : nil }
        attempts = [:]
        persist()
    }

    // MARK: PINs

    /// Checks a PIN for a profile, counting wrong ones under `pinPolicy`.
    public func verifyPIN(_ code: String, for id: Profile.ID, at date: Date = Date()) -> PINVerification {
        guard let profile = self.profile(id: id) else {
            return .rejected(remainingAttempts: nil)
        }
        guard let pin = profile.pin else {
            return .accepted
        }
        var record = attempts[id] ?? PINAttempts()
        if record.isLockedOut(at: date), let until = record.lockedUntil {
            return .lockedOut(until: until)
        }
        let result: PINVerification
        if pin.matches(code) {
            record.reset()
            result = .accepted
        } else {
            result = record.recordFailure(at: date, policy: pinPolicy)
        }
        attempts[id] = record
        return result
    }

    /// When the profile accepts PINs again, if it is locked out at the date.
    public func lockoutEnd(for id: Profile.ID, at date: Date = Date()) -> Date? {
        guard let record = attempts[id], record.isLockedOut(at: date) else { return nil }
        return record.lockedUntil
    }

    // MARK: Persistence

    /// The current state as an archive.
    public var archive: ProfileArchive {
        ProfileArchive(profiles: profiles, lastSelectedID: lastSelectedID)
    }

    /// Reloads from storage, discarding unsaved state.
    public func reload() {
        do {
            let archive = try storage.load() ?? ProfileArchive()
            profiles = archive.profiles
            lastSelectedID = archive.lastSelectedID
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    private func persist() {
        do {
            try storage.save(archive)
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    private func position(of id: Profile.ID) throws(ProfileStoreError) -> Int {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw .profileNotFound }
        return index
    }
}
