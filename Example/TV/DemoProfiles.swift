import Foundation
import TVProfilePicker

/// The demo household: generic made-up names, used by the example app and its screenshots.
/// Sam's profile is locked with the demo PIN 1234; Riley and Casey are kids profiles.
enum DemoProfiles {
    static let pin = "1234"

    static func make() -> [Profile] {
        [
            Profile(name: "Alex", avatar: .initials(.ocean)),
            Profile(name: "Sam", avatar: .symbol("music.note", .sunset), pin: try? ProfilePIN(pin)),
            Profile(name: "Jordan", avatar: .symbol("leaf.fill", .forest)),
            Profile(name: "Riley", avatar: .symbol("star.fill", .grape), isKids: true),
            Profile(name: "Casey", avatar: .symbol("gamecontroller.fill", .ember), isKids: true),
        ]
    }

    /// The store: in memory for screenshot scenes (the same profiles every run, Jordan chosen
    /// last so the picker focuses Jordan), in user defaults otherwise.
    @MainActor
    static func makeStore(for scene: ScreenshotScene?) -> ProfileStore {
        guard scene != nil else {
            return ProfileStore(storage: UserDefaultsProfileStorage(), initialProfiles: make())
        }
        let store = ProfileStore(storage: InMemoryProfileStorage(), initialProfiles: make())
        if let jordan = store.profiles.first(where: { $0.name == "Jordan" }) {
            store.select(jordan.id)
        }
        return store
    }
}
