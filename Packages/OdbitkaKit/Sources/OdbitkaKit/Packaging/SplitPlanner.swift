import Foundation

/// Rozdzielanie plików na archiwa mieszczące się w zadanym limicie.
public enum SplitPlanner {

    /// Narzut struktur ZIP na jeden wpis: nagłówek lokalny, wpis katalogu centralnego,
    /// nazwa dwukrotnie, pola ZIP64. Z zapasem, żeby część nie przekroczyła limitu
    /// przez samą buchalterię archiwum.
    public static let perEntryOverhead: Int64 = 512
    /// Stopka archiwum: katalog centralny plus rekordy końcowe.
    public static let archiveOverhead: Int64 = 1024

    public struct Entry: Sendable, Equatable {
        public let name: String
        public let size: Int64
        public init(name: String, size: Int64) {
            self.name = name
            self.size = size
        }
    }

    /// Dzieli wpisy na części zachłannie, w kolejności wejściowej.
    ///
    /// Kolejność jest zachowana świadomie: numeracja `_001`, `_002` ma odpowiadać
    /// kolejnym paczkom. Upakowanie „optymalne" (bin packing) dałoby ciaśniejsze
    /// archiwa kosztem wymieszania zdjęć między częściami — a odbiorca dokumentacji
    /// oczekuje, że część pierwsza zawiera początek, nie losowy podzbiór.
    ///
    /// - Throws: `ConversionError.fileLargerThanPart`, gdy pojedynczy plik nie mieści się
    ///   w limicie. Nie da się tego obejść podziałem, więc mówimy o tym wprost zamiast
    ///   po cichu produkować część przekraczającą limit.
    public static func plan(entries: [Entry], partLimit: Int64) throws -> [[Int]] {
        guard partLimit > 0 else { return [Array(entries.indices)] }
        guard !entries.isEmpty else { return [] }

        let usableLimit = partLimit - archiveOverhead

        for entry in entries where entry.size + perEntryOverhead > usableLimit {
            throw ConversionError.fileLargerThanPart(
                fileName: entry.name,
                fileSize: entry.size,
                partLimit: partLimit
            )
        }

        var parts: [[Int]] = []
        var current: [Int] = []
        var currentSize: Int64 = 0

        for (index, entry) in entries.enumerated() {
            let cost = entry.size + perEntryOverhead
            if !current.isEmpty, currentSize + cost > usableLimit {
                parts.append(current)
                current = []
                currentSize = 0
            }
            current.append(index)
            currentSize += cost
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}
