import Foundation
import ImageIO
import Testing
@testable import OdbitkaKit

/// Najważniejszy zestaw testów w całym projekcie.
///
/// Błąd w usuwaniu lokalizacji jest niewidoczny: zdjęcie wygląda tak samo, paczka waży
/// tyle samo, aplikacja niczego nie zgłasza — a użytkownik wysyła obcej osobie
/// współrzędne swojego mieszkania. To jedyna klasa błędów w tej aplikacji, której
/// nie da się zauważyć przez używanie jej.
@Suite("Metadane")
struct MetadataTests {

    @Test("Domyślnie lokalizacja znika z pliku wynikowego")
    func stripsLocationByDefault() throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try Fixtures.writeJPEG(at: directory.appendingPathComponent("in.jpg"), withGPS: true)
        #expect(Fixtures.properties(of: source)[kCGImagePropertyGPSDictionary as String] != nil,
                "Plik źródłowy musi mieć GPS, inaczej test niczego nie dowodzi")

        let output = directory.appendingPathComponent("out.jpg")
        try ImageConverter.convert(
            sourceURL: source, destinationURL: output,
            settings: .default, quality: 0.85, displayName: "in.jpg"
        )

        let props = Fixtures.properties(of: output)
        #expect(props[kCGImagePropertyGPSDictionary as String] == nil)
    }

    @Test("Lokalizacja zostaje, gdy użytkownik o to poprosi")
    func keepsLocationWhenAsked() throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try Fixtures.writeJPEG(at: directory.appendingPathComponent("in.jpg"), withGPS: true)
        var settings = ConversionSettings.default
        settings.metadata.keepLocation = true

        let output = directory.appendingPathComponent("out.jpg")
        try ImageConverter.convert(
            sourceURL: source, destinationURL: output,
            settings: settings, quality: 0.85, displayName: "in.jpg"
        )

        let gps = Fixtures.properties(of: output)[kCGImagePropertyGPSDictionary as String] as? [String: Any]
        #expect(gps != nil)
        #expect(gps?[kCGImagePropertyGPSLatitude as String] as? Double != nil)
    }

    @Test("Opisy IPTC nie przechodzą nigdy, niezależnie od ustawień")
    func alwaysStripsIPTC() throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try Fixtures.writeJPEG(at: directory.appendingPathComponent("in.jpg"))
        #expect(Fixtures.properties(of: source)[kCGImagePropertyIPTCDictionary as String] != nil)

        var settings = ConversionSettings.default
        settings.metadata = MetadataPolicy(keepLocation: true, keepDateTime: true, keepCameraInfo: true)

        let output = directory.appendingPathComponent("out.jpg")
        try ImageConverter.convert(
            sourceURL: source, destinationURL: output,
            settings: settings, quality: 0.9, displayName: "in.jpg"
        )

        // Nazwisko autora i słowa kluczowe to dane osobowe, których odbiorca paczki
        // ze zdjęciami łazienki nie ma powodu dostać.
        #expect(Fixtures.properties(of: output)[kCGImagePropertyIPTCDictionary as String] == nil)
    }

    @Test("Wyłączenie daty i aparatu zostawia goły obraz")
    func stripsEverything() throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try Fixtures.writeJPEG(at: directory.appendingPathComponent("in.jpg"))
        var settings = ConversionSettings.default
        settings.metadata = .stripAll

        let output = directory.appendingPathComponent("out.jpg")
        try ImageConverter.convert(
            sourceURL: source, destinationURL: output,
            settings: settings, quality: 0.85, displayName: "in.jpg"
        )

        let props = Fixtures.properties(of: output)
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]

        #expect(props[kCGImagePropertyGPSDictionary as String] == nil)
        #expect(exif[kCGImagePropertyExifDateTimeOriginal as String] == nil)
        #expect(tiff[kCGImagePropertyTIFFMake as String] == nil)
        #expect(tiff[kCGImagePropertyTIFFModel as String] == nil)
    }

    @Test("Data i sprzęt zachowują się niezależnie od siebie")
    func dateAndCameraAreIndependent() throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try Fixtures.writeJPEG(at: directory.appendingPathComponent("in.jpg"))

        var settings = ConversionSettings.default
        settings.metadata = MetadataPolicy(keepLocation: false, keepDateTime: true, keepCameraInfo: false)

        let output = directory.appendingPathComponent("out.jpg")
        try ImageConverter.convert(
            sourceURL: source, destinationURL: output,
            settings: settings, quality: 0.85, displayName: "in.jpg"
        )

        let props = Fixtures.properties(of: output)
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]

        #expect(exif[kCGImagePropertyExifDateTimeOriginal as String] != nil)
        #expect(exif[kCGImagePropertyExifLensModel as String] == nil)
        #expect(tiff[kCGImagePropertyTIFFModel as String] == nil)
    }

    @Test("Orientacja w pliku wynikowym jest zawsze neutralna")
    func orientationIsNormalised() throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try Fixtures.writeJPEG(at: directory.appendingPathComponent("in.jpg"))

        let output = directory.appendingPathComponent("out.jpg")
        try ImageConverter.convert(
            sourceURL: source, destinationURL: output,
            settings: .default, quality: 0.85, displayName: "in.jpg"
        )

        // Obrót jest wpalony w piksele, więc tag musi mówić „nie obracaj" —
        // inaczej przeglądarka obróciłaby zdjęcie drugi raz.
        let orientation = Fixtures.properties(of: output)[kCGImagePropertyOrientation as String] as? Int
        #expect(orientation == nil || orientation == 1)
    }
}
