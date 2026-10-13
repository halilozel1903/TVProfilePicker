import SwiftUI

/// Adds or edits a profile: its name, avatar, kids setting and PIN, and deletes it.
///
/// Changes are kept in a draft and saved to the store with Save; Cancel or the remote's Back
/// (Menu) button leaves the profile as it was. A new profile's avatar follows its name (initials
/// in a palette picked from the name) until an avatar is chosen.
///
/// ```swift
/// ProfileEditorView(store: store, profileID: profile.id) { dismiss() }   // edit
/// ProfileEditorView(store: store, profileID: nil) { dismiss() }          // add
/// ```
public struct ProfileEditorView: View {
    enum Field: Hashable {
        case avatar, name, save, cancel, delete
    }

    enum Cover: String, Identifiable {
        case avatar, pin
        var id: String { rawValue }
    }

    private let store: ProfileStore
    private let profileID: Profile.ID?
    private let showsBackground: Bool
    private let onDone: @MainActor () -> Void
    /// Whether the editor adds a profile; fixed at creation, so the title doesn't change while
    /// a deleted profile's editor closes.
    private let isNew: Bool

    @State private var draft: ProfileDraft
    @State private var avatarWasChosen: Bool
    @State private var errorMessage: String?
    @State private var cover: Cover?
    @State private var confirmingDelete = false
    @State private var confirmingPINChange = false
    @FocusState private var focus: Field?

    /// - Parameters:
    ///   - store: The profiles.
    ///   - profileID: The profile to edit, or nil to add one.
    ///   - showsBackground: Whether the editor draws its own backdrop.
    ///   - onDone: Called after Save, Cancel, Delete or the Back button; dismiss the editor here.
    public init(
        store: ProfileStore,
        profileID: Profile.ID?,
        showsBackground: Bool = true,
        onDone: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.profileID = profileID
        self.showsBackground = showsBackground
        self.onDone = onDone
        let profile = store.profile(id: profileID)
        isNew = profile == nil
        _draft = State(initialValue: profile.map { ProfileDraft($0) } ?? ProfileDraft())
        _avatarWasChosen = State(initialValue: profile != nil)
    }


    public var body: some View {
        HStack(alignment: .center, spacing: 120) {
            VStack(spacing: 40) {
                AvatarView(avatar: draft.avatar, name: draft.name, size: 280)
                    .shadow(color: draft.avatar.palette.glow.opacity(0.55), radius: 44)
                    .overlay(alignment: .bottom) {
                        if draft.isKids {
                            KidsBadge(scale: 1.35)
                                .offset(y: 12)
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: draft.avatar)
                Button {
                    cover = .avatar
                } label: {
                    Label(String(localized: "Change Avatar"), systemImage: "paintpalette.fill")
                }
                .buttonStyle(PillButtonStyle())
                .focused($focus, equals: .avatar)
            }
            .frame(width: 420)

            VStack(alignment: .leading, spacing: 24) {
                Text(isNew ? String(localized: "Add Profile") : String(localized: "Edit Profile"))
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)

                TextField(String(localized: "Name"), text: $draft.name)
                    .font(.system(size: 34, weight: .semibold))
                    .frame(width: 780)
                    .focused($focus, equals: .name)
                    .accessibilityLabel(Text("Profile name"))
                    .onChange(of: draft.name) {
                        errorMessage = nil
                        if !avatarWasChosen {
                            draft.avatar = .suggested(for: draft.name)
                        }
                    }

                Group {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    } else {
                        Text(verbatim: " ")
                    }
                }
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.55))
                .frame(height: 30)

                SettingRow(
                    systemImage: "figure.and.child.holdinghands",
                    title: String(localized: "Kids profile"),
                    detail: String(localized: "Shows a Kids badge on the profile."),
                    value: draft.isKids ? String(localized: "On") : String(localized: "Off")
                ) {
                    draft.isKids.toggle()
                }

                SettingRow(
                    systemImage: draft.pin == nil ? "lock.open.fill" : "lock.fill",
                    title: String(localized: "PIN lock"),
                    detail: draft.pin.map { String(localized: "A \($0.length)-digit PIN opens this profile.") }
                        ?? String(localized: "Ask for a PIN before opening this profile."),
                    value: draft.pin == nil ? String(localized: "Off") : String(localized: "On")
                ) {
                    if draft.pin == nil {
                        cover = .pin
                    } else {
                        confirmingPINChange = true
                    }
                }

                HStack(spacing: 28) {
                    Button(String(localized: "Save")) { save() }
                        .buttonStyle(PillButtonStyle(role: .prominent))
                        .focused($focus, equals: .save)
                    Button(String(localized: "Cancel")) { onDone() }
                        .buttonStyle(PillButtonStyle())
                        .focused($focus, equals: .cancel)
                    if !isNew {
                        Button {
                            confirmingDelete = true
                        } label: {
                            Label(String(localized: "Delete Profile"), systemImage: "trash")
                        }
                        .buttonStyle(PillButtonStyle(role: .destructive))
                        .focused($focus, equals: .delete)
                    }
                }
                .padding(.top, 18)
                .focusSection()
            }
            .frame(width: 820, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .profileBackdrop(showsBackground, accent: draft.avatar.palette)
        .defaultFocus($focus, isNew ? Field.name : Field.avatar)
        .onExitCommand { onDone() }
        .profileCover(item: $cover) { cover in
            switch cover {
            case .avatar:
                AvatarChooserView(name: draft.name, selection: $draft.avatar) {
                    avatarWasChosen = true
                    self.cover = nil
                }
            case .pin:
                PINPadView(creatingPINFor: draft.name, avatar: draft.avatar) { pin in
                    draft.pin = pin
                    self.cover = nil
                } onCancel: {
                    self.cover = nil
                }
            }
        }
        .confirmationDialog(
            Text("PIN lock"),
            isPresented: $confirmingPINChange,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Change PIN")) { cover = .pin }
            Button(String(localized: "Remove PIN"), role: .destructive) { draft.pin = nil }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("Changes take effect when you save the profile.")
        }
        .confirmationDialog(
            Text("Delete \(draft.name)?"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete Profile"), role: .destructive) { delete() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("The profile is removed from this Apple TV.")
        }
    }

    private func save() {
        do {
            try store.save(draft, for: isNew ? nil : profileID)
            onDone()
        } catch {
            errorMessage = error.localizedDescription
            focus = .name
            AccessibilityNotification.Announcement(error.localizedDescription).post()
        }
    }

    private func delete() {
        guard let profileID else { return }
        try? store.delete(profileID)
        onDone()
    }
}

/// A settings row: an icon, a title with a detail line, and the current value.
private struct SettingRow: View {
    let systemImage: String
    let title: String
    let detail: String
    let value: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 26) {
                Image(systemName: systemImage)
                    .font(.system(size: 32, weight: .semibold))
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 30, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 22, weight: .regular))
                        .opacity(0.72)
                        .lineLimit(1)
                }
                Spacer(minLength: 20)
                Text(value)
                    .font(.system(size: 28, weight: .bold))
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
            .frame(width: 780)
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
        .accessibilityHint(Text(detail))
        .accessibilityAddTraits(.isButton)
    }
}
