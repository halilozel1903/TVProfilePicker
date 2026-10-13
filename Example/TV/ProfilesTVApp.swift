import SwiftUI
import TVProfilePicker

@main
struct ProfilesTVApp: App {
    @State private var store: ProfileStore

    init() {
        _store = State(initialValue: DemoProfiles.makeStore(for: ScreenshotScene.current))
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store, scene: ScreenshotScene.current)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    let store: ProfileStore
    let scene: ScreenshotScene?
    @State private var current: Profile?
    @State private var chooserAvatar = Avatar.symbol("gamecontroller.fill", .ember)

    var body: some View {
        content
            .signalsScreenshotReady(scene)
    }

    @ViewBuilder
    private var content: some View {
        switch scene {
        case .pin:
            if let sam = demo("Sam") {
                PINPadView(
                    unlocking: sam,
                    entry: PINEntry(length: 4, digits: [1, 2]),
                    verify: { store.verifyPIN($0, for: sam.id) },
                    onUnlock: {},
                    onCancel: {}
                )
            }
        case .edit:
            if let sam = demo("Sam") {
                ProfileEditorView(store: store, profileID: sam.id) {}
            }
        case .avatar:
            AvatarChooserView(name: "Casey", selection: $chooserAvatar) {}
        case .picker, nil:
            if let current {
                HomeView(profile: current) {
                    self.current = nil
                }
            } else {
                ProfilePicker(store: store) { profile in
                    current = profile
                }
            }
        }
    }

    private func demo(_ name: String) -> Profile? {
        store.profiles.first { $0.name == name }
    }
}

/// What the app shows once a profile is chosen.
struct HomeView: View {
    let profile: Profile
    let switchProfile: () -> Void

    var body: some View {
        VStack(spacing: 40) {
            AvatarView(profile: profile, size: 220)
            Text("Welcome back, \(profile.name)")
                .font(.system(size: 60, weight: .bold))
            if profile.isKids {
                KidsBadge(scale: 1.4)
            }
            Text("Your app's home screen goes here.")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Button("Switch Profile", systemImage: "person.2.fill", action: switchProfile)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { ProfileBackdrop(accent: profile.avatar.palette).ignoresSafeArea() }
    }
}
