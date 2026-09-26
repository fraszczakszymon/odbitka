import Foundation

/// Katalog roboczy jednego przebiegu.
///
/// Wszystko ląduje w `tmp/`, nie w `Documents/`. Powody są dwa: system może to
/// posprzątać sam przy niedoborze miejsca, a przetworzone duplikaty nie zżerają
/// kopii zapasowej iCloud użytkownika. Pliki żyją do końca sesji — tyle, żeby dało się
/// wrócić na ekran wyniku, dokończyć wysyłkę porcjami albo zapisać je do Plików.
public struct Workspace: Sendable {
    public let sessionID: String
    public let sourcesDirectory: URL
    public let outputDirectory: URL

    public static var rootDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Pixport", isDirectory: true)
    }

    public init(sessionID: String = UUID().uuidString) throws {
        self.sessionID = sessionID
        let session = Self.rootDirectory.appendingPathComponent(sessionID, isDirectory: true)
        self.sourcesDirectory = session.appendingPathComponent("zrodla", isDirectory: true)
        self.outputDirectory = session.appendingPathComponent("wynik", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            throw ConversionError.cannotWriteOutput(underlying: error.localizedDescription)
        }
    }

    public var sessionDirectory: URL {
        Self.rootDirectory.appendingPathComponent(sessionID, isDirectory: true)
    }

    /// Kasuje wyniki częściowe. Wołane, gdy przebieg się nie powiódł albo został przerwany —
    /// semantyka aplikacji to „wszystko albo nic", więc połowa paczki nie ma prawa przetrwać.
    public func discardOutputs() {
        try? FileManager.default.removeItem(at: outputDirectory)
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    /// Zwalnia oryginały ściągnięte na czas przetwarzania.
    public func discardSources() {
        try? FileManager.default.removeItem(at: sourcesDirectory)
        try? FileManager.default.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)
    }

    public func destroy() {
        try? FileManager.default.removeItem(at: sessionDirectory)
    }

    // MARK: - Sprzątanie globalne

    /// Usuwa pozostałości po poprzednich uruchomieniach.
    ///
    /// Wołane przy starcie aplikacji, cicho i bez pytania — użytkownik nie ma powodu
    /// wiedzieć o istnieniu katalogu tymczasowego, a apka zjadająca kilka gigabajtów
    /// między uruchomieniami to klasyk jednogwiazdkowych recenzji.
    public static func cleanUpPreviousSessions(keeping sessionID: String? = nil) {
        let manager = FileManager.default
        guard let contents = try? manager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in contents where url.lastPathComponent != sessionID {
            try? manager.removeItem(at: url)
        }
    }

    /// Ile miejsca zajmują pliki robocze — pokazywane w ustawieniach aplikacji.
    public static func occupiedBytes() -> Int64 {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    /// Miejsce, które system jest gotów oddać na dane użytkownika.
    ///
    /// `volumeAvailableCapacityForImportantUsage` to jedyna sensowna miara na iOS —
    /// zwykłe „wolne miejsce" ignoruje pamięć, którą system odda po usunięciu danych
    /// odtwarzalnych, i potrafi zaniżyć wynik o gigabajty.
    public static func availableBytes() -> Int64 {
        let values = try? rootDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
