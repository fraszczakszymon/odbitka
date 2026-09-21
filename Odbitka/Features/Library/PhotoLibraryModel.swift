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

    private(set) var access: Access = .undetermined
    private(set) var assets: [PHAsset] = []
    private(set) var isLoading = false
    private(set) var visibleAssets: [PHAsset] = []
    var selection: Set<String> = [] {
        didSet { scheduleSelectionSizeUpdate() }
    }

    /// Łączny rozmiar zaznaczenia. Liczony w tle, bo wymaga odpytania zasobów.
    private(set) var selectionByteCount: Int64 = 0

    private var fetchResult: PHFetchResult<PHAsset>?
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
        visibleAssets = collected

        // Zdjęcia mogły zniknąć z biblioteki między jednym wczytaniem a drugim.
        let availableIDs = Set(collected.map(\.localIdentifier))
        selection.formIntersection(availableIDs)
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
