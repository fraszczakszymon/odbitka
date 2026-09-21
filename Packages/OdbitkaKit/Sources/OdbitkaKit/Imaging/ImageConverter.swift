import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Konwersja pojedynczego pliku obrazu.
///
/// Cała ścieżka jest synchroniczna i bezstanowa — wołana z wnętrza jednego zadania,
/// nigdy nie przekracza granicy współbieżności. Dzięki temu słowniki `CFDictionary`
/// (z natury nie-`Sendable`) nie muszą nigdzie podróżować.
public enum ImageConverter {

    /// Przetwarza jeden plik i zwraca rozmiar wyniku w bajtach.
    ///
    /// - Note: Skalowanie idzie przez `CGImageSourceCreateThumbnailAtIndex`, a nie przez
    ///   wczytanie pełnego obrazu i przeskalowanie go. Różnica jest zasadnicza:
    ///   zdjęcie 48 Mpx nigdy nie materializuje się w pamięci jako ~190 MB bitmapy,
    ///   bo dekoder od razu produkuje obraz w docelowym rozmiarze. Bez tego aplikacja
    ///   ginie od systemowego zabójcy pamięci przy kilku RAW-ach z rzędu — a w rozszerzeniu
    ///   udostępniania, z limitem rzędu 120 MB, przy pierwszym.
    @discardableResult
    public static func convert(
        sourceURL: URL,
        destinationURL: URL,
        settings: ConversionSettings,
        quality: Double,
        displayName: String
    ) throws -> Int64 {
        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0
        else {
            throw ConversionError.cannotReadSource(fileName: displayName)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] ?? [:]
        let sourceWidth = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let sourceHeight = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        let sourceLongEdge = max(sourceWidth, sourceHeight)

        // Nigdy nie powiększamy. Wybranie 2560 px dla zdjęcia o boku 1200 px nie ma
        // dodać pikseli, których nie ma — dałoby większy plik bez grama więcej treści.
        let requested = settings.targetSize.pixels ?? sourceLongEdge
        let maxPixelSize = sourceLongEdge > 0 ? min(requested, sourceLongEdge) : requested

        let thumbnailOptions: [String: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceCreateThumbnailWithTransform as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: max(maxPixelSize, 1),
            kCGImageSourceShouldCacheImmediately as String: true
        ]

        guard var image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions as CFDictionary) else {
            throw ConversionError.unsupportedSource(fileName: displayName)
        }

        if settings.convertToSRGB, let converted = redrawInSRGB(image, format: settings.format) {
            image = converted
        }

        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            settings.format.utType.identifier as CFString,
            1,
            nil
        ) else {
            throw ConversionError.cannotWriteOutput(underlying: destinationURL.lastPathComponent)
        }

        let destinationProperties = MetadataSanitizer.destinationProperties(
            source: properties,
            policy: settings.metadata,
            format: settings.format,
            quality: quality
        )

        CGImageDestinationAddImage(destination, image, destinationProperties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.encodingFailed(fileName: displayName)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Przerysowuje obraz w przestrzeni sRGB.
    ///
    /// iPhone fotografuje w Display P3. Programy, które ignorują profil ICC — a to
    /// większość świata poza Apple — potraktują te liczby jak sRGB i pokażą zdjęcie
    /// przesycone, z „neonowymi" kolorami. Konwersja kosztuje lekkie przycięcie
    /// najbardziej nasyconych barw i jest tego warta wszędzie poza trybem „Oryginał".
    private static func redrawInSRGB(_ image: CGImage, format: ImageFormat) -> CGImage? {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        if let existing = image.colorSpace, existing.name == CGColorSpace.sRGB { return image }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        // JPEG nie ma kanału alfa; PNG bywa zrzutem ekranu z przezroczystością.
        let alphaInfo: CGImageAlphaInfo = format == .png ? .premultipliedLast : .noneSkipLast

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sRGB,
            bitmapInfo: alphaInfo.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
