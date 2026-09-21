import Foundation

/// Szacowanie rozmiaru wyniku przed przetworzeniem.
///
/// **Dlaczego to jest szacunek, a nie liczba.** Rozmiar pliku JPEG zależy przede
/// wszystkim od treści zdjęcia: kadr gładkiej ściany zejdzie do 200 kB, ten sam aparat
/// i te same ustawienia na zdjęciu liści dadzą 1,8 MB. Przy próbce kilku zdjęć realny
/// błąd potrafi sięgnąć kilkudziesięciu procent, a przy zaznaczeniu mieszanym
/// (zrzuty ekranu obok zdjęć z lasu) jeszcze więcej. Dlatego interfejs pokazuje
/// wartość z tyldą i podpisem „szacunek", a tryb „zmieść w X MB" **nie opiera się**
/// na tej liczbie — tam pipeline mierzy wynik naprawdę.
///
/// **Dlaczego ekstrapolujemy po pikselach, a nie po rozmiarze źródła.** Liczbę pikseli
/// wyjściowych znamy dokładnie dla każdego zdjęcia, więc „bajtów na piksel" z próbki
/// przenosi się na resztę znacznie wierniej niż stosunek rozmiarów plików — ten ostatni
/// mieszałby ze sobą różne formaty źródłowe (HEIC, JPEG, PNG, RAW) o zupełnie innej
/// gęstości informacji.
public struct SizeEstimator: Sendable {

    public static let defaultSampleCount = 3

    /// Liczba pikseli, jaką będzie miał plik wynikowy.
    public static func outputPixelCount(for photo: any SourcePhoto, settings: ConversionSettings) -> Int {
        let width = photo.pixelWidth
        let height = photo.pixelHeight
        guard width > 0, height > 0 else { return 0 }
        guard let target = settings.targetSize.pixels else { return width * height }
        let longEdge = max(width, height)
        guard longEdge > target else { return width * height }
        let scale = Double(target) / Double(longEdge)
        return Int((Double(width) * scale).rounded()) * Int((Double(height) * scale).rounded())
    }

    /// Szacuje łączny rozmiar wyniku.
    ///
    /// - Returns: `nil`, gdy próbki nie udało się przetworzyć. Brak liczby jest lepszy
    ///   niż liczba zmyślona — użytkownik zobaczy wtedy sam rozmiar źródeł.
    public static func estimate(
        photos: [any SourcePhoto],
        settings: ConversionSettings,
        sampleCount: Int = defaultSampleCount
    ) async -> Int64? {
        guard !photos.isEmpty else { return 0 }

        let samples = pickSamples(from: photos, count: sampleCount)
        guard !samples.isEmpty else { return nil }

        let directory = Workspace.rootDirectory.appendingPathComponent("szacunek-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var producedBytes: Int64 = 0
        var sampledPixels = 0

        for photo in samples {
            if Task.isCancelled { return nil }
            // Zdjęcie wiszące w iCloud pominęlibyśmy pobieraniem po sieci tylko po to,
            // żeby narysować szacunek — to zbyt drogo za tyldę.
            guard await photo.isAvailableLocally() else { continue }

            let sourceURL = directory.appendingPathComponent("src-\(FileNamer.normalize(photo.id))")
            let outputURL = directory.appendingPathComponent("out-\(FileNamer.normalize(photo.id)).\(settings.format.fileExtension)")
            do {
                try await photo.materialize(at: sourceURL) { _ in }
                let bytes = try ImageConverter.convert(
                    sourceURL: sourceURL,
                    destinationURL: outputURL,
                    settings: settings,
                    quality: settings.effectiveQuality,
                    displayName: photo.originalFileName ?? photo.id
                )
                producedBytes += bytes
                sampledPixels += outputPixelCount(for: photo, settings: settings)
            } catch {
                continue
            }
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        guard sampledPixels > 0, producedBytes > 0 else { return nil }

        let bytesPerPixel = Double(producedBytes) / Double(sampledPixels)
        let totalPixels = photos.reduce(0) { $0 + outputPixelCount(for: $1, settings: settings) }
        return Int64(bytesPerPixel * Double(totalPixels))
    }

    /// Wybiera próbki równomiernie po całym zaznaczeniu.
    ///
    /// Równomiernie, a nie losowo ani „pierwsze n": zaznaczenie bywa posortowane
    /// czasem, a pierwsze zdjęcia z sesji potrafią być zupełnie inne niż ostatnie.
    static func pickSamples(from photos: [any SourcePhoto], count: Int) -> [any SourcePhoto] {
        guard count > 0 else { return [] }
        guard photos.count > count else { return photos }
        let step = Double(photos.count) / Double(count)
        return (0..<count).map { photos[min(photos.count - 1, Int(Double($0) * step + step / 2))] }
    }
}
