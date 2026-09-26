import Foundation

/// Co zachowujemy z metadanych zdjęcia źródłowego.
///
/// Zasada konstrukcyjna: metadane budujemy od zera i **dokładamy** to, na co polityka
/// pozwala — nigdy nie kopiujemy całości z wycinaniem wybranych kluczy. Przy podejściu
/// odwrotnym każdy nieznany producentowi klucz (Maker Notes, XMP, nowy tag Apple)
/// przeciekłby do pliku wyjściowego. Tu przeciec nie może.
public struct MetadataPolicy: Sendable, Codable, Equatable {
    /// Współrzędne GPS. Domyślnie usuwane — zdjęcie zwykle jedzie do kogoś obcego.
    public var keepLocation: Bool
    /// Data i godzina zrobienia zdjęcia.
    public var keepDateTime: Bool
    /// Producent, model, obiektyw, ISO, przysłona, czas naświetlania, ogniskowa.
    public var keepCameraInfo: Bool

    public init(keepLocation: Bool = false, keepDateTime: Bool = true, keepCameraInfo: Bool = true) {
        self.keepLocation = keepLocation
        self.keepDateTime = keepDateTime
        self.keepCameraInfo = keepCameraInfo
    }

    public static let `default` = MetadataPolicy()
    /// Goły obraz: żadnych metadanych poza orientacją i profilem kolorów.
    public static let stripAll = MetadataPolicy(keepLocation: false, keepDateTime: false, keepCameraInfo: false)
}
