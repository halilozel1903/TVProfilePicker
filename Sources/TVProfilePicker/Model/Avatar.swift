import Foundation

/// A generated avatar: the profile's initials or an SF Symbol, drawn over a two-color gradient.
///
/// Avatars are pure data (no images), so they are tiny to store, look sharp at any size and
/// never need a network request.
public struct Avatar: Codable, Hashable, Sendable {
    /// What is drawn on the gradient.
    public enum Content: Hashable, Sendable {
        /// The profile's initials, computed from its name (`Avatar.initials(from:)`).
        case initials
        /// An SF Symbol, by its system name, such as `"star.fill"`.
        case symbol(String)
    }

    public var content: Content
    public var palette: AvatarPalette

    public init(content: Content = .initials, palette: AvatarPalette) {
        self.content = content
        self.palette = palette
    }

    /// An initials avatar.
    public static func initials(_ palette: AvatarPalette) -> Avatar {
        Avatar(content: .initials, palette: palette)
    }

    /// A symbol avatar.
    public static func symbol(_ systemName: String, _ palette: AvatarPalette) -> Avatar {
        Avatar(content: .symbol(systemName), palette: palette)
    }

    /// An initials avatar whose palette is picked from the name, so new profiles get different
    /// colors without anyone choosing one. The same name always gets the same palette.
    public static func suggested(for name: String) -> Avatar {
        .initials(AvatarPalette.suggested(for: name))
    }

    /// Up to two letters for a name: the first letter of the first and of the last word.
    ///
    /// `"Alex"` gives `"A"`, `"Mary Jane Watson"` gives `"MW"`, `"émile zola"` gives `"ÉZ"`.
    /// Leading punctuation in a word is skipped. A name without letters or digits gives `"?"`.
    public static func initials(from name: String) -> String {
        let words = name
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { word in word.first(where: { $0.isLetter || $0.isNumber }) }
        guard let first = words.first else { return "?" }
        if words.count > 1, let last = words.last {
            return first.uppercased() + last.uppercased()
        }
        return first.uppercased()
    }

    /// A short spoken description, such as "Initials, Ocean" or "Star, Sunset".
    public var accessibilityDescription: String {
        let style: String
        switch content {
        case .initials: style = "Initials"
        case let .symbol(name): style = AvatarSymbol.named(name)?.name ?? "Symbol"
        }
        return style + ", " + palette.displayName
    }

    // MARK: Codable
    //
    // {"kind": "initials", "palette": "ocean"} or {"kind": "symbol", "symbol": "star.fill", "palette": "sunset"}.
    // Unknown kinds and palettes from a newer version decode as initials and the first palette.

    private enum CodingKeys: String, CodingKey {
        case kind, symbol, palette
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "initials"
        let symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        if kind == "symbol", let symbol, !symbol.isEmpty {
            content = .symbol(symbol)
        } else {
            content = .initials
        }
        let paletteName = try container.decodeIfPresent(String.self, forKey: .palette) ?? ""
        palette = AvatarPalette(rawValue: paletteName) ?? .ocean
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch content {
        case .initials:
            try container.encode("initials", forKey: .kind)
        case let .symbol(name):
            try container.encode("symbol", forKey: .kind)
            try container.encode(name, forKey: .symbol)
        }
        try container.encode(palette.rawValue, forKey: .palette)
    }
}

/// An sRGB color with components from 0 to 1.
public struct RGBColor: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// A color from a hex number such as `0x3A7BF2`.
    public init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    /// Relative luminance (WCAG 2), from 0 for black to 1 for white.
    public var luminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}

/// The gradients avatars are drawn with. Every palette is dark enough for white initials and
/// symbols to keep a contrast ratio of at least 3:1 (large text) at its lighter end.
public enum AvatarPalette: String, CaseIterable, Codable, Hashable, Sendable {
    case ocean, sunset, forest, grape, ember, lagoon, rose, gold, slate, aurora

