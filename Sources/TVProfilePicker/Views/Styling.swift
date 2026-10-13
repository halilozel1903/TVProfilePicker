import SwiftUI

extension Color {
    /// A SwiftUI color from an `RGBColor`.
    public init(_ rgb: RGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension AvatarPalette {
    /// The palette as a top-leading to bottom-trailing gradient.
    public var gradient: LinearGradient {
        LinearGradient(colors: [Color(top), Color(bottom)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The color focused avatars glow in.
    public var glow: Color { Color(top) }
}

extension EnvironmentValues {
    /// Whether the button whose label this is has focus; set by the package's button styles.
    @Entry var focusLifted: Bool = false
}

/// A button style for Apple TV that lifts the label when it has focus: it grows (unless Reduce
/// Motion is on) and tells the label through the environment, so the label can add a ring or a
/// glow. Used by the profile tiles, keypad keys and avatar options.
public struct FocusLiftButtonStyle: ButtonStyle {
    public var focusedScale: CGFloat

    public init(focusedScale: CGFloat = 1.1) {
        self.focusedScale = focusedScale
    }

    public func makeBody(configuration: Configuration) -> some View {
        FocusLiftBody(configuration: configuration, focusedScale: focusedScale)
    }
}

private struct FocusLiftBody: View {
    let configuration: ButtonStyleConfiguration
    let focusedScale: CGFloat
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .environment(\.focusLifted, isFocused)
            .scaleEffect(scale)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }

    private var scale: CGFloat {
        if reduceMotion { return 1 }
        if configuration.isPressed { return focusedScale * 0.96 }
        return isFocused ? focusedScale : 1
    }
}

/// The look of the package's text buttons.
enum SurfaceRole {
    case standard, prominent, destructive

    func foreground(focused: Bool) -> Color {
        switch (self, focused) {
        case (.destructive, true): Color(red: 0.78, green: 0.11, blue: 0.13)
        case (.destructive, false): Color(red: 1, green: 0.55, blue: 0.55)
        case (.prominent, _): .black
        case (.standard, true): .black
        case (.standard, false): .white
        }
    }

    func background(focused: Bool) -> Color {
        switch (self, focused) {
        case (_, true): .white
        case (.prominent, false): .white.opacity(0.82)
        default: .white.opacity(0.12)
        }
    }
}

/// A capsule text button: translucent at rest, white and lifted with focus.
struct PillButtonStyle: ButtonStyle {
    var role: SurfaceRole = .standard

    func makeBody(configuration: Configuration) -> some View {
        SurfaceBody(configuration: configuration, role: role, cornerRadius: nil)
    }
}

/// A wide rounded-rectangle row, as in Settings.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SurfaceBody(configuration: configuration, role: .standard, cornerRadius: 22)
    }
}

private struct SurfaceBody: View {
    let configuration: ButtonStyleConfiguration
    let role: SurfaceRole
    let cornerRadius: CGFloat?
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(.system(size: 28, weight: .semibold))
            .padding(.horizontal, cornerRadius == nil ? 40 : 0)
            .padding(.vertical, cornerRadius == nil ? 18 : 0)
            .foregroundStyle(role.foreground(focused: isFocused))
            .background {
                if let cornerRadius {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(role.background(focused: isFocused))
                } else {
                    Capsule().fill(role.background(focused: isFocused))
                }
            }
            .environment(\.focusLifted, isFocused)
            .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: 24, y: 14)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 1.0 : (isFocused ? 1.06 : 1)))
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.75), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The dark background of the picker and its screens, tinted with an avatar palette.
public struct ProfileBackdrop: View {
    public var accent: AvatarPalette?

    public init(accent: AvatarPalette? = nil) {
        self.accent = accent
    }

    public var body: some View {
        let tint = accent.map { Color($0.top) } ?? Color(red: 0.25, green: 0.3, blue: 0.5)
        let deep = accent.map { Color($0.bottom) } ?? Color(red: 0.12, green: 0.14, blue: 0.3)
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.06, blue: 0.1), Color(red: 0.08, green: 0.09, blue: 0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(colors: [tint.opacity(0.32), .clear], center: .top, startRadius: 0, endRadius: 1000)
            RadialGradient(colors: [deep.opacity(0.4), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 900)
        }
        .animation(.easeInOut(duration: 0.6), value: accent)
        .accessibilityHidden(true)
    }
}

/// Shakes a view sideways; each whole step of `animatableData` is one shake.
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 18
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * 6), y: 0))
    }
}

extension View {
    /// A full-screen cover on Apple TV, a sheet on the Mac (where the package only runs tests).
    @ViewBuilder
    func profileCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(macOS)
        sheet(item: item, content: content)
        #else
        fullScreenCover(item: item, content: content)
        #endif
    }

    /// Draws `ProfileBackdrop` behind the view when `isShown`, filling the screen past the
    /// safe area while the content stays inside it (clear of TV overscan).
    @ViewBuilder
    func profileBackdrop(_ isShown: Bool, accent: AvatarPalette?) -> some View {
        if isShown {
            background { ProfileBackdrop(accent: accent).ignoresSafeArea() }
        } else {
            self
        }
    }
}
