import SwiftUI

/// The "Who's watching?" screen: a row of focusable profile tiles, an Add Profile tile and a
/// Manage Profiles button that switches to edit mode.
///
/// Choosing a profile calls `onSelect`, after asking for its PIN when it has one. In edit mode,
/// choosing a profile opens `ProfileEditorView` (after its PIN, for locked profiles), where it can
/// be renamed, given another avatar, marked as a kids profile, locked or deleted.
///
/// ```swift
/// ProfilePicker(store: store) { profile in
///     session.start(as: profile)
/// }
/// ```
public struct ProfilePicker: View {
    private let store: ProfileStore
    private let title: LocalizedStringKey
    private let avatarSize: CGFloat
    private let allowsEditing: Bool
    private let showsBackground: Bool
    private let externalEditing: Binding<Bool>?
    private let onSelect: @MainActor (Profile) -> Void

    @State private var internalEditing = false
    @State private var route: Route?
    @FocusState private var focus: FocusTarget?

    /// - Parameters:
    ///   - store: The profiles.
    ///   - title: The heading above the tiles.
    ///   - avatarSize: The tiles' avatar diameter in points. With more profiles than fit, the
    ///     tiles shrink, then scroll.
    ///   - allowsEditing: Whether the Add Profile tile and the Manage Profiles button are shown.
    ///   - showsBackground: Whether the picker draws its own backdrop, tinted with the focused
    ///     profile's colors. Turn it off to put the picker over your own background.
    ///   - isEditing: Edit mode, if you want to control or observe it; otherwise the picker keeps
    ///     its own.
    ///   - onSelect: Called with the chosen profile, after its PIN when it has one.
    public init(
        store: ProfileStore,
        title: LocalizedStringKey = "Who's watching?",
        avatarSize: CGFloat = 200,
        allowsEditing: Bool = true,
        showsBackground: Bool = true,
        isEditing: Binding<Bool>? = nil,
        onSelect: @escaping @MainActor (Profile) -> Void
    ) {
        self.store = store
        self.title = title
        self.avatarSize = avatarSize
        self.allowsEditing = allowsEditing
        self.showsBackground = showsBackground
        externalEditing = isEditing
        self.onSelect = onSelect
    }

    enum FocusTarget: Hashable {
        case profile(Profile.ID)
        case add
        case manage
    }

    enum Route: Identifiable {
        case unlock(Profile, thenEdit: Bool)
        case edit(Profile)
        case create

        var id: String {
            switch self {
            case let .unlock(profile, thenEdit): "unlock-\(profile.id)-\(thenEdit)"
            case let .edit(profile): "edit-\(profile.id)"
            case .create: "create"
            }
        }
    }

    private var isEditing: Bool {
        externalEditing?.wrappedValue ?? internalEditing
    }

    private func setEditing(_ value: Bool) {
        if let externalEditing {
            externalEditing.wrappedValue = value
        } else {
            internalEditing = value
        }
    }

    /// The last chosen profile, else the first one, else the Add Profile tile.
    private var initialFocus: FocusTarget? {
        if let profile = store.lastSelectedProfile ?? store.profiles.first {
            return .profile(profile.id)
        }
        return allowsEditing ? .add : nil
    }

