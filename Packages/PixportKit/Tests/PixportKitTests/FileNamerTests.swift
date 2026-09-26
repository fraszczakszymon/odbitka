import Foundation
import Testing
@testable import PixportKit

@Suite("Nazewnictwo plików")
struct FileNamerTests {

    @Test("Normalizacja usuwa polskie znaki")
    func normalizesPolishCharacters() {
        #expect(FileNamer.normalize("Łazienka") == "Lazienka")
        #expect(FileNamer.normalize("Zażółć gęślą jaźń") == "Zazolc_gesla_jazn")
        #expect(FileNamer.normalize("Poddasze — remont") == "Poddasze_remont")
    }

    @Test("Normalizacja radzi sobie z innymi alfabetami łacińskimi")
    func normalizesOtherLatinAlphabets() {
        #expect(FileNamer.normalize("Küche") == "Kuche")
        #expect(FileNamer.normalize("Café") == "Cafe")
        #expect(FileNamer.normalize("Straße") == "Strasse")
        #expect(FileNamer.normalize("Ærø") == "AEro")
    }

    @Test("Normalizacja nie zostawia znaków niebezpiecznych dla systemu plików")
    func normalizesUnsafeCharacters() {
        #expect(FileNamer.normalize("a/b\\c:d*e?f") == "a_b_c_d_e_f")
        #expect(FileNamer.normalize("  spacje  ") == "spacje")
        #expect(FileNamer.normalize("kot 🐱 pies") == "kot_pies")
        #expect(FileNamer.normalize("...") == "")
        #expect(FileNamer.normalize("") == "")
    }

    @Test("Normalizacja przycina bardzo długie nazwy")
    func truncatesLongNames() {
        let long = String(repeating: "a", count: 200)
        #expect(FileNamer.normalize(long).count == 60)
    }

    @Test("Liczba cyfr licznika rośnie razem z liczbą zdjęć")
    func digitCountGrows() {
        #expect(FileNamer.digitCount(for: 1) == 3)
        #expect(FileNamer.digitCount(for: 47) == 3)
        #expect(FileNamer.digitCount(for: 999) == 3)
        #expect(FileNamer.digitCount(for: 1000) == 4)
        #expect(FileNamer.digitCount(for: 12345) == 5)
    }

    @Test("Prefiks daje ciągłą numerację w kolejności dat")
    func namesWithPrefix() throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photos = try Fixtures.photos(count: 3, in: directory)

        let ordered = FileNamer.ordered(photos.reversed())
        let names = FileNamer.names(for: ordered, prefix: "Łazienka", format: .jpeg)

        #expect(names == ["Lazienka_001.jpg", "Lazienka_002.jpg", "Lazienka_003.jpg"])
        // Kolejność wyznacza data zrobienia, nie kolejność podania na wejściu.
        #expect(ordered.map(\.id) == ["asset-0", "asset-1", "asset-2"])
    }

    @Test("Pusty prefiks zachowuje nazwy oryginalne, zmieniając rozszerzenie")
    func namesWithoutPrefix() throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photos = try Fixtures.photos(count: 2, in: directory)

        let names = FileNamer.names(for: photos, prefix: "", format: .png)
        #expect(names == ["IMG_0001.png", "IMG_0002.png"])
    }

    @Test("Powtórzone nazwy oryginalne nie nadpisują się nawzajem")
    func deduplicatesOriginalNames() throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = try Fixtures.photos(count: 1, in: directory)[0]
        let twin = FilePhoto(
            id: "asset-twin",
            creationDate: base.creationDate?.addingTimeInterval(1),
            originalFileName: base.originalFileName,
            pixelWidth: base.pixelWidth,
            pixelHeight: base.pixelHeight,
            byteCount: base.byteCount,
            fileURL: base.fileURL
        )

        let names = FileNamer.names(for: [base, twin], prefix: "", format: .jpeg)
        #expect(names == ["IMG_0001.jpg", "IMG_0001_2.jpg"])
        #expect(Set(names).count == 2)
    }

    @Test("Zdjęcia bez daty lądują na końcu, w kolejności deterministycznej")
    func photosWithoutDateGoLast() throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var photos = try Fixtures.photos(count: 2, in: directory)
        let orphan = FilePhoto(
            id: "asset-orphan", creationDate: nil, originalFileName: "SCAN.jpg",
            pixelWidth: 100, pixelHeight: 100, byteCount: 10, fileURL: photos[0].fileURL
        )
        photos.insert(orphan, at: 0)

        let ordered = FileNamer.ordered(photos)
        #expect(ordered.last?.id == "asset-orphan")
    }

    @Test("Nazwa archiwum zależy od liczby części")
    func archiveNames() {
        let date = Date(timeIntervalSince1970: 1_758_412_800)
        #expect(FileNamer.archiveName(prefix: "Łazienka", partIndex: nil, partCount: 1, date: date) == "Lazienka.zip")
        #expect(FileNamer.archiveName(prefix: "Łazienka", partIndex: 0, partCount: 3, date: date) == "Lazienka_cz1.zip")
        #expect(FileNamer.archiveName(prefix: "Łazienka", partIndex: 2, partCount: 3, date: date) == "Lazienka_cz3.zip")
        #expect(FileNamer.archiveName(prefix: "", partIndex: nil, partCount: 1, date: date).hasPrefix("Zdjecia_"))
    }
}
