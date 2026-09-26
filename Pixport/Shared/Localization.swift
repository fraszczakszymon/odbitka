import Foundation

/// Dostęp do napisów z katalogu `Localizable.xcstrings`.
///
/// Klucze są jawne (`library.title`), a nie zdaniami po polsku użytymi jako klucz.
/// Powód: aplikacja żyje w dwóch językach i w dwóch targetach (aplikacja i rozszerzenie),
/// a poprawka literówki w polskim tekście nie może cicho rozwalić angielskiego tłumaczenia.
enum L {
    static func s(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }

    static func f(_ key: String.LocalizationValue, _ arguments: any CVarArg...) -> String {
        String(format: String(localized: key), arguments: arguments)
    }
}
