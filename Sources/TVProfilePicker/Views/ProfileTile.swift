import SwiftUI

/// A profile in the picker: the avatar with its badges and the name. Use it as the label of a
/// button styled with `FocusLiftButtonStyle`, which provides the focus state.
public struct ProfileTileLabel: View {
    public let profile: Profile
    public let size: CGFloat
    public let isEditing: Bool
    @Environment(\.focusLifted) private var isFocused

    public init(profile: Profile, size: CGFloat = 200, isEditing: Bool = false) {
        self.profile = profile
        self.size = size
        self.isEditing = isEditing
    }

    public var body: some View {
        VStack(spacing: size * 0.15) {
            AvatarView(profile: profile, size: size)
                .overlay {
                    if isEditing {
                        ZStack {
                            Circle().fill(.black.opacity(0.5))
                            Image(systemName: "pencil")
                                .font(.system(size: size * 0.26, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(.white, lineWidth: max(4, size * 0.03))
                        .opacity(isFocused ? 1 : 0)
                }
                // The glow in the avatar's own color, then a drop shadow for depth.
                .shadow(color: profile.avatar.palette.glow.opacity(isFocused ? 0.85 : 0), radius: isFocused ? size * 0.2 : 0)
                .shadow(color: .black.opacity(0.45), radius: isFocused ? size * 0.14 : size * 0.05, y: isFocused ? size * 0.1 : size * 0.03)
                .overlay(alignment: .topTrailing) {
                    if profile.isLocked {
                        LockBadge(size: size * 0.24)
                    }
                }
                .overlay(alignment: .bottom) {
                    if profile.isKids {
                        KidsBadge(scale: size / 200)
                            .offset(y: size * 0.04)
                    }
                }
            Text(profile.name)
                .font(.system(size: size * 0.15, weight: isFocused ? .bold : .semibold))
                .foregroundStyle(isFocused ? Color.white : Color.white.opacity(0.62))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: size * 1.15)
        }
    }
}

/// The "Add Profile" tile.
public struct AddProfileTileLabel: View {
    public let size: CGFloat
    @Environment(\.focusLifted) private var isFocused

    public init(size: CGFloat = 200) {
        self.size = size
    }

    public var body: some View {
        VStack(spacing: size * 0.15) {
            ZStack {
                Circle().fill(.white.opacity(isFocused ? 0.24 : 0.07))
                Circle().strokeBorder(
                    Color.white.opacity(isFocused ? 0.95 : 0.4),
                    style: StrokeStyle(lineWidth: max(3, size * 0.02), dash: [size * 0.06, size * 0.05])
                )
                Image(systemName: "plus")
                    .font(.system(size: size * 0.3, weight: .semibold))
                    .foregroundStyle(.white.opacity(isFocused ? 1 : 0.7))
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: size * 0.14, y: size * 0.1)
            Text("Add Profile")
                .font(.system(size: size * 0.15, weight: isFocused ? .bold : .semibold))
                .foregroundStyle(isFocused ? Color.white : Color.white.opacity(0.62))
                .lineLimit(1)
                .frame(width: size * 1.15)
        }
    }
}
