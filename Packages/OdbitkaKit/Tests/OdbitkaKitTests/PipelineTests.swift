import Foundation
import ImageIO
import Testing
@testable import OdbitkaKit

@Suite("Przebieg przetwarzania", .serialized)
struct PipelineTests {

    private func makeWorkspace() throws -> Workspace {
        try Workspace(sessionID: "test-" + UUID().uuidString)
    }

    @Test("Przetwarza komplet zdjęć i nadaje nazwy wg schematu")
    func processesAll() async throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = try makeWorkspace()
        defer { workspace.destroy() }

        let photos = try Fixtures.photos(count: 5, in: directory)
        var settings = ConversionSettings.default
        settings.namePrefix = "Łazienka"
        settings.targetSize = .longEdge(400)

        let pipeline = ConversionPipeline(workspace: workspace)
        let result = try await pipeline.run(photos: photos, settings: settings, isNetworkAvailable: true) { _ in }

        #expect(result.files.count == 5)
        #expect(result.files.map(\.fileName) == (1...5).map { String(format: "Lazienka_%03d.jpg", $0) })
        for file in result.files {
            #expect(FileManager.default.fileExists(atPath: file.url.path))
            #expect(file.byteCount > 0)
        }
        #expect(result.producedByteCount > 0)
    }

    @Test("Zmniejszenie rozdzielczości realnie zmniejsza paczkę")
    func shrinkingActuallyShrinks() async throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = try makeWorkspace()
        defer { workspace.destroy() }

        let photos = try Fixtures.photos(count: 3, in: directory, width: 1600, height: 1200)
        var settings = ConversionSettings.default
        settings.targetSize = .longEdge(400)

        let pipeline = ConversionPipeline(workspace: workspace)
        let result = try await pipeline.run(photos: photos, settings: settings, isNetworkAvailable: true) { _ in }

        #expect(result.producedByteCount < result.originalByteCount)
        #expect((ByteFormatting.savingsPercent(original: result.originalByteCount, produced: result.producedByteCount) ?? 0) > 0)
    }

    @Test("Nie powiększa zdjęć mniejszych niż żądany rozmiar")
    func neverUpscales() async throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = try makeWorkspace()
        defer { workspace.destroy() }

        let photos = try Fixtures.photos(count: 1, in: directory, width: 320, height: 240)
        var settings = ConversionSettings.default
        settings.targetSize = .longEdge(4000)

        let pipeline = ConversionPipeline(workspace: workspace)
        let result = try await pipeline.run(photos: photos, settings: settings, isNetworkAvailable: true) { _ in }

        let props = Fixtures.properties(of: result.files[0].url)
        #expect(props[kCGImagePropertyPixelWidth as String] as? Int == 320)
    }

    @Test("Tryb budżetowy realnie mieści się w limicie")
    func budgetModeFitsLimit() async throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = try makeWorkspace()
        defer { workspace.destroy() }

        let photos = try Fixtures.photos(count: 4, in: directory, width: 1200, height: 900)
        let unlimited = try await ConversionPipeline(workspace: try makeWorkspace())
            .run(photos: photos, settings: .default, isNetworkAvailable: true) { _ in }

        // Limit celowo poniżej tego, co wychodzi „normalnie" — solver musi dołożyć przebieg.
        let budget = unlimited.producedByteCount / 2
        var settings = ConversionSettings.default
        settings.budget = SizeBudget(isEnabled: true, megabytes: max(1, Int(budget / 1_000_000)))

        // Więcej przebiegów niż domyślne cztery: testowe obrazki to czysty szum,
        // który kompresuje się znacznie gorzej niż prawdziwe zdjęcie, więc solver
        // potrzebuje kilku kroków więcej niż w realnym użyciu.
        let result = try await ConversionPipeline(workspace: workspace, maxBudgetPasses: 10)
            .run(photos: photos, settings: settings, isNetworkAvailable: true) { _ in }

        #expect(result.producedByteCount <= settings.budget.bytes)
        #expect(result.budgetPasses > 1, "Powinien być potrzebny co najmniej jeden dodatkowy przebieg")
    }

    @Test("Pakowanie daje jedno archiwum z kompletem plików")
    func packsIntoArchive() async throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = try makeWorkspace()
        defer { workspace.destroy() }

        let photos = try Fixtures.photos(count: 4, in: directory, width: 600, height: 400)
        var settings = ConversionSettings.default
        settings.namePrefix = "Kuchnia"
        settings.packaging = PackagingSettings(makeZip: true)

        let result = try await ConversionPipeline(workspace: workspace)
            .run(photos: photos, settings: settings, isNetworkAvailable: true) { _ in }

        #expect(result.archives.count == 1)
        #expect(result.archives[0].fileName == "Kuchnia.zip")
        #expect(result.shareableFiles.count == 1, "Do udostępniania idzie archiwum, nie luźne pliki")
    }

    @Test("Podział na części tworzy ponumerowane archiwa")
    func splitsIntoParts() async throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = try makeWorkspace()
        defer { workspace.destroy() }

        let photos = try Fixtures.photos(count: 6, in: directory, width: 900, height: 900)
        var settings = ConversionSettings.default
        settings.namePrefix = "Raport"
        settings.targetSize = .original
        settings.quality = 1.0
        settings.packaging = PackagingSettings(makeZip: true, splitIntoParts: true, partMegabytes: 4)

        let result = try await ConversionPipeline(workspace: workspace)
            .run(photos: photos, settings: settings, isNetworkAvailable: true) { _ in }

        #expect(result.archives.count > 1)
        #expect(result.archives[0].fileName == "Raport_cz1.zip")
        for archive in result.archives {
            #expect(archive.byteCount <= settings.packaging.partBytes)
        }
    }

    @Test("Brak sieci przy zdjęciach z iCloud przerywa od razu, przed przetwarzaniem")
    func failsFastWhenOffline() async throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = try makeWorkspace()
        defer { workspace.destroy() }

        var photos = try Fixtures.photos(count: 3, in: directory)
        photos[1].available = false

        await #expect(throws: ConversionError.photosNotAvailableOffline(count: 1)) {
            _ = try await ConversionPipeline(workspace: workspace)
                .run(photos: photos, settings: .default, isNetworkAvailable: false) { _ in }
        }

        // Kontrola wstępna ma zadziałać zanim powstanie choć jeden plik.
        let produced = try FileManager.default.contentsOfDirectory(atPath: workspace.outputDirectory.path)
        #expect(produced.isEmpty)
    }

    @Test("Błąd w środku paczki nie zostawia plików częściowych")
    func allOrNothing() async throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = try makeWorkspace()
        defer { workspace.destroy() }

        var photos = try Fixtures.photos(count: 4, in: directory)
        // Plik, którego ImageIO nie przeczyta — imitacja uszkodzonego zasobu.
        let broken = directory.appendingPathComponent("BROKEN.jpg")
        try Data("to nie jest obrazek".utf8).write(to: broken)
        photos.append(
            FilePhoto(
                id: "asset-broken",
                creationDate: Date(timeIntervalSince1970: 1_700_000_999),
                originalFileName: "BROKEN.jpg",
                pixelWidth: 100, pixelHeight: 100,
                byteCount: 19, fileURL: broken
            )
        )

        await #expect(throws: ConversionError.self) {
            _ = try await ConversionPipeline(workspace: workspace, maxConcurrency: 1)
                .run(photos: photos, settings: .default, isNetworkAvailable: true) { _ in }
        }

        let produced = try FileManager.default.contentsOfDirectory(atPath: workspace.outputDirectory.path)
        #expect(produced.isEmpty, "Wszystko albo nic: po bledzie nie zostaje ani jeden plik")
    }

    @Test("Postęp dochodzi do kompletu")
    func reportsProgressToCompletion() async throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = try makeWorkspace()
        defer { workspace.destroy() }

        let photos = try Fixtures.photos(count: 4, in: directory, width: 400, height: 300)
        let collector = ProgressCollector()

        _ = try await ConversionPipeline(workspace: workspace)
            .run(photos: photos, settings: .default, isNetworkAvailable: true) { progress in
                collector.record(progress.completed)
            }

        #expect(collector.maximum == 4)
    }
}

