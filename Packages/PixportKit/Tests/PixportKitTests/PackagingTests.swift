import Foundation
import Testing
@testable import PixportKit

@Suite("Pakowanie ZIP")
struct PackagingTests {

    /// Weryfikacja systemowym `unzip` zamiast czytania własnego zapisu własnym czytnikiem.
    /// Test, w którym obie strony pisze ten sam autor, potrafi zgodnie przyklepać
    /// archiwum, którego nie otworzy nikt poza nim.
    private func verifyWithSystemUnzip(_ url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-l", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "unzip odrzucił archiwum")
        return String(decoding: data, as: UTF8.self)
    }

    @Test("Archiwum otwiera się systemowym unzip i zawiera właściwe wpisy")
    func writesValidArchive() throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let a = try Fixtures.writeJPEG(at: directory.appendingPathComponent("a.jpg"), width: 200, height: 200)
        let b = try Fixtures.writeJPEG(at: directory.appendingPathComponent("b.jpg"), width: 200, height: 200)

        let archive = directory.appendingPathComponent("paczka.zip")
        let writer = try ZipWriter(url: archive)
        try writer.add(fileAt: a, name: "Lazienka_001.jpg", modificationDate: Date()) { _ in }
        try writer.add(fileAt: b, name: "Lazienka_002.jpg", modificationDate: Date()) { _ in }
        let size = try writer.finish()

        #expect(size > 0)
        let listing = try verifyWithSystemUnzip(archive)
        #expect(listing.contains("Lazienka_001.jpg"))
        #expect(listing.contains("Lazienka_002.jpg"))
    }

    @Test("Rozpakowane pliki są bajt w bajt tym, co spakowaliśmy")
    func roundTripsContents() throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = try Fixtures.writeJPEG(at: directory.appendingPathComponent("a.jpg"), width: 300, height: 200)
        let originalData = try Data(contentsOf: original)

        let archive = directory.appendingPathComponent("paczka.zip")
        let writer = try ZipWriter(url: archive)
        try writer.add(fileAt: original, name: "zdjecie.jpg", modificationDate: Date()) { _ in }
        try writer.finish()

        let unpacked = directory.appendingPathComponent("rozpakowane", isDirectory: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", archive.path, "-d", unpacked.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let extracted = try Data(contentsOf: unpacked.appendingPathComponent("zdjecie.jpg"))
        #expect(extracted == originalData)
    }

    @Test("Postęp raportuje dokładnie tyle bajtów, ile ma plik")
    func reportsProgress() throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try Fixtures.writeJPEG(at: directory.appendingPathComponent("a.jpg"), width: 400, height: 400)
        let expected = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0

        var reported: Int64 = 0
        let writer = try ZipWriter(url: directory.appendingPathComponent("p.zip"))
        try writer.add(fileAt: file, name: "a.jpg", modificationDate: Date()) { reported += $0 }
        try writer.finish()

        #expect(reported == expected)
    }

    @Test("Znacznik czasu MS-DOS koduje datę poprawnie")
    func dosTimestamp() {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 21
        components.hour = 14
        components.minute = 31
        components.second = 3
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: components)!

        let (time, dosDate) = ZipWriter.dosTimestamp(from: date, calendar: calendar)
        #expect(Int(dosDate >> 9) + 1980 == 2026)
        #expect(Int((dosDate >> 5) & 0x0F) == 9)
        #expect(Int(dosDate & 0x1F) == 21)
        #expect(Int(time >> 11) == 14)
        #expect(Int((time >> 5) & 0x3F) == 31)
        // MS-DOS ma dwusekundową rozdzielczość — 3 s zapisuje się jako 1.
        #expect(Int(time & 0x1F) == 1)
    }
}

@Suite("Podział na części")
struct SplitPlannerTests {

    @Test("Pliki trafiają do części w kolejności wejściowej")
    func keepsOrder() throws {
        let entries = (1...6).map { SplitPlanner.Entry(name: "f\($0)", size: 4_000_000) }
        let plan = try SplitPlanner.plan(entries: entries, partLimit: 10_000_000)

        #expect(plan.count == 3)
        #expect(plan == [[0, 1], [2, 3], [4, 5]])
    }

    @Test("Jedna część, gdy wszystko się mieści")
    func singlePart() throws {
        let entries = (1...3).map { SplitPlanner.Entry(name: "f\($0)", size: 1_000_000) }
        let plan = try SplitPlanner.plan(entries: entries, partLimit: 25_000_000)
        #expect(plan == [[0, 1, 2]])
    }

    @Test("Plik większy niż limit części kończy się jasnym błędem")
    func rejectsOversizedFile() {
        let entries = [
            SplitPlanner.Entry(name: "male.jpg", size: 1_000),
            SplitPlanner.Entry(name: "ogromne.png", size: 40_000_000)
        ]
        #expect(throws: ConversionError.self) {
            _ = try SplitPlanner.plan(entries: entries, partLimit: 25_000_000)
        }
    }

    @Test("Żadna część nie przekracza limitu")
    func respectsLimit() throws {
        let sizes: [Int64] = [3_000_000, 7_000_000, 2_000_000, 9_000_000, 1_000_000, 6_000_000]
        let entries = sizes.enumerated().map { SplitPlanner.Entry(name: "f\($0.offset)", size: $0.element) }
        let limit: Int64 = 12_000_000
        let plan = try SplitPlanner.plan(entries: entries, partLimit: limit)

        for part in plan {
            let total = part.reduce(Int64(0)) { $0 + entries[$1].size + SplitPlanner.perEntryOverhead }
            #expect(total <= limit - SplitPlanner.archiveOverhead)
        }
        #expect(plan.flatMap { $0 } == Array(entries.indices))
    }
}
