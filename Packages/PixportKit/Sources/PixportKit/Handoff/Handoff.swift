import Foundation

/// Stałe konfiguracyjne współdzielone przez aplikację i rozszerzenie.
public enum PixportConfig {
    public static let appGroupID = "group.pl.froncek.pixport"
    public static let urlScheme = "pixport"

    /// Powyżej tylu zdjęć rozszerzenie oddaje robotę aplikacji.
    ///
    /// Rozszerzenia mają wielokrotnie niższy limit pamięci niż aplikacja — rzędu
    /// stu kilkudziesięciu megabajtów. Przy skalowaniu przez `ImageIO` pojedyncze
    /// zdjęcie mieści się w tym z zapasem, ale przy dużej paczce margines błędu
    /// robi się cienki, a ubite rozszerzenie wygląda dla użytkownika jak zniknięcie
    /// okienka bez słowa wyjaśnienia.
    public static let extensionPhotoLimit = 20
}

/// Opis jednego zdjęcia przekazanego z rozszerzenia do aplikacji.
public struct HandoffItem: Codable, Sendable {
    public let fileName: String
    public let originalFileName: String?
    public let creationDate: Date?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let byteCount: Int64

    public init(
        fileName: String,
        originalFileName: String?,
        creationDate: Date?,
        pixelWidth: Int,
        pixelHeight: Int,
        byteCount: Int64
    ) {
        self.fileName = fileName
        self.originalFileName = originalFileName
        self.creationDate = creationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteCount = byteCount
    }
}

public struct HandoffManifest: Codable, Sendable {
    public let sessionID: String
    public let items: [HandoffItem]

    public init(sessionID: String, items: [HandoffItem]) {
        self.sessionID = sessionID
        self.items = items
    }
}

/// Przekazywanie zaznaczenia z rozszerzenia udostępniania do aplikacji.
///
/// Rozszerzenie dostaje pliki jako `NSItemProvider` i musi je skopiować do wspólnego
/// kontenera App Group — inaczej aplikacja ich nie przeczyta. To realny koszt
/// (przy dwustu zdjęciach kilkaset megabajtów kopiowania) i właśnie dlatego małe paczki
/// rozszerzenie obsługuje samodzielnie, bez przeskakiwania do aplikacji.
public enum HandoffStore {

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PixportConfig.appGroupID)
    }

    public static func sessionDirectory(_ sessionID: String) -> URL? {
        containerURL?
            .appendingPathComponent("Handoff", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
    }

    public static func createSession() throws -> (id: String, directory: URL) {
        let id = UUID().uuidString
        guard let directory = sessionDirectory(id) else {
            throw ConversionError.cannotWriteOutput(underlying: "App Group")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (id, directory)
    }

    public static func write(_ manifest: HandoffManifest) throws {
        guard let directory = sessionDirectory(manifest.sessionID) else {
            throw ConversionError.cannotWriteOutput(underlying: "App Group")
        }
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"))
    }

    public static func read(sessionID: String) -> HandoffManifest? {
        guard let directory = sessionDirectory(sessionID),
              let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        else { return nil }
        return try? JSONDecoder().decode(HandoffManifest.self, from: data)
    }

    public static func photos(for manifest: HandoffManifest) -> [any SourcePhoto] {
        guard let directory = sessionDirectory(manifest.sessionID) else { return [] }
        return manifest.items.map { item in
            HandoffPhoto(item: item, fileURL: directory.appendingPathComponent(item.fileName))
        }
    }

    /// Usuwa wszystkie przekazane paczki poza wskazaną.
    ///
    /// Wołane przy starcie aplikacji: kontener App Group nie jest sprzątany przez system
    /// tak jak `tmp/`, więc porzucone przekazania zostawałyby tam na zawsze.
    public static func cleanUp(keeping sessionID: String? = nil) {
        guard let root = containerURL?.appendingPathComponent("Handoff", isDirectory: true),
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
              )
        else { return }
        for url in contents where url.lastPathComponent != sessionID {
            try? FileManager.default.removeItem(at: url)
        }
    }

    public static func handoffURL(sessionID: String) -> URL? {
        URL(string: "\(PixportConfig.urlScheme)://handoff?session=\(sessionID)")
    }

    public static func sessionID(from url: URL) -> String? {
        guard url.scheme == PixportConfig.urlScheme,
              url.host == "handoff",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        return components.queryItems?.first { $0.name == "session" }?.value
    }
}

/// Zdjęcie przekazane z rozszerzenia — zwykły plik w kontenerze App Group.
public struct HandoffPhoto: SourcePhoto {
    public let item: HandoffItem
    public let fileURL: URL

    public init(item: HandoffItem, fileURL: URL) {
        self.item = item
        self.fileURL = fileURL
    }

    public var id: String { item.fileName }
    public var creationDate: Date? { item.creationDate }
    public var originalFileName: String? { item.originalFileName }
    public var pixelWidth: Int { item.pixelWidth }
    public var pixelHeight: Int { item.pixelHeight }
    public var byteCount: Int64 { item.byteCount }

    public func isAvailableLocally() async -> Bool {
        // Plik jest już skopiowany do wspólnego kontenera — nie ma czego pobierać.
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    public func materialize(at url: URL, progress: @Sendable @escaping (Double) -> Void) async throws {
        progress(0)
        try? FileManager.default.removeItem(at: url)
        do {
            try FileManager.default.copyItem(at: fileURL, to: url)
        } catch {
            throw ConversionError.cannotReadSource(fileName: originalFileName ?? id)
        }
        progress(1)
    }
}
