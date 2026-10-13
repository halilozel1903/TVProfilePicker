import Foundation
import Testing
@testable import TVProfilePicker

@MainActor
@Suite("Profile store")
struct ProfileStoreTests {
    private func makeStore(
        _ names: [String] = [],
        storage: InMemoryProfileStorage = InMemoryProfileStorage(),
        maxProfiles: Int = 6,
        policy: PINAttemptPolicy = .standard
    ) -> ProfileStore {
        ProfileStore(
            storage: storage,
            initialProfiles: names.map { Profile(name: $0) },
            maxProfiles: maxProfiles,
            pinPolicy: policy
        )
    }

    @Test("Initial profiles are used and saved when storage is empty")
    func seeding() {
        let storage = InMemoryProfileStorage()
        let store = makeStore(["Alex", "Sam"], storage: storage)
        #expect(store.profiles.map(\.name) == ["Alex", "Sam"])
        #expect(storage.archive?.profiles.map(\.name) == ["Alex", "Sam"])
    }

    @Test("Saved profiles win over initial profiles")
    func loadsSaved() {
        let storage = InMemoryProfileStorage(archive: ProfileArchive(profiles: [Profile(name: "Jordan")]))
        let store = makeStore(["Alex"], storage: storage)
        #expect(store.profiles.map(\.name) == ["Jordan"])
        #expect(storage.saveCount == 0)
    }

    @Test("Adding trims the name and suggests an avatar")
    func add() throws {
        let store = makeStore()
        let profile = try store.add(name: "  Riley  ", isKids: true)
        #expect(profile.name == "Riley")
        #expect(profile.isKids)
        #expect(profile.avatar == .suggested(for: "Riley"))
        #expect(store.profiles == [profile])
    }

    @Test("Names are validated", arguments: [
        ("", ProfileStoreError.emptyName),
        ("    ", ProfileStoreError.emptyName),
        ("A name that is far too long", ProfileStoreError.nameTooLong(maxLength: 20)),
        ("alex", ProfileStoreError.duplicateName),
        ("ÀLEX", ProfileStoreError.duplicateName),
    ])
    func validation(name: String, error: ProfileStoreError) {
        let store = makeStore(["Alex"])
        #expect(throws: error) {
            try store.add(name: name)
        }
        #expect(store.profiles.count == 1)
    }

    @Test("The profile limit is enforced")
    func limit() throws {
        let store = makeStore(["A", "B"], maxProfiles: 3)
        #expect(store.canAddProfile)
        try store.add(name: "C")
        #expect(!store.canAddProfile)
        #expect(throws: ProfileStoreError.limitReached(maxProfiles: 3)) {
            try store.add(name: "D")
        }
    }

    @Test("Renaming keeps a profile's own name valid and refuses another's")
    func rename() throws {
        let store = makeStore(["Alex", "Sam"])
        let alex = store.profiles[0]
        try store.rename(alex.id, to: "ALEX")
        #expect(store.profiles[0].name == "ALEX")
        #expect(throws: ProfileStoreError.duplicateName) {
            try store.rename(alex.id, to: "sam")
        }
        #expect(throws: ProfileStoreError.profileNotFound) {
            try store.rename(UUID(), to: "Nobody")
        }
    }

    @Test("Avatar, kids and PIN changes are saved")
    func changes() throws {
        let storage = InMemoryProfileStorage()
        let store = makeStore(["Casey"], storage: storage)
        let id = store.profiles[0].id
        try store.setAvatar(.symbol("gamecontroller.fill", .ember), for: id)
        try store.setKids(true, for: id)
        try store.setPIN(ProfilePIN("1234"), for: id)
        let saved = try #require(storage.archive?.profiles.first)
        #expect(saved.avatar == .symbol("gamecontroller.fill", .ember))
        #expect(saved.isKids)
        #expect(saved.isLocked)
        try store.setPIN(nil, for: id)
        #expect(store.profiles[0].isLocked == false)
    }

    @Test("Saving a draft adds or updates")
    func drafts() throws {
        let store = makeStore(["Alex"])
        let created = try store.save(ProfileDraft(name: "Sam", isKids: true), for: nil)
        #expect(store.profiles.count == 2)
        var draft = ProfileDraft(created)
        draft.name = "Samantha"
        draft.avatar = .symbol("music.note", .rose)
        let updated = try store.save(draft, for: created.id)
        #expect(updated.id == created.id)
        #expect(store.profile(id: created.id)?.name == "Samantha")
        #expect(store.profile(id: created.id)?.avatar == .symbol("music.note", .rose))
    }

    @Test("Deleting forgets the last selection")
    func delete() throws {
        let store = makeStore(["Alex", "Sam"])
        let sam = store.profiles[1]
        store.select(sam.id)
        #expect(store.lastSelectedProfile == sam)
        try store.delete(sam.id)
        #expect(store.profiles.map(\.name) == ["Alex"])
        #expect(store.lastSelectedID == nil)
    }

    @Test("Selecting an unknown profile does nothing")
    func selectUnknown() {
        let store = makeStore(["Alex"])
        store.select(UUID())
        #expect(store.lastSelectedID == nil)
    }

    @Test("Moving reorders and clamps the index")
    func move() throws {
        let store = makeStore(["A", "B", "C"])
        let c = store.profiles[2].id
        try store.move(c, to: 0)
        #expect(store.profiles.map(\.name) == ["C", "A", "B"])
        try store.move(c, to: 99)
        #expect(store.profiles.map(\.name) == ["A", "B", "C"])
    }

    @Test("PINs are verified and wrong ones limited")
    func verify() throws {
        let store = makeStore(policy: PINAttemptPolicy(maxAttempts: 2, lockoutDuration: 60))
        let sam = try store.add(name: "Sam", pin: ProfilePIN("1234"))
        let open = try store.add(name: "Alex")
        let now = Date(timeIntervalSince1970: 2_000_000)

        #expect(store.verifyPIN("0000", for: open.id, at: now) == .accepted)
        #expect(store.verifyPIN("1234", for: sam.id, at: now) == .accepted)
        #expect(store.verifyPIN("1111", for: sam.id, at: now) == .rejected(remainingAttempts: 1))
        #expect(store.verifyPIN("2222", for: sam.id, at: now) == .lockedOut(until: now.addingTimeInterval(60)))
        // Even the right PIN is refused during the lockout.
        #expect(store.verifyPIN("1234", for: sam.id, at: now.addingTimeInterval(5)) == .lockedOut(until: now.addingTimeInterval(60)))
        #expect(store.lockoutEnd(for: sam.id, at: now.addingTimeInterval(5)) == now.addingTimeInterval(60))
        #expect(store.verifyPIN("1234", for: sam.id, at: now.addingTimeInterval(61)) == .accepted)
        #expect(store.lockoutEnd(for: sam.id, at: now.addingTimeInterval(61)) == nil)
        #expect(store.verifyPIN("1234", for: UUID(), at: now) == .rejected(remainingAttempts: nil))
    }

    @Test("A new PIN resets the wrong-PIN count")
    func newPINResets() throws {
        let store = makeStore(policy: PINAttemptPolicy(maxAttempts: 2, lockoutDuration: 60))
        let sam = try store.add(name: "Sam", pin: ProfilePIN("1234"))
        let now = Date()
        _ = store.verifyPIN("1111", for: sam.id, at: now)
        try store.setPIN(ProfilePIN("5678"), for: sam.id)
        #expect(store.verifyPIN("1111", for: sam.id, at: now) == .rejected(remainingAttempts: 1))
    }

    @Test("A storage that fails is reported, not fatal")
    func failingStorage() throws {
        let store = ProfileStore(storage: FailingStorage())
        #expect(store.persistenceError != nil)
        try store.add(name: "Alex")
        #expect(store.profiles.count == 1)
        #expect(store.persistenceError != nil)
    }
}

