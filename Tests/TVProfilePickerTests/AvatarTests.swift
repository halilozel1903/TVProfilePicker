import Foundation
import Testing
@testable import TVProfilePicker

@Suite("Avatars")
struct AvatarTests {
    @Test("Initials use the first letter of the first and last word", arguments: [
        ("Alex", "A"),
        ("Mary Jane Watson", "MW"),
        ("sam rivera", "SR"),
        ("émile zola", "ÉZ"),
        ("  Jordan   ", "J"),
        ("(Demo) Riley", "DR"),
        ("Player 2", "P2"),
        ("", "?"),
        ("   ", "?"),
        ("!!!", "?"),
    ])
    func initials(name: String, expected: String) {
        #expect(Avatar.initials(from: name) == expected)
    }

    @Test("The suggested palette is stable and ignores case and spaces")
    func suggestedPalette() {
        let palette = AvatarPalette.suggested(for: "Casey")
        #expect(AvatarPalette.suggested(for: "Casey") == palette)
        #expect(AvatarPalette.suggested(for: "  casey ") == palette)
        #expect(Avatar.suggested(for: "Casey") == Avatar.initials(palette))
    }

    @Test("Different names spread over several palettes")
    func paletteSpread() {
        let names = ["Alex", "Sam", "Jordan", "Riley", "Casey", "Morgan", "Taylor", "Jamie", "Quinn", "Avery"]
        let palettes = Set(names.map { AvatarPalette.suggested(for: $0) })
        #expect(palettes.count >= 4)
    }

    @Test("White content keeps at least 3:1 contrast on every palette's lighter end")
    func contrast() {
        for palette in AvatarPalette.allCases {
            for color in [palette.top, palette.bottom] {
                let ratio = 1.05 / (color.luminance + 0.05)
                #expect(ratio >= 3.0, "\(palette.rawValue) is too light for white text (\(ratio))")
            }
        }
    }

    @Test("Hex colors convert to components")
    func hexColor() {
        let color = RGBColor(hex: 0xFF8000)
        #expect(color.red == 1.0)
        #expect(abs(color.green - 128.0 / 255.0) < 0.000_001)
        #expect(color.blue == 0.0)
    }

    @Test("Avatars round-trip through JSON")
    func codable() throws {
        let avatars: [Avatar] = [.initials(.ocean), .symbol("star.fill", .sunset), .symbol("crown.fill", .gold)]
        let data = try JSONEncoder().encode(avatars)
        let decoded = try JSONDecoder().decode([Avatar].self, from: data)
        #expect(decoded == avatars)
    }

    @Test("The JSON format is readable")
    func jsonShape() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(Avatar.symbol("leaf.fill", .forest)), as: UTF8.self)
        #expect(json == #"{"kind":"symbol","palette":"forest","symbol":"leaf.fill"}"#)
    }

    @Test("Unknown kinds and palettes from a newer version still decode")
    func forwardCompatible() throws {
        let json = Data(#"{"kind":"photo","palette":"neon","url":"https://example.com/a.png"}"#.utf8)
        let avatar = try JSONDecoder().decode(Avatar.self, from: json)
        #expect(avatar == .initials(.ocean))
    }

    @Test("Every offered symbol has a unique name and a spoken label")
    func symbols() {
        let names = AvatarSymbol.all.map(\.systemName)
        #expect(Set(names).count == names.count)
        #expect(AvatarSymbol.all.allSatisfy { !$0.name.isEmpty })
        #expect(AvatarSymbol.named("star.fill")?.name == "Star")
        #expect(AvatarSymbol.named("not.a.symbol") == nil)
    }

    @Test("Avatars describe themselves for VoiceOver")
    func accessibility() {
        #expect(Avatar.initials(.ocean).accessibilityDescription == "Initials, Ocean")
        #expect(Avatar.symbol("pawprint.fill", .grape).accessibilityDescription == "Paw print, Grape")
        #expect(Avatar.symbol("custom.symbol", .slate).accessibilityDescription == "Symbol, Slate")
    }
}
