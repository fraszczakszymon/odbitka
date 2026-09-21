import Foundation
import ImageIO

/// Buduje słownik metadanych pliku wynikowego.
///
/// **Reguła nadrzędna: budujemy od zera.** Zaczynamy od pustego słownika i dokładamy
/// wyłącznie te klucze, na które polityka użytkownika pozwala. Nigdy nie kopiujemy
/// metadanych źródła z wycinaniem wybranych pól — przy takim podejściu każdy klucz,
/// o którym nie pomyśleliśmy (Maker Notes Apple, XMP, tagi trybu portretowego,
/// cokolwiek dojdzie w przyszłym iOS), przeciekłby do pliku wysłanego obcej osobie.
///
/// Konsekwencja: dopisanie nowego pola do zachowania wymaga świadomej zmiany tutaj.
/// To jest zamierzone.
public enum MetadataSanitizer {

    /// Klucze EXIF opisujące moment zrobienia zdjęcia.
    private static let dateTimeExifKeys: [String] = [
        kCGImagePropertyExifDateTimeOriginal as String,
        kCGImagePropertyExifDateTimeDigitized as String,
        kCGImagePropertyExifOffsetTimeOriginal as String,
        kCGImagePropertyExifSubsecTimeOriginal as String
    ]

    /// Klucze EXIF opisujące sprzęt i parametry ekspozycji.
    private static let cameraExifKeys: [String] = [
        kCGImagePropertyExifISOSpeedRatings as String,
        kCGImagePropertyExifFNumber as String,
        kCGImagePropertyExifExposureTime as String,
        kCGImagePropertyExifFocalLength as String,
        kCGImagePropertyExifFocalLenIn35mmFilm as String,
        kCGImagePropertyExifLensMake as String,
        kCGImagePropertyExifLensModel as String,
        kCGImagePropertyExifExposureBiasValue as String,
        kCGImagePropertyExifMeteringMode as String,
        kCGImagePropertyExifFlash as String
    ]

    /// Klucze TIFF opisujące sprzęt.
    private static let cameraTIFFKeys: [String] = [
        kCGImagePropertyTIFFMake as String,
        kCGImagePropertyTIFFModel as String
    ]

    /// Składa metadane pliku wynikowego.
    ///
    /// - Parameters:
    ///   - source: metadane odczytane z oryginału (`CGImageSourceCopyPropertiesAtIndex`).
    ///   - policy: co użytkownik kazał zachować.
    ///   - format: format docelowy — decyduje, czy jakość ma sens.
    ///   - quality: 0.0 – 1.0, ignorowane dla PNG.
    public static func destinationProperties(
        source: [String: Any],
        policy: MetadataPolicy,
        format: ImageFormat,
        quality: Double
    ) -> [String: Any] {
        var result: [String: Any] = [:]

        // Orientacja zawsze 1 („góra-lewo"). Obrót jest już wpalony w piksele przez
        // kCGImageSourceCreateThumbnailWithTransform, więc pozostawienie tagu z oryginału
        // obróciłoby zdjęcie drugi raz.
        result[kCGImagePropertyOrientation as String] = 1

        if format.supportsQuality {
            result[kCGImageDestinationLossyCompressionQuality as String] = quality
        }

        let sourceExif = source[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let sourceTIFF = source[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]

        var exif: [String: Any] = [:]
        var tiff: [String: Any] = [:]

        if policy.keepDateTime {
            for key in dateTimeExifKeys {
                if let value = sourceExif[key] { exif[key] = value }
            }
            if let value = sourceTIFF[kCGImagePropertyTIFFDateTime as String] {
                tiff[kCGImagePropertyTIFFDateTime as String] = value
            }
        }

        if policy.keepCameraInfo {
            for key in cameraExifKeys {
                if let value = sourceExif[key] { exif[key] = value }
            }
            for key in cameraTIFFKeys {
                if let value = sourceTIFF[key] { tiff[key] = value }
            }
        }

        if policy.keepLocation, let gps = source[kCGImagePropertyGPSDictionary as String] as? [String: Any], !gps.isEmpty {
            // Cały słownik GPS to z definicji dane lokalizacyjne, a użytkownik właśnie
            // świadomie zdecydował, że chce je zachować.
            result[kCGImagePropertyGPSDictionary as String] = gps
        }

        if !exif.isEmpty { result[kCGImagePropertyExifDictionary as String] = exif }
        if !tiff.isEmpty { result[kCGImagePropertyTIFFDictionary as String] = tiff }

        return result
    }
}