/// Zbiera raporty postępu z równoległych zadań.
final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func record(_ completed: Int) {
        lock.lock()
        defer { lock.unlock() }
        value = max(value, completed)
    }

    var maximum: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@Suite("Szacowanie rozmiaru")
struct SizeEstimatorTests {

    @Test("Próbki są rozłożone równomiernie po zaznaczeniu")
    func samplesAreSpread() throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photos = try Fixtures.photos(count: 30, in: directory, width: 40, height: 40)

        let samples = SizeEstimator.pickSamples(from: photos, count: 3)
        #expect(samples.count == 3)
        let ids = samples.map(\.id)
        #expect(Set(ids).count == 3, "Próbki nie mogą się powtarzać")
        #expect(ids != ["asset-0", "asset-1", "asset-2"], "Trzy pierwsze zdjęcia to nie jest reprezentatywna próbka")
    }

    @Test("Mniej zdjęć niż próbek — bierzemy wszystkie")
    func samplesFewerPhotos() throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photos = try Fixtures.photos(count: 2, in: directory, width: 40, height: 40)
        #expect(SizeEstimator.pickSamples(from: photos, count: 5).count == 2)
    }

    @Test("Liczba pikseli wyjściowych uwzględnia skalowanie i brak powiększania")
    func outputPixelCount() throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = try Fixtures.photos(count: 1, in: directory, width: 4000, height: 3000)[0]

        var settings = ConversionSettings.default
        settings.targetSize = .longEdge(2000)
        #expect(SizeEstimator.outputPixelCount(for: photo, settings: settings) == 2000 * 1500)

        settings.targetSize = .longEdge(8000)
        #expect(SizeEstimator.outputPixelCount(for: photo, settings: settings) == 4000 * 3000)

        settings.targetSize = .original
        #expect(SizeEstimator.outputPixelCount(for: photo, settings: settings) == 4000 * 3000)
    }

    @Test("Szacunek trafia w rząd wielkości rzeczywistego wyniku")
    func estimateIsInTheRightBallpark() async throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = try Workspace(sessionID: "est-" + UUID().uuidString)
        defer { workspace.destroy() }

        let photos = try Fixtures.photos(count: 8, in: directory, width: 1000, height: 800)
        var settings = ConversionSettings.default
        settings.targetSize = .longEdge(600)

        let estimate = try #require(await SizeEstimator.estimate(photos: photos, settings: settings))
        #expect(estimate.isMeasured, "Przy plikach na dysku szacunek ma pochodzić z pomiaru")
        let actual = try await ConversionPipeline(workspace: workspace)
            .run(photos: photos, settings: settings, isNetworkAvailable: true) { _ in }
            .producedByteCount

        let ratio = Double(estimate.bytes) / Double(actual)
        // Celowo luźny próg: szacunek z próbki jest z natury przybliżeniem i tak też
        // jest podpisany w interfejsie („~"). Test pilnuje tylko, żeby nie był absurdalny.
        #expect(ratio > 0.5 && ratio < 2.0, "Szacunek \(estimate.bytes) wobec rzeczywistych \(actual)")
    }

    @Test("Zdjęcia wyłącznie w iCloud i tak dają liczbę, oznaczoną jako niemierzoną")
    func fallsBackWhenNothingIsLocal() async throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Dokładnie sytuacja z telefonu z włączoną optymalizacją pamięci: miniatury są
        // lokalnie, oryginałów nie ma. Wcześniej estymator zwracał wtedy nil,
        // a etykieta z rozmiarem znikała z ekranu bez żadnego wyjaśnienia.
        var photos = try Fixtures.photos(count: 5, in: directory, width: 4032, height: 3024)
        for index in photos.indices { photos[index].available = false }

        var settings = ConversionSettings.default
        settings.targetSize = .longEdge(1600)

        let estimate = try #require(await SizeEstimator.estimate(photos: photos, settings: settings))
        #expect(estimate.isMeasured == false)
        #expect(estimate.bytes > 0)

        // 5 zdjęć po 1600×1200 px przy jakości 85% to kilka megabajtów — liczba ma być
        // w rozsądnym rzędzie wielkości, nie symboliczna.
        #expect(estimate.bytes > 1_000_000 && estimate.bytes < 20_000_000, "Wyszło \(estimate.bytes) B")
    }

    @Test("Model zapasowy reaguje na jakość i format")
    func nominalModelRespondsToSettings() {
        var settings = ConversionSettings.default
        settings.quality = 0.9
        let high = SizeEstimator.nominalBytesPerPixel(for: settings)
        settings.quality = 0.4
        let low = SizeEstimator.nominalBytesPerPixel(for: settings)
        #expect(low < high)

        settings.format = .png
        #expect(SizeEstimator.nominalBytesPerPixel(for: settings) > high, "PNG jest bezstratny")
    }

    @Test("Puste zaznaczenie nie produkuje liczby z sufitu")
    func emptySelection() async {
        let estimate = await SizeEstimator.estimate(photos: [], settings: .default)
        #expect(estimate?.bytes == 0)
    }
}
