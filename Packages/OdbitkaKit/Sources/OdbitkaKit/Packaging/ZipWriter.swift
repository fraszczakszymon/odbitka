import Foundation

/// Strumieniowy zapis archiwum ZIP, metodą STORE (bez kompresji).
///
/// **Dlaczego bez kompresji.** JPEG i PNG są już skompresowane; przepuszczenie ich przez
/// deflate daje zwykle 0–2% zysku przy kilkukrotnie dłuższym czasie i zauważalnie
/// większym zużyciu baterii. Wartością ZIP-a w tej aplikacji jest zwinięcie
/// czterdziestu siedmiu plików w jeden, a nie zmniejszenie — zmniejszanie odbywa się
/// dwa kroki wcześniej, przy konwersji. To samo mówimy użytkownikowi w interfejsie:
/// „Spakuj do jednego pliku ZIP", nigdy „Kompresuj".
///
/// **Dlaczego własny zapis, a nie biblioteka.** Potrzebujemy trzech rzeczy naraz:
/// zapisu strumieniowego (paczka bywa większa niż pamięć urządzenia), postępu
/// i podziału na części. Przy metodzie STORE cały format to kilka nagłówków
/// o stałym układzie — mniej kodu niż integracja zewnętrznej zależności i zero
/// ryzyka, że projekt przestanie się budować, bo ktoś usunął tag z GitHuba.
///
/// Obsługuje ZIP64 (archiwa ponad 4 GB i ponad 65 535 wpisów), bo przy setkach
/// zdjęć w pełnej rozdzielczości to nie jest przypadek teoretyczny.
public final class ZipWriter {

    private struct Entry {
        let name: String
        let crc: UInt32
        let size: Int64
        let offset: Int64
        let dosTime: UInt16
        let dosDate: UInt16
    }

    private let handle: FileHandle
    private let url: URL
    private var entries: [Entry] = []
    private var offset: Int64 = 0
    private var isFinished = false

    private static let zip64Threshold: Int64 = 0xFFFF_FFFF

