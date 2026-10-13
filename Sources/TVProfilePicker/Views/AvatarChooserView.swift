import SwiftUI

/// Chooses an avatar: a row of color palettes and a grid of styles (initials and symbols),
/// with a large preview. The selection changes as soon as an option is chosen; Done or the
/// remote's Back (Menu) button closes it.
///
/// Everything fits on one screen without a scroll view, so focused options can grow without
/// being clipped and nothing scrolls under the heading.
///
/// ```swift
/// AvatarChooserView(name: draft.name, selection: $draft.avatar) { dismiss() }
/// ```
public struct AvatarChooserView: View {
    enum Target: Hashable {
        case palette(AvatarPalette)
        case content(Avatar.Content)
        case done
    }

    /// The styles offered: initials, then every symbol in `AvatarSymbol.all`.
    static let contents: [Avatar.Content] = [Avatar.Content.initials] + AvatarSymbol.all.map { Avatar.Content.symbol($0.systemName) }
    static let columns = 7

    private let name: String
    @Binding private var selection: Avatar
    private let showsBackground: Bool
    private let onDone: @MainActor () -> Void
    @FocusState private var focus: Target?

    public init(
        name: String,
        selection: Binding<Avatar>,
        showsBackground: Bool = true,
        onDone: @escaping @MainActor () -> Void
    ) {
        self.name = name
        _selection = selection
        self.showsBackground = showsBackground
        self.onDone = onDone
    }

    private var rows: [[Avatar.Content]] {
        stride(from: 0, to: Self.contents.count, by: Self.columns).map { start in
            Array(Self.contents[start..<min(start + Self.columns, Self.contents.count)])
        }
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 110) {
            VStack(spacing: 30) {
                AvatarView(avatar: selection, name: name, size: 300)
                    .shadow(color: selection.palette.glow.opacity(0.6), radius: 48)
                    .animation(.easeInOut(duration: 0.25), value: selection)
                Text(name.isEmpty ? String(localized: "New Profile") : name)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(selection.accessibilityDescription)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Button(String(localized: "Done")) { onDone() }
                    .buttonStyle(PillButtonStyle(role: .prominent))
                    .focused($focus, equals: .done)
                    .padding(.top, 10)
            }
            .frame(width: 420)

            VStack(alignment: .leading, spacing: 22) {
                Text("Choose an Avatar")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)

                sectionTitle(String(localized: "Color"))
                HStack(spacing: 24) {
                    ForEach(AvatarPalette.allCases, id: \.self) { palette in
                        Button {
                            selection.palette = palette
                        } label: {
                            PaletteSwatch(palette: palette, isSelected: selection.palette == palette)
                        }
                        .buttonStyle(FocusLiftButtonStyle(focusedScale: 1.15))
                        .focused($focus, equals: .palette(palette))
                        .accessibilityLabel(Text(palette.displayName))
                        .accessibilityAddTraits(selection.palette == palette ? .isSelected : [])
                    }
                }
                .padding(.vertical, 14)
                .focusSection()

                sectionTitle(String(localized: "Style"))
                Grid(horizontalSpacing: 30, verticalSpacing: 30) {
                    ForEach(rows.indices, id: \.self) { row in
                        GridRow {
                            ForEach(rows[row], id: \.self) { content in
                                option(content)
                            }
                        }
                    }
                }
                .padding(.vertical, 14)
                .focusSection()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .profileBackdrop(showsBackground, accent: selection.palette)
        .defaultFocus($focus, Target.content(selection.content))
        .onExitCommand { onDone() }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 22, weight: .bold))
            .tracking(2)
            .foregroundStyle(.white.opacity(0.6))
            .accessibilityAddTraits(.isHeader)
    }

    private func option(_ content: Avatar.Content) -> some View {
        let isSelected = selection.content == content
        return Button {
            selection.content = content
        } label: {
            StyleOption(
                avatar: Avatar(content: content, palette: selection.palette),
                name: name,
                isSelected: isSelected
            )
        }
        .buttonStyle(FocusLiftButtonStyle(focusedScale: 1.15))
        .focused($focus, equals: .content(content))
        .accessibilityLabel(Text(label(for: content)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func label(for content: Avatar.Content) -> String {
        switch content {
        case .initials: String(localized: "Initials")
        case let .symbol(systemName): AvatarSymbol.named(systemName)?.name ?? systemName
        }
    }
}

private struct PaletteSwatch: View {
    let palette: AvatarPalette
    let isSelected: Bool
    @Environment(\.focusLifted) private var isFocused

    var body: some View {
        Circle()
            .fill(palette.gradient)
            .frame(width: 76, height: 76)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .overlay {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .padding(-9)
                    .opacity(isFocused ? 1 : 0)
            }
            .shadow(color: palette.glow.opacity(isFocused ? 0.8 : 0), radius: 20)
    }
}

private struct StyleOption: View {
    let avatar: Avatar
    let name: String
    let isSelected: Bool
    @Environment(\.focusLifted) private var isFocused

    var body: some View {
        AvatarView(avatar: avatar, name: name, size: 112)
            .overlay {
                // Selected: a white ring around the avatar; focused: a ring on its edge.
                Circle()
                    .strokeBorder(.white.opacity(isSelected ? 0.9 : 0), lineWidth: 4)
                    .padding(-10)
            }
            .overlay {
                Circle()
                    .strokeBorder(.white, lineWidth: 5)
                    .opacity(isFocused ? 1 : 0)
            }
            .shadow(color: avatar.palette.glow.opacity(isFocused ? 0.85 : 0), radius: 26)
            .shadow(color: .black.opacity(isFocused ? 0.45 : 0.25), radius: isFocused ? 18 : 6, y: isFocused ? 12 : 4)
    }
}
