import Photos
import SwiftUI

/// Miniatura zdjęcia w siatce.
///
/// Żądanie idzie przez wspólny `PHCachingImageManager` w dokładnie takim rozmiarze,
/// w jakim komórka jest rysowana. Proszenie o pełnowymiarowy obraz i skalowanie go
/// w SwiftUI byłoby najprostszą drogą do siatki, która klatkuje i zjada pamięć.
struct ThumbnailView: View {
    let asset: PHAsset
    let side: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        // Kwadrat wymusza tło, nie obraz. Nałożenie `aspectRatio` na sam obraz nic nie
        // daje — `scaledToFill` narzuca własny rozmiar naturalny i komórki rozjeżdżają
        // się na różne wysokości. Rozmiar dyktuje siatka, przycięcie następuje na końcu.
        Rectangle()
            .fill(Color(.secondarySystemFill))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .contentShape(Rectangle())
        .task(id: asset.localIdentifier) {
            image = await ThumbnailLoader.shared.image(for: asset, side: side, scale: displayScale)
        }
    }
}

/// Wspólny dostawca miniatur.
actor ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let manager = PHCachingImageManager()

    /// `scale` przychodzi ze środowiska widoku, a nie z `UIScreen.main` — ten ostatni
    /// jest wycofany i w oknach na iPadzie potrafi zwrócić skalę innego ekranu.
    func image(for asset: PHAsset, side: CGFloat, scale: CGFloat) async -> UIImage? {
        let size = CGSize(width: side * scale, height: side * scale)

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        // Miniatury są w telefonie nawet dla zdjęć trzymanych w iCloud, więc siatka
        // przewija się bez sieci. Pobieranie po sieci zdarza się dopiero przy
        // faktycznym przetwarzaniu, gdzie jest widoczne i opisane.
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            let box = SingleImageResume(continuation)
            manager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                // `opportunistic` woła handler dwa razy: najpierw wersją rozmytą,
                // potem ostrą. Czekamy na ostrą, chyba że to już koniec.
                if !isDegraded || info?[PHImageResultIsInCloudKey] as? Bool == true {
                    box.resume(with: image)
                }
            }
        }
    }
}

private final class SingleImageResume: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage?, Never>?

    init(_ continuation: CheckedContinuation<UIImage?, Never>) {
        self.continuation = continuation
    }

    func resume(with image: UIImage?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: image)
    }
}
