import Foundation

/// Everything `ProfileStore` persists, in one Codable value.
public struct ProfileArchive: Codable, Hashable, Sendable {
    /// The format version, for migrations.
    public var version: Int
    public var profiles: [Profile]
    /// The profile chosen last; the picker focuses it first.
    public var lastSelectedID: Profile.ID?

    public static let currentVersion = 1

    public init(profiles: [Profile] = [], lastSelectedID: Profile.ID? = nil) {
        version = Self.currentVersion
        self.profiles = profiles
        self.lastSelectedID = lastSelectedID
    }

    private enum CodingKeys: String, CodingKey {
        case version, profiles, lastSelectedID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        profiles = try container.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
        lastSelectedID = try container.decodeIfPresent(UUID.self, forKey: .lastSelectedID)
    }

    /// The JSON encoder the built-in storages use: ISO 8601 dates, sorted keys.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// The JSON decoder matching `makeEncoder()`.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// The archive as JSON.
    public func jsonData() throws -> Data {
        try Self.makeEncoder().encode(self)
    }

    /// An archive from JSON written by `jsonData()`.
    public init(jsonData: Data) throws {
        self = try Self.makeDecoder().decode(ProfileArchive.self, from: jsonData)
    }
}

/// Where `ProfileStore` keeps its archive. Conform your own type to sync profiles through
/// iCloud key-value storage or your backend.
public protocol ProfileStorage {
    /// The saved archive, or nil when nothing has been saved yet.
    func load() throws -> ProfileArchive?
    /// Saves the archive, replacing the previous one.
    func save(_ archive: ProfileArchive) throws
}

/// Keeps the archive as JSON in `UserDefaults`.
///
/// This is the right default on Apple TV: tvOS apps have no persistent Documents or Application
/// Support storage (the system may purge it), while user defaults persist. A few profiles take a
/// couple of kilobytes, far below the tvOS limit for user defaults.
public struct UserDefaultsProfileStorage: ProfileStorage {
    public let defaults: UserDefaults
    public let key: String

    public init(defaults: UserDefaults = .standard, key: String = "TVProfilePicker.profiles") {
        self.defaults = defaults
        self.key = key
    }

    public func load() throws -> ProfileArchive? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try ProfileArchive(jsonData: data)
    }

    public func save(_ archive: ProfileArchive) throws {
        defaults.set(try archive.jsonData(), forKey: key)
    }
}

/// Keeps the archive as a JSON file. On tvOS, files outside the caches directory are not
/// guaranteed to persist; prefer `UserDefaultsProfileStorage` there.
public struct FileProfileStorage: ProfileStorage {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> ProfileArchive? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try ProfileArchive(jsonData: Data(contentsOf: url))
    }

    public func save(_ archive: ProfileArchive) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try archive.jsonData().write(to: url, options: .atomic)
    }
}

/// Keeps the archive in memory only: for previews, tests and demos.
public final class InMemoryProfileStorage: ProfileStorage {
    public private(set) var archive: ProfileArchive?
    /// How many times `save(_:)` was called.
    public private(set) var saveCount = 0

    public init(archive: ProfileArchive? = nil) {
        self.archive = archive
    }

    public func load() throws -> ProfileArchive? {
        archive
    }

    public func save(_ archive: ProfileArchive) throws {
        self.archive = archive
        saveCount += 1
    }
}
