import Foundation

/// Zdjęcie wejściowe widziane oczami silnika.
///
/// Celowo nie wie nic o `PhotoKit` — dzięki temu cały pakiet testuje się zwykłymi
/// plikami na dysku, bez symulatora i bez biblioteki zdjęć.
public protocol SourcePhoto: Sendable {
    /// Stabilny identyfikator (w aplikacji: `PHAsset.localIdentifier`).
    var id: String { get }
    /// Data zrobienia zdjęcia. Wyznacza kolejność numerowania.
    var creationDate: Date? { get }
    /// Oryginalna nazwa pliku, np. `IMG_1234.HEIC`.
    var originalFileName: String? { get }
    var pixelWidth: Int { get }
    var pixelHeight: Int { get }
    /// Rozmiar oryginału w bajtach — do podsumowania „47 zdjęć · 182 MB".
    var byteCount: Int64 { get }

    /// Czy plik leży fizycznie na urządzeniu.
    ///
    /// Przy włączonej optymalizacji pamięci oryginał bywa wyłącznie w iCloud,
    /// a lokalnie jest sama miniatura.
    func isAvailableLocally() async -> Bool

    /// Kładzie oryginał na dysku pod wskazaną ścieżką, w razie potrzeby pobierając
    /// go z iCloud. To jedyne miejsce w całej aplikacji, które dotyka sieci.
    func materialize(at url: URL, progress: @Sendable @escaping (Double) -> Void) async throws
}

/// Wynik przetworzenia jednego zdjęcia.
public struct ProcessedFile: Sendable, Equatable {
    public let sourceID: String
    public let url: URL
    public let fileName: String
    public let byteCount: Int64
    public let originalByteCount: Int64

    public init(sourceID: String, url: URL, fileName: String, byteCount: Int64, originalByteCount: Int64) {
        self.sourceID = sourceID
        self.url = url
        self.fileName = fileName
        self.byteCount = byteCount
        self.originalByteCount = originalByteCount
    }
}

/// Komplet wyniku jednego przebiegu.
public struct ConversionResult: Sendable {
    public let files: [ProcessedFile]
    /// Archiwa ZIP, jeśli użytkownik je zamówił. Puste, gdy pakowanie wyłączone.
    public let archives: [ProcessedFile]
    public let originalByteCount: Int64
    public let producedByteCount: Int64
    /// Ile przebiegów kodowania kosztowało zmieszczenie się w limicie.
    public let budgetPasses: Int
    /// Ustawienia faktycznie użyte — mogą się różnić od zamówionych, jeśli
    /// działał tryb „zmieść w X MB".
    public let effectiveSettings: ConversionSettings

    public init(
        files: [ProcessedFile],
        archives: [ProcessedFile],
        originalByteCount: Int64,
        producedByteCount: Int64,
        budgetPasses: Int,
        effectiveSettings: ConversionSettings
    ) {
        self.files = files
        self.archives = archives
        self.originalByteCount = originalByteCount
        self.producedByteCount = producedByteCount
        self.budgetPasses = budgetPasses
        self.effectiveSettings = effectiveSettings
    }

    /// Pliki, które trafiają do udostępniania: archiwa, jeśli powstały, inaczej zdjęcia.
    public var shareableFiles: [ProcessedFile] {
        archives.isEmpty ? files : archives
    }

    public var savedRatio: Double {
        guard originalByteCount > 0 else { return 0 }
        return 1.0 - Double(producedByteCount) / Double(originalByteCount)
    }
}