    public init(url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw ConversionError.cannotWriteOutput(underlying: url.lastPathComponent)
        }
        do {
            self.handle = try FileHandle(forWritingTo: url)
        } catch {
            throw ConversionError.cannotWriteOutput(underlying: error.localizedDescription)
        }
        self.url = url
    }

    /// Dokłada plik do archiwum.
    ///
    /// Plik czytany jest dwukrotnie: raz po sumę kontrolną, raz przy kopiowaniu.
    /// To świadomy wybór — alternatywą byłoby wpisanie CRC dopiero po danych
    /// (deskryptor danych), co część czytników ZIP obsługuje gorzej. Odczyt z dysku
    /// jest tu dużo tańszy niż ryzyko archiwum, którego odbiorca nie otworzy.
    public func add(
        fileAt fileURL: URL,
        name: String,
        modificationDate: Date,
        onProgress: (Int64) -> Void
    ) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let (dosTime, dosDate) = Self.dosTimestamp(from: modificationDate)

        let crc = try checksum(of: fileURL)
        let entryOffset = offset
        let needsZip64 = size >= Self.zip64Threshold

        var header = Data()
        header.appendLE(UInt32(0x0403_4B50))
        header.appendLE(UInt16(needsZip64 ? 45 : 20))
        header.appendLE(UInt16(0x0800))                       // nazwy w UTF-8
        header.appendLE(UInt16(0))                            // metoda: STORE
        header.appendLE(dosTime)
        header.appendLE(dosDate)
        header.appendLE(crc)
        header.appendLE(UInt32(needsZip64 ? 0xFFFF_FFFF : UInt32(size)))
        header.appendLE(UInt32(needsZip64 ? 0xFFFF_FFFF : UInt32(size)))
        let nameBytes = Data(name.utf8)
        header.appendLE(UInt16(nameBytes.count))
        header.appendLE(UInt16(needsZip64 ? 20 : 0))
        header.append(nameBytes)
        if needsZip64 {
            header.appendLE(UInt16(0x0001))
            header.appendLE(UInt16(16))
            header.appendLE(UInt64(size))
            header.appendLE(UInt64(size))
        }

        try write(header)
        try copyContents(of: fileURL, onProgress: onProgress)

        entries.append(
            Entry(name: name, crc: crc, size: size, offset: entryOffset, dosTime: dosTime, dosDate: dosDate)
        )
    }

    /// Domyka archiwum i zwraca jego rozmiar w bajtach.
    @discardableResult
    public func finish() throws -> Int64 {
        guard !isFinished else { return offset }
        isFinished = true

        let directoryOffset = offset
        var directory = Data()

        for entry in entries {
            let needsZip64 = entry.size >= Self.zip64Threshold || entry.offset >= Self.zip64Threshold
            directory.appendLE(UInt32(0x0201_4B50))
            directory.appendLE(UInt16(45))                    // version made by
            directory.appendLE(UInt16(needsZip64 ? 45 : 20))  // version needed
            directory.appendLE(UInt16(0x0800))
            directory.appendLE(UInt16(0))
            directory.appendLE(entry.dosTime)
            directory.appendLE(entry.dosDate)
            directory.appendLE(entry.crc)
            directory.appendLE(UInt32(needsZip64 ? 0xFFFF_FFFF : UInt32(entry.size)))
            directory.appendLE(UInt32(needsZip64 ? 0xFFFF_FFFF : UInt32(entry.size)))
            let nameBytes = Data(entry.name.utf8)
            directory.appendLE(UInt16(nameBytes.count))
            directory.appendLE(UInt16(needsZip64 ? 28 : 0))   // extra
            directory.appendLE(UInt16(0))                     // comment
            directory.appendLE(UInt16(0))                     // disk start
            directory.appendLE(UInt16(0))                     // internal attrs
            directory.appendLE(UInt32(0))                     // external attrs
            directory.appendLE(UInt32(needsZip64 ? 0xFFFF_FFFF : UInt32(entry.offset)))
            directory.append(nameBytes)
            if needsZip64 {
                directory.appendLE(UInt16(0x0001))
                directory.appendLE(UInt16(24))
                directory.appendLE(UInt64(entry.size))
                directory.appendLE(UInt64(entry.size))
                directory.appendLE(UInt64(entry.offset))
            }
        }

        try write(directory)

        let directorySize = Int64(directory.count)
        let needsZip64End = entries.count > 0xFFFE
            || directorySize >= Self.zip64Threshold
            || directoryOffset >= Self.zip64Threshold

        if needsZip64End {
            let zip64Offset = offset
            var record = Data()
            record.appendLE(UInt32(0x0606_4B50))
            record.appendLE(UInt64(44))                       // rozmiar reszty rekordu
            record.appendLE(UInt16(45))
            record.appendLE(UInt16(45))
            record.appendLE(UInt32(0))
            record.appendLE(UInt32(0))
            record.appendLE(UInt64(entries.count))
            record.appendLE(UInt64(entries.count))
            record.appendLE(UInt64(directorySize))
            record.appendLE(UInt64(directoryOffset))
            record.appendLE(UInt32(0x0706_4B50))              // locator
            record.appendLE(UInt32(0))
            record.appendLE(UInt64(zip64Offset))
            record.appendLE(UInt32(1))
            try write(record)
        }

        var end = Data()
        end.appendLE(UInt32(0x0605_4B50))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(needsZip64End ? 0xFFFF : UInt16(entries.count)))
        end.appendLE(UInt16(needsZip64End ? 0xFFFF : UInt16(entries.count)))
        end.appendLE(UInt32(needsZip64End ? 0xFFFF_FFFF : UInt32(directorySize)))
        end.appendLE(UInt32(needsZip64End ? 0xFFFF_FFFF : UInt32(directoryOffset)))
        end.appendLE(UInt16(0))
        try write(end)

        try? handle.close()
        return offset
    }

    // MARK: - Wnętrze

    private func write(_ data: Data) throws {
        guard !data.isEmpty else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            throw ConversionError.cannotWriteOutput(underlying: error.localizedDescription)
        }
        offset += Int64(data.count)
    }

    private static let bufferSize = 1 << 20  // 1 MB

    private func checksum(of fileURL: URL) throws -> UInt32 {
        guard let reader = try? FileHandle(forReadingFrom: fileURL) else {
            throw ConversionError.cannotReadSource(fileName: fileURL.lastPathComponent)
        }
        defer { try? reader.close() }
        var crc = CRC32()
        while let chunk = try reader.read(upToCount: Self.bufferSize), !chunk.isEmpty {
            crc.update(chunk)
        }
        return crc.checksum
    }

    private func copyContents(of fileURL: URL, onProgress: (Int64) -> Void) throws {
        guard let reader = try? FileHandle(forReadingFrom: fileURL) else {
            throw ConversionError.cannotReadSource(fileName: fileURL.lastPathComponent)
        }
        defer { try? reader.close() }
        while let chunk = try reader.read(upToCount: Self.bufferSize), !chunk.isEmpty {
            try write(chunk)
            onProgress(Int64(chunk.count))
        }
    }

    /// ZIP przechowuje czas w formacie MS-DOS: 2-sekundowa rozdzielczość, rok od 1980.
    static func dosTimestamp(from date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> (UInt16, UInt16) {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, components.year ?? 1980)
        let time = UInt16(((components.hour ?? 0) << 11) | ((components.minute ?? 0) << 5) | ((components.second ?? 0) / 2))
        let dosDate = UInt16((((year - 1980) & 0x7F) << 9) | ((components.month ?? 1) << 5) | (components.day ?? 1))
        return (time, dosDate)
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLE(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            append(UInt8((value >> UInt32(shift)) & 0xFF))
        }
    }

    mutating func appendLE(_ value: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
    }
}