private struct FailingStorage: ProfileStorage {
    struct Failure: Error {}

    func load() throws -> ProfileArchive? { throw Failure() }
    func save(_ archive: ProfileArchive) throws { throw Failure() }
}

@MainActor
@Suite("Persistence")
struct PersistenceTests {
    @Test("Archives round-trip through JSON")
    func archive() throws {
        let pin = try ProfilePIN("1234")
        let profiles = [
            Profile(name: "Alex", avatar: .initials(.ocean), createdAt: Date(timeIntervalSince1970: 1_700_000_000)),
            Profile(name: "Sam", avatar: .symbol("music.note", .sunset), pin: pin, createdAt: Date(timeIntervalSince1970: 1_700_000_100)),
            Profile(name: "Riley", avatar: .symbol("star.fill", .grape), isKids: true, createdAt: Date(timeIntervalSince1970: 1_700_000_200)),
        ]
        let archive = ProfileArchive(profiles: profiles, lastSelectedID: profiles[1].id)
        let decoded = try ProfileArchive(jsonData: archive.jsonData())
        #expect(decoded == archive)
        #expect(decoded.profiles[1].pin?.matches("1234") == true)
    }

    @Test("Older archives without optional fields decode with defaults")
    func lenientDecoding() throws {
        let json = #"{"profiles":[{"id":"6F1C1A52-1B44-4C59-9E5B-2F8C1D7A0001","name":"Jordan"}]}"#
        let archive = try ProfileArchive(jsonData: Data(json.utf8))
        let profile = try #require(archive.profiles.first)
        #expect(archive.version == ProfileArchive.currentVersion)
        #expect(profile.name == "Jordan")
        #expect(profile.avatar == .suggested(for: "Jordan"))
        #expect(!profile.isKids)
        #expect(profile.pin == nil)
    }

    @Test("A file storage keeps profiles between stores")
    func fileStorage() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("profiles.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let first = ProfileStore(storage: FileProfileStorage(url: url))
        #expect(first.profiles.isEmpty)
        let riley = try first.add(name: "Riley", isKids: true)
        first.select(riley.id)

        let second = ProfileStore(storage: FileProfileStorage(url: url))
        // Dates are stored to the second, so compare everything else.
        #expect(second.profiles.map(\.id) == first.profiles.map(\.id))
        #expect(second.profiles.first?.name == "Riley")
        #expect(second.profiles.first?.isKids == true)
        #expect(second.profiles.first?.avatar == riley.avatar)
        #expect(second.lastSelectedID == riley.id)
    }

    @Test("A user defaults storage keeps profiles between stores")
    func userDefaultsStorage() throws {
        let suite = "TVProfilePickerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let storage = UserDefaultsProfileStorage(defaults: defaults)
        let first = ProfileStore(storage: storage)
        try first.add(name: "Casey", avatar: .symbol("gamecontroller.fill", .ember))

        let second = ProfileStore(storage: UserDefaultsProfileStorage(defaults: defaults))
        #expect(second.profiles.map(\.name) == ["Casey"])
        #expect(second.profiles.first?.avatar == .symbol("gamecontroller.fill", .ember))
    }

    @Test("Profiles describe themselves for VoiceOver")
    func accessibility() throws {
        #expect(Profile(name: "Alex").accessibilitySummary == "Alex")
        #expect(Profile(name: "Riley", isKids: true).accessibilitySummary == "Riley, kids profile")
        let sam = try Profile(name: "Sam", isKids: true, pin: ProfilePIN("1234"))
        #expect(sam.accessibilitySummary == "Sam, kids profile, locked with a PIN")
    }
}
