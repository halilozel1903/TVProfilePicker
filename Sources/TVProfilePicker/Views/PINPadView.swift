import SwiftUI

/// A full-screen PIN pad for the Siri Remote: the profile's avatar, a row of dots and a 3 by 4
/// keypad. A wrong PIN shakes the dots (a red flash with Reduce Motion) and is announced to
/// VoiceOver; too many wrong PINs lock the profile for a while, with a countdown.
///
/// It unlocks a profile, or creates a new PIN (typed twice):
///
/// ```swift
/// PINPadView(unlocking: profile, verify: { store.verifyPIN($0, for: profile.id) },
///            onUnlock: { open(profile) }, onCancel: { dismiss() })
///
/// PINPadView(creatingPINFor: "Sam", avatar: avatar,
///            onCreate: { pin in draft.pin = pin }, onCancel: { dismiss() })
/// ```
public struct PINPadView: View {
    enum Mode {
        case unlock(verify: @MainActor (String) -> PINVerification, onUnlock: @MainActor () -> Void)
        case create(onCreate: @MainActor (ProfilePIN) -> Void)
    }

    enum Key: Hashable {
        case digit(Int)
        case delete
        case cancel

        var accessibilityLabel: String {
            switch self {
            case let .digit(digit): "\(digit)"
            case .delete: "Delete"
            case .cancel: "Cancel"
            }
        }
    }

    enum Feedback: Equatable {
        case idle
        case wrong(remainingAttempts: Int?)
        case lockedOut(until: Date)
        case mismatch
    }

    private let name: String
    private let avatar: Avatar
    private let mode: Mode
    private let showsBackground: Bool
    private let onCancel: @MainActor () -> Void

    @State private var entry: PINEntry
    @State private var firstCode: String?
    @State private var feedback: Feedback
    @State private var lockedUntil: Date?
    @State private var shakes: CGFloat = 0
    @State private var flash = false
    @State private var isAccepted = false
    @FocusState private var focusedKey: Key?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A pad that asks for a profile's PIN.
    /// - Parameters:
    ///   - profile: The locked profile.
    ///   - entry: Digits already typed; normally empty.
    ///   - lockedUntil: When the profile is locked out, its end (`ProfileStore.lockoutEnd(for:)`).
    ///   - verify: Checks a complete PIN, usually `store.verifyPIN(_:for:)`.
    ///   - onUnlock: Called shortly after the right PIN, once the dots have turned green.
    ///   - onCancel: Called by the Cancel key and the remote's Back (Menu) button.
    public init(
        unlocking profile: Profile,
        entry: PINEntry? = nil,
        lockedUntil: Date? = nil,
        showsBackground: Bool = true,
        verify: @escaping @MainActor (String) -> PINVerification,
        onUnlock: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        name = profile.name
        avatar = profile.avatar
        mode = .unlock(verify: verify, onUnlock: onUnlock)
        self.showsBackground = showsBackground
        self.onCancel = onCancel
        _entry = State(initialValue: entry ?? PINEntry(length: profile.pin?.length ?? 4))
        _firstCode = State(initialValue: nil)
        _lockedUntil = State(initialValue: lockedUntil)
        _feedback = State(initialValue: lockedUntil.map { Feedback.lockedOut(until: $0) } ?? Feedback.idle)
    }

    /// A pad that creates a PIN: it asks for the digits, then for them again, and calls
    /// `onCreate` when both match.
    public init(
        creatingPINFor name: String,
        avatar: Avatar,
        length: Int = 4,
        showsBackground: Bool = true,
        onCreate: @escaping @MainActor (ProfilePIN) -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.name = name
        self.avatar = avatar
        mode = .create(onCreate: onCreate)
        self.showsBackground = showsBackground
        self.onCancel = onCancel
        _entry = State(initialValue: PINEntry(length: length))
        _firstCode = State(initialValue: nil)
        _lockedUntil = State(initialValue: nil)
        _feedback = State(initialValue: .idle)
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 150) {
            VStack(spacing: 28) {
                AvatarView(avatar: avatar, name: name, size: 220)
                    .shadow(color: avatar.palette.glow.opacity(0.6), radius: 40)
                Text(name.isEmpty ? String(localized: "New Profile") : name)
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(prompt)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                dots
                    .padding(.top, 18)
                    .modifier(ShakeEffect(animatableData: shakes))
                message
                    .frame(height: 44)
            }
            .frame(width: 640)
            keypad
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .profileBackdrop(showsBackground, accent: avatar.palette)
        .defaultFocus($focusedKey, Key.digit(5))
        .onExitCommand { onCancel() }
    }

    private var prompt: String {
        switch mode {
        case .unlock:
            String(localized: "Enter your PIN to open this profile.")
        case .create:
            firstCode == nil
                ? String(localized: "Choose a \(entry.length)-digit PIN.")
                : String(localized: "Enter the PIN again to confirm it.")
        }
    }

    private var isError: Bool {
        flash || feedback != .idle
    }

    private var dotColor: Color {
        if isAccepted { return Color(red: 0.3, green: 0.85, blue: 0.5) }
        if isError { return Color(red: 1, green: 0.42, blue: 0.42) }
        return .white
    }

