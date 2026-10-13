import Foundation

/// One person's profile on a shared Apple TV.
public struct Profile: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var avatar: Avatar
    /// Kids profiles get a Kids badge in the picker; your app decides what else changes.
    public var isKids: Bool
    /// When set, the picker asks for this PIN before opening the profile.
    public var pin: ProfilePIN?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        avatar: Avatar? = nil,
        isKids: Bool = false,
        pin: ProfilePIN? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.avatar = avatar ?? .suggested(for: name)
        self.isKids = isKids
        self.pin = pin
        self.createdAt = createdAt
    }

    /// Whether opening the profile asks for a PIN.
    public var isLocked: Bool { pin != nil }

    /// The initials an initials avatar shows.
    public var initials: String { Avatar.initials(from: name) }

    /// What VoiceOver reads for the profile's tile: "Riley, kids profile, locked with a PIN".
    public var accessibilitySummary: String {
        var parts = [name]
        if isKids { parts.append("kids profile") }
        if isLocked { parts.append("locked with a PIN") }
        return parts.joined(separator: ", ")
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, avatar, isKids, pin, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        avatar = try container.decodeIfPresent(Avatar.self, forKey: .avatar) ?? .suggested(for: name)
        isKids = try container.decodeIfPresent(Bool.self, forKey: .isKids) ?? false
        pin = try container.decodeIfPresent(ProfilePIN.self, forKey: .pin)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(avatar, forKey: .avatar)
        try container.encode(isKids, forKey: .isKids)
        try container.encodeIfPresent(pin, forKey: .pin)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

/// The editable fields of a profile, used by `ProfileEditorView` and `ProfileStore.save(_:for:)`.
public struct ProfileDraft: Hashable, Sendable {
    public var name: String
    public var avatar: Avatar
    public var isKids: Bool
    public var pin: ProfilePIN?

    public init(name: String = "", avatar: Avatar? = nil, isKids: Bool = false, pin: ProfilePIN? = nil) {
        self.name = name
        self.avatar = avatar ?? .suggested(for: name)
        self.isKids = isKids
        self.pin = pin
    }

    /// A draft holding a profile's current values.
    public init(_ profile: Profile) {
        name = profile.name
        avatar = profile.avatar
        isKids = profile.isKids
        pin = profile.pin
    }
}
