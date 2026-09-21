import Foundation
import OdbitkaKit
import Photos
import SwiftUI

/// Stan ekranu wyboru zdjęć.
@Observable
@MainActor
final class PhotoLibraryModel: NSObject, PHPhotoLibraryChangeObserver {

    enum Access: Equatable {
        case undetermined
        case authorized
        /// Użytkownik udostępnił tylko wybrane zdjęcia. To nie jest błąd — to wybór,
        /// który system aktywnie promuje, i musi działać pełnoprawnie.
        case limited
        case denied
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all
        case heicOnly
        var id: String { rawValue }
    }

    private(set) var access: Access = .undetermined
    private(set) var assets: [PHAsset] = []
    private(set) var isLoading = false
    private(set) var isIndexingFormats = false

    var filter: Filter = .all {
        didSet { Task { await applyFilter() } }
    }

    private(set) var visibleAssets: [PHAsset] = []
    var selection: Set<String> = [] {
        didSet { scheduleSelectionSizeUpdate() }
    }

    /// Łączny rozmiar zaznaczenia. Liczony w tle, bo wymaga odpytania zasobów.
    private(set) var selectionByteCount: Int64 = 0

    private var fetchResult: PHFetchResult<PHAsset>?
    private var formatCache: [String: String] = [:]
    private var selectionSizeTask: Task<Void, Never>?
    private var assetCache: [String: PhotoAsset] = [:]

    /// Czytane w `deinit`, który nie jest izolowany do głównego aktora. Zapis następuje
    /// wyłącznie na głównym aktorze, więc wyścigu tu nie ma.
    @ObservationIgnored nonisolated(unsafe) private var isObserving = false

    /// Obserwatora biblioteki rejestrujemy **dopiero po uzyskaniu dostępu**.
    ///
    /// Samo sięgnięcie po `PHPhotoLibrary.shared()` potrafi wywołać systemowy prompt
    /// o uprawnienia — a ten musi paść dopiero po ekranie powitalnym, który tłumaczy,
    /// po co nam dostęp. Rejestracja w `init` skutecznie unieważniała cały ten ekran.
    private func startObservingIfNeeded() {
        guard !isObserving else { return }
        isObserving = true
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        if isObserving {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    // MARK: - Uprawnienia

    func refreshAuthorization() {
        access = Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        if access == .authorized || access == .limited {
            startObservingIfNeeded()
            Task { await load() }
        }
    }

    /// Prosi o dostęp. Wołane dopiero po ekranie powitalnym — systemowy prompt
    /// pojawia się raz w życiu aplikacji, a odmowa jest odwracalna wyłącznie
    /// przez Ustawienia systemu, więc kontekst przed pytaniem realnie się opłaca.
    func requestAccess() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        access = Self.map(status)
        if access == .authorized || access == .limited {
            startObservingIfNeeded()
            await load()
        }
    }

    private static func map(_ status: PHAuthorizationStatus) -> Access {
        switch status {
        case .authorized: .authorized
        case .limited: .limited
        case .denied, .restricted: .denied
        case .notDetermined: .undetermined
        @unknown default: .denied
        }
    }

    // MARK: - Wczytywanie

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // Wideo nie pojawia się w ogóle. Aplikacja konwertuje zdjęcia; pokazanie filmu,
        // którego nie umie przetworzyć, tylko rodziłoby pytanie „dlaczego się nie zmniejszył".
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        let result = PHAsset.fetchAssets(with: options)
        fetchResult = result

        var collected: [PHAsset] = []
        collected.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in collected.append(asset) }
        assets = collected

        await applyFilter()
    }

    private func applyFilter() async {
        switch filter {
        case .all:
            visibleAssets = assets
        case .heicOnly:
            await indexFormatsIfNeeded()
            visibleAssets = assets.filter { asset in
                guard let uti = formatCache[asset.localIdentifier]?.lowercased() else { return false }
                return uti.contains("heic") || uti.contains("heif")
            }
        }
        // Zaznaczenie przeżywa zmianę filtra tylko w części, która nadal jest widoczna —
        // inaczej użytkownik przetworzyłby zdjęcia, których nie widzi na ekranie.
        let visibleIDs = Set(visibleAssets.map(\.localIdentifier))
        selection.formIntersection(visibleIDs)
    }

    /// Ustala format każdego zdjęcia.
    ///
    /// `PHAsset` nie wystawia typu pliku wprost — trzeba sięgnąć po jego zasoby, a to
    /// wywołanie synchroniczne. Przy bibliotece z dziesiątkami tysięcy zdjęć potrafi to
    /// zająć kilka sekund, dlatego dzieje się raz, w tle, z widocznym wskaźnikiem,
    /// i zostaje w pamięci na resztę sesji.
    private func indexFormatsIfNeeded() async {
        let missing = assets.filter { formatCache[$0.localIdentifier] == nil }
        guard !missing.isEmpty else { return }

        isIndexingFormats = true
        defer { isIndexingFormats = false }

        for chunk in missing.chunked(into: 200) {
            let identifiers = chunk.map(\.localIdentifier)
            let types = await Task.detached(priority: .userInitiated) { () -> [String: String] in
                var result: [String: String] = [:]
                for asset in chunk {
                    if let uti = PhotoAsset.preferredResource(for: asset)?.uniformTypeIdentifier {
                        result[asset.localIdentifier] = uti
                    }
                }
                return result
            }.value
            for identifier in identifiers {
                formatCache[identifier] = types[identifier] ?? ""
            }
            await Task.yield()
        }
    }

    // MARK: - Zaznaczenie

    func toggle(_ asset: PHAsset) {
        if selection.contains(asset.localIdentifier) {
            selection.remove(asset.localIdentifier)
        } else {
            selection.insert(asset.localIdentifier)
        }
    }

    func selectAllVisible() {
        selection = Set(visibleAssets.map(\.localIdentifier))
    }

    func clearSelection() {
        selection = []
    }

    var selectedAssets: [PHAsset] {
        let selected = selection
        return visibleAssets.filter { selected.contains($0.localIdentifier) }
    }

    /// Zaznaczone zdjęcia w postaci zrozumiałej dla silnika.
    func selectedPhotos() -> [any SourcePhoto] {
        selectedAssets.map { asset in
            if let cached = assetCache[asset.localIdentifier] { return cached }
            let photo = PhotoAsset.make(from: asset)
            assetCache[asset.localIdentifier] = photo
            return photo
        }
    }

    private func scheduleSelectionSizeUpdate() {
        selectionSizeTask?.cancel()
        let assets = selectedAssets
        guard !assets.isEmpty else {
            selectionByteCount = 0
            return
        }
        selectionSizeTask = Task { [weak self] in
            let total = await Task.detached(priority: .utility) { () -> Int64 in
                assets.reduce(Int64(0)) { partial, asset in
                    guard !Task.isCancelled else { return partial }
                    return partial + PhotoAsset.make(from: asset).byteCount
                }
            }.value
            guard !Task.isCancelled else { return }
            self?.selectionByteCount = total
        }
    }

    // MARK: - PHPhotoLibraryChangeObserver

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            guard let current = self.fetchResult,
                  let details = changeInstance.changeDetails(for: current)
            else { return }
            self.fetchResult = details.fetchResultAfterChanges
            await self.load()
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
