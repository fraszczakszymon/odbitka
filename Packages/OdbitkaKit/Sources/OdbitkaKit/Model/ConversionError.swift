import Foundation

/// Błędy silnika.
///
/// Semantyka całej aplikacji to „wszystko albo nic": pierwszy błąd przerywa przebieg,
/// a wyniki częściowe są kasowane. Dlatego komunikaty muszą być na tyle konkretne,
/// żeby użytkownik wiedział, co poprawić — ogólne „coś poszło nie tak" kosztowałoby go
/// całą paczkę bez wskazówki.
public enum ConversionError: Error, Sendable, Equatable {
    /// Kontrola wstępna: część zdjęć siedzi w iCloud, a sieci nie ma.
    case photosNotAvailableOffline(count: Int)
    /// Kontrola wstępna: na dysku zabraknie miejsca.
    case insufficientDiskSpace(required: Int64, available: Int64)
    case cannotReadSource(fileName: String)
    case unsupportedSource(fileName: String)
    case encodingFailed(fileName: String)
    case cannotWriteOutput(underlying: String)
    /// Tryb „zmieść w X MB" nie zbiegł się mimo zejścia do dolnych granic.
    case budgetUnreachable(target: Int64, best: Int64)
    /// Podział na części: pojedynczy plik jest większy niż limit części.
    case fileLargerThanPart(fileName: String, fileSize: Int64, partLimit: Int64)
    case cancelled
}
