import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import PixportKit

/// Zdjęcie wejściowe oparte na zwykłym pliku na dysku.
///
/// Dzięki temu, że silnik nie zna `PhotoKit`, cały pakiet testuje się bez symulatora,
/// bez biblioteki zdjęć i bez uprawnień — w sekundy, nie minuty.
struct FilePhoto: SourcePhoto {
    let id: String
    let creationDate: Date?
    let originalFileName: String?
    let pixelWidth: Int
    let pixelHeight: Int
    let byteCount: Int64
    let fileURL: URL
    var available = true

    func isAvailableLocally() async -> Bool { available }

    func materialize(at url: URL, progress: @Sendable @escaping (Double) -> Void) async throws {
        progress(0)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: fileURL, to: url)
        progress(1)
    }
}

enum Fixtures {

    static func makeDirectory(_ name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PixportTests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Zapisuje syntetyczne zdjęcie JPEG z pełnym kompletem metadanych:
    /// współrzędnymi GPS, datą, producentem i parametrami ekspozycji.
    @discardableResult
    static func writeJPEG(
        at url: URL,
        width: Int = 800,
        height: Int = 600,
        withGPS: Bool = true
    ) throws -> URL {
        let image = try makeImage(width: width, height: height)

        var gps: [String: Any] = [:]
        if withGPS {
            gps = [
                kCGImagePropertyGPSLatitude as String: 52.2297,
                kCGImagePropertyGPSLatitudeRef as String: "N",
                kCGImagePropertyGPSLongitude as String: 21.0122,
                kCGImagePropertyGPSLongitudeRef as String: "E",
                kCGImagePropertyGPSAltitude as String: 113.0
            ]
        }

        var properties: [String: Any] = [
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifDateTimeOriginal as String: "2026:09:21 14:31:02",
                kCGImagePropertyExifDateTimeDigitized as String: "2026:09:21 14:31:02",
                kCGImagePropertyExifISOSpeedRatings as String: [100],
                kCGImagePropertyExifFNumber as String: 1.78,
                kCGImagePropertyExifLensModel as String: "iPhone 15 Pro back camera"
            ],
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFMake as String: "Apple",
                kCGImagePropertyTIFFModel as String: "iPhone 15 Pro",
                kCGImagePropertyTIFFDateTime as String: "2026:09:21 14:31:02"
            ],
            kCGImagePropertyIPTCDictionary as String: [
                kCGImagePropertyIPTCKeywords as String: ["prywatne", "dom"],
                kCGImagePropertyIPTCByline as String: ["Jan Kowalski"]
            ]
        ]
        if !gps.isEmpty {
            properties[kCGImagePropertyGPSDictionary as String] = gps
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    static func makeImage(width: Int, height: Int) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { throw CocoaError(.fileWriteUnknown) }

        // Szum, a nie jednolity kolor: gładka płaszczyzna kompresuje się do kilku
        // kilobajtów niezależnie od ustawień, więc testy jakości i budżetu nic by nie mierzyły.
        var generator = SystemRandomNumberGenerator()
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                context.setFillColor(
                    red: Double(UInt8.random(in: 0...255, using: &generator)) / 255,
                    green: Double(UInt8.random(in: 0...255, using: &generator)) / 255,
                    blue: Double(UInt8.random(in: 0...255, using: &generator)) / 255,
                    alpha: 1
                )
                context.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
        guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        return image
    }

    /// Zestaw zdjęć na dysku, z datami rosnącymi co minutę.
    static func photos(count: Int, in directory: URL, width: Int = 800, height: Int = 600, withGPS: Bool = true) throws -> [FilePhoto] {
        try (0..<count).map { index in
            let name = String(format: "IMG_%04d.jpg", index + 1)
            let url = directory.appendingPathComponent(name)
            try writeJPEG(at: url, width: width, height: height, withGPS: withGPS)
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            return FilePhoto(
                id: "asset-\(index)",
                creationDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(index * 60)),
                originalFileName: name,
                pixelWidth: width,
                pixelHeight: height,
                byteCount: size,
                fileURL: url
            )
        }
    }

    static func properties(of url: URL) -> [String: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return [:] }
        return props
    }
}
