import SwiftUI

/// A round generated avatar: initials or a symbol over the palette's gradient.
///
/// ```swift
/// AvatarView(profile: profile, size: 160)
/// AvatarView(avatar: .symbol("star.fill", .sunset), name: "Sam")
/// ```
public struct AvatarView: View {
    public let avatar: Avatar
    public let name: String
    public let size: CGFloat

    public init(avatar: Avatar, name: String, size: CGFloat = 160) {
        self.avatar = avatar
        self.name = name
        self.size = size
    }

    public init(profile: Profile, size: CGFloat = 160) {
        self.init(avatar: profile.avatar, name: profile.name, size: size)
    }

    public var body: some View {
        ZStack {
            Circle().fill(avatar.palette.gradient)
            // A soft highlight, so the disc reads as an object rather than a flat swatch.
            Circle().fill(
                RadialGradient(
                    colors: [.white.opacity(0.3), .clear],
                    center: UnitPoint(x: 0.3, y: 0.18),
                    startRadius: 0,
                    endRadius: size * 0.75
                )
            )
            Circle().strokeBorder(.white.opacity(0.14), lineWidth: max(1, size * 0.012))
            content
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: size * 0.02, y: size * 0.015)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text(avatar.accessibilityDescription))
    }

    @ViewBuilder
    private var content: some View {
        switch avatar.content {
        case .initials:
            Text(Avatar.initials(from: name))
                .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(size * 0.14)
        case let .symbol(systemName):
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
        }
    }
}

/// The yellow "KIDS" capsule shown on kids profiles.
public struct KidsBadge: View {
    public var scale: CGFloat

    public init(scale: CGFloat = 1) {
        self.scale = scale
    }

    public var body: some View {
        Text("KIDS")
            .font(.system(size: 18 * scale, weight: .heavy, design: .rounded))
            .tracking(1.6 * scale)
            .foregroundStyle(Color(red: 0.2, green: 0.12, blue: 0))
            .padding(.horizontal, 14 * scale)
            .padding(.vertical, 5 * scale)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [Color(red: 1, green: 0.86, blue: 0.3), Color(red: 1, green: 0.65, blue: 0.17)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .overlay(Capsule().strokeBorder(.black.opacity(0.25), lineWidth: max(1, 2 * scale)))
            .accessibilityLabel(Text("Kids profile"))
    }
}

/// The small padlock shown on profiles with a PIN.
struct LockBadge: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(red: 0.08, green: 0.09, blue: 0.14).opacity(0.92)))
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: max(1, size * 0.05)))
            .accessibilityLabel(Text("Locked with a PIN"))
    }
}