    private var focusedPalette: AvatarPalette? {
        guard case let .profile(id)? = focus else { return nil }
        return store.profile(id: id)?.avatar.palette
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            heading
            tiles
                .padding(.top, 64)
            footer
                .padding(.top, 56)
            Spacer(minLength: 0)
        }
        // Content stays inside the safe area, which keeps it clear of TV overscan; only the
        // backdrop runs to the screen's edges.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .profileBackdrop(showsBackground, accent: focusedPalette)
        .defaultFocus($focus, initialFocus)
        .task {
            // Default focus normally places it; this covers the case where the focus engine
            // settled before the tiles appeared.
            try? await Task.sleep(for: .milliseconds(200))
            if focus == nil {
                focus = initialFocus
            }
        }
        .onChange(of: store.profiles.map(\.id)) {
            if case let .profile(id)? = focus, store.profile(id: id) == nil {
                focus = initialFocus
            }
        }
        .onExitCommand(perform: isEditing ? { setEditing(false) } : nil)
        .profileCover(item: $route) { route in
            destination(for: route)
        }
        .animation(.easeInOut(duration: 0.25), value: isEditing)
    }

    @ViewBuilder
    private var heading: some View {
        Group {
            if isEditing {
                Text("Manage Profiles")
            } else {
                Text(title)
            }
        }
        .font(.system(size: 60, weight: .bold))
        .foregroundStyle(.white)
        .accessibilityAddTraits(.isHeader)
    }

    /// One row of tiles at full size, else smaller, else a scrolling row. The scrolling row is
    /// padded inside and clipped, so focused tiles have room to grow without the scroll view
    /// drawing outside its bounds.
    private var tiles: some View {
        ViewThatFits(in: .horizontal) {
            tileRow(size: avatarSize)
            tileRow(size: avatarSize * 0.78)
            ScrollView(.horizontal) {
                tileRow(size: avatarSize * 0.78)
                    .padding(.vertical, avatarSize * 0.22)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled(false)
            .clipped()
        }
    }

    private func tileRow(size: CGFloat) -> some View {
        HStack(alignment: .top, spacing: size * 0.22) {
            ForEach(store.profiles) { profile in
                Button {
                    activate(profile)
                } label: {
                    ProfileTileLabel(profile: profile, size: size, isEditing: isEditing)
                }
                .buttonStyle(FocusLiftButtonStyle(focusedScale: 1.12))
                .focused($focus, equals: .profile(profile.id))
                .accessibilityLabel(Text(profile.accessibilitySummary))
                .accessibilityHint(Text(hint(for: profile)))
            }
            if allowsEditing, store.canAddProfile {
                Button {
                    route = .create
                } label: {
                    AddProfileTileLabel(size: size)
                }
                .buttonStyle(FocusLiftButtonStyle(focusedScale: 1.12))
                .focused($focus, equals: .add)
                .accessibilityLabel(Text("Add Profile"))
            }
        }
        // Room on both sides for the focused tile to grow and glow.
        .padding(.horizontal, size * 0.25)
        .padding(.vertical, size * 0.12)
        .focusSection()
    }

    @ViewBuilder
    private var footer: some View {
        if allowsEditing {
            Button {
                setEditing(!isEditing)
            } label: {
                Label(
                    isEditing ? String(localized: "Done") : String(localized: "Manage Profiles"),
                    systemImage: isEditing ? "checkmark" : "pencil"
                )
            }
            .buttonStyle(PillButtonStyle(role: isEditing ? .prominent : .standard))
            .focused($focus, equals: .manage)
        }
    }

    private func hint(for profile: Profile) -> String {
        if isEditing { return "Edits this profile." }
        return profile.isLocked ? "Asks for the profile's PIN." : "Switches to this profile."
    }

    private func activate(_ profile: Profile) {
        if profile.isLocked {
            route = .unlock(profile, thenEdit: isEditing)
        } else if isEditing {
            route = .edit(profile)
        } else {
            finish(profile)
        }
    }

    private func finish(_ profile: Profile) {
        store.select(profile.id)
        onSelect(profile)
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case let .unlock(profile, thenEdit):
            UnlockFlow(store: store, profile: profile, thenEdit: thenEdit) {
                self.route = nil
            } onUnlock: {
                self.route = nil
                finish(profile)
            }
        case let .edit(profile):
            ProfileEditorView(store: store, profileID: profile.id) {
                self.route = nil
            }
        case .create:
            ProfileEditorView(store: store, profileID: nil) {
                self.route = nil
            }
        }
    }
}

/// The PIN pad for a locked profile, followed by the editor when the profile was chosen in edit
/// mode; both in one cover, so nothing is dismissed and presented again in between.
private struct UnlockFlow: View {
    let store: ProfileStore
    let profile: Profile
    let thenEdit: Bool
    let onClose: @MainActor () -> Void
    let onUnlock: @MainActor () -> Void
    @State private var isUnlocked = false

    var body: some View {
        if isUnlocked {
            ProfileEditorView(store: store, profileID: profile.id, onDone: onClose)
        } else {
            PINPadView(
                unlocking: profile,
                lockedUntil: store.lockoutEnd(for: profile.id),
                verify: { store.verifyPIN($0, for: profile.id) },
                onUnlock: {
                    if thenEdit {
                        isUnlocked = true
                    } else {
                        onUnlock()
                    }
                },
                onCancel: onClose
            )
        }
    }
}
