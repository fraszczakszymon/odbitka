import Foundation
import PixportKit

/// Jedyny trwały stan aplikacji: ostatnio użyte ustawienia.
///
/// Świadomie **nie ma** presetów ani ich zarządzania — ekran ustawień pokazuje wszystkie
/// opcje naraz, a domyślne wartości to te z poprzedniego użycia. Cały „magazyn" to jeden
/// wpis w `UserDefaults`.
@Observable
@MainActor
final class SettingsStore {
    private static let key = "pl.froncek.pixport.settings"

    var settings: ConversionSettings {
        didSet { persist() }
    }

    /// Ustawienia mieszkają w `UserDefaults` grupy aplikacji, a nie w standardowych.
    /// Dzięki temu rozszerzenie udostępniania i aplikacja pamiętają te same wartości —
    /// przetworzenie czegoś z poziomu Zdjęć nie zaczyna się od ustawień fabrycznych,
    /// skoro dziesięć minut wcześniej użytkownik ustawił swoje w aplikacji.
    init(defaults: UserDefaults = UserDefaults(suiteName: PixportConfig.appGroupID) ?? .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           var stored = try? JSONDecoder().decode(ConversionSettings.self, from: data) {
            // Prefiks nazwy celowo nie przeżywa uruchomienia. Opisuje konkretną paczkę,
            // nie sposób przetwarzania — a podpisanie zdjęć kuchni nazwą Lazienka
            // zauważa się dopiero u odbiorcy.
            stored.namePrefix = ""
            self.settings = stored
        } else {
            self.settings = .default
        }
    }

    private let defaults: UserDefaults

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
