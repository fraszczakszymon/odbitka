import Foundation

/// Nadawanie nazw plikom wynikowym.
///
/// Czysta funkcja: zdjęcia wchodzą, nazwy wychodzą. Cała logika, której nie widać
/// na ekranie, a której błąd zauważy dopiero odbiorca paczki — dlatego jest otestowana.
public enum FileNamer {

    /// Sprowadza dowolny tekst od użytkownika do nazwy bezpiecznej w każdym systemie.
    ///
    /// Powód istnienia tej funkcji: archiwum ZIP nie ma zdefiniowanego kodowania nazw.
    /// Flagę UTF-8 ustawiamy, ale starszy Eksplorator Windows i część narzędzi
    /// korporacyjnych i tak zgadują stronę kodową — i „Łazienka" przyjeżdża jako krzaki.
    /// Taniej jest nie wysyłać ogonków, niż tłumaczyć odbiorcy, co się stało.
    public static func normalize(_ raw: String) -> String {
        // Rozkład kanoniczny + odcięcie znaków diakrytycznych: ą→a, ö→o, é→e.
        // „Ł" nie jest literą z diakrytykiem w sensie Unicode, więc wymaga podmiany wprost.
        let preMapped = raw
            .replacingOccurrences(of: "ł", with: "l")
            .replacingOccurrences(of: "Ł", with: "L")
            .replacingOccurrences(of: "ø", with: "o")
            .replacingOccurrences(of: "Ø", with: "O")
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "Æ", with: "AE")

        let folded = preMapped.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))

        var out = ""
        out.reserveCapacity(folded.count)
        for scalar in folded.unicodeScalars {
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", "-", "_":
                out.unicodeScalars.append(scalar)
            default:
                // Wszystko inne — spacje, kropki, ukośniki, emoji, cyrylica — staje się
                // podkreśleniem; nadmiar sklejamy niżej.
                out.append("_")
            }
        }

        while out.contains("__") {
            out = out.replacingOccurrences(of: "__", with: "_")
        }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "_-"))

        // 60 znaków to z zapasem poniżej limitów każdego systemu plików nawet po
        // doklejeniu numeru i rozszerzenia.
        if out.count > 60 {
            out = String(out.prefix(60))
            out = out.trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        }
        return out
    }

    /// Liczba cyfr licznika. Minimum trzy, więcej gdy zdjęć jest więcej niż 999.
    public static func digitCount(for photoCount: Int) -> Int {
        max(3, String(max(photoCount, 1)).count)
    }

    /// Kolejność numerowania: rosnąco wg daty zrobienia.
    ///
    /// Nie wg kolejności zaznaczania (użytkownik nie pamięta, co tapnął pierwsze)
    /// i nie wg nazwy oryginalnej (`IMG_9998` wypadłoby po `IMG_10001`).
    /// Zdjęcia bez daty lądują na końcu, uporządkowane deterministycznie.
    public static func ordered(_ photos: [any SourcePhoto]) -> [any SourcePhoto] {
        photos.sorted { lhs, rhs in
            switch (lhs.creationDate, rhs.creationDate) {
            case let (l?, r?) where l != r:
                return l < r
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                let lName = lhs.originalFileName ?? ""
                let rName = rhs.originalFileName ?? ""
                return lName == rName ? lhs.id < rhs.id : lName < rName
            }
        }
    }

    /// Nazwy plików wynikowych, w kolejności numerowania.
    ///
    /// Pusty prefiks oznacza „nie ruszaj nazw" — zostaje nazwa oryginalna
    /// ze zmienionym rozszerzeniem.
    public static func names(
        for photos: [any SourcePhoto],
        prefix rawPrefix: String,
        format: ImageFormat
    ) -> [String] {
        let ext = format.fileExtension
        let prefix = normalize(rawPrefix)

        if prefix.isEmpty {
            return deduplicated(photos.map { photo in
                let base = (photo.originalFileName as NSString?)?.deletingPathExtension ?? ""
                let normalized = normalize(base)
                return normalized.isEmpty ? "zdjecie" : normalized
            }, extension: ext)
        }

        let digits = digitCount(for: photos.count)
        return photos.indices.map { index in
            let number = String(format: "%0\(digits)d", index + 1)
            return "\(prefix)_\(number).\(ext)"
        }
    }

    /// Nazwa archiwum. Jedna część → `Lazienka.zip`, wiele → `Lazienka_cz1.zip`.
    public static func archiveName(prefix rawPrefix: String, partIndex: Int?, partCount: Int, date: Date, calendar: Calendar = .current) -> String {
        let prefix = normalize(rawPrefix)
        let base: String
        if prefix.isEmpty {
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            base = String(format: "Zdjecia_%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        } else {
            base = prefix
        }
        guard partCount > 1, let partIndex else { return "\(base).zip" }
        return "\(base)_cz\(partIndex + 1).zip"
    }

    /// Rozstrzyga powtórzenia nazw, doklejając `_2`, `_3`…
    ///
    /// Dwa zdjęcia potrafią mieć tę samą nazwę oryginalną (import z różnych źródeł),
    /// a dwa pliki o tej samej nazwie w jednym katalogu to cicha utrata jednego z nich.
    private static func deduplicated(_ bases: [String], extension ext: String) -> [String] {
        var seen: [String: Int] = [:]
        return bases.map { base in
            let key = base.lowercased()
            let count = (seen[key] ?? 0) + 1
            seen[key] = count
            return count == 1 ? "\(base).\(ext)" : "\(base)_\(count).\(ext)"
        }
    }
}
