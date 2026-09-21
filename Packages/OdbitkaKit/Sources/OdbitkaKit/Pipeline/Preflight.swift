import Foundation

/// Kontrola wstępna przed uruchomieniem przetwarzania.
///
/// Aplikacja działa w trybie „wszystko albo nic": pierwszy błąd kasuje cały dorobek
/// przebiegu. Bez kontroli wstępnej byłoby to okrutne — jedno zdjęcie wiszące w iCloud
/// przy wyłączonym Wi-Fi unieważniałoby dziesięć minut pracy telefonu. Dlatego typowa
/// porażka ma nastąpić **w pierwszej sekundzie, z konkretnym komunikatem**,
/// a nie w dziesiątej minucie.
public enum Preflight {

    /// Ile miejsca zajmie wynik względem oryginałów — szacunek dla kontroli miejsca.
    ///
    /// Dla JPEG jesteśmy hojni, dla PNG wręcz pesymistyczni: PNG ze zdjęcia z aparatu
    /// bywa kilkukrotnie większy od źródłowego HEIC-a, bo bezstratna kompresja nie ma
    /// czego uprościć na szumie matrycy.
    static func outputSizeMultiplier(for settings: ConversionSettings) -> Double {
        switch settings.format {
        case .jpeg: 1.0
        case .png: 3.0
        }
    }

    public struct Report: Sendable {
        public let unavailableCount: Int
        public let requiredBytes: Int64
        public let availableBytes: Int64
    }

    /// - Parameter isNetworkAvailable: dostarczane przez warstwę aplikacji. Silnik
    ///   celowo nie zna `Network` ani `PhotoKit` — dzięki temu testuje się bez symulatora.
    public static func check(
        photos: [any SourcePhoto],
        settings: ConversionSettings,
        isNetworkAvailable: Bool,
        availableBytes: Int64 = Workspace.availableBytes()
    ) async throws -> Report {
        var unavailable = 0
        for photo in photos where await !photo.isAvailableLocally() {
            unavailable += 1
        }

        if unavailable > 0 && !isNetworkAvailable {
            throw ConversionError.photosNotAvailableOffline(count: unavailable)
        }

        let originalsTotal = photos.reduce(Int64(0)) { $0 + $1.byteCount }
        let largestOriginal = photos.map(\.byteCount).max() ?? 0
        let outputsEstimate = Int64(Double(originalsTotal) * outputSizeMultiplier(for: settings))

        // Oryginały ściągamy i kasujemy po jednym, więc szczyt zapotrzebowania to
        // największy pojedynczy plik źródłowy plus komplet wyników. Wyjątkiem jest tryb
        // budżetowy, który może potrzebować powtórzyć przebieg — tam trzymamy oryginały.
        var required = outputsEstimate
        required += settings.budget.isEnabled ? originalsTotal : largestOriginal
        // Archiwum ZIP to druga kopia tych samych danych.
        if settings.packaging.makeZip { required += outputsEstimate }
        // Margines na niedoszacowanie i na system.
        required += 50_000_000

        if availableBytes > 0 && required > availableBytes {
            throw ConversionError.insufficientDiskSpace(required: required, available: availableBytes)
        }

        return Report(unavailableCount: unavailable, requiredBytes: required, availableBytes: availableBytes)
    }
}
