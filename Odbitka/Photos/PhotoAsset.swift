import Foundation
import OdbitkaKit
import Photos

/// Adapter `PHAsset` → `SourcePhoto`.
///
/// Jedyne miejsce, w którym świat `PhotoKit` styka się z silnikiem. Dzięki temu
/// `OdbitkaKit` nie wie nic o bibliotece zdjęć i testuje się zwykłymi plikami.
struct PhotoAsset: SourcePhoto, Identifiable {
    let asset: PHAsset
    let originalFileName: String?
    let byteCount: Int64

    var id: String { asset.localIdentifier }
    var creationDate: Date? { asset.creationDate }
    var pixelWidth: Int { asset.pixelWidth }
    var pixelHeight: Int { asset.pixelHeight }

    // MARK: - Tworzenie

    /// Odczytuje metadane zasobu (nazwę i rozmiar) bez ruszania samych pikseli.
    static func make(from asset: PHAsset) -> PhotoAsset {
        let resource = preferredResource(for: asset)
        // `fileSize` nie ma publicznego akcesora, ale jest dostępne przez KVC na
        // `PHAssetResource` i jest to jedyny sposób poznania rozmiaru oryginału bez
        // jego wczytywania. Gdyby klucz kiedyś zniknął, wracamy do szacunku
        // z liczby pikseli — lepiej przybliżyć, niż pokazać zero.
        let size = (resource?.value(forKey: "fileSize") as? NSNumber)?.int64Value
            ?? estimatedByteCount(for: asset)

        return PhotoAsset(
            asset: asset,
            originalFileName: resource?.originalFilename,
            byteCount: size
        )
    }

    /// HEIC z iPhone'a to mniej więcej 0,25 bajta na piksel.
    private static func estimatedByteCount(for asset: PHAsset) -> Int64 {
        Int64(Double(asset.pixelWidth * asset.pixelHeight) * 0.25)
    }

    /// Zasób, który reprezentuje to, co użytkownik widzi w Zdjęciach.
    ///
    /// `fullSizePhoto` istnieje tylko dla zdjęć edytowanych i zawiera wersję **po**
    /// kadrowaniu i filtrach. Bierzemy ją przed oryginałem, bo użytkownik, który
    /// wyprostował horyzont, oczekuje wyprostowanego zdjęcia w paczce.
    static func preferredResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.first { $0.type == .fullSizePhoto }
            ?? resources.first { $0.type == .photo }
            ?? resources.first { $0.type == .alternatePhoto }
            ?? resources.first
    }

    // MARK: - SourcePhoto

    func isAvailableLocally() async -> Bool {
        guard let resource = Self.preferredResource(for: asset) else { return false }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false

        return await withCheckedContinuation { continuation in
            let box = SingleResume(continuation)
            let holder = RequestIDHolder()

            let id = PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { _ in
                    // Pierwszy bajt przyszedł bez sieci — plik leży na urządzeniu.
                    // Nie ma sensu czytać reszty, więc od razu anulujemy.
                    box.resume(with: true)
                    if let id = holder.value {
                        PHAssetResourceManager.default().cancelDataRequest(id)
                    }
                },
                completionHandler: { error in
                    box.resume(with: error == nil)
                }
            )
            holder.value = id
        }
    }

    func materialize(at url: URL, progress: @Sendable @escaping (Double) -> Void) async throws {
        guard let resource = Self.preferredResource(for: asset) else {
            throw ConversionError.cannotReadSource(fileName: originalFileName ?? id)
        }

        let options = PHAssetResourceRequestOptions()
        // Jedyne miejsce w całej aplikacji, które dotyka sieci — i to wyłącznie po to,
        // żeby ściągnąć z iCloud zdjęcie należące do użytkownika.
        options.isNetworkAccessAllowed = true
        options.progressHandler = { fraction in progress(fraction) }

        try? FileManager.default.removeItem(at: url)

        do {
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
        } catch {
            throw ConversionError.cannotReadSource(fileName: originalFileName ?? id)
        }
        progress(1)
    }
}

/// Kontynuacja, którą wolno wznowić dokładnie raz.
///
/// `requestData` woła zarówno handler danych, jak i handler zakończenia — bez tej
/// bramki wznowilibyśmy kontynuację dwukrotnie, co jest błędem krytycznym w Swift Concurrency.
private final class SingleResume: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(with value: Bool) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

private final class RequestIDHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: PHAssetResourceDataRequestID?

    var value: PHAssetResourceDataRequestID? {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
}
