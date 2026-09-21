import Foundation

/// Formatowanie rozmiarów na potrzeby interfejsu.
public enum ByteFormatting {
    /// Rozmiary plików liczymy dziesiętnie (1 MB = 1 000 000 B), tak jak robi to system
    /// iOS i tak jak podaje limity Gmail. Liczenie binarne dawałoby wartości mniejsze
    /// od tych, które użytkownik widzi w Ustawieniach telefonu i w komunikacie
    /// o przekroczonym limicie załącznika.
    public static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.isAdaptive = true
        // Bez tego `ByteCountFormatter` wypisuje dla zera slowne "Zero KB",
        // co w tabeli z rozmiarami wyglada jak usterka.
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: max(0, bytes))
    }

    /// „−92%". Zwraca `nil`, gdy nie ma czego porównywać.
    public static func savingsPercent(original: Int64, produced: Int64) -> Int? {
        guard original > 0, produced >= 0 else { return nil }
        let ratio = 1.0 - Double(produced) / Double(original)
        return Int((ratio * 100).rounded())
    }
}