    /// The gradient's top-leading color.
    public var top: RGBColor {
        switch self {
        case .ocean: RGBColor(hex: 0x3B82F6)
        case .sunset: RGBColor(hex: 0xE35D4C)
        case .forest: RGBColor(hex: 0x22A06B)
        case .grape: RGBColor(hex: 0x9F6BFF)
        case .ember: RGBColor(hex: 0xE0621E)
        case .lagoon: RGBColor(hex: 0x1397AB)
        case .rose: RGBColor(hex: 0xEC4F8E)
        case .gold: RGBColor(hex: 0xB07D0A)
        case .slate: RGBColor(hex: 0x64748B)
        case .aurora: RGBColor(hex: 0x0D9483)
        }
    }

    /// The gradient's bottom-trailing color.
    public var bottom: RGBColor {
        switch self {
        case .ocean: RGBColor(hex: 0x1E3A8A)
        case .sunset: RGBColor(hex: 0xA3245A)
        case .forest: RGBColor(hex: 0x0F5132)
        case .grape: RGBColor(hex: 0x4C1D95)
        case .ember: RGBColor(hex: 0x9A2A0E)
        case .lagoon: RGBColor(hex: 0x0E4F78)
        case .rose: RGBColor(hex: 0x7E1650)
        case .gold: RGBColor(hex: 0x8A4B08)
        case .slate: RGBColor(hex: 0x1F2937)
        case .aurora: RGBColor(hex: 0x4338CA)
        }
    }

    /// The name read by VoiceOver and shown in the avatar chooser.
    public var displayName: String {
        switch self {
        case .ocean: "Ocean"
        case .sunset: "Sunset"
        case .forest: "Forest"
        case .grape: "Grape"
        case .ember: "Ember"
        case .lagoon: "Lagoon"
        case .rose: "Rose"
        case .gold: "Gold"
        case .slate: "Slate"
        case .aurora: "Aurora"
        }
    }

    /// A palette picked from a name with a stable hash (FNV-1a over the lowercased, trimmed
    /// name), so it is the same on every device and every launch.
    public static func suggested(for name: String) -> AvatarPalette {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let all = AvatarPalette.allCases
        return all[Int(hash % UInt64(all.count))]
    }
}

/// An SF Symbol offered in the avatar chooser, with the name VoiceOver reads for it.
///
/// The set avoids emoji on purpose: symbols render consistently, scale cleanly on a 4K screen
/// and take the avatar's gradient and focus effects like the rest of the interface.
public struct AvatarSymbol: Hashable, Sendable, Identifiable {
    public let systemName: String
    public let name: String

    public var id: String { systemName }

    public init(systemName: String, name: String) {
        self.systemName = systemName
        self.name = name
    }

    /// The symbols the avatar chooser offers, all available on tvOS 17.
    public static let all: [AvatarSymbol] = [
        AvatarSymbol(systemName: "star.fill", name: "Star"),
        AvatarSymbol(systemName: "moon.stars.fill", name: "Moon and stars"),
        AvatarSymbol(systemName: "sun.max.fill", name: "Sun"),
        AvatarSymbol(systemName: "cloud.fill", name: "Cloud"),
        AvatarSymbol(systemName: "bolt.fill", name: "Lightning"),
        AvatarSymbol(systemName: "flame.fill", name: "Flame"),
        AvatarSymbol(systemName: "leaf.fill", name: "Leaf"),
        AvatarSymbol(systemName: "snowflake", name: "Snowflake"),
        AvatarSymbol(systemName: "pawprint.fill", name: "Paw print"),
        AvatarSymbol(systemName: "hare.fill", name: "Hare"),
        AvatarSymbol(systemName: "tortoise.fill", name: "Tortoise"),
        AvatarSymbol(systemName: "bird.fill", name: "Bird"),
        AvatarSymbol(systemName: "fish.fill", name: "Fish"),
        AvatarSymbol(systemName: "music.note", name: "Music"),
        AvatarSymbol(systemName: "headphones", name: "Headphones"),
        AvatarSymbol(systemName: "gamecontroller.fill", name: "Game controller"),
        AvatarSymbol(systemName: "film.fill", name: "Film"),
        AvatarSymbol(systemName: "paintpalette.fill", name: "Paint palette"),
        AvatarSymbol(systemName: "sparkles", name: "Sparkles"),
        AvatarSymbol(systemName: "crown.fill", name: "Crown"),
    ]

    /// The symbol with this system name, if it is one of `all`.
    public static func named(_ systemName: String) -> AvatarSymbol? {
        all.first { $0.systemName == systemName }
    }
}