    private var dots: some View {
        HStack(spacing: 28) {
            ForEach(0..<entry.length, id: \.self) { index in
                Circle()
                    .fill(index < entry.digits.count ? dotColor : Color.clear)
                    .overlay(Circle().strokeBorder(dotColor, lineWidth: 3))
                    .frame(width: 30, height: 30)
            }
        }
        .animation(.easeOut(duration: 0.15), value: entry)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("PIN"))
        .accessibilityValue(Text(entry.accessibilityValue))
    }

    @ViewBuilder
    private var message: some View {
        Group {
            switch feedback {
            case .idle:
                Text(verbatim: " ")
            case let .wrong(remaining):
                if let remaining {
                    Text("Wrong PIN. Tries left before a short lock: \(remaining).")
                } else {
                    Text("Wrong PIN. Try again.")
                }
            case let .lockedOut(until):
                let now = Date()
                Text("Too many tries. Try again in \(Text(timerInterval: now...max(now, until), countsDown: true)).")
            case .mismatch:
                Text("The PINs didn't match. Choose a PIN again.")
            }
        }
        .font(.system(size: 26, weight: .semibold))
        .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.55))
        .multilineTextAlignment(.center)
    }

    private var keypad: some View {
        Grid(horizontalSpacing: 34, verticalSpacing: 30) {
            GridRow { key(.digit(1)); key(.digit(2)); key(.digit(3)) }
            GridRow { key(.digit(4)); key(.digit(5)); key(.digit(6)) }
            GridRow { key(.digit(7)); key(.digit(8)); key(.digit(9)) }
            GridRow { key(.cancel); key(.digit(0)); key(.delete) }
        }
        .padding(30)
        .focusSection()
    }

    private func key(_ key: Key) -> some View {
        Button {
            press(key)
        } label: {
            KeypadKeyLabel(key: key)
        }
        .buttonStyle(FocusLiftButtonStyle(focusedScale: 1.14))
        .focused($focusedKey, equals: key)
        .accessibilityLabel(Text(key.accessibilityLabel))
    }

    // MARK: Input

    private func press(_ key: Key) {
        switch key {
        case .cancel:
            onCancel()
        case .delete:
            guard !isAccepted, !entry.isComplete else { return }
            entry.deleteLast()
        case let .digit(digit):
            guard !isAccepted, !entry.isComplete else { return }
            if let lockedUntil, Date() < lockedUntil {
                shake()
                return
            }
            lockedUntil = nil
            if feedback != .idle {
                feedback = .idle
            }
            entry.append(digit)
            if entry.isComplete {
                submit()
            }
        }
    }

    private func submit() {
        let code = entry.code
        switch mode {
        case let .unlock(verify, onUnlock):
            switch verify(code) {
            case .accepted:
                accept(then: onUnlock)
            case let .rejected(remaining):
                reject(.wrong(remainingAttempts: remaining))
            case let .lockedOut(until):
                lockedUntil = until
                reject(.lockedOut(until: until))
            }
        case let .create(onCreate):
            if let firstCode {
                if firstCode == code, let pin = try? ProfilePIN(code) {
                    accept { onCreate(pin) }
                } else {
                    self.firstCode = nil
                    reject(.mismatch)
                }
            } else {
                firstCode = code
                entry.clear()
                announce(prompt)
            }
        }
    }

    private func accept(then action: @escaping @MainActor () -> Void) {
        isAccepted = true
        announce(String(localized: "PIN accepted."))
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            action()
        }
    }

    private func reject(_ newFeedback: Feedback) {
        feedback = newFeedback
        shake()
        switch newFeedback {
        case .wrong: announce(String(localized: "Wrong PIN."))
        case .lockedOut: announce(String(localized: "Too many tries. The profile is locked for a moment."))
        case .mismatch: announce(String(localized: "The PINs didn't match."))
        case .idle: break
        }
        Task {
            try? await Task.sleep(for: .milliseconds(550))
            entry.clear()
        }
    }

    private func shake() {
        if reduceMotion {
            flash = true
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                flash = false
            }
        } else {
            withAnimation(.linear(duration: 0.45)) {
                shakes += 1
            }
        }
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}

/// A round keypad key.
private struct KeypadKeyLabel: View {
    let key: PINPadView.Key
    @Environment(\.focusLifted) private var isFocused

    var body: some View {
        ZStack {
            Circle()
                .fill(isFocused ? Color.white : Color.white.opacity(0.1))
            Circle()
                .strokeBorder(.white.opacity(isFocused ? 0 : 0.18), lineWidth: 2)
            content
                .foregroundStyle(isFocused ? Color.black : Color.white)
        }
        .frame(width: 124, height: 124)
        .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 22, y: 12)
    }

    @ViewBuilder
    private var content: some View {
        switch key {
        case let .digit(digit):
            Text(verbatim: "\(digit)")
                .font(.system(size: 52, weight: .semibold, design: .rounded))
        case .delete:
            Image(systemName: "delete.left")
                .font(.system(size: 38, weight: .semibold))
        case .cancel:
            Image(systemName: "xmark")
                .font(.system(size: 36, weight: .semibold))
        }
    }
}
